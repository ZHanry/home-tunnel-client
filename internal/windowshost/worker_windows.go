//go:build windows

package windowshost

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"

	"github.com/Microsoft/go-winio"
	"github.com/ZHanry/home-tunnel-client/internal/remoteengine"
	"golang.org/x/sys/windows"
)

var clientPIDProc = windows.NewLazySystemDLL("kernel32.dll").NewProc("GetNamedPipeClientProcessId")

func pipeClientPID(conn net.Conn) (uint32, error) {
	fd, ok := conn.(interface{ Fd() uintptr })
	if !ok {
		return 0, ErrRejected
	}
	var pid uint32
	result, _, err := clientPIDProc.Call(fd.Fd(), uintptr(unsafe.Pointer(&pid)))
	if result == 0 || pid == 0 {
		return 0, err
	}
	return pid, nil
}

type workerProcess struct {
	mu          sync.Mutex
	handle, job windows.Handle
	pid         uint32
	done        chan struct{}
	err         error
}

func (p *workerProcess) ProcessID() int { return int(p.pid) }
func (p *workerProcess) Wait() error    { <-p.done; return p.err }
func (p *workerProcess) Kill() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.handle == 0 {
		return nil
	}
	return windows.TerminateProcess(p.handle, 1)
}
func (p *workerProcess) reap() {
	_, waitErr := windows.WaitForSingleObject(p.handle, windows.INFINITE)
	p.mu.Lock()
	var code uint32
	if waitErr == nil {
		waitErr = windows.GetExitCodeProcess(p.handle, &code)
	}
	if waitErr == nil && code != 0 {
		waitErr = fmt.Errorf("native worker exited with code %d", code)
	}
	p.err = waitErr
	windows.CloseHandle(p.handle)
	p.handle = 0
	windows.CloseHandle(p.job)
	p.job = 0
	p.mu.Unlock()
	close(p.done)
}
func (p *workerProcess) duplicate(token windows.Token) (uintptr, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.handle == 0 {
		return 0, ErrUnavailable
	}
	var target windows.Handle
	err := windows.DuplicateHandle(windows.CurrentProcess(), windows.Handle(token), p.handle,
		&target, 0, false, windows.DUPLICATE_SAME_ACCESS)
	return uintptr(target), err
}

// StartWorker accepts installation metadata only; no browser/remote-supplied
// path, process id, command line or environment reaches CreateProcessAsUser.
func StartWorker(parent context.Context, session uint32, expectedSHA256, ownerSID string, policy func() remoteengine.DesktopPolicy) (*remoteengine.Engine, error) {
	if policy == nil {
		return nil, ErrRejected
	}
	if session == 0 || session == 0xffffffff || session != windows.WTSGetActiveConsoleSessionId() {
		return nil, ErrRejected
	}
	directory, unpin, err := pinPackage()
	if err != nil {
		return nil, err
	}
	defer unpin()
	path := filepath.Join(directory, WorkerName)
	pin, err := pinProtected(path, false)
	if err != nil {
		return nil, err
	}
	defer windows.CloseHandle(pin)
	if err = remoteengine.VerifyExecutable(remoteengine.Options{ExecutablePath: path, ExpectedSHA256: expectedSHA256}); err != nil {
		return nil, err
	}
	token, err := systemTokenForSession(session)
	if err != nil {
		return nil, err
	}
	defer token.Close()
	identity, err := token.GetTokenUser()
	if err != nil || !identity.User.Sid.IsWellKnown(windows.WinLocalSystemSid) {
		return nil, ErrRejected
	}
	nonce := make([]byte, 32)
	if _, err = rand.Read(nonce); err != nil {
		return nil, err
	}
	suffix := hex.EncodeToString(nonce)
	listener, err := winio.ListenPipe(`\\.\pipe\HomeTunnelWorker-`+suffix,
		&winio.PipeConfig{SecurityDescriptor: "D:P(A;;GA;;;SY)", InputBufferSize: 262144, OutputBufferSize: 262144})
	if err != nil {
		return nil, err
	}
	defer listener.Close()
	command, err := windows.UTF16PtrFromString(fmt.Sprintf("%s --host-service-pipe=%s --service-pid=%d", windows.EscapeArg(path), suffix, os.Getpid()))
	if err != nil {
		return nil, err
	}
	desktop, _ := windows.UTF16PtrFromString(`WinSta0\Default`)
	cwd, _ := windows.UTF16PtrFromString(directory)
	var environment *uint16
	if err = windows.CreateEnvironmentBlock(&environment, token, false); err != nil {
		return nil, err
	}
	defer windows.DestroyEnvironmentBlock(environment)
	job, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		return nil, err
	}
	limits := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	// Only the worker belongs to this job. Its tiny input-release guard must
	// survive a service/worker crash long enough to release the injected keys.
	limits.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | windows.JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK
	if _, err = windows.SetInformationJobObject(job, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&limits)), uint32(unsafe.Sizeof(limits))); err != nil {
		windows.CloseHandle(job)
		return nil, err
	}
	startup := windows.StartupInfo{Cb: uint32(unsafe.Sizeof(windows.StartupInfo{})), Desktop: desktop}
	var info windows.ProcessInformation
	err = windows.CreateProcessAsUser(token, nil, command, nil, nil, false,
		windows.CREATE_UNICODE_ENVIRONMENT|windows.CREATE_NO_WINDOW|windows.CREATE_SUSPENDED,
		environment, cwd, &startup, &info)
	if err != nil {
		windows.CloseHandle(job)
		return nil, err
	}
	process := &workerProcess{handle: info.Process, job: job, pid: info.ProcessId, done: make(chan struct{})}
	if err = windows.AssignProcessToJobObject(job, info.Process); err == nil {
		_, err = windows.ResumeThread(info.Thread)
	}
	windows.CloseHandle(info.Thread)
	go process.reap()
	if err != nil {
		process.Kill()
		process.Wait()
		return nil, err
	}
	ctx, cancel := context.WithTimeout(parent, 5*time.Second)
	type accepted struct {
		conn net.Conn
		err  error
	}
	ready := make(chan accepted, 1)
	go func() { conn, acceptErr := listener.Accept(); ready <- accepted{conn, acceptErr} }()
	var connection accepted
	select {
	case connection = <-ready:
	case <-ctx.Done():
		listener.Close()
		connection = <-ready
		if connection.conn != nil {
			connection.conn.Close()
		}
		connection = accepted{err: ctx.Err()}
	}
	cancel()
	if connection.err != nil {
		process.Kill()
		process.Wait()
		return nil, connection.err
	}
	pid, pidErr := pipeClientPID(connection.conn)
	if pidErr != nil || pid != info.ProcessId {
		connection.conn.Close()
		process.Kill()
		process.Wait()
		return nil, ErrRejected
	}
	engine, err := remoteengine.NewTransport(parent, process, connection.conn, connection.conn)
	if err != nil {
		return nil, err
	}
	initialize, cancel := context.WithTimeout(parent, time.Second)
	err = engine.DelegateDesktop(initialize, session, time.Now().Add(2*time.Second), policy())
	if err == nil && ownerSID != "" {
		var user windows.Token
		if tokenErr := windows.WTSQueryUserToken(session, &user); tokenErr == nil {
			approved, userErr := user.GetTokenUser()
			if userErr == nil && approved.User.Sid.String() == ownerSID && !approved.User.Sid.IsWellKnown(windows.WinLocalSystemSid) {
				var target uintptr
				target, err = process.duplicate(user)
				if err == nil {
					err = engine.AdoptUserToken(initialize, target)
				}
			}
			user.Close()
		}
	}
	cancel()
	if err != nil {
		engine.Shutdown()
		return nil, err
	}
	go func() {
		ticker := time.NewTicker(650 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-parent.Done():
				return
			case <-process.done:
				return
			case <-ticker.C:
				if session != windows.WTSGetActiveConsoleSessionId() {
					engine.Shutdown()
					return
				}
				renewal, finish := context.WithTimeout(parent, 500*time.Millisecond)
				err := engine.DelegateDesktop(renewal, session, time.Now().Add(2*time.Second), policy())
				finish()
				if err != nil && !errors.Is(err, context.Canceled) {
					engine.Shutdown()
					return
				}
			}
		}
	}()
	return engine, nil
}
