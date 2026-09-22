package remotehost

import (
	"context"
	"errors"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"
)

var fileUUID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

// HostFileEngine only receives paths produced by explicit local OS selection.
// File contents travel in the native peer channel, never via this control plane.
type HostFileEngine interface {
	OfferFiles(context.Context, SessionRef, []string) error
	AcceptFile(context.Context, SessionRef, string, string) error
	CancelFile(context.Context, SessionRef, string) error
}

type FileEvent struct {
	Event      string `json:"event"`
	ID         string `json:"id"`
	Name       string `json:"name"`
	Size       uint64 `json:"size"`
	Offset     uint64 `json:"offset,omitempty"`
	Outgoing   bool   `json:"outgoing"`
	ErrorCode  string `json:"error_code,omitempty"`
	MayBeSaved bool   `json:"may_be_saved,omitempty"`
}

type FileState struct {
	SessionRef
	CanSend    bool        `json:"can_send"`
	CanReceive bool        `json:"can_receive"`
	Items      []FileEvent `json:"items"`
}

// fileSessionLocked requires s.mu. Native code independently checks its live
// feature approval, selected UDP pair and lease for every file operation.
func (s *Service) fileSessionLocked(ref SessionRef, permission string) (*runningSession, error) {
	r := s.active
	if r == nil || r.Closing || !r.Started || !r.Verified || s.disabled || r.Session.SessionRef != ref || !r.Deadline.After(time.Now()) {
		return nil, ErrAuthorization
	}
	d := s.config.Store.snapshot()
	grant, exists := d.Grants[r.Grant.ID]
	if !d.Enabled || !exists || grant.Revoked || grant.Version != r.Grant.Version || !grant.ExpiresAt.After(time.Now()) {
		return nil, ErrAuthorization
	}
	if permission != "" && (!slices.Contains(grant.Permissions, permission) || !slices.Contains(r.Session.Permissions, permission)) {
		return nil, ErrAuthorization
	}
	return r, nil
}

func (s *Service) FileSessionValid(ref SessionRef) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err := s.fileSessionLocked(ref, "")
	return err == nil
}

func (s *Service) FileState() FileState {
	state := FileState{Items: []FileEvent{}}
	if _, ok := s.config.Engine.(HostFileEngine); !ok {
		return state
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.active == nil {
		return state
	}
	r, err := s.fileSessionLocked(s.active.Session.SessionRef, "")
	if err != nil {
		return state
	}
	state.SessionRef = r.Session.SessionRef
	state.CanSend = slices.Contains(r.Session.Permissions, "files.receive")
	state.CanReceive = slices.Contains(r.Session.Permissions, "files.send")
	for _, id := range r.FileOrder {
		if value, ok := r.Files[id]; ok {
			state.Items = append(state.Items, value)
		}
	}
	return state
}

func (s *Service) fileEvent(ref SessionRef, event FileEvent) error {
	if event.ID == "" && event.Event == "error" && event.Name == "" && event.Size == 0 && event.Offset == 0 && event.ErrorCode != "" && !event.MayBeSaved {
		event.ID = randomID()
	}
	if !fileUUID.MatchString(event.ID) || event.Size > 8<<30 || event.Offset > event.Size || len(event.Name) > 1020 || !utf8.ValidString(event.Name) || len(utf16.Encode([]rune(event.Name))) > 255 || strings.ContainsAny(event.Name, "\\/\x00\r\n") {
		return ErrAuthorization
	}
	if !slices.Contains([]string{"offer", "progress", "complete", "cancelled", "error"}, event.Event) {
		return ErrAuthorization
	}
	if event.ErrorCode != "" {
		if !strings.HasPrefix(event.ErrorCode, "RD_") || len(event.ErrorCode) > 80 {
			return ErrAuthorization
		}
		for _, c := range event.ErrorCode {
			if c != '_' && (c < 'A' || c > 'Z') && (c < '0' || c > '9') {
				return ErrAuthorization
			}
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	permission := "files.send"
	if event.Outgoing {
		permission = "files.receive"
	}
	r, err := s.fileSessionLocked(ref, permission)
	if err != nil {
		return err
	}
	if r.Files == nil {
		r.Files = map[string]FileEvent{}
	}
	if previous, exists := r.Files[event.ID]; exists {
		if previous.Outgoing != event.Outgoing || previous.Name != event.Name && event.Event != "complete" || previous.Size != event.Size || previous.Offset > event.Offset && event.Event == "progress" {
			return ErrAuthorization
		}
	} else {
		if len(r.Files) >= 128 {
			removed := false
			for index, id := range r.FileOrder {
				if slices.Contains([]string{"complete", "cancelled", "error"}, r.Files[id].Event) {
					delete(r.Files, id)
					r.FileOrder = slices.Delete(r.FileOrder, index, index+1)
					removed = true
					break
				}
			}
			if !removed {
				return errors.New("RD_FILE_LIMIT")
			}
		}
		r.FileOrder = append(r.FileOrder, event.ID)
	}
	r.Files[event.ID] = event
	return nil
}

func (s *Service) SelectFiles(ctx context.Context, ref SessionRef, choose func(context.Context) ([]string, error)) error {
	return s.fileAction(ctx, ref, "files.receive", func(engine HostFileEngine) error {
		paths, err := choose(ctx)
		if err != nil {
			return err
		}
		if len(paths) < 1 || len(paths) > 64 {
			return errors.New("RD_FILE_LIMIT")
		}
		for _, path := range paths {
			if !filepath.IsAbs(path) || strings.ContainsRune(path, 0) {
				return errors.New("RD_FILE_PATH_INVALID")
			}
		}
		return s.withCurrentFiles(ctx, ref, "files.receive", func() error { return engine.OfferFiles(ctx, ref, paths) })
	})
}

func (s *Service) SelectDestination(ctx context.Context, ref SessionRef, id string, choose func(context.Context, string) (string, error)) error {
	return s.fileAction(ctx, ref, "files.send", func(engine HostFileEngine) error {
		s.mu.Lock()
		r, err := s.fileSessionLocked(ref, "files.send")
		var item FileEvent
		if err == nil {
			item = r.Files[id]
		}
		s.mu.Unlock()
		if err != nil || item.ID == "" || item.Outgoing || item.Event != "offer" {
			return ErrAuthorization
		}
		path, err := choose(ctx, item.Name)
		if err != nil {
			return err
		}
		if !filepath.IsAbs(path) || strings.ContainsRune(path, 0) {
			return errors.New("RD_FILE_PATH_INVALID")
		}
		return s.withCurrentFiles(ctx, ref, "files.send", func() error {
			s.mu.Lock()
			current, check := s.fileSessionLocked(ref, "files.send")
			pending := check == nil && current.Files[id].Event == "offer" && !current.Files[id].Outgoing
			s.mu.Unlock()
			if !pending {
				return ErrAuthorization
			}
			return engine.AcceptFile(ctx, ref, id, path)
		})
	})
}

func (s *Service) CancelFile(ctx context.Context, ref SessionRef, id string) error {
	if !fileUUID.MatchString(id) {
		return ErrAuthorization
	}
	return s.fileAction(ctx, ref, "", func(engine HostFileEngine) error {
		return s.withCurrentFiles(ctx, ref, "", func() error { return engine.CancelFile(ctx, ref, id) })
	})
}

func (s *Service) fileAction(ctx context.Context, ref SessionRef, permission string, work func(HostFileEngine) error) error {
	engine, ok := s.config.Engine.(HostFileEngine)
	if !ok {
		return ErrUnavailable
	}
	s.mu.Lock()
	_, err := s.fileSessionLocked(ref, permission)
	s.mu.Unlock()
	if err != nil || ctx.Err() != nil {
		return ErrAuthorization
	}
	return work(engine)
}

func (s *Service) withCurrentFiles(ctx context.Context, ref SessionRef, permission string, work func() error) error {
	s.engineMu.Lock()
	defer s.engineMu.Unlock()
	s.mu.Lock()
	_, err := s.fileSessionLocked(ref, permission)
	s.mu.Unlock()
	if err != nil || ctx.Err() != nil {
		return ErrAuthorization
	}
	return work()
}
