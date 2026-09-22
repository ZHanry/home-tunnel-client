package remotehost

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"path/filepath"
	"sync"
)

type diskState struct {
	Origin            string                `json:"origin"`
	EndpointID        string                `json:"endpoint_id"`
	OwnerUserID       string                `json:"owner_user_id"`
	KeyPKCS8          string                `json:"key_pkcs8"`
	InitialTrust      json.RawMessage       `json:"initial_trust"`
	Keyset            json.RawMessage       `json:"keyset"`
	Enabled           bool                  `json:"enabled"`
	CapabilityVersion int64                 `json:"capability_version"`
	Grants            map[string]LocalGrant `json:"grants"`
}

// Store wraps the existing OS credential protection in a separate remote-host
// file: Windows DPAPI, macOS Keychain, and Linux Secret Service. Missing OS
// protection fails closed; the legacy headless tunnel fallback is not used.
// Neither online tokens nor account passwords are persisted.
type Store struct {
	mu      sync.Mutex
	backend protectedBackend
	data    diskState
}

func OpenStore(path string) (*Store, error) {
	if !filepath.IsAbs(path) {
		return nil, errors.New("remote host store requires an absolute path")
	}
	backend, e := platformBackend(path)
	if e != nil {
		return nil, e
	}
	return openStore(backend)
}

type protectedBackend interface {
	Load() ([]byte, error)
	Save([]byte) error
}

func openStore(backend protectedBackend) (*Store, error) {
	store := &Store{backend: backend}
	saved, e := backend.Load()
	if e != nil {
		return nil, e
	}
	if len(saved) != 0 {
		if e = strictDecode(saved, &store.data, true); e != nil {
			return nil, e
		}
	}
	if store.data.Grants == nil {
		store.data.Grants = map[string]LocalGrant{}
	}
	if store.data.KeyPKCS8 == "" {
		key, e := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if e != nil {
			return nil, e
		}
		der, e := x509.MarshalPKCS8PrivateKey(key)
		if e != nil {
			return nil, e
		}
		store.data.KeyPKCS8 = base64.StdEncoding.EncodeToString(der)
		if e = store.persist(store.data); e != nil {
			return nil, e
		}
	}
	if _, e = store.privateKey(); e != nil {
		return nil, e
	}
	return store, nil
}
func (s *Store) persist(next diskState) error {
	data, e := json.Marshal(next)
	if e != nil {
		return e
	}
	return s.backend.Save(data)
}
func (s *Store) snapshot() diskState {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, _ := json.Marshal(s.data)
	var copy diskState
	_ = json.Unmarshal(b, &copy)
	return copy
}
func (s *Store) update(work func(*diskState) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, _ := json.Marshal(s.data)
	var next diskState
	if e := json.Unmarshal(b, &next); e != nil {
		return e
	}
	if e := work(&next); e != nil {
		return e
	}
	if e := s.persist(next); e != nil {
		return e
	}
	s.data = next
	return nil
}
func (s *Store) privateKey() (*ecdsa.PrivateKey, error) {
	d := s.snapshot()
	der, e := base64.StdEncoding.DecodeString(d.KeyPKCS8)
	if e != nil {
		return nil, e
	}
	parsed, e := x509.ParsePKCS8PrivateKey(der)
	if e != nil {
		return nil, e
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() {
		return nil, ErrAuthorization
	}
	return key, nil
}

// RevokeGrant writes the tombstone before any network request or native stop.
// A server backup can therefore never replace a newer local revocation.
func (s *Store) RevokeGrant(id string) error {
	return s.update(func(d *diskState) error {
		g, ok := d.Grants[id]
		if !ok {
			return ErrAuthorization
		}
		g.Revoked = true
		g.Version++
		d.Grants[id] = g
		return nil
	})
}
func (s *Store) Grants() []LocalGrant {
	d := s.snapshot()
	result := make([]LocalGrant, 0, len(d.Grants))
	for _, g := range d.Grants {
		g.GrantJWS = ""
		g.Permissions = append([]string(nil), g.Permissions...)
		result = append(result, g)
	}
	return result
}
