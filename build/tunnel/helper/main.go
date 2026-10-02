// HOMEDESK: 仅供同目录 HomeDesk 父进程调用的受管隧道助手；不启动上游 GUI 或远控。
package main

import (
    "bufio"
    "bytes"
    "context"
    "encoding/json"
    "errors"
    "flag"
    "io"
    "log"
    "net/http"
    "net/url"
    "os"
    "path/filepath"
    "strconv"
    "strings"
    "sync/atomic"
    "time"
    "unsafe"

    "github.com/ZHanry/home-tunnel-client/internal/api"
    "github.com/ZHanry/home-tunnel-client/internal/app"
    "github.com/ZHanry/home-tunnel-client/internal/model"
    statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
    "golang.org/x/sys/windows"
)

var parentExecutable string
var expectedAgentSHA256 string

func emit(phase, code, deviceID, state string) {
    _ = json.NewEncoder(os.Stdout).Encode(map[string]string{
        "phase": phase, "code": code, "device_id": deviceID, "agent_state": state,
    })
}

// 后台网络在原生进程校验许可、分配 Job Object 并写入 stdin 门闩后才开始。
func readLine(reader *bufio.Reader) (string, error) {
    line, err := reader.ReadString('\n')
    if len(line) > 4096 || (err != nil && !errors.Is(err, io.EOF)) {
        return "", errors.New("invalid input")
    }
    return strings.TrimRight(line, "\r\n"), nil
}

func checkParent(parentID uint32) error {
    snapshot, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
    if err != nil { return err }
    defer windows.CloseHandle(snapshot)
    var entry windows.ProcessEntry32
    entry.Size = uint32(unsafe.Sizeof(entry))
    err = windows.Process32First(snapshot, &entry)
    matched := false
    for err == nil {
        if entry.ProcessID == uint32(os.Getpid()) {
            matched = entry.ParentProcessID == parentID
            break
        }
        err = windows.Process32Next(snapshot, &entry)
    }
    if !matched { return errors.New("parent mismatch") }
    process, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, parentID)
    if err != nil { return err }
    defer windows.CloseHandle(process)
    buffer := make([]uint16, 32768)
    size := uint32(len(buffer))
    if err = windows.QueryFullProcessImageName(process, 0, &buffer[0], &size); err != nil { return err }
    executable, err := os.Executable()
    if err != nil { return err }
    expected := filepath.Join(filepath.Dir(filepath.Dir(executable)), parentExecutable)
    if !strings.EqualFold(filepath.Clean(windows.UTF16ToString(buffer[:size])), filepath.Clean(expected)) {
        return errors.New("parent image mismatch")
    }
    return nil
}

// 控制请求只发往本机已批准的 HTTPS origin；公开配置不能授予其他服务器地址。
type guardedTransport struct {
    origin *url.URL
    transport *http.Transport
    enrollmentPosted atomic.Bool
}

func validateProfile(profile model.Profile, origin *url.URL) error {
    base, err := url.Parse(profile.PublicBaseURL)
    // 公共配置不包含 api_base_url；上游 Discover 会在同一 origin 下派生 /api/v1/。
    if err != nil || base.Scheme != "https" || base.User != nil ||
        base.RawQuery != "" || base.Fragment != "" || (base.Path != "" && base.Path != "/") ||
        !strings.EqualFold(base.Host, origin.Host) ||
        !strings.EqualFold(profile.FRPSHost, origin.Hostname()) || profile.FRPSPort < 1 ||
        profile.FRPSPort > 65535 || profile.FRPSTLSCertificatePEM == "" {
        return errors.New("configuration boundary")
    }
    return nil
}

func (guard *guardedTransport) RoundTrip(request *http.Request) (*http.Response, error) {
    if request.URL.Scheme != "https" || !strings.EqualFold(request.URL.Host, guard.origin.Host) {
        return nil, errors.New("origin mismatch")
    }
    if request.Method == http.MethodPost && request.URL.Path == "/api/v1/auth/enroll" {
        guard.enrollmentPosted.Store(true)
    }
    response, err := guard.transport.RoundTrip(request)
    if err != nil || response.StatusCode != http.StatusOK || request.URL.Path != "/api/v1/public/config" {
        return response, err
    }
    payload, err := io.ReadAll(io.LimitReader(response.Body, 32769))
    response.Body.Close()
    if err != nil || len(payload) > 32768 { return nil, errors.New("configuration size") }
    var profile model.Profile
    if json.Unmarshal(payload, &profile) != nil { return nil, errors.New("configuration format") }
    if err = validateProfile(profile, guard.origin); err != nil { return nil, err }
    response.Body = io.NopCloser(bytes.NewReader(payload))
    return response, nil
}

func protectDirectory(path string) error {
    if err := os.MkdirAll(path, 0700); err != nil { return err }
    descriptor, err := windows.SecurityDescriptorFromString("D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;OW)")
    if err != nil { return err }
    dacl, _, err := descriptor.DACL()
    if err != nil { return err }
    return windows.SetNamedSecurityInfo(path, windows.SE_FILE_OBJECT,
        windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION,
        nil, nil, dacl, nil)
}

func execute() int {
    if len(os.Args) < 2 { return 2 }
    command := os.Args[1]
    flags := flag.NewFlagSet(command, flag.ContinueOnError)
    flags.SetOutput(io.Discard)
    statePath := flags.String("state", "", "")
    origin := flags.String("origin", "", "")
    name := flags.String("name", app.DefaultDeviceName(), "")
    parent := flags.String("parent", "", "")
    if flags.Parse(os.Args[2:]) != nil || flags.NArg() != 0 { return 2 }
    parentID, err := strconv.ParseUint(*parent, 10, 32)
    if err != nil || checkParent(uint32(parentID)) != nil { return 2 }
    reader := bufio.NewReader(io.LimitReader(os.Stdin, 8193))
    gate, err := readLine(reader)
    if err != nil || gate != "HOMEDESK_AGENT_ALLOWED" { return 2 }
    root, err := url.Parse(*origin)
    if err != nil || root.Scheme != "https" || root.Host == "" || root.User != nil ||
        root.RawQuery != "" || root.Fragment != "" || !filepath.IsAbs(*statePath) { return 2 }
    if err = protectDirectory(filepath.Dir(*statePath)); err != nil {
        emit("error", "STATE_PROTECTION_FAILED", "", ""); return 1
    }
    store := statepkg.Store{Path:*statePath}
    state, err := store.Load()
    if err != nil { emit("error", "STATE_DAMAGED", "", ""); return 1 }
    marker := *statePath + ".enrolling"
    _, pending := os.Stat(marker)
    if state.Enrolled() && !strings.EqualFold(strings.TrimRight(state.Profile.PublicBaseURL, "/"), strings.TrimRight(*origin, "/")) {
        emit("error", "ORIGIN_MISMATCH", "", ""); return 1
    }
    if command == "inspect" {
        if state.Enrolled() {
            emit("registered", "", state.DeviceID, state.AgentState)
        } else if pending == nil {
            emit("error", "ENROLLMENT_RESULT_UNKNOWN", "", "")
        } else {
            if err = store.Save(state); err != nil { emit("error", "STATE_PROTECTION_FAILED", "", ""); return 1 }
            emit("needs_enrollment", "", "", "")
        }
        return 0
    }
    transport := http.DefaultTransport.(*http.Transport).Clone()
    transport.Proxy = nil
    guard := &guardedTransport{origin:root,transport:transport}
    client := &http.Client{Timeout:12*time.Second, Transport:guard,
        CheckRedirect:func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
    if command == "enroll" {
        if state.Enrolled() || pending == nil { emit("error", "ENROLLMENT_RESULT_UNKNOWN", "", ""); return 1 }
        code, readErr := readLine(reader)
        if readErr != nil || code == "" { return 2 }
        file, markerErr := os.OpenFile(marker, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
        if markerErr != nil { emit("error", "STATE_DAMAGED", "", ""); return 1 }
        file.Close()
        ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
        defer cancel()
        err = app.Enroll(ctx, app.EnrollOptions{StatePath:*statePath, Server:*origin,
            DeviceName:*name, EnrollmentCode:code, HTTPClient:client})
        if err != nil {
            var rejection *api.Error
            if !guard.enrollmentPosted.Load() {
                _ = os.Remove(marker)
                emit("error", "DISCOVERY_FAILED", "", "")
            } else if errors.As(err, &rejection) && rejection.StatusCode >= 400 && rejection.StatusCode < 500 {
                _ = os.Remove(marker)
                emit("error", "ENROLLMENT_REJECTED", "", "")
            } else { emit("error", "ENROLLMENT_RESULT_UNKNOWN", "", "") }
            return 1
        }
        _ = os.Remove(marker)
        state, err = store.Load()
        if err != nil { emit("error", "STATE_DAMAGED", "", ""); return 1 }
        emit("registered", "", state.DeviceID, state.AgentState)
        return 0
    }
    if command != "run" || !state.Enrolled() || state.AgentState == "Revoked" {
        emit("error", "DEVICE_UNAVAILABLE", "", ""); return 1
    }
    executable, err := os.Executable()
    if err != nil { return 1 }
    emit("running", "", state.DeviceID, "Starting")
    // 进程及其 FRP 子进程由父进程 Job Object 管理；标准日志不带出服务端原始错误。
    log.SetOutput(io.Discard)
    err = app.Run(context.Background(), app.RunOptions{StatePath:*statePath,
        AgentPath:filepath.Join(filepath.Dir(executable), "home-tunnel-agent.exe"),
        ExpectedAgentHash:expectedAgentSHA256, AgentVersion:model.Version, HTTPClient:client})
    if errors.Is(err, app.ErrRevoked) { emit("error", "DEVICE_REVOKED", state.DeviceID, "Revoked"); return 1 }
    if err != nil { emit("error", "AGENT_STOPPED", state.DeviceID, "Stopped"); return 1 }
    return 0
}

func main() { os.Exit(execute()) }
