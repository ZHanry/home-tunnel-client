package gui

import (
	"context"
	"errors"
	"github.com/ZHanry/home-tunnel-client/internal/api"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/origin"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

var remoteDeviceID = regexp.MustCompile(`^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$`)
var remoteAccessID = regexp.MustCompile(`^[0-9]{9}$`)

func remoteWindowURL(base, deviceID string) (string, error) {
	return remoteViewURL(base, "remoteDevice", deviceID)
}

func remoteAssistanceURL(base, accessID string) (string, error) {
	if accessID == "" {
		return remoteViewURL(base, "remoteAssist", "1")
	}
	return remoteViewURL(base, "remoteAssist", "1", "remoteAccessId", accessID)
}

func remoteViewURL(base string, query ...string) (string, error) {
	address, err := origin.HTTPS(base)
	if err != nil {
		return "", url.InvalidHostError(base)
	}
	address.Path = "/admin"
	address.RawPath = ""
	values := url.Values{"nativeRemote": []string{"1"}}
	for i := 0; i+1 < len(query); i += 2 {
		values.Set(query[i], query[i+1])
	}
	address.RawQuery = values.Encode()
	address.ForceQuery = false
	address.Fragment = "remote"
	address.RawFragment = ""
	return address.String(), nil
}

func (server *Server) remoteWindow(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, 256)
	var body struct {
		DeviceID string `json:"device_id"`
		Assist   bool   `json:"assist"`
		AccessID string `json:"access_id"`
	}
	if err := readJSON(request, &body); err != nil || (body.Assist && body.DeviceID != "") || (!body.Assist && (body.AccessID != "" || !remoteDeviceID.MatchString(body.DeviceID))) || (body.AccessID != "" && !remoteAccessID.MatchString(body.AccessID)) {
		writeError(writer, http.StatusBadRequest, "设备标识无效")
		return
	}
	server.mu.Lock()
	open := server.openRemote
	server.mu.Unlock()
	if open == nil {
		writeError(writer, http.StatusServiceUnavailable, "远程控制窗口不可用")
		return
	}
	server.remoteMu.Lock()
	accountGeneration, blocked := server.accountGeneration, server.remoteBlocked
	server.remoteMu.Unlock()
	if blocked {
		writeRemoteError(writer, http.StatusConflict, "NATIVE_HANDOFF_CANCELLED", "账号正在更改，请稍后重试")
		return
	}
	work, cancel := context.WithTimeout(request.Context(), 30*time.Second)
	defer cancel()
	server.remoteSessionMu.Lock()
	server.remoteGeneration++
	generation := server.remoteGeneration
	previousCancel := server.remoteSessionCancel
	server.remoteSessionCancel = cancel
	server.remoteSessionMu.Unlock()
	if previousCancel != nil {
		previousCancel()
	}
	request = request.WithContext(work)
	client, state, err := server.client()
	if err != nil {
		writeError(writer, http.StatusUnauthorized, "请先登录")
		return
	}
	keepSession := false
	defer func() {
		if !keepSession {
			closeRemoteClient(client)
		}
	}()
	if strings.EqualFold(body.DeviceID, state.DeviceID) || (body.Assist && body.AccessID != "" && server.ownRemoteAccessID(body.AccessID)) {
		writeRemoteError(writer, http.StatusConflict, "RD_SELF_CONNECTION", "不能远程连接当前设备")
		return
	}
	if !body.Assist {
		ctx, cancel := context.WithTimeout(request.Context(), 12*time.Second)
		defer cancel()
		devices, listErr := client.ListRemoteDevices(ctx)
		if listErr != nil {
			writeClientError(writer, listErr)
			return
		}
		allowed := false
		for _, device := range devices {
			if device.ID == body.DeviceID && device.ID != state.DeviceID && device.Status == "active" && device.Online {
				allowed = true
				break
			}
		}
		if !allowed {
			writeError(writer, http.StatusNotFound, "设备离线或不属于当前账号")
			return
		}
	}
	var address string
	if body.Assist {
		address, err = remoteAssistanceURL(state.Profile.PublicBaseURL, body.AccessID)
	} else {
		address, err = remoteWindowURL(state.Profile.PublicBaseURL, body.DeviceID)
	}
	if err != nil {
		writeError(writer, http.StatusBadGateway, "服务器地址无效")
		return
	}
	handoff, err := client.CreateRemoteHandoff(request.Context(), state.Profile.PublicBaseURL)
	if err != nil {
		if errors.Is(err, api.ErrRemoteHandoffUnsupported) {
			writeRemoteError(writer, http.StatusUpgradeRequired, "NATIVE_HANDOFF_UNSUPPORTED", "请将服务器升级至 10.1.0 或更高版本后使用远程窗口")
		} else {
			writeClientError(writer, err)
		}
		return
	}
	// Lock order is account state, then remote session. Account transitions
	// invalidate this generation before starting their slower cleanup.
	server.remoteMu.Lock()
	defer server.remoteMu.Unlock()
	server.remoteSessionMu.Lock()
	if work.Err() != nil || generation != server.remoteGeneration || server.remoteBlocked || accountGeneration != server.accountGeneration {
		server.remoteSessionMu.Unlock()
		writeRemoteError(writer, http.StatusConflict, "NATIVE_HANDOFF_CANCELLED", "远程窗口请求已取消")
		return
	}
	if err := open(model.RemoteWindowLaunch{URL: address, HandoffCode: handoff.Code, WindowID: handoff.WindowID, Generation: generation}); err != nil {
		server.remoteSessionMu.Unlock()
		writeError(writer, http.StatusServiceUnavailable, "远程控制窗口不可用")
		return
	}
	previous := server.remoteSession
	server.remoteSession = client
	server.remoteSessionGeneration = generation
	server.remoteSessionMu.Unlock()
	closeRemoteClient(previous)
	keepSession = true
	writeJSON(writer, map[string]bool{"ok": true})
}

func writeRemoteError(writer http.ResponseWriter, status int, code, message string) {
	writer.Header().Set("content-type", "application/json")
	writer.WriteHeader(status)
	writeJSON(writer, map[string]string{"error_code": code, "message": message})
}
func closeRemoteClient(client *api.Client) {
	if client == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = client.CloseSession(ctx)
}
func (server *Server) CloseRemoteSession() { server.RemoteWindowClosed(0) }
func (server *Server) RemoteWindowClosed(generation uint64) {
	server.remoteSessionMu.Lock()
	if generation != 0 && generation != server.remoteSessionGeneration {
		server.remoteSessionMu.Unlock()
		return
	}
	server.remoteGeneration++
	client, cancel := server.remoteSession, server.remoteSessionCancel
	server.remoteSession, server.remoteSessionCancel = nil, nil
	server.remoteSessionMu.Unlock()
	if cancel != nil {
		cancel()
	}
	closeRemoteClient(client)
}
func (server *Server) ownRemoteAccessID(id string) bool {
	server.remoteMu.Lock()
	host := server.remoteHost
	server.remoteMu.Unlock()
	if host == nil {
		return false
	}
	host.mu.Lock()
	defer host.mu.Unlock()
	return host.accessProfile.DeviceID == id
}
