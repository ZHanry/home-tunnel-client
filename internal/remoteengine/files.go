package remoteengine

import (
	"context"

	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

var _ remotehost.HostFileEngine = (*Engine)(nil)

func (e *Engine) OfferFiles(ctx context.Context, ref remotehost.SessionRef, paths []string) error {
	return e.call(ctx, "file_offer_sources", struct {
		remotehost.SessionRef
		Paths []string `json:"paths"`
	}{ref, paths}, nil)
}
func (e *Engine) AcceptFile(ctx context.Context, ref remotehost.SessionRef, id, path string) error {
	return e.call(ctx, "file_accept", struct {
		remotehost.SessionRef
		ID   string `json:"file_id"`
		Path string `json:"path"`
	}{ref, id, path}, nil)
}
func (e *Engine) CancelFile(ctx context.Context, ref remotehost.SessionRef, id string) error {
	return e.call(ctx, "file_cancel", struct {
		remotehost.SessionRef
		ID string `json:"file_id"`
	}{ref, id}, nil)
}
