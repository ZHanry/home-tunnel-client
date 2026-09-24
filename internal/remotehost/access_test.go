package remotehost

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestFixedPasswordRevisionIsDurableBeforeServerAcceptsCredential(t *testing.T) {
	service, _, _ := authorityFixture(t)
	service.running = true
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	profile := AccessProfile{DeviceID: "123456789", Revision: 1}
	service.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if request.URL.Path == "/api/v1/rd/access-profile" {
			return fixtureResponse(profile), nil
		}
		if request.URL.Path == "/api/v1/rd/access-profile/password" {
			if service.config.Store.snapshot().FixedRevision != 2 {
				t.Fatal("fixed credential became live before protected local revision")
			}
			return fixtureResponse(AccessProfile{DeviceID: "123456789", FixedPasswordEnabled: true, Revision: 2}), nil
		}
		t.Fatalf("unexpected path %s", request.URL.Path)
		return nil, nil
	})
	result, err := service.SetFixedPassword(context.Background(), "strong-password-2026")
	if err != nil || result.Revision != 2 || service.config.Store.snapshot().FixedRevision != 2 {
		t.Fatalf("fixed password was not enabled safely: %+v %v", result, err)
	}
	stored, _ := json.Marshal(service.config.Store.snapshot())
	if strings.Contains(string(stored), "strong-password-2026") {
		t.Fatal("password was persisted locally")
	}
}

func TestApprovedRequestIsActivatedOnlyAfterLocalTrust(t *testing.T) {
	service, _, _ := authorityFixture(t)
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	requestID, inviteID := randomID(), randomID()
	expires := time.Now().Add(5 * time.Minute)
	service.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		if strings.HasSuffix(request.URL.Path, "/decision") {
			if _, trusted := service.config.Store.snapshot().AssistInvites[inviteID]; trusted {
				t.Fatal("request was trusted before local decision response")
			}
			return fixtureResponse(AccessDecision{ID: requestID, State: "preparing", InviteID: inviteID, ExpiresAt: expires}), nil
		}
		if strings.HasSuffix(request.URL.Path, "/activate") {
			if _, trusted := service.config.Store.snapshot().AssistInvites[inviteID]; !trusted {
				t.Fatal("controller target was activated before local trust persisted")
			}
			return fixtureResponse(AccessDecision{ID: requestID, State: "approved"}), nil
		}
		t.Fatalf("unexpected path %s", request.URL.Path)
		return nil, nil
	})
	if err := service.DecideAccessRequest(context.Background(), requestID, true); err != nil {
		t.Fatal(err)
	}
}

func TestFixedInviteRequiresMatchingLocalPasswordRevision(t *testing.T) {
	service, _, _ := authorityFixture(t)
	service.token = onlineToken{Token: "fixture", Nonce: strings.Repeat("n", 43), ExpiresAt: time.Now().Add(time.Hour)}
	if err := service.config.Store.update(func(state *diskState) error { state.FixedRevision = 3; return nil }); err != nil {
		t.Fatal(err)
	}
	inviteID := randomID()
	service.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) {
		return fixtureResponse(map[string]any{"invite_id": inviteID, "access_kind": "fixed_password", "profile_revision": 2, "expires_at": time.Now().Add(5 * time.Minute)}), nil
	})
	if err := service.loadFixedAccessAuthorization(context.Background(), inviteID); err != nil {
		t.Fatal(err)
	}
	if _, trusted := service.config.Store.snapshot().FixedInvites[inviteID]; trusted {
		t.Fatal("stale password revision auto-approved a pairing")
	}
	if err := service.SetEmergencyKey("F12"); err != nil || service.State(context.Background()).EmergencyKey != "F12" {
		t.Fatal("emergency shortcut was not persisted")
	}
	if err := service.SetEmergencyKey("F11"); err == nil {
		t.Fatal("unsupported emergency shortcut accepted")
	}
}
