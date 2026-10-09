package app

import (
	"context"
	"errors"
	"github.com/ZHanry/home-tunnel-client/internal/api"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
	"net/http"
	"strings"
)

// AdoptRegistration stores only a separately issued background device credential.
// The device login verifies the credential with the selected HTTPS service before committing it.
func AdoptRegistration(ctx context.Context, statePath, server, name string, registration model.DeviceRegistration, transport *http.Client) error {
	store := statepkg.Store{Path: statePath}
	state, err := store.Load()
	if err != nil {
		return err
	}
	if state.Enrolled() {
		return errors.New("existing device identity cannot be replaced")
	}
	if registration.DeviceID == "" || len(registration.DeviceCredential) < 32 || len(registration.DeviceCredential) > 256 {
		return errors.New("invalid background credential")
	}
	profile, err := api.Discover(ctx, server, transport)
	if err != nil {
		return err
	}
	client, err := api.New(profile.APIBaseURL, transport)
	if err != nil {
		return err
	}
	if _, err := client.DeviceLogin(ctx, registration.DeviceID, registration.DeviceCredential); err != nil {
		return err
	}
	state.Profile = profile
	state.DeviceID = registration.DeviceID
	state.DeviceCredential = registration.DeviceCredential
	state.DeviceName = strings.TrimSpace(name)
	state.AgentState = "Offline"
	state.AgentMessage = "registered; waiting for first sync"
	state.LastConfigVersion = 0
	state.SyncCapabilityVersion = 0
	state.AppliedConfigVersion = 0
	state.CachedConnections = nil
	state.LeaseExpiresAt = nil
	if err := ctx.Err(); err != nil {
		return err
	}
	return store.Save(state)
}
