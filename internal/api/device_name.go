package api

import (
	"context"
	"errors"
	"net/http"

	"github.com/ZHanry/home-tunnel-client/internal/model"
)

// RenameCurrentDevice uses the authenticated session's device binding. It
// deliberately accepts no device ID or account ID from the desktop form.
func (client *Client) RenameCurrentDevice(ctx context.Context, name string) (string, error) {
	name, err := model.NormalizeDeviceName(name)
	if err != nil {
		return "", err
	}
	client.mu.Lock()
	defer client.mu.Unlock()
	if client.deviceID == "" {
		return "", errors.New("a device session is required to rename this computer")
	}
	var response struct {
		DeviceID   string `json:"device_id"`
		DeviceName string `json:"device_name"`
	}
	if err := client.authJSON(ctx, http.MethodPatch, "devices/current/name", map[string]string{"name": name}, &response); err != nil {
		return "", err
	}
	canonical, err := model.NormalizeDeviceName(response.DeviceName)
	if err != nil || response.DeviceID != client.deviceID || canonical != response.DeviceName {
		return "", errors.New("server returned an invalid current-device name")
	}
	return canonical, nil
}
