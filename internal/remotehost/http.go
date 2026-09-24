package remotehost

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type Config struct {
	Origin     string
	Store      *Store
	Engine     HostEngine
	HTTPClient *http.Client
	TLSConfig  *tls.Config
	// The existing account API supplies a temporary management access token only
	// during explicit enrollment/reauthentication. It is never persisted here.
	AccountToken func(context.Context) (string, error)
	// InitialTrust must present and approve the locally verified origin/key pin.
	// Missing callback fails closed; later changes require the old signed key chain.
	InitialTrust          func(context.Context, string, Keyset) error
	LocalAdminCheck       func(context.Context) error
	AllowInsecureLoopback bool
}
type APIError struct {
	Status int
	Code   string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("remote host request failed (HTTP %d, %s)", e.Status, e.Code)
}

type onlineToken struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	Nonce     string    `json:"dpop_nonce"`
}
type Service struct {
	config            Config
	origin            string
	http              *http.Client
	key               *ecdsa.PrivateKey
	tokenMu           sync.Mutex
	token             onlineToken
	mu                sync.Mutex
	engineMu          sync.Mutex
	capabilityMu      sync.Mutex
	generation        uint64
	disabled          bool
	active            *runningSession
	pending           map[string]Session
	autoApproving     map[string]int64
	autoAttempted     map[string]int64
	assistInvites     map[string]time.Time
	assistRevoked     map[string]bool
	autoPairing       map[string]bool
	autoPairAttempted map[string]bool
	approvals         chan ApprovalEvent
	running           bool
}

func New(config Config) (*Service, error) {
	if config.Store == nil {
		return nil, errors.New("remote host requires a protected store")
	}
	if config.Engine == nil {
		config.Engine = UnavailableEngine{}
	}
	u, e := url.Parse(config.Origin)
	if e != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return nil, errors.New("remote host requires an HTTPS origin")
	}
	if u.Scheme != "https" {
		ip := net.ParseIP(u.Hostname())
		if u.Scheme != "http" || !config.AllowInsecureLoopback || ip == nil || !ip.IsLoopback() {
			return nil, errors.New("remote host requires HTTPS")
		}
	}
	u.Path = ""
	origin := strings.TrimRight(u.String(), "/")
	saved := config.Store.snapshot()
	if saved.Origin != "" && saved.Origin != origin {
		return nil, ErrAuthorization
	}
	key, e := config.Store.privateKey()
	if e != nil {
		return nil, e
	}
	client := http.Client{Timeout: 12 * time.Second}
	if config.HTTPClient != nil {
		client = *config.HTTPClient
	}
	if client.Timeout == 0 || client.Timeout > 30*time.Second {
		client.Timeout = 12 * time.Second
	}
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	assists := map[string]time.Time{}
	if saved.Enabled {
		for id, expiry := range saved.AssistInvites {
			if expiry.After(time.Now()) {
				assists[id] = expiry
			}
		}
		for id, expiry := range saved.FixedInvites {
			if saved.FixedRevision > 0 && expiry.After(time.Now()) {
				assists[id] = expiry
			}
		}
	}
	return &Service{config: config, origin: origin, http: &client, key: key, disabled: !saved.Enabled, pending: map[string]Session{}, autoApproving: map[string]int64{}, autoAttempted: map[string]int64{}, assistInvites: assists, assistRevoked: map[string]bool{}, autoPairing: map[string]bool{}, autoPairAttempted: map[string]bool{}, approvals: make(chan ApprovalEvent, 8)}, nil
}
func (s *Service) Approvals() <-chan ApprovalEvent { return s.approvals }

// InitialKeyset returns public data for the local trust preview. Returning it
// does not pin it; enrollment still requires Config.InitialTrust to approve the
// exact origin/keyset the user saw.
func (s *Service) InitialKeyset(ctx context.Context) (Keyset, error) {
	var raw json.RawMessage
	if e := s.request(ctx, "GET", "/server-keys", nil, "", &raw); e != nil {
		return Keyset{}, e
	}
	keys, e := parseKeyset(raw)
	if e != nil {
		return keys, e
	}
	return keys, verifyKeyset(keys, keys, time.Now())
}
func (s *Service) request(ctx context.Context, method, path string, body any, mode string, result any) error {
	var data []byte
	var e error
	if body != nil {
		data, e = json.Marshal(body)
		if e != nil {
			return e
		}
		if len(data) > 16384 {
			return errors.New("RD request exceeds 16 KiB")
		}
	}
	request, e := http.NewRequestWithContext(ctx, method, s.origin+"/api/v1/rd"+path, bytes.NewReader(data))
	if e != nil {
		return e
	}
	request.Header.Set("accept", "application/json")
	if body != nil {
		request.Header.Set("content-type", "application/json")
	}
	if mode == "account" {
		if s.config.AccountToken == nil {
			return ErrLocalApproval
		}
		token, e := s.config.AccountToken(ctx)
		if e != nil {
			return e
		}
		request.Header.Set("authorization", "Bearer "+token)
	}
	if mode == "dpop" {
		token, e := s.online(ctx)
		if e != nil {
			return e
		}
		proof, e := signJWS(s.key, "dpop+jwt", map[string]any{"htu": s.origin + "/api/v1/rd" + path, "htm": method, "iat": time.Now().Unix(), "jti": randomID(), "ath": digest([]byte(token.Token)), "nonce": token.Nonce}, true)
		if e != nil {
			return e
		}
		request.Header.Set("authorization", "DPoP "+token.Token)
		request.Header.Set("DPoP", proof)
	}
	response, e := s.http.Do(request)
	if e != nil {
		return errors.New("remote host network request failed")
	}
	defer response.Body.Close()
	limit := 65536
	if path == "/server-keys" {
		limit = 262144
	}
	raw, e := io.ReadAll(io.LimitReader(response.Body, int64(limit+1)))
	if e != nil || len(raw) > limit {
		return errors.New("remote host response exceeds bound")
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		var failure struct {
			Code string `json:"error_code"`
		}
		_ = strictDecode(raw, &failure, false)
		if len(failure.Code) > 80 || strings.ContainsAny(failure.Code, "\r\n ") {
			failure.Code = "RD_REQUEST_FAILED"
		}
		return &APIError{response.StatusCode, failure.Code}
	}
	if result != nil {
		if target, ok := result.(*json.RawMessage); ok {
			if e = strictDecode(raw, new(any), false); e != nil {
				return e
			}
			*target = append((*target)[:0], raw...)
			return nil
		}
		return strictDecode(raw, result, false)
	}
	return nil
}
func (s *Service) online(ctx context.Context) (onlineToken, error) {
	s.tokenMu.Lock()
	defer s.tokenMu.Unlock()
	if s.token.Token != "" && time.Until(s.token.ExpiresAt) > 60*time.Second {
		return s.token, nil
	}
	d := s.config.Store.snapshot()
	if d.EndpointID == "" {
		return onlineToken{}, ErrLocalApproval
	}
	var challenge struct {
		ID      string          `json:"challenge_id"`
		Payload json.RawMessage `json:"proof_payload"`
	}
	if e := s.request(ctx, "POST", "/token-challenges", map[string]any{"endpoint_id": d.EndpointID, "purpose": "host_online"}, "", &challenge); e != nil {
		return onlineToken{}, e
	}
	var proofContext struct {
		Purpose    string `json:"purpose"`
		EndpointID string `json:"endpoint_id"`
		Instance   string `json:"server_instance_id"`
	}
	if e := strictDecode(challenge.Payload, &proofContext, false); e != nil {
		return onlineToken{}, e
	}
	keys, e := parseKeyset(d.Keyset)
	if e != nil || proofContext.Purpose != "host_online" || proofContext.EndpointID != d.EndpointID || proofContext.Instance != keys.ServerInstanceID {
		return onlineToken{}, ErrAuthorization
	}
	proof, e := signJWS(s.key, "ht-rd-proof+jwt", challenge.Payload, false)
	if e != nil {
		return onlineToken{}, e
	}
	var token onlineToken
	if e = s.request(ctx, "POST", "/tokens", map[string]any{"endpoint_id": d.EndpointID, "challenge_id": challenge.ID, "proof": proof}, "", &token); e != nil {
		return onlineToken{}, e
	}
	if token.Token == "" || len(token.Token) > 256 || len(token.Nonce) != 43 || time.Until(token.ExpiresAt) <= 0 || time.Until(token.ExpiresAt) > 11*time.Minute {
		return onlineToken{}, ErrAuthorization
	}
	s.token = token
	return token, nil
}

type Enrollment struct {
	LinkedDeviceID string
	Name           string
	Platform       string
	Password       string
	MFACode        string
}

func (s *Service) Enroll(ctx context.Context, options Enrollment) error {
	capabilities, e := s.config.Engine.Capabilities(ctx)
	if e != nil || !capabilities.Available || capabilities.Status != "ready" {
		return ErrUnavailable
	}
	if s.config.Store.snapshot().EndpointID != "" {
		return errors.New("remote host is already enrolled")
	}
	if s.config.InitialTrust == nil || options.LinkedDeviceID == "" {
		return ErrLocalApproval
	}
	reauth := map[string]any{"password": options.Password}
	if options.MFACode != "" {
		reauth["mfa_code"] = options.MFACode
	}
	var raw json.RawMessage
	if e = s.request(ctx, "GET", "/server-keys", nil, "", &raw); e != nil {
		return e
	}
	keys, e := parseKeyset(raw)
	if e != nil {
		return e
	}
	if e = verifyKeyset(keys, keys, time.Now()); e != nil {
		return e
	}
	if e = s.config.InitialTrust(ctx, s.origin, keys); e != nil {
		return e
	}
	public := jwk(&s.key.PublicKey)
	var challenge struct {
		ID      string          `json:"challenge_id"`
		Payload json.RawMessage `json:"proof_payload"`
	}
	challengeBody := map[string]any{"endpoint_kind": "desktop", "role": "host", "public_jwk": public, "linked_device_id": options.LinkedDeviceID}
	if e = s.request(ctx, "POST", "/enrollment-challenges", challengeBody, "account", &challenge); e != nil {
		var failure *APIError
		if !errors.As(e, &failure) || failure.Code != "RD_REAUTH_REQUIRED" {
			return e
		}
		if options.Password == "" {
			return ErrLocalApproval
		}
		if e = s.request(ctx, "POST", "/reauth", reauth, "account", nil); e != nil {
			return e
		}
		if e = s.request(ctx, "POST", "/enrollment-challenges", challengeBody, "account", &challenge); e != nil {
			return e
		}
	}
	var claim struct {
		Instance       string    `json:"server_instance_id"`
		Purpose        string    `json:"purpose"`
		PublicJWK      PublicJWK `json:"public_jwk"`
		Role           string    `json:"role"`
		Kind           string    `json:"endpoint_kind"`
		LinkedDeviceID string    `json:"linked_device_id"`
	}
	if e = strictDecode(challenge.Payload, &claim, false); e != nil || claim.Instance != keys.ServerInstanceID || claim.Purpose != "enrollment" || claim.PublicJWK.Thumbprint() != public.Thumbprint() || claim.Role != "host" || claim.Kind != "desktop" || claim.LinkedDeviceID != options.LinkedDeviceID {
		return ErrAuthorization
	}
	proof, e := signJWS(s.key, "ht-rd-proof+jwt", challenge.Payload, false)
	if e != nil {
		return e
	}
	var result struct {
		onlineToken
		Endpoint struct {
			ID    string `json:"id"`
			Owner string `json:"owner_user_id"`
			JKT   string `json:"jkt"`
		} `json:"endpoint"`
	}
	if e = s.request(ctx, "POST", "/endpoints", map[string]any{"challenge_id": challenge.ID, "signed_proof": proof, "name": options.Name, "platform": options.Platform}, "account", &result); e != nil {
		return e
	}
	if result.Endpoint.ID == "" || result.Endpoint.Owner == "" || result.Endpoint.JKT != public.Thumbprint() {
		return ErrAuthorization
	}
	if e = s.config.Store.update(func(d *diskState) error {
		d.Origin = s.origin
		d.EndpointID = result.Endpoint.ID
		d.OwnerUserID = result.Endpoint.Owner
		d.InitialTrust = append([]byte(nil), raw...)
		d.Keyset = append([]byte(nil), raw...)
		d.Enabled = false
		revokePersistentGrants(d)
		clear(d.AssistInvites)
		return nil
	}); e != nil {
		return e
	}
	s.tokenMu.Lock()
	s.token = result.onlineToken
	s.tokenMu.Unlock()
	return nil
}
func (s *Service) RefreshKeys(ctx context.Context) (bool, error) {
	d := s.config.Store.snapshot()
	old, e := parseKeyset(d.Keyset)
	if e != nil {
		return false, e
	}
	var raw json.RawMessage
	if e = s.request(ctx, "GET", "/server-keys", nil, "", &raw); e != nil {
		return false, e
	}
	next, e := parseKeyset(raw)
	if e != nil {
		return false, e
	}
	if e = verifyKeyset(old, next, time.Now()); e != nil {
		return false, e
	}
	changed := next.RestoreEpoch != old.RestoreEpoch
	e = s.config.Store.update(func(d *diskState) error {
		d.Keyset = raw
		if changed {
			d.Enabled = false
			revokePersistentGrants(d)
			clear(d.AssistInvites)
		}
		return nil
	})
	if changed {
		s.mu.Lock()
		s.disabled = true
		clear(s.assistInvites)
		s.mu.Unlock()
		_ = s.Stop(ctx, "RD_RESTORE_INVALIDATED")
		s.tokenMu.Lock()
		s.token = onlineToken{}
		s.tokenMu.Unlock()
	}
	return changed, e
}
func (s *Service) SetEnabled(ctx context.Context, enabled bool) error {
	s.mu.Lock()
	if !enabled {
		s.disabled = true
		clear(s.assistInvites)
	}
	generation := s.generation
	s.mu.Unlock()
	if !enabled {
		session, present, engineError := s.stopLocal(ctx, "RD_HOST_DISABLED")
		if e := s.config.Store.update(func(d *diskState) error {
			d.Enabled = false
			revokePersistentGrants(d)
			clear(d.AssistInvites)
			return nil
		}); e != nil {
			return errors.Join(engineError, e)
		}
		// Native shutdown and the durable disable both precede any HTTP wait.
		if present {
			_ = s.request(ctx, "POST", "/sessions/"+url.PathEscape(session.SessionID)+"/close", map[string]any{}, "dpop", nil)
		}
		if engineError != nil {
			return engineError
		}
	}
	// Serialize capability revisions, but never hold this lock while stopping capture.
	s.capabilityMu.Lock()
	defer s.capabilityMu.Unlock()
	if enabled {
		s.mu.Lock()
		stale := generation != s.generation
		s.mu.Unlock()
		if stale {
			return ErrLocalApproval
		}
	}
	caps, e := s.config.Engine.Capabilities(ctx)
	if enabled && (e != nil || !caps.Available || caps.Status != "ready") {
		return ErrUnavailable
	}
	d := s.config.Store.snapshot()
	if d.EndpointID == "" {
		return ErrLocalApproval
	}
	caps.UnattendedEnabled = caps.UnattendedEnabled && d.UnattendedEnabled
	wire := map[string]any{"permissions": caps.Permissions, "unattended_enabled": caps.UnattendedEnabled, "displays": caps.Displays, "codecs": caps.Codecs, "status": caps.Status}
	if !enabled {
		wire = map[string]any{"permissions": []string{"view"}, "unattended_enabled": false, "displays": []Display{}, "codecs": []string{}, "status": "unavailable"}
	}
	payload := map[string]any{"endpoint_id": d.EndpointID, "local_enabled": enabled, "capability_version": d.CapabilityVersion + 1, "capabilities": wire}
	proof, e := signJWS(s.key, "ht-rd-capabilities+jwt", payload, false)
	if e != nil {
		return e
	}
	delete(payload, "endpoint_id")
	payload["signed_proof"] = proof
	if e = s.request(ctx, "PUT", "/endpoints/"+url.PathEscape(d.EndpointID)+"/capabilities", payload, "dpop", nil); e != nil {
		return e
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	stale := enabled && generation != s.generation
	e = s.config.Store.update(func(next *diskState) error {
		next.Enabled = enabled && !stale
		next.CapabilityVersion = d.CapabilityVersion + 1
		return nil
	})
	if e == nil && enabled && !stale {
		s.disabled = false
	}
	if e == nil && stale {
		return ErrLocalApproval
	}
	return e
}
