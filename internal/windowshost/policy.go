package windowshost

import (
	"errors"
	"unicode/utf8"
)

const (
	ServiceName    = "HomeTunnelHost"
	PipeName       = `\\.\pipe\HomeTunnelHost`
	GrantMapping   = `Local\HomeTunnelDesktopGrant`
	ProgramDataDir = `C:\ProgramData\Home Tunnel\service`
	ServiceSDDL    = "D:P(A;;GA;;;SY)(A;;GR;;;BA)"
	StoreSDDL      = "D:P(A;;FA;;;SY)(A;;FA;;;BA)"
	WorkerName     = "home_tunnel_remote_host.exe"
	ServiceBinary  = "home-tunnel-service.exe"
)

var (
	ErrNotInstalled = errors.New("windows service is not installed")
	ErrAdmin        = errors.New("local administrator approval is required")
	ErrIdentity     = errors.New("controller identity does not match the enrolled binding")
	ErrUnavailable  = errors.New("packaged service worker did not report unattended access")
	ErrRejected     = errors.New("windows host request was rejected")
)

type Record struct {
	Schema               int    `json:"schema"`
	EndpointID           string `json:"endpoint_id"`
	Origin               string `json:"origin"`
	ControllerEndpointID string `json:"controller_endpoint_id"`
	ControllerThumbprint string `json:"controller_thumbprint"`
	Unattended           bool   `json:"unattended"`
	SealedEndpointKey    []byte `json:"sealed_endpoint_key,omitempty"`
	InitialTrust         []byte `json:"initial_trust,omitempty"`
	Keyset               []byte `json:"keyset,omitempty"`
}

func ValidEndpointID(value string) bool {
	if len(value) < 8 || len(value) > 128 || !utf8.ValidString(value) {
		return false
	}
	for _, r := range value {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '-' && r != '_' {
			return false
		}
	}
	return true
}

func ValidThumbprint(value string) bool {
	if len(value) != 43 || !utf8.ValidString(value) {
		return false
	}
	for _, r := range value {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '-' && r != '_' {
			return false
		}
	}
	return true
}

// EnableUnattended persists the exact controller binding only after an
// administrator request and a packaged worker report. It never turns the
// policy on by itself when the report is false.
func EnableUnattended(current Record, admin bool, controllerID, thumbprint string, workerUnattended bool) (Record, error) {
	if !admin {
		return current, ErrAdmin
	}
	if !ValidEndpointID(controllerID) || !ValidThumbprint(thumbprint) || !ValidEndpointID(current.EndpointID) {
		return current, ErrIdentity
	}
	if current.Unattended && (current.ControllerEndpointID != controllerID || current.ControllerThumbprint != thumbprint) {
		return current, ErrIdentity
	}
	if !workerUnattended {
		return current, ErrUnavailable
	}
	next := current
	next.Schema = 1
	next.ControllerEndpointID = controllerID
	next.ControllerThumbprint = thumbprint
	next.Unattended = true
	return next, nil
}

// DisableUnattended clears the binding and the flag before the caller may
// touch the network. The returned record is the local authority.
func DisableUnattended(current Record) Record {
	next := current
	next.Unattended = false
	next.ControllerEndpointID = ""
	next.ControllerThumbprint = ""
	return next
}

func BindingMatches(record Record, controllerID, thumbprint string) bool {
	return record.Unattended && record.ControllerEndpointID == controllerID && record.ControllerThumbprint == thumbprint && ValidEndpointID(controllerID) && ValidThumbprint(thumbprint)
}
