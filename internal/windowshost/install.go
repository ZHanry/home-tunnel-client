package windowshost

import (
	"path/filepath"
	"strings"
)

type Layout struct {
	Scope            string
	ExePath          string
	PreviousPerUser  bool
	ServiceRequested bool
	ProgramFiles     string
}

type Plan struct {
	RegisterService    bool
	QuotedPath         string
	DirectoryACL       string
	StoreACL           string
	StoreDir           string
	UnattendedEnabled  bool
	KeepPerUserProfile bool
	StopBeforeReplace  bool
	RemovedService     string
	RemovedStore       string
}

func QuoteServicePath(path string) (string, error) {
	if path == "" || strings.ContainsAny(path, "\"\r\n") || strings.Contains(path, "..") {
		return "", ErrRejected
	}
	if strings.Contains(path, " ") {
		return `"` + path + `"`, nil
	}
	return path, nil
}

func userWritable(path string) bool {
	folded := strings.ToLower(filepath.Clean(path))
	for _, marker := range []string{`\users\`, `\temp\`, `\appdata\`, `\public\`, `\programdata\temp\`} {
		if strings.Contains(folded, marker) {
			return true
		}
	}
	return false
}

func PlanInstall(layout Layout) (Plan, error) {
	plan := Plan{DirectoryACL: StoreSDDL, StoreACL: StoreSDDL, StoreDir: ProgramDataDir, UnattendedEnabled: false, KeepPerUserProfile: true, StopBeforeReplace: true, RemovedService: ServiceName, RemovedStore: ProgramDataDir}
	if layout.PreviousPerUser {
		plan.KeepPerUserProfile = true
	}
	if layout.Scope != "per-machine" || !layout.ServiceRequested {
		return plan, nil
	}
	cleaned := filepath.Clean(layout.ExePath)
	program := filepath.Clean(layout.ProgramFiles)
	expected := filepath.Join(program, "Home Tunnel", ServiceBinary)
	if !strings.EqualFold(cleaned, expected) || userWritable(cleaned) {
		return Plan{}, ErrRejected
	}
	quoted, err := QuoteServicePath(cleaned)
	if err != nil {
		return Plan{}, err
	}
	plan.RegisterService = true
	plan.QuotedPath = quoted
	return plan, nil
}
