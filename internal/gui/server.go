package gui

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/api"
	"github.com/ZHanry/home-tunnel-client/internal/app"
	"github.com/ZHanry/home-tunnel-client/internal/filedialog"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

//go:embed web/*
var webFiles embed.FS

type Options struct {
	Version           string
	LocalToken        string
	StatePath         string
	AgentPath         string
	ExpectedAgentHash string
	AgentVersion      string
	RemoteEngine      remotehost.HostEngine
	RemoteFilePicker  filedialog.Picker
}

type Server struct {
	options            Options
	parent             context.Context
	mu                 sync.Mutex
	cancel             context.CancelFunc
	done               chan struct{}
	running            bool
	quit               func()
	show               func()
	openRemote         func(string) error
	closeRemote        func()
	remoteMu           sync.Mutex
	remoteHost         *localRemoteHost
	remoteBlocked      bool
	setEmergencyHotkey func(string) error
	accountMu          sync.Mutex
	accountGeneration  uint64
	accountCancel      context.CancelFunc
}

func New(options Options) *Server {
	if options.LocalToken == "" {
		options.LocalToken = newLocalToken()
	}
	return &Server{options: options, parent: context.Background()}
}

func (server *Server) Attach(parent context.Context) {
	server.parent = parent
}

func (server *Server) SetQuit(quit func()) {
	server.mu.Lock()
	server.quit = quit
	server.mu.Unlock()
}

func (server *Server) SetShow(show func()) {
	server.mu.Lock()
	server.show = show
	server.mu.Unlock()
}

func (server *Server) SetOpenRemote(open func(string) error) {
	server.mu.Lock()
	server.openRemote = open
	server.mu.Unlock()
}

func (server *Server) SetCloseRemote(close func()) {
	server.mu.Lock()
	server.closeRemote = close
	server.mu.Unlock()
}

func (server *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	content, err := fs.Sub(webFiles, "web")
	if err != nil {
		panic(err)
	}
	mux.Handle("/", http.FileServer(http.FS(content)))
	mux.HandleFunc("/local/ping", func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, map[string]any{"ok": true})
	})
	mux.HandleFunc("/local/state", server.state)
	mux.HandleFunc("/local/login", server.login)
	mux.HandleFunc("/local/connections", server.connections)
	mux.HandleFunc("/local/devices", server.devices)
	mux.HandleFunc("/local/connections/", server.connectionItem)
	mux.HandleFunc("/local/logout", server.logout)
	mux.HandleFunc("/local/show", server.showWindow)
	mux.HandleFunc("/local/quit", server.quitProcess)
	mux.HandleFunc("/local/update", server.update)
	mux.HandleFunc("/local/update/download", server.downloadUpdate)
	mux.HandleFunc("/local/remote/capabilities", server.remoteCapabilities)
	mux.HandleFunc("/local/remote/state", server.remoteState)
	mux.HandleFunc("/local/remote/trust", server.remoteTrust)
	mux.HandleFunc("/local/remote/action", server.remoteAction)
	mux.HandleFunc("/local/remote/files", server.remoteFiles)
	mux.HandleFunc("/local/remote/window", server.remoteWindow)
	mux.HandleFunc("/local/subdomain", server.subdomain)
	mux.HandleFunc("/local/doctor", server.doctor)
	mux.HandleFunc("/local/device/metadata", server.deviceMetadata)
	mux.HandleFunc("/local/batch", server.batchConnections)
	return protectLocalUI(mux, server.options.LocalToken)
}

func ListenLoopback() (net.Listener, error) {
	return net.Listen("tcp", UIAddress)
}

func (server *Server) StartAgent(parent context.Context) {
	server.mu.Lock()
	if server.running {
		server.mu.Unlock()
		return
	}
	ctx, cancel := context.WithCancel(parent)
	done := make(chan struct{})
	server.cancel = cancel
	server.done = done
	server.running = true
	server.mu.Unlock()
	go func() {
		_ = app.Run(ctx, app.RunOptions{
			StatePath:         server.options.StatePath,
			AgentPath:         server.options.AgentPath,
			ExpectedAgentHash: server.options.ExpectedAgentHash,
			AgentVersion:      server.options.AgentVersion,
		})
		close(done)
		server.mu.Lock()
		server.running = false
		server.cancel = nil
		server.done = nil
		server.mu.Unlock()
	}()
}

func (server *Server) StopAgent() {
	server.beginAccountChange(nil)
	server.stopRemote(false)
	server.mu.Lock()
	cancel := server.cancel
	done := server.done
	server.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if done == nil {
		return
	}
	select {
	case <-done:
	case <-time.After(20 * time.Second):
	}
}

// Filter both live and cached results, including results from older servers.
func localConnections(items []model.Connection, deviceID string) []model.Connection {
	local := make([]model.Connection, 0, len(items))
	if deviceID == "" {
		return local
	}
	for _, item := range items {
		if item.DeviceID == deviceID {
			local = append(local, item)
		}
	}
	return local
}

func (server *Server) state(writer http.ResponseWriter, request *http.Request) {
	state, err := (statepkg.Store{Path: server.options.StatePath}).Load()
	if err != nil && !errors.Is(err, statepkg.ErrStateDamaged) {
		writeError(writer, http.StatusInternalServerError, err.Error())
		return
	}
	stale := false
	capabilities := model.ConnectionCapabilities{}
	connections := localConnections(state.CachedConnections, state.DeviceID)
	console := state.Profile.PublicBaseURL
	if state.Enrolled() {
		if client, _, clientErr := server.client(); clientErr == nil {
			ctx, cancel := context.WithTimeout(request.Context(), 12*time.Second)
			catalog, listErr := client.ListConnectionCatalog(ctx)
			cancel()
			if listErr == nil {
				connections = localConnections(catalog.Items, state.DeviceID)
				capabilities = catalog.Capabilities
			} else {
				stale = true
			}
		} else {
			stale = true
		}
	}
	writeJSON(writer, map[string]any{
		"enrolled":       state.Enrolled(),
		"stale":          stale,
		"last_synced_at": state.UpdatedAt,
		"agent_state":    state.AgentState,
		"agent_message":  state.AgentMessage,
		"console_url":    console,
		"device_id":      state.DeviceID,
		"device_name":    app.DefaultDeviceName(),
		"version":        currentVersion(server.options),
		"connections":    connections,
		"capabilities":   capabilities,
	})
}

func (server *Server) login(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Server         string `json:"server"`
		Username       string `json:"username"`
		Password       string `json:"password"`
		NewPassword    string `json:"new_password"`
		MFACode        string `json:"mfa_code"`
		EnrollmentCode string `json:"enrollment_code"`
	}
	if err := readJSON(request, &body); err != nil {
		writeError(writer, http.StatusBadRequest, err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 45*time.Second)
	defer cancel()
	generation := server.beginAccountChange(cancel)
	server.stopRemote(true)
	server.accountMu.Lock()
	defer server.accountMu.Unlock()
	if !server.currentAccountChange(ctx, generation) {
		writeError(writer, http.StatusConflict, "Account operation superseded")
		return
	}
	if err := app.Enroll(ctx, app.EnrollOptions{
		StatePath:      server.options.StatePath,
		Server:         body.Server,
		Username:       body.Username,
		Password:       body.Password,
		NewPassword:    body.NewPassword,
		MFACode:        body.MFACode,
		EnrollmentCode: body.EnrollmentCode,
		DeviceName:     app.DefaultDeviceName(),
		CommitState:    func(state model.State) error { return server.commitEnrollment(ctx, generation, state) },
	}); err != nil {
		writeError(writer, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(writer, map[string]any{"ok": true})
}

// Account mutations are serialized; their generation is invalidated immediately
// so a slow login cannot save credentials or restart services after sign-out.
func (server *Server) beginAccountChange(cancel context.CancelFunc) uint64 {
	server.mu.Lock()
	closeRemote := server.closeRemote
	server.mu.Unlock()
	if closeRemote != nil {
		closeRemote()
	}
	server.remoteMu.Lock()
	defer server.remoteMu.Unlock()
	if server.accountCancel != nil {
		server.accountCancel()
	}
	server.accountGeneration++
	server.accountCancel = cancel
	server.remoteBlocked = true
	return server.accountGeneration
}

func (server *Server) currentAccountChange(ctx context.Context, generation uint64) bool {
	server.remoteMu.Lock()
	defer server.remoteMu.Unlock()
	return ctx.Err() == nil && generation == server.accountGeneration
}

func (server *Server) commitEnrollment(ctx context.Context, generation uint64, state model.State) error {
	server.remoteMu.Lock()
	defer server.remoteMu.Unlock()
	if ctx.Err() != nil || generation != server.accountGeneration {
		return errors.New("account operation superseded")
	}
	if err := (statepkg.Store{Path: server.options.StatePath}).Save(state); err != nil {
		return err
	}
	server.remoteHost = nil
	server.remoteBlocked = false
	server.StartAgent(server.parent)
	return nil
}

func (server *Server) connections(writer http.ResponseWriter, request *http.Request) {
	client, state, err := server.client()
	if err != nil {
		writeError(writer, http.StatusUnauthorized, err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 20*time.Second)
	defer cancel()
	if request.Method == http.MethodGet {
		items, err := client.ListConnections(ctx)
		if err != nil {
			writeError(writer, http.StatusBadGateway, err.Error())
			return
		}
		writeJSON(writer, map[string]any{"items": localConnections(items, state.DeviceID)})
		return
	}
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Name                string `json:"name"`
		Subdomain           string `json:"subdomain"`
		LocalHost           string `json:"local_host"`
		LocalPort           int    `json:"local_port"`
		LocalScheme         string `json:"local_scheme"`
		Enabled             bool   `json:"enabled"`
		ProxyType           string `json:"proxy_type"`
		ApplicationProtocol string `json:"application_protocol"`
	}
	if err := readJSON(request, &body); err != nil {
		writeError(writer, http.StatusBadRequest, err.Error())
		return
	}
	if body.ProxyType == "" {
		body.ProxyType = "http"
	}
	if body.LocalScheme == "" {
		body.LocalScheme = "http"
	}
	if body.ProxyType != "http" && body.ProxyType != "tcp" && body.ProxyType != "udp" {
		writeError(writer, http.StatusBadRequest, "请选择 HTTP、TCP 或 UDP 传输")
		return
	}
	created, err := client.CreateConnection(ctx, state.DeviceID, body.Name, body.Subdomain, body.LocalScheme, body.LocalHost, body.LocalPort, body.Enabled, body.ProxyType, body.ApplicationProtocol)
	if err != nil {
		writeClientError(writer, err)
		return
	}
	writeJSON(writer, created)
}

func (server *Server) devices(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	client, state, err := server.client()
	if err != nil {
		writeError(writer, http.StatusUnauthorized, err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 20*time.Second)
	defer cancel()
	items, err := client.ListRemoteDevices(ctx)
	if err != nil {
		writeError(writer, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(writer, map[string]any{"items": items, "local_device_id": state.DeviceID})
}

func (server *Server) connectionItem(writer http.ResponseWriter, request *http.Request) {
	id := strings.TrimPrefix(request.URL.Path, "/local/connections/")
	if id == "" {
		writer.WriteHeader(http.StatusNotFound)
		return
	}
	client, state, err := server.client()
	if err != nil {
		writeError(writer, http.StatusUnauthorized, err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 20*time.Second)
	defer cancel()
	items, err := client.ListConnections(ctx)
	if err != nil {
		writeError(writer, http.StatusBadGateway, err.Error())
		return
	}
	var current *model.Connection
	for index := range items {
		if items[index].ID == id && items[index].DeviceID == state.DeviceID {
			current = &items[index]
			break
		}
	}
	if current == nil {
		writeError(writer, http.StatusNotFound, "连接不存在")
		return
	}
	switch request.Method {
	case http.MethodDelete:
		if err := client.DeleteConnection(ctx, current.ID, current.Version); err != nil {
			writeError(writer, http.StatusBadRequest, err.Error())
			return
		}
		writer.WriteHeader(http.StatusNoContent)
	case http.MethodPatch:
		var body struct {
			Name            *string `json:"name"`
			Subdomain       *string `json:"subdomain"`
			LocalHost       *string `json:"local_host"`
			LocalPort       *int    `json:"local_port"`
			LocalScheme     *string `json:"local_scheme"`
			ExpectedVersion *int64  `json:"expected_version"`
			Enabled         *bool   `json:"enabled"`
		}
		if err := readJSON(request, &body); err != nil {
			writeError(writer, http.StatusBadRequest, err.Error())
			return
		}
		patch := map[string]any{}
		if body.Name != nil {
			patch["name"] = *body.Name
		}
		if body.Subdomain != nil {
			patch["subdomain"] = *body.Subdomain
		}
		if body.LocalHost != nil {
			patch["local_host"] = *body.LocalHost
		}
		if body.LocalPort != nil {
			patch["local_port"] = *body.LocalPort
		}
		if body.LocalScheme != nil {
			patch["local_scheme"] = *body.LocalScheme
		}
		if body.Enabled != nil {
			patch["enabled"] = *body.Enabled
		}
		expectedVersion := current.Version
		if body.ExpectedVersion != nil {
			expectedVersion = *body.ExpectedVersion
		}
		updated, err := client.UpdateConnection(ctx, current.ID, expectedVersion, patch)
		if err != nil {
			writeClientError(writer, err)
			return
		}
		writeJSON(writer, updated)
	default:
		writer.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (server *Server) logout(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	generation := server.beginAccountChange(cancel)
	server.stopRemote(true)
	server.accountMu.Lock()
	defer server.accountMu.Unlock()
	if !server.currentAccountChange(ctx, generation) {
		writeError(writer, http.StatusConflict, "Account operation superseded")
		return
	}
	if client, _, err := server.client(); err == nil {
		ctx, cancel := context.WithTimeout(request.Context(), 8*time.Second)
		_ = client.Logout(ctx)
		cancel()
	}
	server.StopAgent()
	_ = os.Remove(server.options.StatePath)
	_ = os.RemoveAll(filepath.Join(filepath.Dir(server.options.StatePath), "runtime"))
	writeJSON(writer, map[string]any{"ok": true})
}

func (server *Server) showWindow(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost && request.Method != http.MethodGet {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	server.mu.Lock()
	show := server.show
	server.mu.Unlock()
	if show != nil {
		show()
	}
	writeJSON(writer, map[string]any{"ok": true})
}

func (server *Server) quitProcess(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	server.beginAccountChange(nil)
	server.StopAgent()
	writeJSON(writer, map[string]any{"ok": true})
	server.mu.Lock()
	quit := server.quit
	server.mu.Unlock()
	if quit != nil {
		go quit()
	}
}

func (server *Server) subdomain(writer http.ResponseWriter, request *http.Request) {
	client, _, err := server.client()
	if err != nil {
		writeError(writer, http.StatusUnauthorized, err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 20*time.Second)
	defer cancel()
	result, err := client.SubdomainAvailability(ctx, request.URL.Query().Get("name"))
	if err != nil {
		writeError(writer, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(writer, result)
}

func (server *Server) client() (*api.Client, model.State, error) {
	server.mu.Lock()
	defer server.mu.Unlock()
	state, err := (statepkg.Store{Path: server.options.StatePath}).Load()
	if err != nil {
		return nil, state, err
	}
	if !state.Enrolled() {
		return nil, state, errors.New("尚未登录")
	}
	client, err := api.New(state.Profile.APIBaseURL, nil)
	if err != nil {
		return nil, state, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if _, err := client.DeviceLogin(ctx, state.DeviceID, state.DeviceCredential); err != nil {
		return nil, state, err
	}
	return client, state, nil
}

func readJSON(request *http.Request, target any) error {
	defer request.Body.Close()
	data, err := io.ReadAll(io.LimitReader(request.Body, 1<<20))
	if err != nil {
		return err
	}
	return json.Unmarshal(data, target)
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("content-type", "application/json")
	_ = json.NewEncoder(writer).Encode(value)
}

func writeError(writer http.ResponseWriter, status int, message string) {
	writer.Header().Set("content-type", "application/json")
	writer.WriteHeader(status)
	_ = json.NewEncoder(writer).Encode(map[string]string{"message": message})
}
