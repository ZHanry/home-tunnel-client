// Package remotehost coordinates the explicitly enabled desktop host control plane.
// Native code remains responsible for independently verifying every authorization,
// binding the peer proof to its own ephemeral/DTLS state, and enforcing the lease.
package remotehost

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

var ErrUnavailable = errors.New("RD_BACKEND_UNAVAILABLE")
var ErrAuthorization = errors.New("RD_AUTHORIZATION_INVALID")
var ErrLocalApproval = errors.New("RD_LOCAL_APPROVAL_REQUIRED")

type Display struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}
type Capabilities struct {
	Available         bool      `json:"available"`
	Permissions       []string  `json:"permissions"`
	UnattendedEnabled bool      `json:"unattended_enabled"`
	Displays          []Display `json:"displays"`
	Codecs            []string  `json:"codecs"`
	Status            string    `json:"status"`
}
type SessionRef struct {
	SessionID       string `json:"session_id"`
	ConnectionEpoch int64  `json:"connection_epoch"`
}
type PreparedSession struct {
	EphemeralPublicJWK    json.RawMessage `json:"ephemeral_public_jwk"`
	DTLSFingerprintSHA256 string          `json:"dtls_fingerprint_sha256"`
	HostNonce             []byte          `json:"host_nonce"`
}
type StartRequest struct {
	SessionRef
	DisplayID            string          `json:"display_id"`
	STUNURLs             []string        `json:"stun_urls"`
	SessionRequestID     string          `json:"session_request_id"`
	GrantID              string          `json:"grant_id"`
	GrantVersion         int64           `json:"grant_version"`
	RestoreEpoch         int64           `json:"restore_epoch"`
	UserTokenVersion     int64           `json:"user_token_version"`
	Origin               string          `json:"origin"`
	OwnerUserID          string          `json:"owner_user_id"`
	HostEndpointID       string          `json:"host_endpoint_id"`
	ControllerEndpointID string          `json:"controller_endpoint_id"`
	HostPublicJWK        json.RawMessage `json:"host_public_jwk"`
	ControllerPublicJWK  json.RawMessage `json:"controller_public_jwk"`
	TicketJWS            string          `json:"ticket_jws"`
	LeaseJWS             string          `json:"lease_jws"`
	GrantJWS             string          `json:"grant_jws"`
	InitialTrustPin      json.RawMessage `json:"initial_trust_pin"`
	ServerKeyset         json.RawMessage `json:"server_keyset"`
	LocalPermissions     []string        `json:"local_permissions"`
	LocalGrantRevoked    bool            `json:"local_grant_revoked"`
	Prepared             PreparedSession `json:"prepared"`
}
type EngineEvent struct {
	SessionRef
	// outgoing_signal payload is {type:"answer",sdp:...} or the fixed candidates object.
	// sign_peer_proof carries the exact bounded ht-rd-proof-v1 binary transcript.
	// verified_ready may be emitted only after native signature and selected-path checks.
	Kind       string          `json:"kind"`
	RequestID  string          `json:"request_id,omitempty"`
	SignalType string          `json:"signal_type,omitempty"`
	Payload    json.RawMessage `json:"payload,omitempty"`
	Transcript []byte          `json:"transcript,omitempty"`
	ErrorCode  string          `json:"error_code,omitempty"`
}
type HostEngine interface {
	Capabilities(context.Context) (Capabilities, error)
	PrepareSession(context.Context, SessionRef) (PreparedSession, error)
	Start(context.Context, StartRequest) error
	OnSignal(context.Context, SessionRef, json.RawMessage) error
	RespondProof(context.Context, SessionRef, string, []byte) error
	Events() <-chan EngineEvent
	Close(context.Context, SessionRef, string) error
}
type UnavailableEngine struct{}

func (UnavailableEngine) Capabilities(context.Context) (Capabilities, error) {
	return Capabilities{Status: "unavailable"}, ErrUnavailable
}
func (UnavailableEngine) PrepareSession(context.Context, SessionRef) (PreparedSession, error) {
	return PreparedSession{}, ErrUnavailable
}
func (UnavailableEngine) Start(context.Context, StartRequest) error { return ErrUnavailable }
func (UnavailableEngine) OnSignal(context.Context, SessionRef, json.RawMessage) error {
	return ErrUnavailable
}
func (UnavailableEngine) RespondProof(context.Context, SessionRef, string, []byte) error {
	return ErrUnavailable
}
func (UnavailableEngine) Events() <-chan EngineEvent                      { return nil }
func (UnavailableEngine) Close(context.Context, SessionRef, string) error { return nil }

type ApprovalEvent struct {
	ConnectionEpoch      int64     `json:"connection_epoch,omitempty"`
	StateVersion         int64     `json:"state_version,omitempty"`
	Kind                 string    `json:"kind"`
	ID                   string    `json:"id"`
	ControllerEndpointID string    `json:"controller_endpoint_id"`
	ControllerThumbprint string    `json:"controller_thumbprint"`
	Permissions          []string  `json:"permissions"`
	Mode                 string    `json:"mode"`
	DisplayCode          string    `json:"display_code"`
	ExpiresAt            time.Time `json:"expires_at"`
}
type LocalGrant struct {
	ID                   string    `json:"id"`
	ControllerEndpointID string    `json:"controller_endpoint_id"`
	ControllerJKT        string    `json:"controller_jkt"`
	Permissions          []string  `json:"permissions"`
	Mode                 string    `json:"mode"`
	OneSessionRequestID  string    `json:"one_session_request_id"`
	SessionID            string    `json:"session_id"`
	Version              int64     `json:"grant_version"`
	ExpiresAt            time.Time `json:"expires_at"`
	Revoked              bool      `json:"revoked"`
	GrantJWS             string    `json:"grant_jws"`
}
type Session struct {
	SessionRef
	DisplayID            string          `json:"display_id"`
	SessionRequestID     string          `json:"session_request_id"`
	ID                   string          `json:"id"`
	State                string          `json:"state"`
	StateVersion         int64           `json:"state_version"`
	HostEndpointID       string          `json:"host_endpoint_id"`
	ControllerEndpointID string          `json:"controller_endpoint_id"`
	Permissions          []string        `json:"permissions"`
	TicketJWS            string          `json:"ticket_jws"`
	LeaseJWS             string          `json:"lease_jws"`
	GrantJWS             string          `json:"grant_jws"`
	HostPublicJWK        json.RawMessage `json:"host_public_jwk"`
	ControllerPublicJWK  json.RawMessage `json:"controller_public_jwk"`
	LeaseSeq             int64           `json:"lease_seq"`
	ApprovalExpiresAt    time.Time       `json:"approval_expires_at"`
	LeaseExpiresAt       time.Time       `json:"lease_expires_at"`
}
