//go:build windows

package agent

import (
	"os"
	"os/exec"
	"testing"

	"golang.org/x/sys/windows"
)

func TestAgentConsoleProbe(t *testing.T) {
	if os.Getenv("HOME_TUNNEL_CONSOLE_PROBE") != "1" {
		return
	}
	window, _, _ := windows.NewLazySystemDLL("kernel32.dll").NewProc("GetConsoleWindow").Call()
	if window != 0 {
		t.Fatal("background child allocated or inherited a console")
	}
}

func TestBackgroundAgentDoesNotAllocateAConsole(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	command := exec.Command(executable, "-test.run=^TestAgentConsoleProbe$")
	command.Env = append(os.Environ(), "HOME_TUNNEL_CONSOLE_PROBE=1")
	configureAgentProcess(command)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("console-free child failed: %v\n%s", err, output)
	}
}
