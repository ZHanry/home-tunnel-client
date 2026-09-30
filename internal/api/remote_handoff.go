package api

import (
	"context"
	"errors"
	"github.com/ZHanry/home-tunnel-client/internal/origin"
	"net/http"
	"regexp"
	"time"
)

var ErrRemoteHandoffUnsupported = errors.New("native remote handoff requires an updated server")
var handoffWindowPattern = regexp.MustCompile(`^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$`)
var handoffCodePattern = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)

type RemoteHandoff struct {
	Code      string    `json:"code"`
	WindowID  string    `json:"window_id"`
	ExpiresAt time.Time `json:"expires_at"`
}

func (client *Client) CreateRemoteHandoff(ctx context.Context, publicBase string) (RemoteHandoff, error) {
	client.mu.Lock()
	defer client.mu.Unlock()
	canonical, err := origin.HTTPS(publicBase)
	apiOrigin, apiErr := origin.HTTPS(client.baseURL.String())
	if err != nil || apiErr != nil || canonical.Scheme != "https" || canonical.User != nil || canonical.Opaque != "" || canonical.Host == "" || !sameOrigin(canonical, apiOrigin) {
		return RemoteHandoff{}, errors.New("native remote handoff origin mismatch")
	}
	var result RemoteHandoff
	err = client.authJSON(ctx, http.MethodPost, "auth/native-remote-handoff", map[string]string{"origin": canonical.Scheme + "://" + canonical.Host}, &result)
	var remote *Error
	if errors.As(err, &remote) && (remote.StatusCode == http.StatusNotFound || remote.StatusCode == http.StatusMethodNotAllowed) {
		return RemoteHandoff{}, ErrRemoteHandoffUnsupported
	}
	if err != nil {
		return RemoteHandoff{}, err
	}
	if !handoffWindowPattern.MatchString(result.WindowID) || !handoffCodePattern.MatchString(result.Code) || !result.ExpiresAt.After(time.Now()) || result.ExpiresAt.After(time.Now().Add(time.Minute)) {
		return RemoteHandoff{}, errors.New("invalid native remote handoff")
	}
	return result, nil
}
