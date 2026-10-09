package gui

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/api"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remote"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
	"github.com/ZHanry/home-tunnel-client/internal/windowshost"
)

// A manager belongs to one device and origin. Cancellation invalidates pending
// local requests as well as signaling; account tokens are only held for Enroll.
type localRemoteHost struct {
	service                    *remotehost.Service
	key                        string
	ctx                        context.Context
	cancel                     context.CancelFunc
	mu                         sync.Mutex
	actions                    sync.Mutex
	token, trustPin, lastError string
	running                    bool
	// trustFirstUse accepts the self-verified keyset served by the origin the
	// user just signed in to; an explicit trustPin is not required then.
	trustFirstUse  bool
	setup          string
	pending        map[string]remotehost.ApprovalEvent
	invites        []remotehost.AssistInvite
	invitesAt      time.Time
	accessProfile  remotehost.AccessProfile
	accessRequests []remotehost.AccessRequest
	accessAt       time.Time
}

func remoteIdentity(state model.State) string {
	return strings.TrimRight(state.Profile.PublicBaseURL, "/") + "\n" + state.DeviceID
}

func keysetPin(keys remotehost.Keyset) string {
	raw, _ := json.Marshal(keys)
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

// enrollAndEnable registers this computer as a remote host and turns hosting on.
// Strangers still need local approval per connection; the grant model is unchanged.
// enrollWithLogin enrolls through a dedicated account session. The desktop's
// own session is bound to its device and the server refuses it for enrollment.
func (server *Server) enrollWithLogin(ctx context.Context, host *localRemoteHost, state model.State, username, password, trustPin string) error {
	client, err := api.New(state.Profile.APIBaseURL, nil)
	if err != nil {
		return err
	}
	if _, err = client.Login(ctx, username, password); err != nil {
		return err
	}
	defer func() {
		end, done := context.WithTimeout(context.Background(), 3*time.Second)
		defer done()
		_ = client.CloseSession(end)
	}()
	token, err := client.AccessToken(ctx)
	if err != nil {
		return err
	}
	return host.enrollAndEnable(ctx, state, token, trustPin, password)
}

func (host *localRemoteHost) enrollAndEnable(ctx context.Context, state model.State, token, trustPin, password string) error {
	host.mu.Lock()
	host.token = token
	host.trustPin = trustPin
	host.trustFirstUse = trustPin == ""
	host.mu.Unlock()
	err := host.service.Enroll(ctx, remotehost.Enrollment{LinkedDeviceID: state.DeviceID, Name: localDeviceName(state), Platform: runtime.GOOS, Password: password})
	host.mu.Lock()
	host.token = ""
	host.trustPin = ""
	host.trustFirstUse = false
	host.mu.Unlock()
	if err != nil {
		return err
	}
	if err = host.service.SetEnabled(ctx, true); err != nil {
		return err
	}
	host.start()
	return nil
}

// setupRemoteAfterLogin signs in once more with the password the user just
// entered. A fresh login counts as recent verification on the server, so
// signing in is the only step needed before this computer can be reached by its
// device ID.
func (server *Server) setupRemoteAfterLogin(ctx context.Context, username, password string) {
	host, state, err := server.localRemote(ctx)
	if err != nil || username == "" || password == "" || host.service.State(ctx).Enrolled {
		return
	}
	host.mu.Lock()
	host.setup = "pending"
	host.mu.Unlock()
	go func() {
		work, cancel := context.WithTimeout(host.ctx, 40*time.Second)
		defer cancel()
		host.actions.Lock()
		err := server.enrollWithLogin(work, host, state, username, password, "")
		host.actions.Unlock()
		host.mu.Lock()
		defer host.mu.Unlock()
		host.setup = ""
		if err != nil && host.ctx.Err() == nil {
			host.setup = "failed"
			host.lastError = safeRemoteCode(err)
		}
	}()
}

func (server *Server) localRemote(ctx context.Context) (*localRemoteHost, model.State, error) {
	server.remoteMu.Lock()
	defer server.remoteMu.Unlock()
	state, err := (statepkg.Store{Path: server.options.StatePath}).Load()
	if err != nil || !state.Enrolled() {
		return nil, state, errors.New("RD_DEVICE_LOGIN_REQUIRED")
	}
	if server.options.RemoteEngine == nil {
		return nil, state, remotehost.ErrUnavailable
	}
	if server.remoteBlocked {
		return nil, state, errors.New("RD_ACCOUNT_CHANGED")
	}
	if existing := server.remoteHost; existing != nil {
		if existing.key != remoteIdentity(state) || existing.ctx.Err() != nil {
			return nil, state, errors.New("RD_ACCOUNT_CHANGED")
		}
		return existing, state, nil
	}
	caps, err := server.options.RemoteEngine.Capabilities(ctx)
	if err != nil || !caps.Available || caps.Status != "ready" {
		return nil, state, remotehost.ErrUnavailable
	}
	sum := sha256.Sum256([]byte(remoteIdentity(state)))
	path, err := filepath.Abs(filepath.Join(filepath.Dir(server.options.StatePath), "remote-host-"+hex.EncodeToString(sum[:16])+".json"))
	if err != nil {
		return nil, state, err
	}
	store, err := remotehost.OpenStore(path)
	if err != nil {
		return nil, state, err
	}
	life, cancel := context.WithCancel(server.parent)
	host := &localRemoteHost{key: remoteIdentity(state), ctx: life, cancel: cancel, pending: map[string]remotehost.ApprovalEvent{}}
	host.service, err = remotehost.New(remotehost.Config{
		Origin: state.Profile.PublicBaseURL, Store: store, Engine: server.options.RemoteEngine,
		AccountToken: func(context.Context) (string, error) {
			host.mu.Lock()
			defer host.mu.Unlock()
			if host.ctx.Err() != nil || host.token == "" {
				return "", remotehost.ErrLocalApproval
			}
			return host.token, nil
		},
		InitialTrust: func(_ context.Context, origin string, keys remotehost.Keyset) error {
			host.mu.Lock()
			defer host.mu.Unlock()
			if host.ctx.Err() != nil || origin != strings.TrimRight(state.Profile.PublicBaseURL, "/") || !host.trustFirstUse && (host.trustPin == "" || host.trustPin != keysetPin(keys)) {
				return remotehost.ErrLocalApproval
			}
			return nil
		},
		LocalAdminCheck: remotehost.RequireElevatedAdmin,
	})
	if err != nil {
		cancel()
		return nil, state, err
	}
	server.remoteHost = host
	server.mu.Lock()
	setHotkey := server.setEmergencyHotkey
	server.mu.Unlock()
	if setHotkey != nil {
		_ = setHotkey(host.service.State(ctx).EmergencyKey)
	}
	go func() {
		for {
			select {
			case <-life.Done():
				return
			case event := <-host.service.Approvals():
				if event.Kind == "session" {
					continue
				}
				host.mu.Lock()
				for id, old := range host.pending {
					if !old.ExpiresAt.After(time.Now()) {
						delete(host.pending, id)
					}
				}
				if event.Kind == "pairing_complete" {
					delete(host.pending, event.ID)
				} else if len(host.pending) < 16 {
					host.pending[event.ID] = event
				}
				host.mu.Unlock()
			}
		}
	}()
	if status := host.service.State(ctx); status.Enrolled && status.Enabled {
		host.start()
	}
	return host, state, nil
}

func (host *localRemoteHost) start() {
	host.mu.Lock()
	if host.running || host.ctx.Err() != nil {
		host.mu.Unlock()
		return
	}
	host.running = true
	host.lastError = ""
	host.mu.Unlock()
	release, owned, ownerErr := windowshost.AcquireOwner(host.key)
	if ownerErr != nil || owned {
		if release != nil {
			release()
		}
		host.mu.Lock()
		host.running = false
		host.lastError = "RD_BACKEND_UNAVAILABLE"
		host.mu.Unlock()
		return
	}
	go func() {
		defer release()
		// Signaling drops on network changes and server restarts; keep the host
		// reachable like other remote desktop tools instead of waiting for a restart.
		delay := remoteRetryMin / 2
		for {
			started := time.Now()
			err := host.service.Run(host.ctx)
			stop := host.ctx.Err() != nil || errors.Is(err, remotehost.ErrLocalApproval)
			if !stop {
				status := host.service.State(host.ctx)
				stop = !status.Enrolled || !status.Enabled
			}
			host.mu.Lock()
			if err != nil && host.ctx.Err() == nil {
				host.lastError = safeRemoteCode(err)
			}
			if stop {
				host.running = false
				host.mu.Unlock()
				return
			}
			host.mu.Unlock()
			delay = nextRemoteRetry(delay, time.Since(started))
			log.Printf("remote host offline: %s; reconnecting in %s", safeRemoteCode(err), delay)
			select {
			case <-host.ctx.Done():
				host.mu.Lock()
				host.running = false
				host.mu.Unlock()
				return
			case <-time.After(delay):
			}
		}
	}()
}

const (
	remoteRetryMin = 2 * time.Second
	remoteRetryMax = time.Minute
)

// nextRemoteRetry doubles the wait after quick failures and starts over after
// a connection that stayed up for a while.
func nextRemoteRetry(previous, uptime time.Duration) time.Duration {
	if uptime >= remoteRetryMax {
		return remoteRetryMin
	}
	return min(previous*2, remoteRetryMax)
}

// Stop local input/media before potentially slow tunnel or server logout.
func (server *Server) stopRemote(disable bool) {
	if disable {
		ctx, done := context.WithTimeout(context.Background(), 2*time.Second)
		if state, err := (statepkg.Store{Path: server.options.StatePath}).Load(); err == nil && state.Enrolled() {
			_, _ = windowshost.Control(ctx, windowshost.ControlRequest{Operation: "disable", Origin: state.Profile.PublicBaseURL, DeviceID: state.DeviceID})
		}
		done()
	}
	server.remoteMu.Lock()
	server.remoteBlocked = true
	host := server.remoteHost
	if host != nil {
		host.cancel()
	}
	server.remoteMu.Unlock()
	if host == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if disable {
		_ = host.service.SetEnabled(ctx, false)
	} else {
		_ = host.service.Stop(ctx, "RD_LOCAL_SHUTDOWN")
	}
	host.mu.Lock()
	host.token = ""
	host.trustPin = ""
	host.trustFirstUse = false
	clear(host.pending)
	host.invites = nil
	host.invitesAt = time.Time{}
	host.mu.Unlock()
}

func (server *Server) SetEmergencyHotkey(set func(string) error) {
	server.mu.Lock()
	server.setEmergencyHotkey = set
	server.serviceEmergencyKey = ""
	server.mu.Unlock()
}

func (server *Server) EmergencyStopRemote() {
	serviceCtx, serviceDone := context.WithTimeout(context.Background(), 2*time.Second)
	_, _ = windowshost.Control(serviceCtx, windowshost.ControlRequest{Operation: "emergency_stop"})
	serviceDone()
	server.remoteMu.Lock()
	host := server.remoteHost
	server.remoteMu.Unlock()
	if host == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := host.service.SetEnabled(ctx, false); err != nil {
		host.mu.Lock()
		host.lastError = safeRemoteCode(err)
		host.mu.Unlock()
	}
}

func safeRemoteCode(err error) string {
	valid := func(code string) bool {
		if !strings.HasPrefix(code, "RD_") || len(code) > 80 {
			return false
		}
		for _, c := range code {
			if (c < 'A' || c > 'Z') && (c < '0' || c > '9') && c != '_' {
				return false
			}
		}
		return true
	}
	var apiErr *remotehost.APIError
	if errors.As(err, &apiErr) {
		if valid(apiErr.Code) {
			return apiErr.Code
		}
	}
	var accountErr *api.Error
	if errors.As(err, &accountErr) {
		return "RD_ACCOUNT_AUTH_FAILED"
	}
	if err != nil && valid(err.Error()) {
		return err.Error()
	}
	return "RD_REQUEST_FAILED"
}

func remoteError(writer http.ResponseWriter, err error) {
	code := safeRemoteCode(err)
	writer.Header().Set("content-type", "application/json")
	writer.WriteHeader(http.StatusConflict)
	_ = json.NewEncoder(writer).Encode(map[string]string{"error_code": code, "message": code})
}

func (server *Server) remoteCapabilities(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	result := remote.Unavailable("RD_BACKEND_UNAVAILABLE")
	if engine := server.options.RemoteEngine; engine != nil {
		ctx, cancel := context.WithTimeout(request.Context(), 2*time.Second)
		defer cancel()
		caps, err := engine.Capabilities(ctx)
		if err == nil && caps.Available && caps.Status == "ready" {
			result.Available = true
			result.CanHost = true
			result.Reason = ""
		}
	}
	writeJSON(writer, result)
}

func (server *Server) remoteState(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 3*time.Second)
	defer cancel()
	payload, _, _ := server.remoteSnapshot(ctx)
	writeJSON(writer, payload)
}

// remoteSnapshot is the single source of the host state shown by the main
// window, the approval popup and the popup watcher. ok is false when there is
// no usable host status (signed out, no backend); payload is then the
// placeholder the UI renders.
func (server *Server) remoteSnapshot(ctx context.Context) (payload any, status remotehost.Status, ok bool) {
	if response, managed := server.serviceRemoteState(ctx); managed {
		return response, response, true
	}
	host, saved, err := server.localRemote(ctx)
	if err != nil {
		if errors.Is(err, remotehost.ErrServiceManaged) {
			if pending, pendingErr := server.pendingServiceState(ctx, saved); pendingErr == nil {
				return pending, pending, true
			}
		}
		return map[string]any{"enrolled": false, "enabled": false, "running": false, "capabilities": remote.Unavailable(safeRemoteCode(err)), "error_code": safeRemoteCode(err), "pending": []any{}, "grants": []any{}}, remotehost.Status{}, false
	}
	status = host.service.State(ctx)
	host.mu.Lock()
	status.Invites = append([]remotehost.AssistInvite(nil), host.invites...)
	refreshInvites := status.Enrolled && status.Enabled && time.Since(host.invitesAt) > 30*time.Second
	status.AccessProfile = host.accessProfile
	status.AccessRequests = append([]remotehost.AccessRequest(nil), host.accessRequests...)
	refreshAccess := status.Enrolled && status.Enabled && time.Since(host.accessAt) > 5*time.Second
	status.Setup = host.setup
	host.mu.Unlock()
	if refreshInvites {
		if invites, listErr := host.service.ListAssistInvites(ctx); listErr == nil {
			host.mu.Lock()
			host.invites = invites
			host.invitesAt = time.Now()
			status.Invites = append([]remotehost.AssistInvite(nil), invites...)
			host.mu.Unlock()
		}
	}
	if refreshAccess {
		profile, profileErr := host.service.AccessProfile(ctx, false)
		// Every running host gets its 9-digit device ID without an extra click.
		if profileErr == nil && profile.DeviceID == "" && status.Running {
			profile, profileErr = host.service.AccessProfile(ctx, true)
		}
		requests, requestErr := host.service.ListAccessRequests(ctx)
		if profileErr == nil && requestErr == nil {
			host.mu.Lock()
			host.accessProfile = profile
			host.accessRequests = requests
			host.accessAt = time.Now()
			status.AccessProfile = profile
			status.AccessRequests = append([]remotehost.AccessRequest(nil), requests...)
			host.mu.Unlock()
		}
	}
	for i := range status.Grants {
		status.Grants[i].GrantJWS = ""
	}
	// The UI iterates these lists; never send null before the first refresh.
	if status.Invites == nil {
		status.Invites = []remotehost.AssistInvite{}
	}
	if status.AccessRequests == nil {
		status.AccessRequests = []remotehost.AccessRequest{}
	}
	host.mu.Lock()
	if host.lastError != "" {
		status.ErrorCode = host.lastError
	}
	seen := map[string]bool{}
	for _, event := range status.Pending {
		seen[event.ID] = true
	}
	for id, event := range host.pending {
		if !event.ExpiresAt.After(time.Now()) {
			delete(host.pending, id)
			continue
		}
		if !seen[id] {
			status.Pending = append(status.Pending, event)
		}
	}
	host.mu.Unlock()
	surface := windowshost.Inspect(ctx)
	status.Service = remotehost.ServiceSurface{Installed: surface.Installed, Running: surface.Running, UnattendedEnabled: surface.UnattendedEnabled, SecureDesktop: surface.SecureDesktop, Detail: surface.Detail}
	return status, status, true
}

func (server *Server) remoteTrust(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 12*time.Second)
	defer cancel()
	host, state, err := server.localRemote(ctx)
	if err != nil {
		remoteError(writer, err)
		return
	}
	keys, err := host.service.InitialKeyset(ctx)
	if err != nil {
		remoteError(writer, err)
		return
	}
	writeJSON(writer, map[string]any{"origin": state.Profile.PublicBaseURL, "server_instance_id": keys.ServerInstanceID, "active_kid": keys.ActiveKid, "trust_pin": keysetPin(keys)})
}

func (server *Server) remoteAction(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, 16<<10)
	// Decisions made in either window update the popup without waiting a tick.
	defer server.pokeApprovalWatcher()
	var body windowshost.RemoteAction

	if err := readJSON(request, &body); err != nil {
		writeError(writer, http.StatusBadRequest, "Invalid remote action")
		return
	}
	if body.Action == "enable_unattended" {
		err := server.enableServiceRemote(request.Context(), body)
		if err != nil {
			remoteError(writer, err)
		} else {
			writeJSON(writer, map[string]bool{"ok": true})
		}
		return
	}
	if server.serviceRemoteAction(writer, request, body) {
		return
	}
	host, state, err := server.localRemote(request.Context())
	if err != nil {
		remoteError(writer, err)
		return
	}
	ctx, cancel := context.WithTimeout(host.ctx, 35*time.Second)
	defer cancel()
	unregister := context.AfterFunc(request.Context(), cancel)
	defer unregister()
	var invite *remotehost.AssistInvite
	var profile *remotehost.AccessProfile
	// Emergency controls never queue behind enrollment's network requests.
	if body.Action == "stop" {
		err = host.service.Stop(ctx, "RD_LOCAL_STOP")
	} else if body.Action == "disable" {
		err = host.service.SetEnabled(ctx, false)
	} else {
		if !host.actions.TryLock() {
			remoteError(writer, errors.New("RD_ACTION_IN_PROGRESS"))
			return
		}
		defer host.actions.Unlock()
		if ctx.Err() != nil {
			remoteError(writer, errors.New("RD_ACCOUNT_CHANGED"))
			return
		}
		switch body.Action {
		case "enroll":
			if body.TrustPin != "" && len(body.TrustPin) != 64 || body.Username == "" || body.Password == "" {
				err = remotehost.ErrLocalApproval
				break
			}
			caps, capsErr := server.options.RemoteEngine.Capabilities(ctx)
			if capsErr != nil || !caps.Available || caps.Status != "ready" {
				err = remotehost.ErrUnavailable
				break
			}
			err = server.enrollWithLogin(ctx, host, state, body.Username, body.Password, body.TrustPin)
		case "enable":
			err = host.service.SetEnabled(ctx, true)
			if err == nil {
				host.start()
			}
		case "disable_unattended":
			err = host.service.SetUnattendedEnabled(ctx, false)
		case "approve", "reject":
			if body.Kind == "pairing" {
				if body.Action == "approve" {
					expires := time.Now().Add(10 * time.Minute)
					if body.Mode == "persistent" {
						expires = time.Now().Add(30 * 24 * time.Hour)
					}
					err = host.service.ApprovePairing(ctx, body.ID, body.Permissions, body.Mode, expires)
				} else {
					err = host.service.RejectPairing(ctx, body.ID)
				}
			} else if body.Kind == "session" {
				if body.Action == "approve" {
					err = host.service.ApproveSessionExpected(ctx, body.ID, body.ConnectionEpoch, body.StateVersion)
				} else {
					err = host.service.RejectSessionExpected(ctx, body.ID, body.ConnectionEpoch, body.StateVersion)
				}
			} else {
				err = remotehost.ErrLocalApproval
			}
			if err == nil {
				host.mu.Lock()
				if pending, exists := host.pending[body.ID]; exists && pending.Kind == body.Kind {
					delete(host.pending, body.ID)
				}
				host.mu.Unlock()
			}
		case "revoke":
			err = host.service.RevokeGrant(ctx, body.ID)
		case "create_invite":
			created, createErr := host.service.CreateAssistInvite(ctx)
			err = createErr
			if err == nil {
				invite = &created
			}
		case "revoke_invite":
			err = host.service.RevokeAssistInvite(ctx, body.ID)
		case "create_access_profile":
			created, profileErr := host.service.AccessProfile(ctx, true)
			err, profile = profileErr, &created
		case "set_fixed_password":
			created, profileErr := host.service.SetFixedPassword(ctx, body.FixedPassword)
			err, profile = profileErr, &created
		case "disable_fixed_password":
			err = host.service.DisableFixedPassword(ctx)
		case "approve_access_request", "reject_access_request":
			err = host.service.DecideAccessRequest(ctx, body.ID, body.Action == "approve_access_request")
		case "set_emergency_hotkey":
			if !remotehost.ValidEmergencyKey(body.EmergencyKey) {
				err = remotehost.ErrLocalApproval
				break
			}
			server.mu.Lock()
			setHotkey := server.setEmergencyHotkey
			server.mu.Unlock()
			if setHotkey == nil {
				err = remotehost.ErrUnavailable
				break
			}
			previous := host.service.State(ctx).EmergencyKey
			if err = setHotkey(body.EmergencyKey); err == nil {
				err = host.service.SetEmergencyKey(body.EmergencyKey)
				if err != nil {
					_ = setHotkey(previous)
				}
			}
		default:
			err = errors.New("RD_ACTION_INVALID")
		}
	}
	if err != nil {
		remoteError(writer, err)
		return
	}
	if body.Action == "create_invite" || body.Action == "revoke_invite" || body.Action == "disable" || body.Action == "create_access_profile" || body.Action == "set_fixed_password" || body.Action == "disable_fixed_password" || body.Action == "approve_access_request" || body.Action == "reject_access_request" {
		host.mu.Lock()
		host.invitesAt = time.Time{}
		host.accessAt = time.Time{}
		if body.Action == "disable" {
			host.invites = nil
		}
		host.mu.Unlock()
	}
	if invite != nil {
		writer.Header().Set("cache-control", "no-store")
		writeJSON(writer, invite)
		return
	}
	if profile != nil {
		writer.Header().Set("cache-control", "no-store")
		writeJSON(writer, profile)
		return
	}
	writeJSON(writer, map[string]bool{"ok": true})
}
