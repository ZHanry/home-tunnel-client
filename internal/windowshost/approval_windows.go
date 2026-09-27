//go:build windows

package windowshost

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unsafe"

	"github.com/Microsoft/go-winio"
	"github.com/ZHanry/home-tunnel-client/internal/remoteengine"
	"golang.org/x/sys/windows"
)

type shellExecuteInfo struct {
	Size, Mask                        uint32
	Window                            windows.Handle
	Verb, File, Parameters, Directory *uint16
	Show                              int32
	Instance                          windows.Handle
	IDList                            uintptr
	Class                             *uint16
	ClassKey                          windows.Handle
	HotKey                            uint32
	Icon, Process                     windows.Handle
}

var shellExecuteEx = windows.NewLazySystemDLL("shell32.dll").NewProc("ShellExecuteExW")

// EnableWithApproval runs a short-lived, packaged UAC helper. Neither account
// passwords nor private endpoint state appear in its command line or files.
func EnableWithApproval(ctx context.Context, request ControlRequest) error {
	directory, unpin, err := pinPackage()
	if err != nil {
		return err
	}
	defer unpin()
	image := filepath.Join(directory, ServiceBinary)
	pin, err := pinProtected(image, false)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(pin)
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return err
	}
	nonce := make([]byte, 32)
	if _, err = rand.Read(nonce); err != nil {
		return err
	}
	suffix := hex.EncodeToString(nonce)
	pipe := `\\.\pipe\HomeTunnelApproval-` + suffix
	listener, err := winio.ListenPipe(pipe, &winio.PipeConfig{SecurityDescriptor: "D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;" + user.User.Sid.String() + ")"})
	if err != nil {
		return err
	}
	defer listener.Close()
	file, _ := windows.UTF16PtrFromString(image)
	verb, _ := windows.UTF16PtrFromString("runas")
	arguments, _ := windows.UTF16PtrFromString(fmt.Sprintf("--approve-unattended=%s --gui-pid=%d", suffix, os.Getpid()))
	info := shellExecuteInfo{Mask: 0x40 | 0x100 | 0x400, File: file, Verb: verb, Parameters: arguments, Show: 0}
	info.Size = uint32(unsafe.Sizeof(info))
	result, _, _ := shellExecuteEx.Call(uintptr(unsafe.Pointer(&info)))
	if result == 0 || info.Process == 0 {
		return ErrAdmin
	}
	defer windows.CloseHandle(info.Process)
	expectedPID, err := windows.GetProcessId(info.Process)
	if err != nil {
		return err
	}
	deadline, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	closeAccept := context.AfterFunc(deadline, func() { listener.Close() })
	defer closeAccept()
	watchDone := make(chan struct{})
	go func() {
		defer close(watchDone)
		for deadline.Err() == nil {
			state, waitErr := windows.WaitForSingleObject(info.Process, 100)
			if waitErr != nil || state == windows.WAIT_OBJECT_0 {
				listener.Close()
				return
			}
		}
	}()
	defer func() { cancel(); <-watchDone }()
	conn, err := listener.Accept()
	if err != nil {
		return ErrUnavailable
	}
	defer conn.Close()
	peer, err := pipeClientPID(conn)
	if err != nil || peer != expectedPID {
		return ErrRejected
	}
	var token windows.Token
	if windows.OpenProcessToken(info.Process, windows.TOKEN_QUERY, &token) != nil {
		return ErrRejected
	}
	identity, err := token.GetTokenUser()
	token.Close()
	// UAC using another account must not transfer this user's endpoint key.
	if err != nil || !identity.User.Sid.Equals(user.User.Sid) {
		return ErrIdentity
	}
	until, _ := deadline.Deadline()
	conn.SetDeadline(until)
	disconnect := context.AfterFunc(deadline, func() { conn.Close() })
	defer disconnect()
	request.Version = 1
	if err = writeControl(conn, request); err != nil {
		return err
	}
	var response ControlResponse
	if err = readControl(conn, &response); err != nil {
		return err
	}
	if response.Version != 1 {
		return ErrRejected
	}
	if response.Error != "" {
		return fmt.Errorf("RD_SERVICE_APPROVAL_FAILED: %s", response.Error)
	}
	return nil
}

func approvalSource(conn net.Conn, pid uint32, expectedGUI string) error {
	fd, ok := conn.(interface{ Fd() uintptr })
	if !ok {
		return ErrRejected
	}
	var actual uint32
	result, _, _ := serverPIDProc.Call(fd.Fd(), uintptr(unsafe.Pointer(&actual)))
	if result == 0 || pid == 0 || actual != pid {
		return ErrRejected
	}
	process, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(process)
	var token windows.Token
	if windows.OpenProcessToken(process, windows.TOKEN_QUERY, &token) != nil {
		return ErrRejected
	}
	caller, err := token.GetTokenUser()
	token.Close()
	self, selfErr := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil || selfErr != nil || !caller.User.Sid.Equals(self.User.Sid) {
		return ErrIdentity
	}
	path := make([]uint16, 32768)
	length := uint32(len(path))
	if windows.QueryFullProcessImageName(process, 0, &path[0], &length) != nil {
		return ErrRejected
	}
	image := windows.UTF16ToString(path[:length])
	directory, unpin, err := pinPackage()
	if err != nil {
		return err
	}
	defer unpin()
	if !strings.EqualFold(image, filepath.Join(directory, "home-tunnel-gui.exe")) {
		return ErrRejected
	}
	return remoteengine.VerifyExecutable(remoteengine.Options{ExecutablePath: image, ExpectedSHA256: expectedGUI})
}

func RunApprovalHelper(nonce string, parentPID uint32, expectedGUI string) error {
	if len(nonce) != 64 || !windows.GetCurrentProcessToken().IsElevated() {
		return ErrAdmin
	}
	if decoded, err := hex.DecodeString(nonce); err != nil || len(decoded) != 32 {
		return ErrRejected
	}
	ctx, cancel := context.WithTimeout(context.Background(), 75*time.Second)
	defer cancel()
	conn, err := winio.DialPipeContext(ctx, `\\.\pipe\HomeTunnelApproval-`+nonce)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err = approvalSource(conn, parentPID, expectedGUI); err != nil {
		return err
	}
	conn.SetDeadline(time.Now().Add(70 * time.Second))
	var request ControlRequest
	if err = readControl(conn, &request); err != nil || request.Version != 1 {
		return ErrRejected
	}
	if !ValidEndpointID(request.ControllerID) || !ValidThumbprint(request.Thumbprint) {
		return ErrIdentity
	}
	response := ControlResponse{Version: 1}
	if len(request.State) > 0 {
		request.Operation = "adopt"
		_, err = Control(ctx, request)
	}
	if err == nil {
		ready := false
		until := time.Now().Add(25 * time.Second)
		for time.Now().Before(until) && ctx.Err() == nil {
			state, probeErr := Control(ctx, ControlRequest{Operation: "status", Origin: request.Origin, DeviceID: request.DeviceID})
			if probeErr == nil && state.Managed && state.State != nil && state.State.Capabilities.Available {
				ready = true
				break
			}
			timer := time.NewTimer(400 * time.Millisecond)
			select {
			case <-ctx.Done():
				timer.Stop()
			case <-timer.C:
			}
		}
		if !ready {
			err = ErrUnavailable
		} else {
			request.Operation = "enable_unattended"
			request.State = nil
			request.Action = nil
			request.File = nil
			_, err = Control(ctx, request)
		}
	}
	response.Error = controlError(err)
	if writeErr := writeControl(conn, response); writeErr != nil {
		return writeErr
	}
	return err
}
