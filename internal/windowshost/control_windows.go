//go:build windows

package windowshost

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/Microsoft/go-winio"
	"github.com/ZHanry/home-tunnel-client/internal/remoteengine"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
)

const controlLimit = 768 << 10

type controlPeer struct {
	SID          string
	Session, PID uint32
	Admin        bool
}

func readControl(reader io.Reader, value any) error {
	var size uint32
	if err := binary.Read(reader, binary.BigEndian, &size); err != nil {
		return err
	}
	if size == 0 || size > controlLimit {
		return ErrRejected
	}
	body := make([]byte, size)
	if _, err := io.ReadFull(reader, body); err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		return ErrRejected
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		return ErrRejected
	}
	return nil
}
func writeControl(writer io.Writer, value any) error {
	body, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if len(body) > controlLimit {
		return ErrRejected
	}
	frame := make([]byte, len(body)+4)
	binary.BigEndian.PutUint32(frame, uint32(len(body)))
	copy(frame[4:], body)
	for len(frame) > 0 {
		count, err := writer.Write(frame)
		if err != nil {
			return err
		}
		if count == 0 {
			return io.ErrShortWrite
		}
		frame = frame[count:]
	}
	return nil
}

var impersonatePipe = windows.NewLazySystemDLL("advapi32.dll").NewProc("ImpersonateNamedPipeClient")
var serverPIDProc = windows.NewLazySystemDLL("kernel32.dll").NewProc("GetNamedPipeServerProcessId")

func identifyClient(conn net.Conn, guiSHA string) (controlPeer, error) {
	pid, err := pipeClientPID(conn)
	if err != nil {
		return controlPeer{}, ErrRejected
	}
	handle, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if err != nil {
		return controlPeer{}, ErrRejected
	}
	defer windows.CloseHandle(handle)
	buffer := make([]uint16, 32768)
	size := uint32(len(buffer))
	if windows.QueryFullProcessImageName(handle, 0, &buffer[0], &size) != nil {
		return controlPeer{}, ErrRejected
	}
	path := windows.UTF16ToString(buffer[:size])
	directory, unpin, err := pinPackage()
	if err != nil {
		return controlPeer{}, err
	}
	defer unpin()
	serviceImage := filepath.Join(directory, ServiceBinary)
	guiImage := filepath.Join(directory, "home-tunnel-gui.exe")
	if !strings.EqualFold(path, serviceImage) && !strings.EqualFold(path, guiImage) {
		return controlPeer{}, ErrRejected
	}
	pin, err := pinProtected(path, false)
	if err != nil {
		return controlPeer{}, err
	}
	defer windows.CloseHandle(pin)
	if strings.EqualFold(path, guiImage) {
		if err = remoteengine.VerifyExecutable(remoteengine.Options{ExecutablePath: path, ExpectedSHA256: guiSHA}); err != nil {
			return controlPeer{}, ErrRejected
		}
	} else {
		self, selfErr := os.Executable()
		if selfErr != nil || !strings.EqualFold(self, serviceImage) {
			return controlPeer{}, ErrRejected
		}
	}
	fd, ok := conn.(interface{ Fd() uintptr })
	if !ok {
		return controlPeer{}, ErrRejected
	}
	// Impersonation is thread-local. Never let the goroutine move to another
	// OS thread, and never leave an impersonated thread in Go's thread pool.
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	result, _, _ := impersonatePipe.Call(fd.Fd())
	if result == 0 {
		return controlPeer{}, ErrRejected
	}
	defer func() {
		if windows.RevertToSelf() != nil {
			os.Exit(1)
		}
	}()
	var token windows.Token
	if err = windows.OpenThreadToken(windows.CurrentThread(), windows.TOKEN_QUERY, true, &token); err != nil {
		return controlPeer{}, ErrRejected
	}
	defer token.Close()
	user, err := token.GetTokenUser()
	if err != nil {
		return controlPeer{}, ErrRejected
	}
	var session, needed uint32
	if windows.GetTokenInformation(token, windows.TokenSessionId, (*byte)(unsafe.Pointer(&session)), 4, &needed) != nil {
		return controlPeer{}, ErrRejected
	}
	var processSession uint32
	if windows.ProcessIdToSessionId(pid, &processSession) != nil || processSession != session {
		return controlPeer{}, ErrRejected
	}
	administrators, _ := windows.CreateWellKnownSid(windows.WinBuiltinAdministratorsSid)
	admin, _ := token.IsMember(administrators)
	if session == 0 && !user.User.Sid.IsWellKnown(windows.WinLocalSystemSid) {
		return controlPeer{}, ErrRejected
	}
	return controlPeer{SID: user.User.Sid.String(), Session: session, PID: pid, Admin: admin && token.IsElevated()}, nil
}

func authenticatedService(conn net.Conn) error {
	fd, ok := conn.(interface{ Fd() uintptr })
	if !ok {
		return ErrRejected
	}
	var pid uint32
	value, _, _ := serverPIDProc.Call(fd.Fd(), uintptr(unsafe.Pointer(&pid)))
	if value == 0 || pid == 0 {
		return ErrRejected
	}
	status, err := queryInstalledStatus()
	if err != nil || status.ProcessId != pid {
		return ErrRejected
	}
	config, err := queryInstalledConfiguration()
	if err != nil || config.ServiceStartName != "LocalSystem" ||
		(config.BinaryPathName != filepath.Join(CurrentProgramFiles(), "Home Tunnel", ServiceBinary) &&
			config.BinaryPathName != windows.EscapeArg(filepath.Join(CurrentProgramFiles(), "Home Tunnel", ServiceBinary))) {
		return ErrRejected
	}
	return nil
}

func Control(ctx context.Context, request ControlRequest) (ControlResponse, error) {
	request.Version = 1
	status, statusErr := queryInstalledStatus()
	if statusErr != nil || status.State != svc.Running {
		return ControlResponse{}, ErrNotInstalled
	}
	deadline, cancel := context.WithTimeout(ctx, 35*time.Second)
	defer cancel()
	dial, stopDial := context.WithTimeout(deadline, time.Second)
	// Identification permits SID/elevation checks without giving the service
	// an impersonation/delegation token usable as the caller.
	conn, err := winio.DialPipeAccessImpLevel(dial, PipeName, windows.GENERIC_READ|windows.GENERIC_WRITE, winio.PipeImpLevelIdentification)
	stopDial()
	if err != nil {
		return ControlResponse{}, ErrNotInstalled
	}
	defer conn.Close()
	if err = authenticatedService(conn); err != nil {
		return ControlResponse{}, err
	}
	until, _ := deadline.Deadline()
	conn.SetDeadline(until)
	stop := context.AfterFunc(deadline, func() { conn.Close() })
	defer stop()
	if err = writeControl(conn, request); err != nil {
		return ControlResponse{}, err
	}
	var response ControlResponse
	if err = readControl(conn, &response); err != nil {
		return response, err
	}
	if response.Version != 1 {
		return ControlResponse{}, ErrRejected
	}
	switch response.Error {
	case "":
		return response, nil
	case "admin_required":
		return response, ErrAdmin
	case "identity_mismatch":
		return response, ErrIdentity
	case "unavailable":
		return response, ErrUnavailable
	default:
		if strings.HasPrefix(response.Error, "RD_") && len(response.Error) < 80 {
			return response, errors.New(response.Error)
		}
		return response, ErrRejected
	}
}

func (s *Supervisor) serveControl(parent context.Context) error {
	listener, err := winio.ListenPipe(PipeName, &winio.PipeConfig{
		SecurityDescriptor: "D:P(A;;GA;;;SY)(A;;GRGW;;;BA)(A;;GRGW;;;IU)",
		InputBufferSize:    65536, OutputBufferSize: 65536})
	if err != nil {
		return err
	}
	return s.serveListener(parent, listener)
}

func (s *Supervisor) serveListener(parent context.Context, listener net.Listener) error {
	ctx, cancel := context.WithCancel(parent)
	var handlers sync.WaitGroup
	defer func() { cancel(); handlers.Wait() }()
	defer listener.Close()
	stop := context.AfterFunc(ctx, func() { listener.Close() })
	defer stop()
	slots := make(chan struct{}, 16)
	for {
		conn, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		select {
		case slots <- struct{}{}:
		default:
			conn.Close()
			continue
		}
		handlers.Add(1)
		go func() {
			defer handlers.Done()
			defer func() { conn.Close(); <-slots }()
			closeOnStop := context.AfterFunc(ctx, func() { conn.Close() })
			defer closeOnStop()
			conn.SetReadDeadline(time.Now().Add(5 * time.Second))
			var request ControlRequest
			if readControl(conn, &request) != nil || request.Version != 1 {
				return
			}
			peer, err := identifyClient(conn, s.guiSHA)
			if err != nil {
				return
			}
			life, cancel := context.WithTimeout(ctx, 30*time.Second)
			defer cancel()
			conn.SetDeadline(time.Now().Add(31 * time.Second))
			response := s.control(life, peer, request)
			response.Version = 1
			_ = writeControl(conn, response)
		}()
	}
}

func controlError(err error) string {
	var apiError *remotehost.APIError
	if errors.As(err, &apiError) && strings.HasPrefix(apiError.Code, "RD_") {
		return apiError.Code
	}
	switch {
	case err == nil:
		return ""
	case errors.Is(err, ErrAdmin), errors.Is(err, remotehost.ErrLocalApproval):
		return "admin_required"
	case errors.Is(err, ErrIdentity):
		return "identity_mismatch"
	case errors.Is(err, ErrUnavailable), errors.Is(err, remotehost.ErrUnavailable):
		return "unavailable"
	default:
		return "rejected"
	}
}
