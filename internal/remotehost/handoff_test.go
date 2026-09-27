package remotehost

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"
)

func TestServiceTransferPreservesIdentityAndRevocations(t *testing.T) {
	service, running := approvalFixture(t)
	grant := running.Grant
	grant.Mode = "persistent"
	service.config.Store.update(func(data *diskState) error { data.Grants[grant.ID] = grant; return nil })
	before := service.config.Store.snapshot()
	service.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) { return fixtureResponse(nil), nil })
	raw, err := service.ExportForService(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if err = ValidateServiceTransfer(raw, service.origin); err != nil {
		t.Fatal(err)
	}
	after := service.config.Store.snapshot()
	if after.KeyPKCS8 != before.KeyPKCS8 || after.EndpointID != before.EndpointID || !after.ServiceManaged ||
		after.Enabled || after.UnattendedEnabled || !after.Grants[grant.ID].Revoked {
		t.Fatal("handoff changed identity or retained active authority")
	}
	if _, err = New(service.config); !errors.Is(err, ErrServiceManaged) {
		t.Fatal("tray reopened a service-owned endpoint", err)
	}
	backend := &memoryBackend{data: raw}
	imported, err := OpenStoreWith(backend)
	if err != nil {
		t.Fatal(err)
	}
	if imported.snapshot().Grants[grant.ID].Version != before.Grants[grant.ID].Version+1 {
		t.Fatal("local revocation tombstone lost")
	}
	if _, err = New(Config{Origin: service.origin, Store: imported, ServiceOwned: true}); err != nil {
		t.Fatal(err)
	}
	if err = ValidateServiceTransfer(raw, "https://foreign.example"); err == nil {
		t.Fatal("cross-server transfer accepted")
	}
	after.Enabled = true
	forged, _ := json.Marshal(after)
	if ValidateServiceTransfer(forged, service.origin) == nil {
		t.Fatal("active tray identity accepted for import")
	}
}

func TestLocalEmergencyWinsInflightEnable(t *testing.T) {
	service, _ := approvalFixture(t)
	entered, release := make(chan struct{}), make(chan struct{})
	service.http.Transport = fixtureTransport(func(*http.Request) (*http.Response, error) {
		close(entered)
		<-release
		return fixtureResponse(nil), nil
	})
	result := make(chan error, 1)
	go func() { result <- service.SetEnabled(context.Background(), true) }()
	<-entered
	if err := service.DisableLocally(context.Background()); err != nil {
		t.Fatal(err)
	}
	close(release)
	if err := awaitResult(t, result); !errors.Is(err, ErrLocalApproval) {
		t.Fatal("in-flight enable survived emergency", err)
	}
	if service.config.Store.snapshot().Enabled {
		t.Fatal("emergency was not durable")
	}
}
