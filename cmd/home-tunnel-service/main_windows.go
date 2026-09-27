//go:build windows

package main

import (
	"context"
	"fmt"
	"github.com/ZHanry/home-tunnel-client/internal/windowshost"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"os"
	"strconv"
	"strings"
	"time"
	"unsafe"
)

var expectedRemoteHostSHA256 string
var expectedGUISHA256 string

func main() {
	service, err := svc.IsWindowsService()
	if err != nil {
		os.Exit(2)
	}
	if service {
		if err = svc.Run(windowshost.ServiceName, handler{}); err != nil {
			os.Exit(1)
		}
		return
	}
	if len(os.Args) == 3 && strings.HasPrefix(os.Args[1], "--approve-unattended=") && strings.HasPrefix(os.Args[2], "--gui-pid=") {
		pid, parseErr := strconv.ParseUint(strings.TrimPrefix(os.Args[2], "--gui-pid="), 10, 32)
		if parseErr != nil || pid == 0 || windowshost.RunApprovalHelper(strings.TrimPrefix(os.Args[1], "--approve-unattended="), uint32(pid), expectedGUISHA256) != nil {
			os.Exit(1)
		}
		return
	}
	if len(os.Args) != 2 {
		usage()
	}
	var runErr error
	switch os.Args[1] {
	case "install":
		runErr = windowshost.Install(windowshost.CurrentProgramFiles())
	case "uninstall":
		runErr = windowshost.Uninstall()
	case "start":
		runErr = windowshost.Start()
	case "stop":
		runErr = windowshost.Stop()
	case "restart":
		runErr = windowshost.Restart()
	case "status":
		fmt.Println(windowshost.Inspect(context.Background()).Detail)
		return
	default:
		usage()
	}
	if runErr != nil {
		fmt.Fprintln(os.Stderr, "service command failed:", runErr)
		os.Exit(1)
	}
}
func usage() {
	fmt.Fprintln(os.Stderr, "usage: home-tunnel-service install|uninstall|start|stop|restart|status")
	os.Exit(2)
}

type handler struct{}

func (handler) Execute(_ []string, requests <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	status <- svc.Status{State: svc.StartPending, WaitHint: 10000}
	supervisor, err := windowshost.NewSupervisor(expectedRemoteHostSHA256, expectedGUISHA256)
	if err != nil {
		return true, 1
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	finished := make(chan error, 1)
	go func() { finished <- supervisor.Run(ctx) }()
	status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown | svc.AcceptSessionChange}
	for {
		select {
		case err := <-finished:
			if err != nil {
				return true, 2
			}
			return false, 0
		case request, open := <-requests:
			if !open {
				cancel()
				<-finished
				return false, 0
			}
			switch request.Cmd {
			case svc.Interrogate:
				status <- request.CurrentStatus
			case svc.Stop, svc.Shutdown:
				status <- svc.Status{State: svc.StopPending, WaitHint: 15000}
				cancel()
				timer := time.NewTicker(time.Second)
				for checkpoint := uint32(1); ; checkpoint++ {
					select {
					case <-finished:
						timer.Stop()
						return false, 0
					case <-timer.C:
						status <- svc.Status{State: svc.StopPending, WaitHint: 15000, CheckPoint: checkpoint}
					}
				}
			case svc.SessionChange:
				// EventData points to WTSSESSION_NOTIFICATION; it is not itself
				// a session id. Ignore malformed and unrelated notifications.
				session, valid := notificationSession(request.EventData)
				if !valid {
					continue
				}
				if session == windows.WTSGetActiveConsoleSessionId() || request.EventType == 1 || request.EventType == 2 {
					supervisor.NotifySession()
				}
			}
		}
	}
}
func notificationSession(data uintptr) (uint32, bool) {
	if data == 0 {
		return 0, false
	}
	type notification struct{ Size, Session uint32 }
	value := (*notification)(unsafe.Pointer(data))
	if value.Size < uint32(unsafe.Sizeof(notification{})) || value.Session == 0 || value.Session == 0xffffffff {
		return 0, false
	}
	return value.Session, true
}
