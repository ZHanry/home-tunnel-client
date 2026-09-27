package windowshost

import (
	"path"
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

// Installation plans always describe Windows paths, including when the pure
// policy tests run on Linux or macOS. OS ACL and reparse-point checks are still
// performed by the Windows installer before using the resulting plan.
func cleanInstallPath(value string) (string, error) {
	value = strings.ReplaceAll(value, `/`, `\`)
	if len(value) < 3 || !((value[0] >= 'A' && value[0] <= 'Z') || (value[0] >= 'a' && value[0] <= 'z')) || value[1:3] != `:\` {
		return "", ErrRejected
	}
	if strings.ContainsAny(value[2:], ":*?\"<>|\x00\r\n\t") || strings.Contains(value, "..") {
		return "", ErrRejected
	}
	for _, component := range strings.Split(value[3:], `\`) {
		if strings.TrimRight(component, " .") != component {
			return "", ErrRejected
		}
	}
	return strings.ReplaceAll(path.Clean(strings.ReplaceAll(value, `\`, `/`)), `/`, `\`), nil
}

func userWritable(value string) bool {
	folded := strings.ToLower(value)
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
	cleaned, err := cleanInstallPath(layout.ExePath)
	if err != nil {
		return Plan{}, err
	}
	program, err := cleanInstallPath(layout.ProgramFiles)
	if err != nil {
		return Plan{}, err
	}
	expected := strings.TrimRight(program, `\`) + `\Home Tunnel\` + ServiceBinary
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
