package remotehost

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type memoryBackend struct {
	data []byte
	fail bool
}

func (b *memoryBackend) Load() ([]byte, error) { return append([]byte(nil), b.data...), nil }
func (b *memoryBackend) Save(value []byte) error {
	if b.fail {
		return errors.New("fixture storage failure")
	}
	b.data = append([]byte(nil), value...)
	return nil
}
func testStore(t *testing.T) *Store {
	t.Helper()
	s, e := openStore(&memoryBackend{})
	if e != nil {
		t.Fatal(e)
	}
	return s
}

type fakeEngine struct {
	mu         sync.Mutex
	available  bool
	unattended bool
	events     chan EngineEvent
	started    []StartRequest
	signals    []json.RawMessage
	closed     int
	proofs     [][]byte
}

func (e *fakeEngine) Capabilities(context.Context) (Capabilities, error) {
	if !e.available {
		return Capabilities{Status: "unavailable"}, ErrUnavailable
	}
	return Capabilities{Available: true, Permissions: []string{"view", "input.pointer"}, UnattendedEnabled: e.unattended, Displays: []Display{{ID: "display-1", Name: "Fixture", Width: 1920, Height: 1080}}, Codecs: []string{"H264"}, Status: "ready"}, nil
}
func (e *fakeEngine) PrepareSession(context.Context, SessionRef) (PreparedSession, error) {
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	raw, _ := json.Marshal(jwk(&key.PublicKey))
	return PreparedSession{EphemeralPublicJWK: raw, HostNonce: bytes.Repeat([]byte{7}, 32), DTLSFingerprintSHA256: strings.Repeat("AB", 32)}, nil
}
func (e *fakeEngine) Start(_ context.Context, r StartRequest) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.started = append(e.started, r)
	return nil
}
func (e *fakeEngine) OnSignal(_ context.Context, _ SessionRef, r json.RawMessage) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.signals = append(e.signals, append([]byte(nil), r...))
	return nil
}
func (e *fakeEngine) RespondProof(_ context.Context, _ SessionRef, _ string, p []byte) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.proofs = append(e.proofs, append([]byte(nil), p...))
	return nil
}
func (e *fakeEngine) Events() <-chan EngineEvent { return e.events }
func (e *fakeEngine) Close(context.Context, SessionRef, string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.closed++
	return nil
}
func newKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	key, e := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	return key
}
func fixtureKeyset(t *testing.T, key *ecdsa.PrivateKey) Keyset {
	t.Helper()
	now := time.Now().UTC().Truncate(time.Second)
	public := jwk(&key.PublicKey)
	return Keyset{ServerInstanceID: "11111111-1111-4111-8111-111111111111", RestoreEpoch: 1, KeysetVersion: 1, ActiveKid: public.Thumbprint(), Keys: []ServerKey{{Kid: public.Thumbprint(), Alg: "ES256", PublicJWK: public, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour)}}, RotationProofs: []string{}}
}
func TestStrictJSONAndProofs(t *testing.T) {
	for _, bad := range []string{`{"a":1,"a":2}`, `{"a":1,"\u0061":2}`, `{"a":9007199254740992}`, `{"a":1e999}`, `{} []`, "{\"a\":\"\xff\"}"} {
		if strictDecode([]byte(bad), new(any), false) == nil {
			t.Fatalf("accepted %q", bad)
		}
	}
	key := newKey(t)
	token, e := signJWS(key, "fixture", map[string]any{"hello": "world"}, true)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = verifyJWS(token, jwk(&key.PublicKey), "fixture"); e != nil {
		t.Fatal(e)
	}
	if _, e = verifyJWS(token, jwk(&newKey(t).PublicKey), "fixture"); e == nil {
		t.Fatal("key substitution accepted")
	}
	if _, e = verifyJWS(token, jwk(&key.PublicKey), "other"); e == nil {
		t.Fatal("type substitution accepted")
	}
}
func TestKeysetRotationAndRollback(t *testing.T) {
	oldKey := newKey(t)
	old := fixtureKeyset(t, oldKey)
	nextKey := newKey(t)
	next := fixtureKeyset(t, nextKey)
	next.KeysetVersion = 2
	issued := time.Now().UTC().Truncate(time.Second)
	proof, e := signJWS(oldKey, "ht-rd-keyset+jwt", map[string]any{"server_instance_id": old.ServerInstanceID, "from_version": 1, "to_version": 2, "from_kid": old.ActiveKid, "issued_at": issued.Format(time.RFC3339), "keyset": bodyOf(next)}, false)
	if e != nil {
		t.Fatal(e)
	}
	next.RotationProofs = []string{proof}
	if e = verifyKeyset(old, next, time.Now()); e != nil {
		t.Fatal(e)
	}
	if e = verifyKeyset(next, old, time.Now()); e == nil {
		t.Fatal("rollback accepted")
	}
	changed := next
	changed.ServerInstanceID = "foreign"
	if verifyKeyset(old, changed, time.Now()) == nil {
		t.Fatal("foreign instance accepted")
	}
	changed = next
	changed.RotationProofs = nil
	if verifyKeyset(old, changed, time.Now()) == nil {
		t.Fatal("unsigned rotation accepted")
	}
	changed = old
	changed.Keys = next.Keys
	changed.ActiveKid = next.ActiveKid
	if verifyKeyset(old, changed, time.Now()) == nil {
		t.Fatal("same-version replacement accepted")
	}
}
func TestProtectedStateIsAtomicAndRevocationSurvivesReload(t *testing.T) {
	backend := &memoryBackend{}
	store, e := openStore(backend)
	if e != nil {
		t.Fatal(e)
	}
	if e = store.update(func(d *diskState) error {
		d.Grants["grant"] = LocalGrant{ID: "grant", Version: 1, GrantJWS: "public-signed-proof"}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	if e = store.RevokeGrant("grant"); e != nil {
		t.Fatal(e)
	}
	reloaded, e := openStore(backend)
	if e != nil {
		t.Fatal(e)
	}
	if !reloaded.Grants()[0].Revoked || reloaded.Grants()[0].Version != 2 || reloaded.Grants()[0].GrantJWS != "" {
		t.Fatal("lost tombstone or exposed signed grant")
	}
	backend.fail = true
	if e = store.update(func(d *diskState) error { d.Enabled = true; return nil }); e == nil || store.snapshot().Enabled {
		t.Fatal("failed write changed authority")
	}
}
func TestUnavailableEngineNeverRegistersOrEnables(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { requests++ }))
	defer server.Close()
	service, e := New(Config{Origin: server.URL, Store: testStore(t), AllowInsecureLoopback: true})
	if e != nil {
		t.Fatal(e)
	}
	if !errors.Is(service.Enroll(context.Background(), Enrollment{LinkedDeviceID: randomID(), Password: "fixture"}), ErrUnavailable) {
		t.Fatal("unavailable engine enrolled")
	}
	if !errors.Is(service.SetEnabled(context.Background(), true), ErrUnavailable) {
		t.Fatal("unavailable engine enabled")
	}
	if requests != 0 || service.State(context.Background()).Capabilities.Available {
		t.Fatal("unavailable engine made authenticated traffic")
	}
}

func TestLoadSessionUsesUint32EpochAfterRepeatedDisplaySwitches(t *testing.T) {
	id, endpoint := randomID(), randomID()
	var epoch atomic.Int64
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/api/v1/rd/sessions/"+id || request.Header.Get("DPoP") == "" {
			t.Error("unexpected unauthenticated session request")
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(Session{ID: id, SessionRef: SessionRef{SessionID: id, ConnectionEpoch: epoch.Load()}, HostEndpointID: endpoint})
	}))
	defer server.Close()
	store := testStore(t)
	if err := store.update(func(value *diskState) error { value.EndpointID = endpoint; return nil }); err != nil {
		t.Fatal(err)
	}
	s, err := New(Config{Origin: server.URL, Store: store, AllowInsecureLoopback: true})
	if err != nil {
		t.Fatal(err)
	}
	s.token = onlineToken{Token: "local-test-token", Nonce: strings.Repeat("a", 43), ExpiresAt: time.Now().Add(time.Minute * 5)}
	for _, value := range []int64{1, 4, 5, 100, 0xffffffff} {
		epoch.Store(value)
		session, err := s.loadSession(context.Background(), id)
		if err != nil || session.ConnectionEpoch != value {
			t.Fatalf("valid display reconnect epoch %d rejected: %v", value, err)
		}
	}
	for _, value := range []int64{-1, 0, 0x100000000} {
		epoch.Store(value)
		if _, err := s.loadSession(context.Background(), id); !errors.Is(err, ErrAuthorization) {
			t.Fatalf("invalid epoch %d accepted: %v", value, err)
		}
	}
}
func authorityFixture(t *testing.T) (*Service, *runningSession, *ecdsa.PrivateKey) {
	t.Helper()
	store := testStore(t)
	serverKey := newKey(t)
	keys := fixtureKeyset(t, serverKey)
	keyset, _ := json.Marshal(keys)
	hostKey, _ := store.privateKey()
	host := jwk(&hostKey.PublicKey)
	controller := jwk(&newKey(t).PublicKey)
	hostRaw, _ := json.Marshal(host)
	controllerRaw, _ := json.Marshal(controller)
	grant := LocalGrant{ID: randomID(), ControllerEndpointID: randomID(), ControllerJKT: controller.Thumbprint(), Permissions: []string{"view"}, Mode: "one_session", OneSessionRequestID: randomID(), Version: 1, ExpiresAt: time.Now().Add(time.Hour)}
	_ = store.update(func(d *diskState) error {
		d.Origin = "https://console.example.com"
		d.EndpointID = randomID()
		d.OwnerUserID = randomID()
		d.InitialTrust = keyset
		d.Keyset = keyset
		d.Enabled = true
		d.Grants[grant.ID] = grant
		return nil
	})
	d := store.snapshot()
	service, e := New(Config{Origin: d.Origin, Store: store, Engine: &fakeEngine{available: true, events: make(chan EngineEvent, 8)}})
	if e != nil {
		t.Fatal(e)
	}
	session := Session{SessionRef: SessionRef{SessionID: randomID(), ConnectionEpoch: 1}, SessionRequestID: grant.OneSessionRequestID, HostEndpointID: d.EndpointID, ControllerEndpointID: grant.ControllerEndpointID, Permissions: []string{"view"}, HostPublicJWK: hostRaw, ControllerPublicJWK: controllerRaw, LeaseSeq: 1}
	session.ID = session.SessionID
	now := time.Now().Unix()
	claims := authority{Iss: d.Origin, Aud: "ht-rd-start", Instance: keys.ServerInstanceID, RestoreEpoch: 1, SessionID: session.SessionID, RequestID: session.SessionRequestID, Epoch: 1, Owner: d.OwnerUserID, Host: d.EndpointID, Controller: grant.ControllerEndpointID, HostJKT: host.Thumbprint(), ControllerJKT: controller.Thumbprint(), Permissions: []string{"view"}, GrantID: grant.ID, GrantVersion: 1, UserVersion: 1, Iat: now, Nbf: now, Exp: now + 60, JTI: randomID()}
	session.TicketJWS, _ = signJWS(serverKey, "ht-rd-ticket+jwt", claims, false)
	claims.Aud = "ht-rd-use"
	claims.Exp = now + 900
	claims.LeaseSeq = 1
	session.LeaseJWS, _ = signJWS(serverKey, "ht-rd-lease+jwt", claims, false)
	return service, &runningSession{Session: session, Grant: grant, PeerSeen: map[uint64]bool{}, Proofs: map[string]bool{}}, serverKey
}
func TestAuthorityBindsSingleRequestAndCannotWidenScopes(t *testing.T) {
	service, r, _ := authorityFixture(t)
	if e := service.checkAuthority(r); e != nil {
		t.Fatal(e)
	}
	if time.Until(r.Deadline) > 900*time.Second {
		t.Fatal("lease expanded")
	}
	r.Session.SessionRequestID = randomID()
	if service.checkAuthority(r) == nil {
		t.Fatal("single request substitution accepted")
	}
	r.Session.SessionRequestID = r.Grant.OneSessionRequestID
	r.Session.Permissions = append(r.Session.Permissions, "input.keyboard")
	if service.checkAuthority(r) == nil {
		t.Fatal("scope expansion accepted")
	}
}
func TestApprovePairingSignsTranscriptScopeOrder(t *testing.T) {
	service, _, _ := authorityFixture(t)
	state := service.config.Store.snapshot()
	controller := jwk(&newKey(t).PublicKey)
	expires := time.Now().UTC().Add(2 * time.Minute).Truncate(time.Millisecond)
	transcript := transcript{
		Domain: "ht-rd-pairing-v1", Instance: "11111111-1111-4111-8111-111111111111",
		PairingID: randomID(), HostID: state.EndpointID, ControllerID: randomID(),
		HostJKT: jwk(&service.key.PublicKey).Thumbprint(), ControllerJKT: controller.Thumbprint(),
		ControllerNonce: strings.Repeat("a", 43), Scope: []string{"view", "input.pointer"},
		Mode: "one_session", RequestID: randomID(), ExpiresAt: expires,
	}
	raw, err := json.Marshal(transcript)
	if err != nil {
		t.Fatal(err)
	}
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	var signedScope []string
	service.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if request.Method == http.MethodGet {
			return fixtureResponse(pairing{ID: transcript.PairingID, State: "pending", ExpiresAt: expires, Transcript: raw}), nil
		}
		var body struct {
			GrantJWS string `json:"grant_jws"`
		}
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		claims, err := verifyJWS(body.GrantJWS, jwk(&service.key.PublicKey), "ht-rd-grant+jwt")
		if err != nil {
			t.Fatal(err)
		}
		var grantClaims struct {
			Scope []string `json:"scope"`
		}
		if err := json.Unmarshal(claims, &grantClaims); err != nil {
			t.Fatal(err)
		}
		signedScope = grantClaims.Scope
		return fixtureResponse(nil), nil
	})
	if err := service.ApprovePairing(context.Background(), transcript.PairingID, []string{"input.pointer", "view"}, "one_session", time.Now().Add(10*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(signedScope, transcript.Scope) {
		t.Fatalf("grant scope order %v differs from transcript %v", signedScope, transcript.Scope)
	}
	grant := service.config.Store.snapshot().Grants[transcript.PairingID]
	if !slices.Equal(grant.Permissions, transcript.Scope) {
		t.Fatalf("local grant scope order %v differs from transcript %v", grant.Permissions, transcript.Scope)
	}
}
func TestAssistPairingRequiresHostAndGuestAccountBinding(t *testing.T) {
	service, _, _ := authorityFixture(t)
	state := service.config.Store.snapshot()
	controller := jwk(&newKey(t).PublicKey)
	expires := time.Now().UTC().Add(2 * time.Minute).Truncate(time.Millisecond)
	proof := transcript{
		Domain: "ht-rd-pairing-v1", Instance: "11111111-1111-4111-8111-111111111111",
		PairingID: randomID(), HostID: state.EndpointID, ControllerID: randomID(),
		AssistInviteID: randomID(), HostOwnerID: state.OwnerUserID, ControllerOwnerID: randomID(),
		HostJKT: jwk(&service.key.PublicKey).Thumbprint(), ControllerJKT: controller.Thumbprint(),
		ControllerNonce: strings.Repeat("a", 43), Scope: []string{"view"},
		Mode: "one_session", RequestID: randomID(), ExpiresAt: expires,
	}
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	service.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		raw, err := json.Marshal(proof)
		if err != nil {
			t.Fatal(err)
		}
		return fixtureResponse(pairing{ID: proof.PairingID, State: "pending", ExpiresAt: expires, Transcript: raw}), nil
	})
	if _, _, err := service.loadPairing(context.Background(), proof.PairingID); err != nil {
		t.Fatal(err)
	}
	proof.HostOwnerID = randomID()
	if _, _, err := service.loadPairing(context.Background(), proof.PairingID); err == nil {
		t.Fatal("foreign host owner accepted")
	}
	proof.HostOwnerID = state.OwnerUserID
	proof.ControllerOwnerID = state.OwnerUserID
	if _, _, err := service.loadPairing(context.Background(), proof.PairingID); err == nil {
		t.Fatal("same-account invitation accepted as cross-account assistance")
	}
	proof.ControllerOwnerID = randomID()
	proof.Mode = "persistent"
	if _, _, err := service.loadPairing(context.Background(), proof.PairingID); err == nil {
		t.Fatal("persistent cross-account invitation accepted")
	}
}
func TestAssistInviteAutoApprovalIncludesInputAndClipboardButNotFilesOrAudio(t *testing.T) {
	service, _, _ := authorityFixture(t)
	state := service.config.Store.snapshot()
	expires := time.Now().UTC().Add(time.Minute).Truncate(time.Millisecond)
	request := transcript{
		Domain: "ht-rd-pairing-v1", Instance: "11111111-1111-4111-8111-111111111111",
		PairingID: randomID(), HostID: state.EndpointID, ControllerID: randomID(),
		AssistInviteID: randomID(), HostOwnerID: state.OwnerUserID, ControllerOwnerID: randomID(),
		HostJKT: jwk(&service.key.PublicKey).Thumbprint(), ControllerJKT: jwk(&newKey(t).PublicKey).Thumbprint(),
		ControllerNonce: strings.Repeat("a", 43), Scope: []string{"view", "input.pointer"},
		Mode: "one_session", RequestID: randomID(), ExpiresAt: expires,
	}
	service.assistInvites[request.AssistInviteID] = expires
	if !canAutoApproveAssist(expires, request, time.Now()) {
		t.Fatal("locally generated assistance did not authorize standard permissions")
	}
	for _, permission := range []string{"clipboard.read", "clipboard.write"} {
		request.Scope = []string{"view", permission}
		if !canAutoApproveAssist(expires, request, time.Now()) {
			t.Fatalf("assistance did not authorize %s", permission)
		}
	}
	for _, permission := range []string{"files.send", "audio.system"} {
		request.Scope = []string{"view", permission}
		if canAutoApproveAssist(expires, request, time.Now()) {
			t.Fatalf("assistance silently authorized %s", permission)
		}
	}
	request.Scope = []string{"view", "input.pointer"}
	if canAutoApproveAssist(time.Now().Add(-time.Second), request, time.Now()) {
		t.Fatal("expired assistance auto-approved")
	}
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	service.http.Transport = fixtureTransport(func(httpRequest *http.Request) (*http.Response, error) {
		if httpRequest.Method == http.MethodGet {
			return fixtureResponse(pairing{ID: request.PairingID, State: "pending", ExpiresAt: expires, Transcript: raw}), nil
		}
		return fixtureResponse(nil), nil
	})
	event, _ := json.Marshal(map[string]any{"v": 1, "type": "pairing.updated", "payload": pairing{ID: request.PairingID, State: "pending"}})
	if err := service.handleServer(context.Background(), event); err != nil {
		t.Fatal(err)
	}
	select {
	case approval := <-service.Approvals():
		if approval.Kind != "pairing_display" || approval.ID != request.PairingID {
			t.Fatalf("unexpected assistance approval event: %+v", approval)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("locally generated assistance did not auto-approve")
	}
	grant := service.config.Store.snapshot().Grants[request.PairingID]
	if grant.AssistInviteID != request.AssistInviteID || !slices.Equal(grant.Permissions, request.Scope) {
		t.Fatal("automatic grant lost its invitation or permissions binding")
	}
}
func TestAssistInviteRevocationTombstonesLocalGrant(t *testing.T) {
	service, running, _ := authorityFixture(t)
	inviteID := randomID()
	if err := service.config.Store.update(func(state *diskState) error {
		grant := state.Grants[running.Grant.ID]
		grant.AssistInviteID = inviteID
		state.Grants[grant.ID] = grant
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	service.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) { return fixtureResponse(nil), nil })
	if err := service.RevokeAssistInvite(context.Background(), inviteID); err != nil {
		t.Fatal(err)
	}
	grant := service.config.Store.snapshot().Grants[running.Grant.ID]
	if !grant.Revoked || grant.Version != 2 || !service.assistRevoked[inviteID] {
		t.Fatal("revoking assistance did not persist its local grant tombstone")
	}
}
func TestOfflineHostCannotIssueAssistancePassword(t *testing.T) {
	service, _, _ := authorityFixture(t)
	service.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) {
		t.Fatal("offline host requested a temporary password")
		return fixtureResponse(nil), nil
	})
	if _, err := service.CreateAssistInvite(context.Background()); !errors.Is(err, ErrLocalApproval) {
		t.Fatalf("offline invitation was not blocked: %v", err)
	}
}
func TestAssistInvitationSurvivesRestartWithoutPersistingPassword(t *testing.T) {
	service, _, _ := authorityFixture(t)
	service.running = true
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	invite := AssistInvite{ID: randomID(), DeviceID: "123456789", TemporaryPassword: "ABcd2345EFgh", ExpiresAt: time.Now().Add(5 * time.Minute)}
	service.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) { return fixtureResponse(invite), nil })
	created, err := service.CreateAssistInvite(context.Background())
	if err != nil || created.ID != invite.ID {
		t.Fatalf("could not create locally authorized invitation: %v", err)
	}
	backend := service.config.Store.backend.(*memoryBackend)
	if bytes.Contains(backend.data, []byte(invite.TemporaryPassword)) {
		t.Fatal("temporary password was persisted")
	}
	restarted, err := New(service.config)
	if err != nil || !canAutoApproveAssist(restarted.assistInvites[invite.ID], transcript{AssistInviteID: invite.ID, Mode: "one_session", Scope: []string{"view"}}, time.Now()) {
		t.Fatal("protected invitation did not survive restart")
	}
	if err := service.RevokeAssistInvite(context.Background(), invite.ID); err != nil {
		t.Fatal(err)
	}
	restarted, err = New(service.config)
	if err != nil || !restarted.assistInvites[invite.ID].IsZero() {
		t.Fatal("revoked invitation survived restart")
	}
}
func TestSupersededInvitationCannotSurviveHostDisable(t *testing.T) {
	service, _, _ := authorityFixture(t)
	service.running = true
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	invite := AssistInvite{ID: randomID(), DeviceID: "123456789", TemporaryPassword: "ABcd2345EFgh", ExpiresAt: time.Now().Add(5 * time.Minute)}
	revoked := false
	service.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if request.Method == http.MethodDelete {
			revoked = true
			return fixtureResponse(nil), nil
		}
		service.mu.Lock()
		service.generation++
		service.mu.Unlock()
		return fixtureResponse(invite), nil
	})
	if _, err := service.CreateAssistInvite(context.Background()); !errors.Is(err, ErrLocalApproval) {
		t.Fatalf("superseded invitation was accepted: %v", err)
	}
	if !revoked || !service.config.Store.snapshot().AssistInvites[invite.ID].IsZero() {
		t.Fatal("superseded invitation was not revoked without local persistence")
	}
}
func TestPeerSigningIsBoundToNativeNonceAndSignedSDP(t *testing.T) {
	service, r, _ := authorityFixture(t)
	r.OfferJWS = "controller-signed-offer"
	r.AnswerJWS = "host-signed-answer"
	r.Prepared.HostNonce = bytes.Repeat([]byte{7}, 32)
	service.active = r
	var transcript bytes.Buffer
	prefix := func(value []byte) {
		_ = binary.Write(&transcript, binary.BigEndian, uint32(len(value)))
		transcript.Write(value)
	}
	prefix([]byte("ht-rd-proof-v1"))
	uuid, _ := hex.DecodeString(strings.ReplaceAll(r.Session.SessionID, "-", ""))
	prefix(uuid)
	_ = binary.Write(&transcript, binary.BigEndian, uint32(1))
	prefix(bytes.Repeat([]byte{3}, 32))
	prefix(r.Prepared.HostNonce)
	for _, v := range []string{r.OfferJWS, r.AnswerJWS, r.Session.TicketJWS} {
		h := sha256.Sum256([]byte(v))
		prefix(h[:])
	}
	event := EngineEvent{SessionRef: r.Session.SessionRef, Kind: "sign_peer_proof", RequestID: randomID(), Transcript: transcript.Bytes()}
	if e := service.signPeerProof(context.Background(), r, event); e != nil {
		t.Fatal(e)
	}
	if service.signPeerProof(context.Background(), r, event) == nil {
		t.Fatal("duplicate proof request accepted")
	}
	event.RequestID = randomID()
	event.Transcript = append([]byte(nil), event.Transcript...)
	event.Transcript[len(event.Transcript)-1] ^= 1
	if service.signPeerProof(context.Background(), r, event) == nil {
		t.Fatal("ticket transcript substitution accepted")
	}
}
func TestDirectSDPRequiresNativeFingerprintAndUDP(t *testing.T) {
	fingerprint := strings.Repeat("AB", 32)
	sdp := "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=fingerprint:sha-256 " + fingerprint + "\r\n"
	raw, _ := json.Marshal(map[string]string{"type": "answer", "sdp": sdp})
	if e := validateSignalPayload("peer.answer", raw, fingerprint); e != nil {
		t.Fatal(e)
	}
	if validateSignalPayload("peer.answer", raw, strings.Repeat("CD", 32)) == nil {
		t.Fatal("native fingerprint substitution accepted")
	}
	for _, candidate := range []string{"candidate:1 1 tcp 123 192.168.1.1 5000 typ host", "candidate:1 1 udp 123 127.0.0.1 5000 typ host", "candidate:1 1 udp 123 192.168.1.1 5000 typ relay"} {
		if directCandidate(candidate) {
			t.Fatalf("unsafe candidate accepted: %s", candidate)
		}
	}
	if !directCandidate("candidate:1 1 udp 123 192.168.1.2 5000 typ host") {
		t.Fatal("LAN UDP rejected")
	}
}
