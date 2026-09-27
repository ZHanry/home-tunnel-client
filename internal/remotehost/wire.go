package remotehost

func validBindingID(value string) bool {
	if len(value) < 8 || len(value) > 128 {
		return false
	}
	for _, r := range value {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '-' && r != '_' {
			return false
		}
	}
	return true
}

func wireCapabilities(caps Capabilities, enabled, discovered bool) map[string]any {
	if !enabled {
		return map[string]any{"permissions": []string{"view"}, "unattended_enabled": false, "displays": []Display{}, "codecs": []string{}, "status": "unavailable"}
	}
	if discovered && caps.Native == nil {
		caps.Native = ordinaryNative(caps)
	}
	permissions := append([]string(nil), caps.Permissions...)
	var native any
	if discovered && caps.Native != nil && caps.Native.Schema == 1 && caps.Native.Reporter == "agent" {
		filtered := permissionsForNative(permissions, caps.Native.Backends)
		for _, permission := range filtered {
			if permission == "view" && caps.Native.Backends["capture"] == "available" {
				permissions = filtered
				native = caps.Native
				break
			}
		}
	}
	displays := make([]any, 0, len(caps.Displays))
	for _, display := range caps.Displays {
		item := map[string]any{"id": display.ID, "name": display.Name, "width": display.Width, "height": display.Height}
		if native != nil && display.DpiX > 0 && display.WidthPx == display.Width && display.HeightPx == display.Height && display.ScalePercent == (display.DpiX*100+48)/96 {
			item["slot"] = display.Slot
			item["width_px"] = display.WidthPx
			item["height_px"] = display.HeightPx
			item["dpi_x"] = display.DpiX
			item["dpi_y"] = display.DpiY
			item["scale_percent"] = display.ScalePercent
			item["origin_x"] = display.OriginX
			item["origin_y"] = display.OriginY
		}
		displays = append(displays, item)
	}
	wire := map[string]any{"permissions": permissions, "unattended_enabled": caps.UnattendedEnabled, "displays": displays, "codecs": caps.Codecs, "status": caps.Status}
	if native != nil {
		wire["native"] = native
	}
	return wire
}

func ordinaryNative(caps Capabilities) *NativeCapability {
	backends := map[string]string{
		"capture": "unavailable", "input_keyboard": "unavailable", "input_pointer": "unavailable", "input_text": "unavailable",
		"system_audio": "unavailable", "microphone": "unavailable", "clipboard": "unavailable", "files": "unavailable",
		"secure_desktop": "unavailable",
	}
	mark := func(permission, backend string) {
		for _, item := range caps.Permissions {
			if item == permission {
				backends[backend] = "available"
			}
		}
	}
	mark("view", "capture")
	mark("input.keyboard", "input_keyboard")
	mark("input.pointer", "input_pointer")
	mark("input.text", "input_text")
	mark("clipboard.read", "clipboard")
	mark("clipboard.write", "clipboard")
	mark("files.send", "files")
	mark("files.receive", "files")
	return &NativeCapability{Schema: 1, Reporter: "agent", Backends: backends}
}

func permissionsForNative(permissions []string, backends map[string]string) []string {
	required := map[string]string{
		"view": "capture", "input.keyboard": "input_keyboard", "input.pointer": "input_pointer", "input.text": "input_text",
		"audio.system": "system_audio", "audio.microphone": "microphone", "clipboard.read": "clipboard", "clipboard.write": "clipboard",
		"files.send": "files", "files.receive": "files",
	}
	kept := make([]string, 0, len(permissions))
	for _, permission := range permissions {
		if backends[required[permission]] == "available" {
			kept = append(kept, permission)
		}
	}
	if len(kept) == 0 {
		return []string{"view"}
	}
	return kept
}
