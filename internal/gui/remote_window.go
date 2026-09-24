package gui

import (
	"context"
	"net/http"
	"net/url"
	"regexp"
	"time"
)

var remoteDeviceID = regexp.MustCompile(`^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$`)

func remoteWindowURL(base, deviceID string) (string, error) {
	return remoteViewURL(base, "remoteDevice", deviceID)
}

func remoteAssistanceURL(base string) (string, error) {
	return remoteViewURL(base, "remoteAssist", "1")
}

func remoteViewURL(base, queryKey, queryValue string) (string, error) {
	address, err := url.Parse(base)
	if err != nil || address.Host == "" || address.User != nil || (address.Scheme != "http" && address.Scheme != "https") {
		return "", url.InvalidHostError(base)
	}
	address.Path = "/admin"
	address.RawPath = ""
	address.RawQuery = url.Values{queryKey: {queryValue}}.Encode()
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
	}
	if err := readJSON(request, &body); err != nil || (body.Assist && body.DeviceID != "") || (!body.Assist && !remoteDeviceID.MatchString(body.DeviceID)) {
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
	client, state, err := server.client()
	if err != nil {
		writeError(writer, http.StatusUnauthorized, "请先登录")
		return
	}
	defer func() {
		closeContext, closeCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer closeCancel()
		_ = client.CloseSession(closeContext)
	}()
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
		address, err = remoteAssistanceURL(state.Profile.PublicBaseURL)
	} else {
		address, err = remoteWindowURL(state.Profile.PublicBaseURL, body.DeviceID)
	}
	if err != nil {
		writeError(writer, http.StatusBadGateway, "服务器地址无效")
		return
	}
	if err := open(address); err != nil {
		writeError(writer, http.StatusServiceUnavailable, "远程控制窗口不可用")
		return
	}
	writeJSON(writer, map[string]bool{"ok": true})
}
