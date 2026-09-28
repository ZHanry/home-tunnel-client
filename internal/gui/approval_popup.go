package gui

import (
	"context"
	"net/http"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
)

// Popup modes. The native host sizes the always-on-top window from the mode;
// the page decides what to draw inside it from /local/remote/state.
const (
	PopupHidden  = ""
	PopupRequest = "request"
	PopupSession = "session"
)

const approvalWatchInterval = 2 * time.Second

// approvalItem is one incoming request the local user has to look at. Keys
// match the ones popup.js derives from the same /local/remote/state payload.
type approvalItem struct {
	Key string
	// Decidable items carry accept/deny buttons. A pairing that already shows
	// its compare code only needs to be read, so it never demands attention.
	Decidable bool
	ExpiresAt time.Time
}

// pendingApprovals lists the requests that still need local attention, in the
// order they arrived at the host. It only reflects host-side state; it never
// decides anything itself.
func pendingApprovals(status remotehost.Status, now time.Time) []approvalItem {
	items := []approvalItem{}
	for _, request := range status.AccessRequests {
		if request.ID == "" || !request.ExpiresAt.After(now) {
			continue
		}
		items = append(items, approvalItem{Key: "access:" + request.ID, Decidable: true, ExpiresAt: request.ExpiresAt})
	}
	for _, event := range status.Pending {
		if event.ID == "" || !event.ExpiresAt.After(now) {
			continue
		}
		switch event.Kind {
		case "pairing", "session":
			items = append(items, approvalItem{Key: event.Kind + ":" + event.ID, Decidable: event.DisplayCode == "", ExpiresAt: event.ExpiresAt})
		case "pairing_display":
			items = append(items, approvalItem{Key: event.Kind + ":" + event.ID, ExpiresAt: event.ExpiresAt})
		}
	}
	return items
}

// approvalTracker turns successive host snapshots into a popup mode. It
// remembers which requests were already announced so the taskbar flashes once
// per new request, and which read-only notices the user closed.
type approvalTracker struct {
	seen         map[string]bool
	acknowledged map[string]bool
	current      map[string]bool
	mode         string
}

func newApprovalTracker() *approvalTracker {
	return &approvalTracker{seen: map[string]bool{}, acknowledged: map[string]bool{}, current: map[string]bool{}}
}

// update returns the mode to show and whether a request arrived that the user
// has not been told about yet.
func (tracker *approvalTracker) update(status remotehost.Status, now time.Time) (mode string, attention bool) {
	items := pendingApprovals(status, now)
	current := make(map[string]bool, len(items))
	decidable, notices := 0, 0
	for _, item := range items {
		current[item.Key] = true
		if tracker.acknowledged[item.Key] {
			continue
		}
		if item.Decidable {
			decidable++
			if !tracker.seen[item.Key] {
				attention = true
			}
		} else {
			notices++
		}
		tracker.seen[item.Key] = true
	}
	// Forget requests the host no longer lists so the maps stay bounded.
	for key := range tracker.seen {
		if !current[key] {
			delete(tracker.seen, key)
		}
	}
	for key := range tracker.acknowledged {
		if !current[key] {
			delete(tracker.acknowledged, key)
		}
	}
	tracker.current = current
	switch {
	case decidable > 0:
		mode = PopupRequest
	// A compare code keeps an already open request popup up after "accept",
	// but a code confirmed from the main window does not open a new popup.
	case notices > 0 && tracker.mode == PopupRequest:
		mode = PopupRequest
	case status.ActiveSessionID != "":
		mode = PopupSession
	default:
		mode = PopupHidden
	}
	tracker.mode = mode
	return mode, attention
}

// acknowledge hides one listed request from the popup without deciding it.
// Unknown keys are ignored so a page cannot grow the tracker.
func (tracker *approvalTracker) acknowledge(key string) bool {
	if !tracker.current[key] {
		return false
	}
	tracker.acknowledged[key] = true
	return true
}

// SetApprovalPopup connects the native popup. show reports whether the window
// is on screen; the watcher retries on its next tick when it is not.
func (server *Server) SetApprovalPopup(show func(mode string, attention bool) bool, hide func()) {
	server.popupMu.Lock()
	server.popupShow = show
	server.popupHide = hide
	server.popupMu.Unlock()
}

// WatchApprovals polls the host state while the desktop runs so incoming
// requests surface even when the main window is hidden in the tray.
func (server *Server) WatchApprovals(ctx context.Context) {
	ticker := time.NewTicker(approvalWatchInterval)
	defer ticker.Stop()
	for {
		server.approvalTick(ctx)
		select {
		case <-ctx.Done():
			server.popupMu.Lock()
			hide := server.popupHide
			server.popupMu.Unlock()
			if hide != nil {
				hide()
			}
			return
		case <-ticker.C:
		case <-server.popupPoke:
		}
	}
}

func (server *Server) pokeApprovalWatcher() {
	select {
	case server.popupPoke <- struct{}{}:
	default:
	}
}

func (server *Server) approvalTick(ctx context.Context) {
	server.popupMu.Lock()
	wired := server.popupShow != nil
	server.popupMu.Unlock()
	if !wired || ctx.Err() != nil {
		return
	}
	probe, cancel := context.WithTimeout(ctx, 4*time.Second)
	_, status, ok := server.remoteSnapshot(probe)
	cancel()
	if !ok {
		// Never keep a stale approval prompt on screen.
		status = remotehost.Status{}
	}
	server.applyApprovalState(status, time.Now())
}

func (server *Server) applyApprovalState(status remotehost.Status, now time.Time) {
	server.popupMu.Lock()
	mode, attention := server.popupTracker.update(status, now)
	// Keep a flash that could not be shown yet for the next successful show.
	attention = attention || server.popupAttention && mode == PopupRequest
	server.popupAttention = attention
	previous := server.popupMode
	show, hide := server.popupShow, server.popupHide
	if mode == PopupHidden {
		server.popupMode = PopupHidden
	}
	server.popupMu.Unlock()
	if mode == previous && !attention {
		return
	}
	if mode == PopupHidden {
		if hide != nil {
			hide()
		}
		return
	}
	if show != nil && show(mode, attention) {
		server.popupMu.Lock()
		server.popupMode = mode
		server.popupAttention = false
		server.popupMu.Unlock()
	}
}

// remotePopup lets the popup page ask for an immediate re-check after a
// decision and close read-only notices. Decisions themselves go through
// /local/remote/action exactly like the main window.
func (server *Server) remotePopup(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, 512)
	var body struct {
		Action string `json:"action"`
		Key    string `json:"key"`
	}
	if err := readJSON(request, &body); err != nil {
		writeError(writer, http.StatusBadRequest, "Invalid popup action")
		return
	}
	switch body.Action {
	case "refresh":
	case "acknowledge":
		server.popupMu.Lock()
		known := server.popupTracker.acknowledge(body.Key)
		server.popupMu.Unlock()
		if !known {
			writeError(writer, http.StatusNotFound, "Request is no longer pending")
			return
		}
	default:
		writeError(writer, http.StatusBadRequest, "Invalid popup action")
		return
	}
	server.pokeApprovalWatcher()
	writeJSON(writer, map[string]bool{"ok": true})
}
