package windowshost

type Phase string

const (
	PhaseStopped   Phase = "stopped"
	PhaseSignedOut Phase = "signed_out"
	PhaseActive    Phase = "active"
	PhaseLocked    Phase = "locked"
	PhaseSecure    Phase = "secure"
)

type EventKind string

const (
	EventStart     EventKind = "start"
	EventStop      EventKind = "stop"
	EventLogon     EventKind = "logon"
	EventLogoff    EventKind = "logoff"
	EventLock      EventKind = "lock"
	EventUnlock    EventKind = "unlock"
	EventSwitch    EventKind = "switch"
	EventSecure    EventKind = "secure"
	EventOrdinary  EventKind = "ordinary"
	EventEmergency EventKind = "emergency"
)

type Event struct {
	Kind      EventKind
	SessionID uint32
	UserSID   string
}

type ActionKind string

const (
	ActionLaunchAgent       ActionKind = "launch_agent"
	ActionStopAgent         ActionKind = "stop_agent"
	ActionReleaseInput      ActionKind = "release_input"
	ActionStartSecureWorker ActionKind = "start_secure_worker"
	ActionStopSecureWorker  ActionKind = "stop_secure_worker"
	ActionRevokeLocal       ActionKind = "revoke_local"
)

type Action struct {
	Kind      ActionKind
	SessionID uint32
	Arg       string
}

type Machine struct {
	Running    bool
	Unattended bool
	Active     uint32
	Phase      Phase
	UserSID    string
	Agent      bool
	Secure     bool
	InputHeld  bool
}

const sessionAgentArg = "--session-agent"

func (m *Machine) Apply(event Event) []Action {
	var actions []Action
	release := func() {
		if m.InputHeld {
			actions = append(actions, Action{Kind: ActionReleaseInput, SessionID: m.Active})
			m.InputHeld = false
		}
	}
	stopAgent := func() {
		if m.Agent {
			actions = append(actions, Action{Kind: ActionStopAgent, SessionID: m.Active})
			m.Agent = false
		}
	}
	stopSecure := func() {
		if m.Secure {
			actions = append(actions, Action{Kind: ActionStopSecureWorker, SessionID: m.Active})
			m.Secure = false
		}
	}
	switch event.Kind {
	case EventStart:
		m.Running = true
		m.Phase = PhaseSignedOut
	case EventStop, EventEmergency:
		if event.Kind == EventEmergency {
			actions = append(actions, Action{Kind: ActionRevokeLocal, SessionID: m.Active})
			m.Unattended = false
		}
		release()
		stopSecure()
		stopAgent()
		m.Running = false
		m.Phase = PhaseStopped
		m.Active = 0
	case EventLogon:
		if !m.Running || event.SessionID == 0 {
			return actions
		}
		release()
		if m.Active != 0 && m.Active != event.SessionID {
			stopAgent()
			stopSecure()
		}
		m.Active = event.SessionID
		m.UserSID = event.UserSID
		m.Phase = PhaseActive
		actions = append(actions, Action{Kind: ActionLaunchAgent, SessionID: event.SessionID, Arg: sessionAgentArg})
		m.Agent = true
	case EventLogoff:
		release()
		stopSecure()
		stopAgent()
		if m.Active == event.SessionID {
			m.Active = 0
			m.UserSID = ""
		}
		m.Phase = PhaseSignedOut
	case EventLock:
		release()
		m.Phase = PhaseLocked
		if m.Unattended {
			actions = append(actions, Action{Kind: ActionStartSecureWorker, SessionID: m.Active, Arg: "--host-inherited-pipe"})
			m.Secure = true
			m.InputHeld = true
		} else {
			stopSecure()
		}
	case EventUnlock, EventOrdinary:
		release()
		stopSecure()
		m.Phase = PhaseActive
		if m.Running && m.Active != 0 && !m.Agent && m.UserSID != "" {
			actions = append(actions, Action{Kind: ActionLaunchAgent, SessionID: m.Active, Arg: sessionAgentArg})
			m.Agent = true
		}
	case EventSecure:
		release()
		m.Phase = PhaseSecure
		if m.Unattended && m.Active != 0 {
			actions = append(actions, Action{Kind: ActionStartSecureWorker, SessionID: m.Active, Arg: "--host-inherited-pipe"})
			m.Secure = true
			m.InputHeld = true
		}
	case EventSwitch:
		release()
		stopSecure()
		stopAgent()
		m.Active = event.SessionID
		m.UserSID = event.UserSID
		if event.SessionID == 0 || event.UserSID == "" {
			m.Phase = PhaseSignedOut
			return actions
		}
		m.Phase = PhaseActive
		actions = append(actions, Action{Kind: ActionLaunchAgent, SessionID: event.SessionID, Arg: sessionAgentArg})
		m.Agent = true
	}
	return actions
}

func ExecuteActions(actions []Action, launch func(string) error) error {
	for _, action := range actions {
		switch action.Kind {
		case ActionLaunchAgent, ActionStartSecureWorker:
			expected, ok := FixedLaunch(action.Kind)
			if !ok || action.Arg != expected || launch == nil {
				return ErrRejected
			}
			if err := launch(expected); err != nil {
				return err
			}
		}
	}
	return nil
}

func FixedLaunch(kind ActionKind) (string, bool) {
	switch kind {
	case ActionLaunchAgent:
		return sessionAgentArg, true
	case ActionStartSecureWorker:
		return "--host-inherited-pipe", true
	default:
		return "", false
	}
}
