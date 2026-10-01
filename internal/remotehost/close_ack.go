package remotehost

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"net/url"
	"strconv"
)

const maximumCloseAcks = 64

// stoppedAck is created only after native closed or verified producer exit.
// It contains the exact stopped epoch, not permission to close future epochs.
// Persisting the signed proof with the protected identity lets a replacement
// Service retry it without consulting (or stopping) its new worker.
type stoppedAck struct {
	SessionRef
	LeaseSeq    int64  `json:"lease_seq"`
	SignedProof string `json:"signed_proof"`
}

func (a stoppedAck) key() string {
	return a.SessionID + ":" + strconv.FormatInt(a.ConnectionEpoch, 10)
}
func (a stoppedAck) body() map[string]any {
	return map[string]any{"connection_epoch": a.ConnectionEpoch, "lease_seq": a.LeaseSeq, "signed_proof": a.SignedProof}
}

func validateCloseAcks(acks map[string]stoppedAck, key *ecdsa.PrivateKey) error {
	if len(acks) > maximumCloseAcks {
		return ErrAuthorization
	}
	for id, ack := range acks {
		if id != ack.key() || !validBindingID(ack.SessionID) || ack.ConnectionEpoch < 1 || ack.ConnectionEpoch > 0xffffffff || ack.LeaseSeq < 0 || len(ack.SignedProof) > 2048 {
			return ErrAuthorization
		}
		raw, err := verifyJWS(ack.SignedProof, jwk(&key.PublicKey), "ht-rd-session+jwt")
		if err != nil {
			return err
		}
		var claims struct {
			SessionRef
			Type     string `json:"type"`
			LeaseSeq int64  `json:"lease_seq"`
			Stopped  bool   `json:"stopped"`
		}
		if strictDecode(raw, &claims, true) != nil || claims.Type != "session.close_ack" || !claims.Stopped || claims.SessionRef != ack.SessionRef || claims.LeaseSeq != ack.LeaseSeq {
			return ErrAuthorization
		}
	}
	return nil
}

func (s *Store) closeAcks() []stoppedAck {
	s.mu.Lock()
	defer s.mu.Unlock()
	acks := make([]stoppedAck, 0, len(s.data.CloseAcks))
	for _, ack := range s.data.CloseAcks {
		acks = append(acks, ack)
	}
	return acks
}

func (s *Store) withCloseRequest(ctx context.Context, work func() error) error {
	s.mu.Lock()
	if s.closeGate == nil {
		s.closeGate = make(chan struct{}, 1)
	}
	gate := s.closeGate
	s.mu.Unlock()
	select {
	case gate <- struct{}{}:
		defer func() { <-gate }()
		return work()
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (s *Service) requestSessionClose(ctx context.Context, session Session, running *runningSession) error {
	return s.config.Store.withCloseRequest(ctx, func() error {
		ref := session.SessionRef
		for attempt := 0; attempt < 2; attempt++ {
			if s.stopAlreadySettled(running) || session.SessionRef != ref {
				return nil
			}
			if session.State == "closing" || session.State == "closed" || session.State == "failed" || session.State == "expired" {
				return nil
			}
			// Generic /close is epoch-unbound. Even a timed-out request could
			// later close a replacement, so use existing epoch/version-bound
			// failure reports or signed pending-session rejection instead.
			var err error
			if session.State == "pending_approval" || session.State == "reconnecting" {
				err = s.requestSessionRejection(ctx, session, running.Grant.Version)
			} else {
				body := map[string]any{"phase": "failed", "connection_epoch": session.ConnectionEpoch, "expected_version": session.StateVersion, "error_code": "RD_CANCELLED"}
				err = s.request(ctx, "POST", "/sessions/"+url.PathEscape(session.SessionID)+"/report", body, "dpop", nil)
			}
			var rejected *APIError
			if err == nil || attempt != 0 || !errors.As(err, &rejected) || rejected.Status != 409 || (rejected.Code != "RD_STATE_CONFLICT" && rejected.Code != "RD_VERSION_CONFLICT") {
				return err
			}
			var loadErr error
			session, loadErr = s.loadSession(ctx, ref.SessionID)
			if loadErr != nil {
				return loadErr
			}
		}
		return nil
	})
}

// requestSessionRejection binds even delayed requests to the visible epoch and
// revision. Rejection does not require a still-live grant or consume a new one.
func (s *Service) requestSessionRejection(ctx context.Context, session Session, grantVersion int64) error {
	body := map[string]any{"type": "session.decision", "session_id": session.SessionID, "connection_epoch": session.ConnectionEpoch, "decision": "reject", "grant_version": grantVersion, "permissions": session.Permissions, "expected_version": session.StateVersion}
	proof, err := signJWS(s.key, "ht-rd-session+jwt", body, false)
	if err != nil {
		return err
	}
	delete(body, "type")
	delete(body, "session_id")
	delete(body, "connection_epoch")
	body["signed_proof"] = proof
	return s.request(ctx, "POST", "/sessions/"+url.PathEscape(session.SessionID)+"/decision", body, "dpop", nil)
}

func (s *Store) rememberCloseAck(ack stoppedAck) (stoppedAck, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if old, exists := s.data.CloseAcks[ack.key()]; exists {
		if old.LeaseSeq >= ack.LeaseSeq {
			return old, s.persist(s.data)
		}
	} else if len(s.data.CloseAcks) >= maximumCloseAcks {
		return stoppedAck{}, errors.New("remote host stopped-session debt limit reached")
	}
	if s.data.CloseAcks == nil {
		s.data.CloseAcks = make(map[string]stoppedAck)
	}
	s.data.CloseAcks[ack.key()] = ack
	// Unlike settings, this is a monotonic fact about an already stopped
	// producer. Keep it in this Store even if disk fails, so a replacement
	// Service in the supervisor cannot lose it. Report the persistence failure.
	return ack, s.persist(s.data)
}

// changeCloseAck compares the exact proof to prevent an old completion from
// erasing newer renewal debt. A nil replacement settles only that proof.
func (s *Store) changeCloseAck(old stoppedAck, replacement *stoppedAck) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if current, exists := s.data.CloseAcks[old.key()]; !exists || current != old {
		return false, nil
	}
	if replacement == nil {
		delete(s.data.CloseAcks, old.key())
	} else {
		if replacement.SessionRef != old.SessionRef || replacement.LeaseSeq <= old.LeaseSeq {
			return false, ErrAuthorization
		}
		s.data.CloseAcks[old.key()] = *replacement
	}
	return true, s.persist(s.data)
}

func (s *Service) makeCloseAck(ref SessionRef, sequence int64) (stoppedAck, error) {
	proof, err := signJWS(s.key, "ht-rd-session+jwt", map[string]any{"type": "session.close_ack", "session_id": ref.SessionID, "connection_epoch": ref.ConnectionEpoch, "lease_seq": sequence, "stopped": true}, false)
	return stoppedAck{SessionRef: ref, LeaseSeq: sequence, SignedProof: proof}, err
}

// flushOwedAcks uses the shared Store, not a generation-local retry map.
func (s *Service) flushOwedAcks(ctx context.Context) error {
	for _, ack := range s.config.Store.closeAcks() {
		if err := s.sendCloseAck(ctx, ack); err != nil {
			return err
		}
	}
	return nil
}

// acknowledgeStopped records proof before network waits and releases exactly
// this local session. A late event must not clear a replacement session.
func (s *Service) acknowledgeStopped(ctx context.Context, r *runningSession) error {
	ack, persistErr := s.recordStopped(r)
	if ack.SignedProof != "" {
		return errors.Join(persistErr, s.sendCloseAck(ctx, ack))
	}
	return persistErr
}

func (s *Service) recordStopped(r *runningSession) (stoppedAck, error) {
	s.mu.Lock()
	if s.active != r || r.Stopped {
		s.mu.Unlock()
		return stoppedAck{}, nil
	}
	snapshot := *r
	var ack stoppedAck
	var persistErr error
	if !snapshot.Superseded {
		var err error
		ack, err = s.makeCloseAck(snapshot.Session.SessionRef, snapshot.Session.LeaseSeq)
		if err == nil {
			ack, persistErr = s.config.Store.rememberCloseAck(ack)
			err = persistErr
		}
		if ack.SignedProof == "" {
			s.mu.Unlock()
			return stoppedAck{}, err
		}
	}
	r.Stopped, r.Closing = true, true
	s.active = nil
	if !snapshot.Superseded && s.pending[snapshot.Session.SessionID].SessionRef == snapshot.Session.SessionRef {
		delete(s.pending, snapshot.Session.SessionID)
	}
	s.mu.Unlock()
	return ack, persistErr
}

func (s *Service) sendCloseAck(ctx context.Context, ack stoppedAck) error {
	return s.config.Store.withCloseRequest(ctx, func() error {
		return s.sendCloseAckLocked(ctx, ack)
	})
}

func (s *Service) sendCloseAckLocked(ctx context.Context, ack stoppedAck) error {
	path := "/sessions/" + url.PathEscape(ack.SessionID) + "/close-ack"
	err := s.request(ctx, "POST", path, ack.body(), "dpop", nil)
	var rejected *APIError
	settled := err == nil || (errors.As(err, &rejected) && rejected.Status == 404 && rejected.Code == "RD_NOT_FOUND")
	if !settled && errors.As(err, &rejected) && rejected.Status == 409 && rejected.Code == "RD_STATE_CONFLICT" {
		// A renewal can commit before the stopped producer receives its lease.
		// Reconcile only that exact epoch, never the replacement worker's epoch.
		current, loadErr := s.loadSession(ctx, ack.SessionID)
		if loadErr != nil {
			return loadErr
		}
		settled = current.ConnectionEpoch > ack.ConnectionEpoch || current.State == "closed" || current.State == "failed" || current.State == "expired"
		if !settled && current.ConnectionEpoch == ack.ConnectionEpoch && current.LeaseSeq > ack.LeaseSeq {
			replacement, signErr := s.makeCloseAck(ack.SessionRef, current.LeaseSeq)
			if signErr != nil {
				return signErr
			}
			changed, persistErr := s.config.Store.changeCloseAck(ack, &replacement)
			if !changed || persistErr != nil {
				return persistErr
			}
			ack = replacement
			err = s.request(ctx, "POST", path, ack.body(), "dpop", nil)
			settled = err == nil
		}
	}
	if !settled {
		// Throttling, authorization errors and server/network errors provide no
		// evidence of closure and must retain the exact stopped-session debt.
		return err
	}
	_, persistErr := s.config.Store.changeCloseAck(ack, nil)
	return persistErr
}
