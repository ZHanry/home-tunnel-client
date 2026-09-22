//go:build windows && remote_native_e2e

// This opt-in executable connects the real Go host service to its pinned native
// engine. It only approves view requests from one isolated test controller.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/remoteengine"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

type configuration struct {
	Origin           string `json:"origin"`
	AccountToken     string `json:"account_token"`
	DeviceID         string `json:"device_id"`
	ServerInstanceID string `json:"server_instance_id"`
	ActiveKid        string `json:"active_kid"`
	StorePath        string `json:"store_path"`
	Worker           string `json:"worker"`
	SHA256           string `json:"sha256"`
}

type command struct {
	ID            int64  `json:"id"`
	Action        string `json:"action"`
	TargetID      string `json:"target_id"`
	ControllerID  string `json:"controller_id"`
	ControllerJKT string `json:"controller_jkt"`
}

var outputMu sync.Mutex

func emit(value any) {
	outputMu.Lock()
	defer outputMu.Unlock()
	raw, _ := json.Marshal(value)
	fmt.Printf("HT_NATIVE %s\n", raw)
}

func main() {
	if err := run(); err != nil {
		// Arbitrary errors may contain protocol content; expose only an opaque code.
		emit(map[string]any{"event": "fatal", "code": "RD_NATIVE_HOST_FAILED"})
		os.Exit(1)
	}
}

func run() error {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 65536)
	if !scanner.Scan() {
		return errors.New("missing private configuration")
	}
	var initial configuration
	if err := json.Unmarshal(scanner.Bytes(), &initial); err != nil {
		return err
	}
	origin, err := url.Parse(initial.Origin)
	if err != nil || origin.Scheme != "http" || origin.Hostname() != "127.0.0.1" || origin.Port() == "" || origin.User != nil || origin.RawQuery != "" || origin.Fragment != "" || origin.Path != "" || !filepath.IsAbs(initial.StorePath) {
		return errors.New("fixture must be isolated IPv4 loopback")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	engine, err := remoteengine.New(ctx, remoteengine.Options{ExecutablePath: initial.Worker, ExpectedSHA256: initial.SHA256})
	if err != nil {
		emit(map[string]any{"event": "unavailable", "code": "RD_BACKEND_UNAVAILABLE"})
		return err
	}
	defer engine.Shutdown()
	caps, err := engine.Capabilities(ctx)
	if err != nil || !caps.Available || caps.Status != "ready" || len(caps.Displays) == 0 {
		emit(map[string]any{"event": "unavailable", "code": "RD_BACKEND_UNAVAILABLE"})
		return remotehost.ErrUnavailable
	}
	store, err := remotehost.OpenStore(initial.StorePath)
	if err != nil {
		return err
	}
	service, err := remotehost.New(remotehost.Config{
		Origin: initial.Origin, Store: store, Engine: engine, AllowInsecureLoopback: true,
		AccountToken: func(context.Context) (string, error) { return initial.AccountToken, nil },
		InitialTrust: func(_ context.Context, actual string, keys remotehost.Keyset) error {
			if actual != initial.Origin || keys.ServerInstanceID != initial.ServerInstanceID || keys.ActiveKid != initial.ActiveKid {
				return remotehost.ErrAuthorization
			}
			return nil
		},
	})
	if err != nil {
		return err
	}
	defer func() {
		stop, release := context.WithTimeout(context.Background(), 5*time.Second)
		defer release()
		_ = service.SetEnabled(stop, false)
	}()
	if err = service.Enroll(ctx, remotehost.Enrollment{LinkedDeviceID: initial.DeviceID, Name: "Native acceptance host", Platform: "windows"}); err != nil {
		return err
	}
	if err = service.SetEnabled(ctx, true); err != nil {
		return err
	}
	var approvalMu sync.Mutex
	approvals := map[string]remotehost.ApprovalEvent{}
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case event := <-service.Approvals():
				approvalMu.Lock()
				approvals[event.ID] = event
				approvalMu.Unlock()
				emit(map[string]any{"event": "approval", "approval": event})
			}
		}
	}()
	go func() {
		if service.Run(ctx) != nil && ctx.Err() == nil {
			emit(map[string]any{"event": "fatal", "code": "RD_NATIVE_HOST_SIGNAL_FAILED"})
		}
	}()
	state := service.State(ctx)
	emit(map[string]any{"event": "host", "endpoint_id": state.EndpointID, "capabilities": caps})
	var controllerID, controllerJKT string
	for scanner.Scan() {
		var request command
		if json.Unmarshal(scanner.Bytes(), &request) != nil || request.ID < 1 {
			return errors.New("invalid command")
		}
		var operation error
		switch request.Action {
		case "bind_controller":
			if controllerID != "" || len(request.ControllerID) != 36 || len(request.ControllerJKT) != 43 {
				operation = remotehost.ErrLocalApproval
			} else {
				controllerID, controllerJKT = request.ControllerID, request.ControllerJKT
			}
		case "approve_pairing", "approve_session":
			approvalMu.Lock()
			approval, exists := approvals[request.TargetID]
			approvalMu.Unlock()
			if !exists || controllerID == "" || approval.ControllerEndpointID != controllerID || approval.ControllerThumbprint != controllerJKT || len(approval.Permissions) != 1 || approval.Permissions[0] != "view" || approval.Mode != "one_session" || !approval.ExpiresAt.After(time.Now()) {
				operation = remotehost.ErrLocalApproval
			} else if request.Action == "approve_pairing" && approval.Kind == "pairing" {
				operation = service.ApprovePairing(ctx, approval.ID, []string{"view"}, "one_session", time.Now().Add(3*time.Minute))
			} else if request.Action == "approve_session" && approval.Kind == "session" {
				operation = service.ApproveSessionExpected(ctx, approval.ID, approval.ConnectionEpoch, approval.StateVersion)
			} else {
				operation = remotehost.ErrLocalApproval
			}
		case "shutdown":
			emit(map[string]any{"id": request.ID, "ok": true})
			return nil
		default:
			operation = errors.New("unknown action")
		}
		result := map[string]any{"id": request.ID, "ok": operation == nil}
		if operation != nil {
			result["code"] = "RD_NATIVE_E2E_ACTION_FAILED"
		}
		emit(result)
	}
	return scanner.Err()
}
