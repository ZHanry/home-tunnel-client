package desktop

import (
	_ "embed"
	"encoding/json"
	"errors"
	"regexp"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/origin"
)

var remoteWindowID = regexp.MustCompile(`^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$`)
var remoteHandoffCode = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)

//go:embed remote_handoff.js
var nativeRemoteBootstrap string

// Execute before the server app boots. The one-time code stays in a closure,
// is posted only to the exact trusted HTTPS origin, and never enters navigation,
// storage, logs, global bridge methods or a redirected/subframe document.
func remoteHandoffScript(launch model.RemoteWindowLaunch) (string, error) {
	address, err := origin.HTTPS(launch.URL)
	if err != nil || address.Scheme != "https" || address.Host == "" || address.User != nil || address.Opaque != "" || address.Path != "/admin" || address.RawPath != "" || !remoteHandoffCode.MatchString(launch.HandoffCode) || !remoteWindowID.MatchString(launch.WindowID) {
		return "", errors.New("invalid remote handoff")
	}
	payload, err := json.Marshal(map[string]string{"origin": address.Scheme + "://" + address.Host, "url": address.String(), "code": launch.HandoffCode, "window_id": launch.WindowID})
	if err != nil {
		return "", errors.New("invalid remote handoff")
	}
	return nativeRemoteBootstrap + "(" + string(payload) + ");", nil
}
