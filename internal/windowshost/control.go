package windowshost

import (
	"encoding/json"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

type ControlRequest struct {
	Version      int             `json:"version"`
	Operation    string          `json:"operation"`
	Origin       string          `json:"origin,omitempty"`
	DeviceID     string          `json:"device_id,omitempty"`
	State        json.RawMessage `json:"state,omitempty"`
	ControllerID string          `json:"controller_endpoint_id,omitempty"`
	Thumbprint   string          `json:"controller_thumbprint,omitempty"`
	Action       *RemoteAction   `json:"action,omitempty"`
	File         *FileAction     `json:"file,omitempty"`
}
type ControlResponse struct {
	Version int                       `json:"version"`
	Error   string                    `json:"error,omitempty"`
	Surface Surface                   `json:"surface"`
	State   *remotehost.Status        `json:"state,omitempty"`
	Managed bool                      `json:"managed"`
	Invite  *remotehost.AssistInvite  `json:"invite,omitempty"`
	Profile *remotehost.AccessProfile `json:"profile,omitempty"`
	Valid   bool                      `json:"valid,omitempty"`
}

// Mirrors the GUI's existing local action schema. It contains no executable,
// command line, native handle, environment or filesystem path.
type RemoteAction struct {
	Action               string   `json:"action"`
	Username             string   `json:"username"`
	Password             string   `json:"password"`
	TrustPin             string   `json:"trust_pin"`
	ID                   string   `json:"id"`
	Kind                 string   `json:"kind"`
	Mode                 string   `json:"mode"`
	Permissions          []string `json:"permissions"`
	FixedPassword        string   `json:"fixed_password"`
	ControllerEndpointID string   `json:"controller_endpoint_id"`
	ControllerThumbprint string   `json:"controller_thumbprint"`
	EmergencyKey         string   `json:"emergency_key"`
	ConnectionEpoch      int64    `json:"connection_epoch"`
	StateVersion         int64    `json:"state_version"`
}

// File paths are produced only by the native picker in the authenticated GUI,
// never decoded from its HTTP/browser request.
type FileAction struct {
	remotehost.SessionRef
	Action      string   `json:"action"`
	ID          string   `json:"id"`
	Paths       []string `json:"paths,omitempty"`
	Destination string   `json:"destination,omitempty"`
}
