//go:build windows

package agent

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"

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

func TestAgentLifetimeProbe(t *testing.T) {
	switch os.Getenv("HOME_TUNNEL_LIFETIME_PROBE") {
	case "agent":
		time.Sleep(time.Minute)
	case "supervisor":
		executable, _ := os.Executable()
		command := exec.Command(executable, "-test.run=^TestAgentLifetimeProbe$")
		command.Env = append(os.Environ(), "HOME_TUNNEL_LIFETIME_PROBE=agent")
		if err := command.Start(); err != nil {
			t.Fatal(err)
		}
		bindAgentToSupervisor(command)
		fmt.Println("agent", command.Process.Pid)
		time.Sleep(time.Minute)
	}
}

func TestAgentExitsWithItsSupervisor(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	supervisor := exec.Command(executable, "-test.run=^TestAgentLifetimeProbe$")
	supervisor.Env = append(os.Environ(), "HOME_TUNNEL_LIFETIME_PROBE=supervisor")
	output, err := supervisor.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := supervisor.Start(); err != nil {
		t.Fatal(err)
	}
	defer supervisor.Process.Kill()
	line, err := bufio.NewReader(output).ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(line, "agent ")))
	if err != nil {
		t.Fatalf("unexpected probe output %q", line)
	}
	agent, err := windows.OpenProcess(windows.SYNCHRONIZE|windows.PROCESS_TERMINATE, false, uint32(pid))
	if err != nil {
		t.Fatal(err)
	}
	defer windows.CloseHandle(agent)
	// A crash or a forced kill of the GUI must not leave its Agent running.
	_ = supervisor.Process.Kill()
	_ = supervisor.Wait()
	if event, _ := windows.WaitForSingleObject(agent, 5000); event != windows.WAIT_OBJECT_0 {
		_ = windows.TerminateProcess(agent, 1)
		t.Fatal("agent kept running after its supervisor was killed")
	}
}
