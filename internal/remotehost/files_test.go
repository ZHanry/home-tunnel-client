package remotehost

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"
	"time"
)

type fileTestEngine struct {
	fakeEngine
	offers, accepts, cancels int
}

func (e *fileTestEngine) OfferFiles(context.Context, SessionRef, []string) error {
	e.offers++
	return nil
}
func (e *fileTestEngine) AcceptFile(context.Context, SessionRef, string, string) error {
	e.accepts++
	return nil
}
func (e *fileTestEngine) CancelFile(context.Context, SessionRef, string) error {
	e.cancels++
	return nil
}

func fileFixture(t *testing.T) (*Service, *runningSession, *fileTestEngine) {
	t.Helper()
	s, r, _ := authorityFixture(t)
	r.Grant.Permissions = []string{"view", "files.send", "files.receive"}
	r.Session.Permissions = append([]string(nil), r.Grant.Permissions...)
	r.Started, r.Verified = true, true
	r.Deadline = time.Now().Add(time.Minute)
	if err := s.config.Store.update(func(d *diskState) error { d.Grants[r.Grant.ID] = r.Grant; return nil }); err != nil {
		t.Fatal(err)
	}
	engine := &fileTestEngine{}
	s.config.Engine, s.active = engine, r
	return s, r, engine
}

func TestLocalFileSelectionCannotOutliveSessionOrGrant(t *testing.T) {
	for _, change := range []string{"epoch", "session", "revoked", "expired", "closed", "scope"} {
		t.Run(change, func(t *testing.T) {
			s, r, engine := fileFixture(t)
			ref := r.Session.SessionRef
			err := s.SelectFiles(context.Background(), ref, func(context.Context) ([]string, error) {
				switch change {
				case "epoch":
					r.Session.ConnectionEpoch++
				case "session":
					r.Session.SessionID = randomID()
				case "revoked":
					if err := s.config.Store.RevokeGrant(r.Grant.ID); err != nil {
						t.Fatal(err)
					}
				case "expired":
					r.Deadline = time.Now().Add(-time.Second)
				case "closed":
					r.Closing = true
				case "scope":
					r.Session.Permissions = []string{"view"}
				}
				return []string{filepath.Join(t.TempDir(), "selected.txt")}, nil
			})
			if err == nil || engine.offers != 0 {
				t.Fatal("stale file selection reached native worker")
			}
		})
	}
}

func TestFileDialogsRequireVerifiedSessionAndPendingOffer(t *testing.T) {
	s, r, engine := fileFixture(t)
	selected := false
	r.Verified = false
	if err := s.SelectFiles(context.Background(), r.Session.SessionRef, func(context.Context) ([]string, error) { selected = true; return nil, nil }); err == nil || selected {
		t.Fatal("unverified peer opened local dialog")
	}
	r.Verified = true
	id := randomID()
	item := FileEvent{Event: "offer", ID: id, Name: "remote.txt", Size: 2}
	if err := s.fileEvent(r.Session.SessionRef, item); err != nil {
		t.Fatal(err)
	}
	if err := s.SelectDestination(context.Background(), r.Session.SessionRef, id, func(_ context.Context, name string) (string, error) {
		if name != "remote.txt" {
			t.Fatal("unexpected dialog suggestion")
		}
		item.Event = "cancelled"
		if err := s.fileEvent(r.Session.SessionRef, item); err != nil {
			t.Fatal(err)
		}
		return filepath.Join(t.TempDir(), "save.txt"), nil
	}); err == nil || engine.accepts != 0 {
		t.Fatal("cancelled offer was accepted after dialog returned")
	}
}

func TestFileEventsStayLocalAndCannotChangeTransferIdentity(t *testing.T) {
	s, r, _ := fileFixture(t)
	item := FileEvent{Event: "offer", ID: randomID(), Name: "测试.txt", Size: 5 << 30}
	body, _ := json.Marshal(item)
	if err := s.handleEngine(context.Background(), EngineEvent{SessionRef: r.Session.SessionRef, Kind: "file", Payload: body}, func(any) error { t.Fatal("file metadata sent through server signaling"); return nil }); err != nil {
		t.Fatal(err)
	}
	state := s.FileState()
	if len(state.Items) != 1 || !state.CanReceive || !state.CanSend || state.Items[0].Size != 5<<30 {
		t.Fatal("valid large file offer was lost")
	}
	item.Outgoing = true
	if err := s.fileEvent(r.Session.SessionRef, item); err == nil {
		t.Fatal("transfer direction changed")
	}
	item.Outgoing = false
	item.Event = "complete"
	item.Name = "chosen-name.txt"
	item.MayBeSaved = true
	if err := s.fileEvent(r.Session.SessionRef, item); err != nil {
		t.Fatal(err)
	}
	if !s.FileState().Items[0].MayBeSaved {
		t.Fatal("commit uncertainty was hidden")
	}
}
