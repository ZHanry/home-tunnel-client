// Package remote isolates native remote desktop capabilities from the tunnel agent.
package remote

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const ABIVersion = 1
const MaxControllerSessions = 4

var ErrUnavailable = errors.New("RD_BACKEND_UNAVAILABLE")

type Capabilities struct {
	ABI                   int    `json:"abi"`
	Available             bool   `json:"available"`
	Reason                string `json:"reason"`
	CanHost               bool   `json:"can_host"`
	CanControl            bool   `json:"can_control"`
	MaxControllerSessions int    `json:"max_controller_sessions"`
}

func Unavailable(reason string) Capabilities {
	return Capabilities{ABI: ABIVersion, Reason: reason, MaxControllerSessions: MaxControllerSessions}
}

// WorkerFiles must come from the installed, verified release manifest, never a browser request.
type WorkerFiles struct {
	Executable    string
	SHA256        string
	Library       string
	LibrarySHA256 string
}

func verifyFile(path, expected string) error {
	if !filepath.IsAbs(path) || len(expected) != 64 {
		return errors.New("remote worker requires an absolute installation path and pinned SHA256")
	}
	want, err := hex.DecodeString(expected)
	if err != nil || len(want) != sha256.Size {
		return errors.New("invalid remote worker digest")
	}
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > 256<<20 {
		return errors.New("invalid remote worker file")
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return err
	}
	if !bytes.Equal(hash.Sum(nil), want) {
		return errors.New("remote worker digest mismatch")
	}
	return nil
}

func QueryWorker(parent context.Context, files WorkerFiles) (Capabilities, error) {
	failure := Unavailable("RD_BACKEND_UNAVAILABLE")
	if files.Executable == "" {
		return failure, ErrUnavailable
	}
	for _, file := range [][2]string{{files.Executable, files.SHA256}, {files.Library, files.LibrarySHA256}} {
		if err := verifyFile(file[0], file[1]); err != nil {
			return failure, fmt.Errorf("remote worker integrity: %w", err)
		}
	}
	if filepath.Dir(files.Executable) != filepath.Dir(files.Library) {
		return failure, errors.New("remote worker and library must share a protected installation directory")
	}
	ctx, cancel := context.WithTimeout(parent, 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, files.Executable, "--inherited-pipe")
	configureWorker(cmd)
	cmd.Dir = filepath.Dir(files.Executable)
	cmd.Env = workerEnvironment()
	cmd.Stderr = io.Discard
	// No server credentials, capability tokens, URLs or private keys are put in argv or env.
	payload := []byte(`{"abi":1,"operation":"capabilities"}`)
	var input bytes.Buffer
	_ = binary.Write(&input, binary.BigEndian, uint32(len(payload)))
	input.Write(payload)
	cmd.Stdin = &input
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return failure, err
	}
	if err = cmd.Start(); err != nil {
		return failure, err
	}
	read := func() (Capabilities, error) {
		var size uint32
		if err := binary.Read(stdout, binary.BigEndian, &size); err != nil {
			return failure, err
		}
		if size == 0 || size > 4096 {
			return failure, errors.New("remote worker response exceeds bound")
		}
		body := make([]byte, size)
		if _, err := io.ReadFull(stdout, body); err != nil {
			return failure, err
		}
		decoder := json.NewDecoder(bytes.NewReader(body))
		decoder.DisallowUnknownFields()
		var capability Capabilities
		if err := decoder.Decode(&capability); err != nil {
			return failure, err
		}
		var trailing any
		if decoder.Decode(&trailing) != io.EOF || capability.ABI != ABIVersion || capability.MaxControllerSessions != MaxControllerSessions {
			return failure, errors.New("remote worker ABI or framing mismatch")
		}
		// The current worker is a capability probe only; unsupported builds cannot open controls.
		if capability.Available || capability.CanHost || capability.CanControl || capability.Reason != "RD_BACKEND_UNAVAILABLE" {
			return failure, errors.New("remote worker reported capabilities unsupported by this integration")
		}
		var extra [1]byte
		if n, err := stdout.Read(extra[:]); n != 0 || err != io.EOF {
			return failure, errors.New("unexpected trailing worker frame")
		}
		return capability, nil
	}
	capability, readErr := read()
	if readErr != nil {
		cancel()
	}
	waitErr := cmd.Wait()
	if readErr != nil {
		return failure, readErr
	}
	if waitErr != nil {
		return failure, waitErr
	}
	return capability, nil
}

func workerEnvironment() []string {
	allowed := map[string]bool{"SYSTEMROOT": true, "WINDIR": true, "TEMP": true, "TMP": true, "PATH": true, "LANG": true, "LC_ALL": true, "HOME": true, "USERPROFILE": true}
	values := make([]string, 0, len(allowed))
	for _, value := range os.Environ() {
		name, _, _ := strings.Cut(value, "=")
		if allowed[strings.ToUpper(name)] {
			values = append(values, value)
		}
	}
	return values
}
