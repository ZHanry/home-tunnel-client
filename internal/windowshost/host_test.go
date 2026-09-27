package windowshost

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestIPCRejectsUnknownReplayAndForeignPath(t *testing.T) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	body := []byte(`{"controller_endpoint_id":"controller1","controller_thumbprint":"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"}`)
	frame, err := Marshal(key, Message{Type: TypeEnableUnattended, Counter: 1, Session: 4, Body: body})
	if err != nil {
		t.Fatal(err)
	}
	state := &ConnState{Expected: 1}
	message, err := ReadMessage(bytes.NewReader(frame), key, state)
	if err != nil || message.Type != TypeEnableUnattended || state.Expected != 2 {
		t.Fatalf("accepted frame failed: %v %+v", err, message)
	}
	if _, err = ReadMessage(bytes.NewReader(frame), key, state); !errors.Is(err, ErrRejected) {
		t.Fatal("replay was accepted")
	}
	frame[1] = 255
	macStart := len(frame) - 32
	copy(frame[macStart:], bytes.Repeat([]byte{1}, 32))
	if _, err = Marshal(key, Message{Type: 255, Counter: 2, Body: body}); !errors.Is(err, ErrRejected) {
		t.Fatal("execute-style type was encoded")
	}
	oversized, err := Marshal(key, Message{Type: TypeStatus, Counter: 2, Body: bytes.Repeat([]byte{1}, maxBody+1)})
	if err == nil || oversized != nil {
		t.Fatal("oversized body was encoded")
	}
	if !RejectedPath(`C:\Users\Public\home-tunnel-service.exe`, []string{`C:\Program Files\Home Tunnel\home-tunnel-service.exe`}) {
		t.Fatal("user-writable image was allowed")
	}
	if RejectedPath(`C:\Program Files\Home Tunnel\home-tunnel-service.exe`, []string{`C:\Program Files\Home Tunnel\home-tunnel-service.exe`}) {
		t.Fatal("packaged image was rejected")
	}
	var raw map[string]any
	if json.Unmarshal(body, &raw) != nil {
		t.Fatal(err)
	}
	if _, ok := raw["command"]; ok {
		t.Fatal("ipc body carries a command")
	}
}

func TestLifecycleReleasesInputAndSwitchesSession(t *testing.T) {
	var machine Machine
	if actions := machine.Apply(Event{Kind: EventStart}); len(actions) != 0 || machine.Phase != PhaseSignedOut {
		t.Fatalf("start launched work: %+v", actions)
	}
	actions := machine.Apply(Event{Kind: EventLogon, SessionID: 2, UserSID: "S-1-5-21-1"})
	if len(actions) != 1 || actions[0].Arg != "--session-agent" || actions[0].SessionID != 2 {
		t.Fatalf("logon launch: %+v", actions)
	}
	machine.Unattended = true
	machine.InputHeld = true
	actions = machine.Apply(Event{Kind: EventLock, SessionID: 2})
	if len(actions) < 2 || actions[0].Kind != ActionReleaseInput || actions[1].Kind != ActionStartSecureWorker || actions[1].Arg != "--host-inherited-pipe" {
		t.Fatalf("lock transition: %+v", actions)
	}
	machine.InputHeld = true
	actions = machine.Apply(Event{Kind: EventSwitch, SessionID: 3, UserSID: "S-1-5-21-2"})
	if actions[0].Kind != ActionReleaseInput || machine.Active != 3 || machine.UserSID != "S-1-5-21-2" {
		t.Fatalf("session switch: %+v state=%+v", actions, machine)
	}
	found := false
	for _, action := range actions {
		if action.Kind == ActionLaunchAgent && action.Arg != "--session-agent" {
			t.Fatalf("switch used a caller argument: %+v", action)
		}
		if action.Kind == ActionLaunchAgent {
			found = true
		}
	}
	if !found {
		t.Fatal("new session did not get the fixed agent")
	}
	machine.InputHeld = true
	actions = machine.Apply(Event{Kind: EventEmergency})
	if actions[0].Kind != ActionRevokeLocal || machine.Unattended || machine.Running {
		t.Fatalf("emergency did not revoke first: %+v %+v", actions, machine)
	}
}

func TestActionsRejectCallerCommands(t *testing.T) {
	var machine Machine
	machine.Apply(Event{Kind: EventStart})
	actions := machine.Apply(Event{Kind: EventLogon, SessionID: 4, UserSID: "S-1-5-21-4"})
	launched := []string{}
	if err := ExecuteActions(actions, func(arg string) error {
		launched = append(launched, arg)
		return nil
	}); err != nil || len(launched) != 1 || launched[0] != "--session-agent" {
		t.Fatalf("launch: %v %v", err, launched)
	}
	actions[0].Arg = "cmd.exe /c whoami"
	if err := ExecuteActions(actions, func(string) error { return nil }); !errors.Is(err, ErrRejected) {
		t.Fatal(err)
	}
}

func TestUnattendedEnableRequiresAdminAndExactIdentity(t *testing.T) {
	current := Record{Schema: 1, EndpointID: "host-endpoint"}
	if _, err := EnableUnattended(current, false, "controller1", strings.Repeat("a", 43), true); !errors.Is(err, ErrAdmin) {
		t.Fatal(err)
	}
	if _, err := EnableUnattended(current, true, "controller1", strings.Repeat("a", 43), false); !errors.Is(err, ErrUnavailable) {
		t.Fatal(err)
	}
	thumb := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"
	enabled, err := EnableUnattended(current, true, "controller1", thumb, true)
	if err != nil || !BindingMatches(enabled, "controller1", thumb) {
		t.Fatal(err, enabled)
	}
	if _, err = EnableUnattended(enabled, true, "controller2", thumb, true); !errors.Is(err, ErrIdentity) {
		t.Fatal("controller substitution was accepted")
	}
	disabled := DisableUnattended(enabled)
	if disabled.Unattended || disabled.ControllerEndpointID != "" || BindingMatches(disabled, "controller1", thumb) {
		t.Fatal("disable left the binding in place")
	}
}

func TestInstallPathsACLAndPortableFallback(t *testing.T) {
	portable, err := PlanInstall(Layout{Scope: "per-user", PreviousPerUser: true, ServiceRequested: true, ExePath: `C:\Users\Ada\AppData\Local\Home Tunnel\home-tunnel-service.exe`})
	if err != nil || portable.RegisterService || !portable.KeepPerUserProfile || portable.UnattendedEnabled {
		t.Fatalf("per-user install registered a service: %+v %v", portable, err)
	}
	if _, err = PlanInstall(Layout{Scope: "per-machine", ServiceRequested: true, ProgramFiles: `C:\Program Files`, ExePath: `C:\Program Files\Home Tunnel\other.exe`}); !errors.Is(err, ErrRejected) {
		t.Fatal("unexpected binary was accepted")
	}
	if _, err = PlanInstall(Layout{Scope: "per-machine", ServiceRequested: true, ProgramFiles: `C:\Users\Public`, ExePath: `C:\Users\Public\Home Tunnel\home-tunnel-service.exe`}); !errors.Is(err, ErrRejected) {
		t.Fatal("user-writable service path was accepted")
	}
	planned, err := PlanInstall(Layout{Scope: "per-machine", ServiceRequested: true, PreviousPerUser: true, ProgramFiles: `C:\Program Files`, ExePath: `C:\Program Files\Home Tunnel\home-tunnel-service.exe`})
	if err != nil || !planned.RegisterService || planned.UnattendedEnabled || !planned.KeepPerUserProfile || !planned.StopBeforeReplace {
		t.Fatalf("machine plan: %+v %v", planned, err)
	}
	if planned.QuotedPath != `"C:\Program Files\Home Tunnel\home-tunnel-service.exe"` || planned.DirectoryACL != StoreSDDL || planned.RemovedService != ServiceName || planned.RemovedStore != ProgramDataDir {
		t.Fatalf("path or cleanup scope: %+v", planned)
	}
	if _, err = QuoteServicePath(`C:\Program Files\Home Tunnel\home-tunnel-service.exe" -arg`); err == nil {
		t.Fatal("quoted injection was accepted")
	}
}

func TestNativeCapabilityComesFromWorkerProbe(t *testing.T) {
	if _, ok := NativeReport(Probe{Capture: true, SecureDesktop: true}); ok {
		t.Fatal("secure desktop was declared without a service worker")
	}
	report, ok := NativeReport(Probe{WorkerObserved: true, ServiceConnected: true, WorkerUnattended: true, Capture: true, Keyboard: true, Pointer: true, Text: true, SecureDesktop: true, SignedIn: false})
	if !ok || report.Reporter != "agent" || report.Backends["secure_desktop"] != "available" || report.Backends["system_audio"] != "unavailable" || report.Backends["clipboard"] != "unavailable" || report.Backends["files"] != "permission_required" && report.Backends["files"] != "unavailable" {
		t.Fatalf("probe report: %+v", report)
	}
	if report.Backends["files"] != "permission_required" && report.Backends["files"] != "unavailable" {
		t.Fatal(report.Backends["files"])
	}
	signedOut := report.Backends["files"]
	if signedOut == "available" {
		t.Fatal("sign-in desktop gained file authority")
	}
	user, ok := NativeReport(Probe{WorkerObserved: true, ServiceConnected: true, WorkerUnattended: true, Capture: true, SecureDesktop: false, UserContext: true, SignedIn: true})
	if !ok || user.Backends["files"] != "available" || user.Backends["clipboard"] != "available" || user.Backends["secure_desktop"] != "unavailable" {
		t.Fatalf("user context report: %+v", user.Backends)
	}
}

func TestRoutineEmergencyDoesNotRequireElevation(t *testing.T) {
	tray := Peer{Packaged: true, Interactive: true}
	if err := Authorize(tray, TypeEmergencyStop); err != nil {
		t.Fatal(err)
	}
	if err := Authorize(tray, TypeDisableUnattended); err != nil {
		t.Fatal(err)
	}
	if err := Authorize(tray, TypeEnableUnattended); !errors.Is(err, ErrAdmin) {
		t.Fatal(err)
	}
	if err := Authorize(Peer{Packaged: true, Elevated: true}, TypeEnableUnattended); err != nil {
		t.Fatal(err)
	}
	if err := Authorize(Peer{Interactive: true}, TypeEmergencyStop); !errors.Is(err, ErrRejected) {
		t.Fatal("unpackaged peer was accepted")
	}
	if _, err := WorkerDesktop(0, true); !errors.Is(err, ErrRejected) {
		t.Fatal("session 0 was treated as an interactive desktop")
	}
	desktop, err := WorkerDesktop(2, true)
	if err != nil || desktop != `WinSta0\Winlogon` {
		t.Fatal(desktop, err)
	}
}

func TestGrantRecordMatchesNativeLayout(t *testing.T) {
	encoded := EncodeGrant(2, 100000000)
	want := []byte{0x47, 0x44, 0x54, 0x48, 1, 0, 0, 0, 2, 0, 0, 0, 0x00, 0xE1, 0xF5, 0x05}
	if !bytes.Equal(encoded[:len(want)], want) || !GrantAccepts(encoded, 2, 99999999) || GrantAccepts(encoded, 2, 100000000) || GrantAccepts(encoded, 9, 1) {
		t.Fatalf("grant bytes: %x", encoded[:16])
	}
}
