package gui

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

func newLocalToken() string {
	value := make([]byte, 32)
	if _, err := rand.Read(value); err != nil {
		panic("cannot create a secure desktop session")
	}
	return hex.EncodeToString(value)
}

func localSessionPath(statePath string) string {
	return filepath.Join(filepath.Dir(statePath), ".ui-session")
}

func readLocalToken(statePath string) (string, error) {
	file, err := os.Open(localSessionPath(statePath))
	if err != nil {
		return "", err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, 128))
	if err != nil {
		return "", err
	}
	token := strings.TrimSpace(string(data))
	decoded, err := hex.DecodeString(token)
	if err != nil || len(decoded) != 32 {
		return "", errors.New("invalid local desktop session")
	}
	return token, nil
}

func (server *Server) LocalToken() string {
	return server.options.LocalToken
}

// PublishLocalSession supports same-user singleton signaling. The token is
// written atomically into the user's private state directory, never into HTML.
func (server *Server) PublishLocalSession() (func(), error) {
	directory := filepath.Dir(server.options.StatePath)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return nil, err
	}
	file, err := os.CreateTemp(directory, ".ui-session-*")
	if err != nil {
		return nil, err
	}
	defer os.Remove(file.Name())
	if err := file.Chmod(0o600); err != nil {
		file.Close()
		return nil, err
	}
	if _, err := file.WriteString(server.options.LocalToken + "\n"); err != nil {
		file.Close()
		return nil, err
	}
	if err := file.Close(); err != nil {
		return nil, err
	}
	if err := os.Rename(file.Name(), localSessionPath(server.options.StatePath)); err != nil {
		return nil, err
	}
	var once sync.Once
	cleanup := func() {
		once.Do(func() {
			current, err := readLocalToken(server.options.StatePath)
			if err == nil && subtle.ConstantTimeCompare([]byte(current), []byte(server.options.LocalToken)) == 1 {
				_ = os.Remove(localSessionPath(server.options.StatePath))
			}
		})
	}
	return cleanup, nil
}
