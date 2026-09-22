package remotehost

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"strconv"
	"strings"
	"unicode/utf8"
)

type PublicJWK struct {
	KTY string `json:"kty"`
	CRV string `json:"crv"`
	X   string `json:"x"`
	Y   string `json:"y"`
}

func jwk(key *ecdsa.PublicKey) PublicJWK {
	if key == nil || key.Curve != elliptic.P256() {
		return PublicJWK{}
	}
	point, err := key.Bytes()
	if err != nil || len(point) != 65 || point[0] != 4 {
		return PublicJWK{}
	}
	return PublicJWK{"EC", "P-256", encode(point[1:33]), encode(point[33:])}
}
func encode(data []byte) string { return base64.RawURLEncoding.EncodeToString(data) }
func decode(text string) ([]byte, error) {
	b, e := base64.RawURLEncoding.Strict().DecodeString(text)
	if e != nil || encode(b) != text {
		return nil, ErrAuthorization
	}
	return b, nil
}
func digest(data []byte) string { v := sha256.Sum256(data); return encode(v[:]) }
func (key PublicJWK) public() (*ecdsa.PublicKey, error) {
	x, e := decode(key.X)
	if e != nil {
		return nil, e
	}
	y, e := decode(key.Y)
	if e != nil || key.KTY != "EC" || key.CRV != "P-256" || len(x) != 32 || len(y) != 32 {
		return nil, ErrAuthorization
	}
	point := make([]byte, 65)
	point[0] = 4
	copy(point[1:33], x)
	copy(point[33:], y)
	public, err := ecdsa.ParseUncompressedPublicKey(elliptic.P256(), point)
	if err != nil {
		return nil, ErrAuthorization
	}
	return public, nil
}
func (key PublicJWK) Thumbprint() string {
	data, _ := json.Marshal(map[string]string{"crv": key.CRV, "kty": key.KTY, "x": key.X, "y": key.Y})
	return digest(data)
}
func rawSignature(key *ecdsa.PrivateKey, data []byte) ([]byte, error) {
	h := sha256.Sum256(data)
	r, s, e := ecdsa.Sign(rand.Reader, key, h[:])
	if e != nil {
		return nil, e
	}
	return append(r.FillBytes(make([]byte, 32)), s.FillBytes(make([]byte, 32))...), nil
}
func signJWS(key *ecdsa.PrivateKey, typ string, payload any, includePublic bool) (string, error) {
	header := map[string]any{"alg": "ES256", "typ": typ, "kid": jwk(&key.PublicKey).Thumbprint()}
	if includePublic {
		header["jwk"] = jwk(&key.PublicKey)
	}
	h, _ := json.Marshal(header)
	p, e := json.Marshal(payload)
	if e != nil {
		return "", e
	}
	message := encode(h) + "." + encode(p)
	sig, e := rawSignature(key, []byte(message))
	return message + "." + encode(sig), e
}
func verifyJWS(compact string, key PublicJWK, typ string) (json.RawMessage, error) {
	parts := strings.Split(compact, ".")
	if len(parts) != 3 || len(compact) > 65536 {
		return nil, ErrAuthorization
	}
	h, e := decode(parts[0])
	if e != nil {
		return nil, e
	}
	p, e := decode(parts[1])
	if e != nil {
		return nil, e
	}
	s, e := decode(parts[2])
	if e != nil || len(s) != 64 {
		return nil, ErrAuthorization
	}
	var header struct {
		Alg string     `json:"alg"`
		Typ string     `json:"typ"`
		Kid string     `json:"kid"`
		JWK *PublicJWK `json:"jwk,omitempty"`
	}
	if e = strictDecode(h, &header, true); e != nil || header.Alg != "ES256" || header.Typ != typ || (header.Kid != "" && header.Kid != key.Thumbprint()) || (header.JWK != nil && header.JWK.Thumbprint() != key.Thumbprint()) {
		return nil, ErrAuthorization
	}
	public, e := key.public()
	if e != nil {
		return nil, e
	}
	sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(public, sum[:], new(big.Int).SetBytes(s[:32]), new(big.Int).SetBytes(s[32:])) {
		return nil, ErrAuthorization
	}
	if e = strictDecode(p, new(any), false); e != nil {
		return nil, e
	}
	return p, nil
}

// Validate token-by-token before decoding: encoding/json alone silently accepts
// duplicate security fields, invalid UTF-8, and lossy large numeric values.
func strictDecode(data []byte, target any, rejectUnknown bool) error {
	if len(data) > 262144 || !utf8.Valid(data) {
		return ErrAuthorization
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	var visit func(int) error
	visit = func(depth int) error {
		if depth > 20 {
			return ErrAuthorization
		}
		t, e := d.Token()
		if e != nil {
			return e
		}
		if delimiter, ok := t.(json.Delim); ok {
			switch delimiter {
			case '{':
				keys := map[string]bool{}
				for d.More() {
					k, e := d.Token()
					if e != nil {
						return e
					}
					name, ok := k.(string)
					if !ok || keys[name] || len(keys) >= 128 {
						return ErrAuthorization
					}
					keys[name] = true
					if e = visit(depth + 1); e != nil {
						return e
					}
				}
				end, e := d.Token()
				if e != nil || end != json.Delim('}') {
					return ErrAuthorization
				}
			case '[':
				count := 0
				for d.More() {
					count++
					if count > 4096 {
						return ErrAuthorization
					}
					if e = visit(depth + 1); e != nil {
						return e
					}
				}
				end, e := d.Token()
				if e != nil || end != json.Delim(']') {
					return ErrAuthorization
				}
			default:
				return ErrAuthorization
			}
		} else if n, ok := t.(json.Number); ok {
			v, e := strconv.ParseFloat(string(n), 64)
			if e != nil || v > 9007199254740991 || v < -9007199254740991 {
				return ErrAuthorization
			}
		}
		return nil
	}
	if e := visit(0); e != nil {
		return e
	}
	if _, e := d.Token(); e != io.EOF {
		return errors.New("trailing JSON")
	}
	d = json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	if rejectUnknown {
		d.DisallowUnknownFields()
	}
	return d.Decode(target)
}
func randomID() string {
	b := make([]byte, 16)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	h := []byte("0123456789abcdef")
	out := make([]byte, 0, 36)
	for i, v := range b {
		if i == 4 || i == 6 || i == 8 || i == 10 {
			out = append(out, '-')
		}
		out = append(out, h[v>>4], h[v&15])
	}
	return string(out)
}
func nonce() string {
	b := make([]byte, 32)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	return encode(b)
}
