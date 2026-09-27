package remotehost

import "testing"

func TestDiscoveredPortableReportKeepsFilesAndRefusesSecureDesktop(t *testing.T) {
	caps := Capabilities{Available: true, Status: "ready", Permissions: []string{"view", "input.pointer", "clipboard.read", "files.send", "files.receive"}, Displays: []Display{{ID: "display-1", Name: "Desk", Width: 1920, Height: 1080, DpiX: 144, WidthPx: 1920, HeightPx: 1080, ScalePercent: 150}}, Codecs: []string{"H264"}}
	legacy := wireCapabilities(caps, true, false)
	if _, ok := legacy["native"]; ok {
		t.Fatal("v9 wire gained a native object")
	}
	wire := wireCapabilities(caps, true, true)
	native, ok := wire["native"].(*NativeCapability)
	if !ok || native.Reporter != "agent" || native.Backends["files"] != "available" || native.Backends["clipboard"] != "available" || native.Backends["secure_desktop"] != "unavailable" || native.Backends["system_audio"] != "unavailable" {
		t.Fatalf("portable native report: %#v", wire["native"])
	}
	permissions, _ := wire["permissions"].([]string)
	foundFile := false
	for _, permission := range permissions {
		if permission == "files.send" || permission == "files.receive" {
			foundFile = true
		}
		if permission == "audio.system" {
			t.Fatal("audio permission was invented")
		}
	}
	if !foundFile {
		t.Fatal("file scope was dropped for a discovered portable host")
	}
	displays, _ := wire["displays"].([]any)
	if len(displays) != 1 {
		t.Fatal(displays)
	}
	item := displays[0].(map[string]any)
	if item["scale_percent"] != 150 || item["width_px"] != 1920 {
		t.Fatalf("dpi fields: %#v", item)
	}
}
