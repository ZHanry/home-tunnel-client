//go:build linux

package remotehost

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os/exec"
	"strings"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/state"
)

type secretServiceBackend struct{ path, tool string }

func platformBackend(path string) (protectedBackend, error) {
	tool, e := exec.LookPath("secret-tool")
	if e != nil {
		return nil, errors.New("RD_KEYSTORE_UNAVAILABLE")
	}
	return secretServiceBackend{path, tool}, nil
}

type boundedSecretBuffer struct{ bytes.Buffer }

func (b *boundedSecretBuffer) Write(p []byte) (int, error) {
	if b.Len()+len(p) > 262144 {
		return 0, errors.New("secret exceeds bound")
	}
	return b.Buffer.Write(p)
}
func (b secretServiceBackend) call(operation, id string, input []byte) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	args := []string{operation}
	if operation == "store" {
		args = append(args, "--label=Home Tunnel Remote Host")
	}
	args = append(args, "application", "home-tunnel-remote-host", "record", id)
	command := exec.CommandContext(ctx, b.tool, args...)
	if input != nil {
		command.Stdin = bytes.NewReader(append(append([]byte(nil), input...), '\n'))
	}
	var output boundedSecretBuffer
	command.Stdout = &output
	command.Stderr = io.Discard
	if e := command.Run(); e != nil {
		return nil, errors.New("RD_KEYSTORE_UNAVAILABLE")
	}
	return bytes.TrimSuffix(output.Bytes(), []byte("\n")), nil
}
func (b secretServiceBackend) Load() ([]byte, error) {
	saved, e := (state.Store{Path: b.path}).Load()
	if e != nil {
		return nil, e
	}
	if saved.DeviceCredential == "" {
		return nil, nil
	}
	if !strings.HasPrefix(saved.DeviceCredential, "secret-service:") {
		return nil, errors.New("RD_KEYSTORE_UNAVAILABLE")
	}
	return b.call("lookup", strings.TrimPrefix(saved.DeviceCredential, "secret-service:"), nil)
}
func (b secretServiceBackend) Save(data []byte) error {
	previous, e := (state.Store{Path: b.path}).Load()
	if e != nil {
		return e
	}
	id := randomID()
	if _, e = b.call("store", id, data); e != nil {
		return e
	}
	if e = (state.Store{Path: b.path}).Save(model.State{InstallID: "remote-host", DeviceCredential: "secret-service:" + id}); e != nil {
		_, _ = b.call("clear", id, nil)
		return e
	}
	if strings.HasPrefix(previous.DeviceCredential, "secret-service:") {
		_, _ = b.call("clear", strings.TrimPrefix(previous.DeviceCredential, "secret-service:"), nil)
	}
	return nil
}
