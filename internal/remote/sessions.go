package remote

import (
	"errors"
	"sync"
)

// SessionRuntime belongs to a single native window/session. ReleaseInput affects only
// that session's injected keys; it must never synthesize releases for local user input.
type SessionRuntime interface {
	ReleaseInput()
	Close()
}

type SessionIdentity struct {
	SessionID, ServerInstanceID, UserID, HostEndpointID string
}

type ManagedSession struct {
	Identity SessionIdentity
	Runtime  SessionRuntime
}

type SessionManager struct {
	mu         sync.Mutex
	sessions   map[string]ManagedSession
	serverID   string
	userID     string
	focused    string
	microphone string
	clipboard  string
}

func NewSessionManager() *SessionManager {
	return &SessionManager{sessions: make(map[string]ManagedSession)}
}

// Attach runs after native authentication. It does not establish authority or enable input.
func (manager *SessionManager) Attach(session ManagedSession) error {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	id := session.Identity
	if session.Runtime == nil || id.SessionID == "" || id.ServerInstanceID == "" || id.UserID == "" || id.HostEndpointID == "" {
		return errors.New("incomplete remote session identity")
	}
	if _, exists := manager.sessions[id.SessionID]; exists {
		return errors.New("remote session already attached")
	}
	if len(manager.sessions) >= MaxControllerSessions {
		return errors.New("RD_QUOTA_EXCEEDED")
	}
	if len(manager.sessions) > 0 && (manager.serverID != id.ServerInstanceID || manager.userID != id.UserID) {
		return errors.New("remote sessions cannot cross server/account boundaries")
	}
	for _, current := range manager.sessions {
		if current.Identity.HostEndpointID == id.HostEndpointID {
			return errors.New("remote host already has a window")
		}
	}
	manager.serverID, manager.userID = id.ServerInstanceID, id.UserID
	manager.sessions[id.SessionID] = session
	return nil
}

func (manager *SessionManager) Focus(id string) error {
	manager.mu.Lock()
	if id != "" {
		if _, exists := manager.sessions[id]; !exists {
			manager.mu.Unlock()
			return errors.New("unknown remote window")
		}
	}
	previous, exists := manager.sessions[manager.focused]
	changed := id != manager.focused
	manager.focused = id
	manager.mu.Unlock()
	if exists && changed {
		previous.Runtime.ReleaseInput()
	}
	return nil
}

// BindPeripheral records an explicit UI choice; focus changes never move private
// microphone/clipboard data to another machine. Feature grants are enforced natively.
func (manager *SessionManager) BindPeripheral(kind, id string) error {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	if id != "" {
		if _, exists := manager.sessions[id]; !exists {
			return errors.New("unknown remote session")
		}
	}
	switch kind {
	case "microphone":
		manager.microphone = id
	case "clipboard":
		manager.clipboard = id
	default:
		return errors.New("unknown peripheral")
	}
	return nil
}

func (manager *SessionManager) Close(id string) {
	manager.mu.Lock()
	session, exists := manager.sessions[id]
	delete(manager.sessions, id)
	if manager.focused == id {
		manager.focused = ""
	}
	if manager.microphone == id {
		manager.microphone = ""
	}
	if manager.clipboard == id {
		manager.clipboard = ""
	}
	if len(manager.sessions) == 0 {
		manager.serverID, manager.userID = "", ""
	}
	manager.mu.Unlock()
	if exists {
		session.Runtime.ReleaseInput()
		session.Runtime.Close()
	}
}

// RevokeAll detaches atomically before invoking native callbacks.
func (manager *SessionManager) RevokeAll() {
	manager.mu.Lock()
	sessions := manager.sessions
	manager.sessions = make(map[string]ManagedSession)
	manager.focused, manager.microphone, manager.clipboard = "", "", ""
	manager.serverID, manager.userID = "", ""
	manager.mu.Unlock()
	for _, session := range sessions {
		session.Runtime.ReleaseInput()
		session.Runtime.Close()
	}
}
