package remotehost

import (
	"bytes"
	"encoding/json"
	"strings"
	"time"
)

type ServerKey struct {
	Kid       string    `json:"kid"`
	Alg       string    `json:"alg"`
	PublicJWK PublicJWK `json:"public_jwk"`
	NotBefore time.Time `json:"not_before"`
	NotAfter  time.Time `json:"not_after"`
}
type Keyset struct {
	ServerInstanceID string      `json:"server_instance_id"`
	RestoreEpoch     int64       `json:"restore_epoch"`
	KeysetVersion    int64       `json:"keyset_version"`
	ActiveKid        string      `json:"active_kid"`
	Keys             []ServerKey `json:"keys"`
	RotationProofs   []string    `json:"rotation_proofs"`
}

func parseKeyset(data []byte) (Keyset, error) {
	var k Keyset
	e := strictDecode(data, &k, true)
	if e != nil {
		return k, e
	}
	if k.ServerInstanceID == "" || k.RestoreEpoch < 1 || k.KeysetVersion < 1 || len(k.Keys) < 1 || len(k.Keys) > 8 || len(k.RotationProofs) > 32 {
		return k, ErrAuthorization
	}
	seen := map[string]bool{}
	for _, key := range k.Keys {
		if _, e = key.PublicJWK.public(); e != nil || key.Alg != "ES256" || key.Kid != key.PublicJWK.Thumbprint() || seen[key.Kid] || !key.NotAfter.After(key.NotBefore) {
			return k, ErrAuthorization
		}
		seen[key.Kid] = true
	}
	if !seen[k.ActiveKid] {
		return k, ErrAuthorization
	}
	for _, p := range k.RotationProofs {
		if len(p) > 8192 {
			return k, ErrAuthorization
		}
	}
	return k, nil
}
func (k Keyset) active() (ServerKey, error) {
	for _, key := range k.Keys {
		if key.Kid == k.ActiveKid {
			return key, nil
		}
	}
	return ServerKey{}, ErrAuthorization
}

type keysetBody struct {
	Version   int64       `json:"keyset_version"`
	ActiveKid string      `json:"active_kid"`
	Keys      []ServerKey `json:"keys"`
}

func bodyOf(k Keyset) keysetBody { return keysetBody{k.KeysetVersion, k.ActiveKid, k.Keys} }
func verifyKeyset(old, next Keyset, now time.Time) error {
	if next.ServerInstanceID != old.ServerInstanceID || next.RestoreEpoch < old.RestoreEpoch || next.KeysetVersion < old.KeysetVersion {
		return ErrAuthorization
	}
	current := old
	var issuedBefore time.Time
	for _, compact := range next.RotationProofs {
		parts := strings.Split(compact, ".")
		if len(parts) != 3 {
			return ErrAuthorization
		}
		payload, e := decode(parts[1])
		if e != nil {
			return e
		}
		var hint struct {
			To int64 `json:"to_version"`
		}
		if e = strictDecode(payload, &hint, false); e != nil {
			return e
		}
		if hint.To <= old.KeysetVersion {
			continue
		}
		key, e := current.active()
		if e != nil {
			return e
		}
		headerRaw, e := decode(parts[0])
		var header struct {
			Kid string `json:"kid"`
		}
		if e != nil || strictDecode(headerRaw, &header, false) != nil || header.Kid != key.Kid {
			return ErrAuthorization
		}
		raw, e := verifyJWS(compact, key.PublicJWK, "ht-rd-keyset+jwt")
		if e != nil {
			return e
		}
		var proof struct {
			Instance string     `json:"server_instance_id"`
			From     int64      `json:"from_version"`
			To       int64      `json:"to_version"`
			Kid      string     `json:"from_kid"`
			Issued   time.Time  `json:"issued_at"`
			Keyset   keysetBody `json:"keyset"`
		}
		if e = strictDecode(raw, &proof, true); e != nil {
			return e
		}
		if proof.Instance != old.ServerInstanceID || proof.From != current.KeysetVersion || proof.To != proof.From+1 || proof.Kid != current.ActiveKid || proof.Issued.Before(key.NotBefore) || !proof.Issued.Before(key.NotAfter) || proof.Issued.After(now.Add(time.Minute)) || proof.Issued.Before(issuedBefore) || proof.Keyset.Version != proof.To || proof.Keyset.ActiveKid == current.ActiveKid {
			return ErrAuthorization
		}
		current.KeysetVersion, current.ActiveKid, current.Keys = proof.Keyset.Version, proof.Keyset.ActiveKid, proof.Keyset.Keys
		candidate, _ := json.Marshal(current)
		if _, e = parseKeyset(candidate); e != nil {
			return e
		}
		active, e := current.active()
		if e != nil || active.NotBefore.After(proof.Issued) || !active.NotAfter.After(proof.Issued) {
			return ErrAuthorization
		}
		issuedBefore = proof.Issued
	}
	a, _ := json.Marshal(bodyOf(current))
	b, _ := json.Marshal(bodyOf(next))
	if !bytes.Equal(a, b) {
		return ErrAuthorization
	}
	active, e := next.active()
	if e != nil || now.Before(active.NotBefore) || !now.Before(active.NotAfter) {
		return ErrAuthorization
	}
	return nil
}
func verifyServerJWS(compact, typ string, keys Keyset) (json.RawMessage, error) {
	parts := strings.Split(compact, ".")
	if len(parts) != 3 {
		return nil, ErrAuthorization
	}
	h, e := decode(parts[0])
	if e != nil {
		return nil, e
	}
	var header struct {
		Kid string `json:"kid"`
	}
	if e = strictDecode(h, &header, false); e != nil {
		return nil, e
	}
	for _, key := range keys.Keys {
		if key.Kid == header.Kid {
			raw, e := verifyJWS(compact, key.PublicJWK, typ)
			if e != nil {
				return nil, e
			}
			var times struct {
				Iat int64 `json:"iat"`
				Exp int64 `json:"exp"`
			}
			if e = strictDecode(raw, &times, false); e != nil {
				return nil, e
			}
			if time.Unix(times.Iat, 0).Before(key.NotBefore) || time.Unix(times.Exp, 0).After(key.NotAfter) {
				return nil, ErrAuthorization
			}
			return raw, nil
		}
	}
	return nil, ErrAuthorization
}
