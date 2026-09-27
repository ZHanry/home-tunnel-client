//go:build windows

package windowshost

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/remoteengine"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	"golang.org/x/sys/windows"
)

// Supervisor owns the endpoint across logon sessions. RPC requests never
// choose a process, executable, desktop or credential-store path.
type Supervisor struct {
	mu                sync.Mutex
	mutation          sync.Mutex
	machine           *machineStore
	store             *remotehost.Store
	host              *remotehost.Service
	nativeSHA, guiSHA string
	wake              chan struct{}
	cancel            context.CancelFunc
	generation        context.Context
	lastError         string
	pending           map[string]remotehost.ApprovalEvent
	view              remotehost.Status
}

func NewSupervisor(nativeSHA, guiSHA string) (*Supervisor, error) {
	if len(nativeSHA) != 64 || len(guiSHA) != 64 {
		return nil, ErrUnavailable
	}
	machine, err := openMachineStore()
	if err != nil {
		return nil, err
	}
	s := &Supervisor{machine: machine, nativeSHA: nativeSHA, guiSHA: guiSHA, wake: make(chan struct{}, 1), pending: map[string]remotehost.ApprovalEvent{}}
	if machine.metadata().Schema == 1 {
		s.store, err = remotehost.OpenStoreWith(machine)
		if err != nil {
			machine.Close()
			return nil, err
		}
	}
	return s, nil
}
func (s *Supervisor) NotifySession() {
	s.mu.Lock()
	if s.cancel != nil {
		s.cancel()
	}
	s.mu.Unlock()
	select {
	case s.wake <- struct{}{}:
	default:
	}
}
func (s *Supervisor) Run(parent context.Context) error {
	ctx, cancel := context.WithCancel(parent)
	rpcDone := make(chan struct{})
	var rpcError error
	go func() {
		rpcError = s.serveControl(ctx)
		cancel()
		close(rpcDone)
	}()
	defer func() {
		cancel()
		// Every admitted RPC must finish before releasing the store's path
		// pins. In particular, an adoption/save can outlive a WTS change.
		<-rpcDone
		s.machine.Close()
	}()
	for {
		s.mu.Lock()
		store := s.store
		s.mu.Unlock()
		if store != nil && windows.WTSGetActiveConsoleSessionId() != 0xffffffff {
			err := s.runGeneration(ctx, store)
			if ctx.Err() != nil {
				<-rpcDone
				return rpcError
			}
			s.mu.Lock()
			if err != nil {
				s.lastError = "RD_BACKEND_UNAVAILABLE"
			}
			s.mu.Unlock()
		}
		select {
		case <-ctx.Done():
			return nil
		case <-rpcDone:
			if rpcError == nil {
				return ErrUnavailable
			}
			return rpcError
		case <-s.wake:
		case <-time.After(3 * time.Second):
		}
	}
}
func (s *Supervisor) runGeneration(parent context.Context, store *remotehost.Store) error {
	meta := s.machine.metadata()
	identity := strings.TrimRight(meta.Origin, "/") + "\n" + meta.DeviceID
	release, held, err := AcquireServiceOwner(identity, meta.OwnerSID)
	if err != nil {
		return err
	}
	if held {
		return ErrUnavailable
	}
	defer release()
	life, cancel := context.WithCancel(parent)
	defer cancel()
	s.mu.Lock()
	s.cancel = cancel
	s.generation = life
	s.mu.Unlock()
	defer func() { s.mu.Lock(); s.cancel = nil; s.host = nil; s.generation = nil; s.mu.Unlock() }()
	worker, err := StartWorker(life, windows.WTSGetActiveConsoleSessionId(), s.nativeSHA, meta.OwnerSID, func() remoteengine.DesktopPolicy {
		enabled, controller, thumbprint := store.UnattendedBinding()
		return remoteengine.DesktopPolicy{Enabled: enabled, ControllerID: controller, Thumbprint: thumbprint}
	})
	if err != nil {
		return err
	}
	defer worker.Shutdown()
	host, err := remotehost.New(remotehost.Config{Origin: meta.Origin, Store: store, Engine: worker,
		ServiceOwned: true, LocalAdminCheck: func(context.Context) error { return nil }})
	// Admin-only commands are admitted by the impersonated RPC peer check.
	if err != nil {
		return err
	}
	s.mu.Lock()
	s.host = host
	clear(s.pending)
	s.view = remotehost.Status{}
	s.lastError = ""
	s.mu.Unlock()
	viewDone := make(chan struct{})
	go func() {
		defer close(viewDone)
		s.refreshView(life, host)
	}()
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	var runDone chan error
	var runCancel context.CancelFunc
	var retryAt time.Time
	defer func() {
		cancel()
		if runCancel != nil {
			runCancel()
		}
		// Close the worker first so input/media stop even during HTTP failure.
		worker.Shutdown()
		if runDone != nil {
			<-runDone
		}
		<-viewDone
	}()
	for {
		_, _, _, enabled := store.Identity()
		if enabled && runDone == nil && !time.Now().Before(retryAt) {
			runCtx, stop := context.WithCancel(life)
			runCancel = stop
			runDone = make(chan error, 1)
			go func(done chan<- error) { done <- host.Run(runCtx) }(runDone)
		} else if !enabled && runCancel != nil {
			runCancel()
		}
		select {
		case event := <-host.Approvals():
			s.mu.Lock()
			for id, old := range s.pending {
				if !old.ExpiresAt.After(time.Now()) {
					delete(s.pending, id)
				}
			}
			if event.Kind == "pairing_complete" {
				delete(s.pending, event.ID)
			} else if event.Kind != "session" && len(s.pending) < 32 {
				s.pending[event.ID] = event
			}
			s.mu.Unlock()
		case <-life.Done():
			return life.Err()
		case <-worker.Done():
			return ErrUnavailable
		case <-s.wake:
			return nil
		case <-tick.C:
		case err := <-runDone:
			runCancel()
			runCancel = nil
			runDone = nil
			retryAt = time.Now().Add(2 * time.Second)
			s.mu.Lock()
			if err != nil {
				s.lastError = "RD_SIGNAL_DISCONNECTED"
			}
			s.mu.Unlock()
		}
	}
}
func (s *Supervisor) control(ctx context.Context, peer controlPeer, request ControlRequest) ControlResponse {
	response := ControlResponse{Surface: Surface{Installed: true, Running: true, SecureDesktop: "unavailable"}}
	meta := s.machine.metadata()
	response.Managed = meta.Schema == 1
	if meta.Schema == 1 && peer.SID != meta.OwnerSID {
		response.Error = "identity_mismatch"
		return response
	}
	if request.Operation == "adopt" {
		if !peer.Admin || peer.Session == 0 {
			response.Error = "admin_required"
			return response
		}
		if !s.mutation.TryLock() {
			response.Error = "unavailable"
			return response
		}
		defer s.mutation.Unlock()
		err := s.machine.adopt(peer.SID, request.Origin, request.DeviceID, request.State)
		s.mu.Lock()
		alreadyLoaded := s.store != nil
		s.mu.Unlock()
		if err == nil && !alreadyLoaded {
			var store *remotehost.Store
			store, err = remotehost.OpenStoreWith(s.machine)
			if err == nil {
				s.mu.Lock()
				s.store = store
				s.mu.Unlock()
				s.NotifySession()
			}
		}
		response.Error = controlError(err)
		return response
	}
	if request.Operation != "status" && meta.Schema != 1 {
		response.Error = "unavailable"
		return response
	}
	if request.Origin != "" && request.Origin != meta.Origin || request.DeviceID != "" && request.DeviceID != meta.DeviceID {
		response.Error = "identity_mismatch"
		return response
	}
	s.mu.Lock()
	host, store, life, lastError := s.host, s.store, s.generation, s.lastError
	s.mu.Unlock()
	if request.Operation == "emergency_stop" || request.Operation == "disable" {
		// Cancel the worker regardless of disk/network failures. No mutation
		// lock or network call may delay emergency shutdown.
		s.NotifySession()
		var err error
		if host != nil {
			stop, done := context.WithTimeout(ctx, time.Second)
			err = host.DisableLocally(stop)
			done()
		} else if store != nil {
			err = store.DisableLocally()
		}
		response.Error = controlError(err)
		return response
	}
	if host == nil {
		response.Surface.Detail = "系统服务等待可用的控制台会话。 / Waiting for an available console session."
		if request.Operation != "status" {
			response.Error = "unavailable"
		} else if store != nil {
			origin, endpoint, _, enabled := store.Identity()
			response.State = &remotehost.Status{Origin: origin, EndpointID: endpoint, Enrolled: endpoint != "", Enabled: enabled, ErrorCode: "RD_BACKEND_UNAVAILABLE", Capabilities: remotehost.Capabilities{Status: "unavailable"}}
		}
		return response
	}
	requestCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	unhook := context.AfterFunc(life, cancel)
	defer unhook()
	var err error
	switch request.Operation {
	case "status":
		state := host.State(requestCtx)
		s.mu.Lock()
		state.Invites = append([]remotehost.AssistInvite(nil), s.view.Invites...)
		state.AccessProfile = s.view.AccessProfile
		state.AccessRequests = append([]remotehost.AccessRequest(nil), s.view.AccessRequests...)
		for _, event := range s.pending {
			if event.ExpiresAt.After(time.Now()) {
				state.Pending = append(state.Pending, event)
			}
		}
		s.mu.Unlock()
		response.Surface.UnattendedEnabled = state.UnattendedEnabled
		if state.Capabilities.Native != nil {
			response.Surface.SecureDesktop = state.Capabilities.Native.Backends["secure_desktop"]
		}
		if lastError != "" {
			state.ErrorCode = lastError
		}
		response.State = &state
	case "host_action":
		if request.Action == nil {
			err = ErrRejected
			break
		}
		err = s.hostAction(requestCtx, peer, host, *request.Action, &response)
	case "file_action":
		if peer.Session != windows.WTSGetActiveConsoleSessionId() {
			err = ErrRejected
			break
		}
		if request.File == nil {
			err = ErrRejected
			break
		}
		err = hostFileAction(requestCtx, host, *request.File, &response)
	case "enable_unattended":
		if !peer.Admin || peer.Session != windows.WTSGetActiveConsoleSessionId() {
			err = ErrAdmin
			break
		}
		if !ValidEndpointID(request.ControllerID) || !ValidThumbprint(request.Thumbprint) {
			err = ErrIdentity
			break
		}
		if !s.mutation.TryLock() {
			err = ErrUnavailable
			break
		}
		defer s.mutation.Unlock()
		if err = host.SetEnabled(requestCtx, true); err == nil {
			if err = host.SetUnattendedController(requestCtx, request.ControllerID, request.Thumbprint); err == nil {
				err = host.SetUnattendedEnabled(requestCtx, true)
			}
		}
	case "disable_unattended":
		err = host.SetUnattendedEnabled(requestCtx, false)
	default:
		err = ErrRejected
	}
	if errors.Is(err, context.Canceled) {
		err = ErrUnavailable
	}
	response.Error = controlError(err)
	return response
}

func (s *Supervisor) refreshView(ctx context.Context, host *remotehost.Service) {
	for {
		request, cancel := context.WithTimeout(ctx, 12*time.Second)
		invites, inviteErr := host.ListAssistInvites(request)
		profile, profileErr := host.AccessProfile(request, false)
		access, accessErr := host.ListAccessRequests(request)
		cancel()
		s.mu.Lock()
		if s.host == host {
			if inviteErr == nil {
				s.view.Invites = invites
			}
			if profileErr == nil {
				s.view.AccessProfile = profile
			}
			if accessErr == nil {
				s.view.AccessRequests = access
			}
		}
		s.mu.Unlock()
		timer := time.NewTimer(10 * time.Second)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}
