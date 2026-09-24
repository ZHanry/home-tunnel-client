package remotehost

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"sync"
	"testing"
	"time"
)

func TestUnattendedRequiresAdminAndNativeSupport(t *testing.T) {
	service, _ := approvalFixture(t)
	requests := 0
	service.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) {
		requests++
		return fixtureResponse(nil), nil
	})
	if !errors.Is(service.SetUnattendedEnabled(context.Background(), true), ErrLocalApproval) {
		t.Fatal("unattended mode enabled without a local administrator check")
	}
	service.config.LocalAdminCheck = func(context.Context) error { return ErrLocalApproval }
	if !errors.Is(service.SetUnattendedEnabled(context.Background(), true), ErrLocalApproval) {
		t.Fatal("unattended mode enabled after administrator rejection")
	}
	service.config.LocalAdminCheck = func(context.Context) error { return nil }
	if !errors.Is(service.SetUnattendedEnabled(context.Background(), true), ErrUnavailable) {
		t.Fatal("unattended mode enabled without native service support")
	}
	if requests != 0 || service.config.Store.snapshot().UnattendedEnabled {
		t.Fatal("denied unattended setup changed local or server authority")
	}
}

func TestUnattendedGrantBindsControllerAndRevokesBeforeNetwork(t *testing.T) {
	service, running := approvalFixture(t)
	service.config.LocalAdminCheck = func(context.Context) error { return nil }
	service.config.Engine.(*fakeEngine).unattended = true
	grant := running.Grant
	grant.Mode = "persistent"
	grant.OneSessionRequestID = ""
	grant.SessionID = ""
	if err := service.config.Store.update(func(state *diskState) error {
		state.Grants[grant.ID] = grant
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	var updates []bool
	service.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		var body struct {
			Capabilities struct {
				UnattendedEnabled bool `json:"unattended_enabled"`
			} `json:"capabilities"`
		}
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			return nil, err
		}
		updates = append(updates, body.Capabilities.UnattendedEnabled)
		if len(updates) == 2 {
			state := service.config.Store.snapshot()
			if state.UnattendedEnabled || !state.Grants[grant.ID].Revoked {
				t.Error("network disable preceded durable local revocation")
			}
		}
		return fixtureResponse(nil), nil
	})
	if err := service.SetUnattendedEnabled(context.Background(), true); err != nil {
		t.Fatal(err)
	}
	session := running.Session
	if !canAutoApprove(grant, session, true) || canAutoApprove(grant, session, false) {
		t.Fatal("trusted controller did not follow the unattended local policy")
	}
	session.ControllerEndpointID = randomID()
	if canAutoApprove(grant, session, true) {
		t.Fatal("another controller inherited unattended access")
	}
	session = running.Session
	session.Permissions = []string{"view", "input.keyboard"}
	if canAutoApprove(grant, session, true) {
		t.Fatal("persistent grant widened its scope")
	}
	if err := service.SetUnattendedEnabled(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	if len(updates) != 2 || !updates[0] || updates[1] {
		t.Fatalf("wrong server capability revisions: %v", updates)
	}
	state := service.config.Store.snapshot()
	if state.UnattendedEnabled || !state.Grants[grant.ID].Revoked || state.Grants[grant.ID].Version != grant.Version+1 {
		t.Fatal("unattended authorization survived local revoke")
	}
	grant.Revoked = true
	grant.ExpiresAt = time.Now().Add(time.Minute)
	if canAutoApprove(grant, running.Session, true) {
		t.Fatal("revoked persistent grant auto-approved")
	}
}

func TestHostDisableWinsInFlightUnattendedEnable(t *testing.T) {
	service, _ := approvalFixture(t)
	service.config.LocalAdminCheck = func(context.Context) error { return nil }
	service.config.Engine.(*fakeEngine).unattended = true
	entered, release := make(chan struct{}), make(chan struct{})
	var mu sync.Mutex
	var revisions []int64
	service.http.Transport = fixtureTransport(func(request *http.Request) (*http.Response, error) {
		var body struct {
			Version      int64 `json:"capability_version"`
			Capabilities struct {
				UnattendedEnabled bool `json:"unattended_enabled"`
			} `json:"capabilities"`
		}
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			return nil, err
		}
		mu.Lock()
		revisions = append(revisions, body.Version)
		mu.Unlock()
		if body.Capabilities.UnattendedEnabled {
			close(entered)
			<-release
		}
		return fixtureResponse(nil), nil
	})
	enableResult := make(chan error, 1)
	go func() { enableResult <- service.SetUnattendedEnabled(context.Background(), true) }()
	<-entered
	disableResult := make(chan error, 1)
	go func() { disableResult <- service.SetEnabled(context.Background(), false) }()
	deadline := time.After(5 * time.Second)
	for {
		service.mu.Lock()
		disabled := service.disabled
		service.mu.Unlock()
		if disabled {
			break
		}
		select {
		case <-deadline:
			t.Fatal("host disable did not begin")
		default:
			time.Sleep(time.Millisecond)
		}
	}
	close(release)
	if !errors.Is(awaitResult(t, enableResult), ErrLocalApproval) || awaitResult(t, disableResult) != nil {
		t.Fatal("host disable did not win the unattended setup race")
	}
	state := service.config.Store.snapshot()
	if state.Enabled || state.UnattendedEnabled || state.CapabilityVersion != 2 {
		t.Fatal("disabled host retained unattended authority or lost the server revision")
	}
	mu.Lock()
	defer mu.Unlock()
	if len(revisions) != 2 || revisions[0] != 1 || revisions[1] != 2 {
		t.Fatalf("capability revisions were not monotonic: %v", revisions)
	}
}
