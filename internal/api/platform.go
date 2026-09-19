package api

import (
	"context"
	"net/http"
	"net/url"
)

type BatchItem struct {
	ID              string `json:"id"`
	ExpectedVersion int64  `json:"expected_version"`
}

type BatchResult struct {
	ID        string `json:"id"`
	Status    int    `json:"status"`
	ErrorCode string `json:"error_code,omitempty"`
}

func (client *Client) SetDeviceMetadata(ctx context.Context, id string, tags []string, favorite bool, version int64) error {
	client.mu.Lock()
	defer client.mu.Unlock()
	return client.authJSON(ctx, http.MethodPatch, "client/devices/"+url.PathEscape(id)+"/metadata",
		map[string]any{"tags": tags, "favorite": favorite, "expected_metadata_version": version}, nil)
}

func (client *Client) BatchConnections(ctx context.Context, items []BatchItem, enabled bool) ([]BatchResult, error) {
	client.mu.Lock()
	defer client.mu.Unlock()
	var result struct {
		Results []BatchResult `json:"results"`
	}
	err := client.authJSON(ctx, http.MethodPost, "client/connections/batch", map[string]any{"items": items, "enabled": enabled}, &result)
	return result.Results, err
}
