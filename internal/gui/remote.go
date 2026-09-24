package gui

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/api"
	"github.com/ZHanry/home-tunnel-client/internal/app"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remote"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
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
	pending                    map[string]remotehost.ApprovalEvent
	invites                    []remotehost.AssistInvite
	invitesAt                  time.Time
	accessProfile              remotehost.AccessProfile
	accessRequests             []remotehost.AccessRequest
	accessAt                   time.Time
}

func remoteIdentity(state model.State) string {
	return strings.TrimRight(state.Profile.PublicBaseURL, "/") + "\n" + state.DeviceID
}

func keysetPin(keys remotehost.Keyset) string {
	raw, _ := json.Marshal(keys)
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
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
			if host.ctx.Err() != nil || origin != strings.TrimRight(state.Profile.PublicBaseURL, "/") || host.trustPin == "" || host.trustPin != keysetPin(keys) {
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
	go func() {
		err := host.service.Run(host.ctx)
		host.mu.Lock()
		defer host.mu.Unlock()
		host.running = false
		if err != nil && host.ctx.Err() == nil {
			host.lastError = safeRemoteCode(err)
		}
	}()
}

// Stop local input/media before potentially slow tunnel or server logout.
func (server *Server) stopRemote(disable bool) {
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
	clear(host.pending)
	host.invites = nil
	host.invitesAt = time.Time{}
	host.mu.Unlock()
}

func (server *Server) SetEmergencyHotkey(set func(string) error) {
	server.mu.Lock()
	server.setEmergencyHotkey = set
	server.mu.Unlock()
}

func (server *Server) EmergencyStopRemote() {
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
		switch apiErr.Code {
		case "MFA_REQUIRED":
			return "RD_MFA_REQUIRED"
		case "MFA_INVALID":
			return "RD_MFA_INVALID"
		}
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
	host, _, err := server.localRemote(ctx)
	if err != nil {
		writeJSON(writer, map[string]any{"enrolled": false, "enabled": false, "running": false, "capabilities": remote.Unavailable(safeRemoteCode(err)), "error_code": safeRemoteCode(err), "pending": []any{}, "grants": []any{}})
		return
	}
	status := host.service.State(ctx)
	host.mu.Lock()
	status.Invites = append([]remotehost.AssistInvite(nil), host.invites...)
	refreshInvites := status.Enrolled && status.Enabled && time.Since(host.invitesAt) > 30*time.Second
	status.AccessProfile = host.accessProfile
	status.AccessRequests = append([]remotehost.AccessRequest(nil), host.accessRequests...)
	refreshAccess := status.Enrolled && status.Enabled && time.Since(host.accessAt) > 5*time.Second
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
	writeJSON(writer, status)
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
	var body struct {
		Action          string   `json:"action"`
		Username        string   `json:"username"`
		Password        string   `json:"password"`
		MFACode         string   `json:"mfa_code"`
		TrustPin        string   `json:"trust_pin"`
		ID              string   `json:"id"`
		Kind            string   `json:"kind"`
		Mode            string   `json:"mode"`
		Permissions     []string `json:"permissions"`
		FixedPassword   string   `json:"fixed_password"`
		EmergencyKey    string   `json:"emergency_key"`
		ConnectionEpoch int64    `json:"connection_epoch"`
		StateVersion    int64    `json:"state_version"`
	}
	if err := readJSON(request, &body); err != nil {
		writeError(writer, http.StatusBadRequest, "Invalid remote action")
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
			if len(body.TrustPin) != 64 || body.Username == "" || body.Password == "" {
				err = remotehost.ErrLocalApproval
				break
			}
			caps, capsErr := server.options.RemoteEngine.Capabilities(ctx)
			if capsErr != nil || !caps.Available || caps.Status != "ready" {
				err = remotehost.ErrUnavailable
				break
			}
			client, clientErr := api.New(state.Profile.APIBaseURL, nil)
			if clientErr != nil {
				err = clientErr
				break
			}
			if _, err = client.Login(ctx, body.Username, body.Password, body.MFACode); err != nil {
				break
			}
			defer func() {
				end, done := context.WithTimeout(context.Background(), 3*time.Second)
				defer done()
				_ = client.CloseSession(end)
			}()
			token, tokenErr := client.AccessToken(ctx)
			if tokenErr != nil {
				err = tokenErr
				break
			}
			host.mu.Lock()
			host.token = token
			host.trustPin = body.TrustPin
			host.mu.Unlock()
			err = host.service.Enroll(ctx, remotehost.Enrollment{LinkedDeviceID: state.DeviceID, Name: app.DefaultDeviceName(), Platform: runtime.GOOS, Password: body.Password, MFACode: body.MFACode})
			host.mu.Lock()
			host.token = ""
			host.trustPin = ""
			host.mu.Unlock()
		case "enable":
			err = host.service.SetEnabled(ctx, true)
			if err == nil {
				host.start()
			}
		case "enable_unattended":
			err = host.service.SetUnattendedEnabled(ctx, true)
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
