package windowshost

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"io"
)

const (
	ipcVersion = 1
	maxBody    = 64 << 10

	TypeServerHello       uint8 = 1
	TypeClientHello       uint8 = 2
	TypeStatus            uint8 = 3
	TypeClipboardRead     uint8 = 4
	TypeClipboardWrite    uint8 = 5
	TypeFileRead          uint8 = 6
	TypeFileWrite         uint8 = 7
	TypeDesktop           uint8 = 8
	TypeEmergencyStop     uint8 = 9
	TypeCapability        uint8 = 10
	TypeEnableUnattended  uint8 = 11
	TypeDisableUnattended uint8 = 12
)

type Message struct {
	Type    uint8
	Counter uint64
	Session uint32
	Body    []byte
}

type ConnState struct {
	Key      []byte
	Expected uint64
}

func knownType(kind uint8) bool {
	switch kind {
	case TypeServerHello, TypeClientHello, TypeStatus, TypeClipboardRead, TypeClipboardWrite, TypeFileRead, TypeFileWrite, TypeDesktop, TypeEmergencyStop, TypeCapability, TypeEnableUnattended, TypeDisableUnattended:
		return true
	default:
		return false
	}
}

func Marshal(key []byte, message Message) ([]byte, error) {
	if !knownType(message.Type) || len(message.Body) > maxBody || len(key) != 32 {
		return nil, ErrRejected
	}
	frame := make([]byte, 1+1+8+4+4+len(message.Body)+32)
	frame[0] = ipcVersion
	frame[1] = message.Type
	binary.BigEndian.PutUint64(frame[2:], message.Counter)
	binary.BigEndian.PutUint32(frame[10:], message.Session)
	binary.BigEndian.PutUint32(frame[14:], uint32(len(message.Body)))
	copy(frame[18:], message.Body)
	mac := hmac.New(sha256.New, key)
	_, _ = mac.Write(frame[:18+len(message.Body)])
	copy(frame[18+len(message.Body):], mac.Sum(nil))
	return frame, nil
}

func ReadMessage(reader io.Reader, key []byte, state *ConnState) (Message, error) {
	if len(key) != 32 || state == nil {
		return Message{}, ErrRejected
	}
	header := make([]byte, 18)
	if _, err := io.ReadFull(reader, header); err != nil {
		return Message{}, err
	}
	if header[0] != ipcVersion || !knownType(header[1]) {
		return Message{}, ErrRejected
	}
	size := binary.BigEndian.Uint32(header[14:])
	if size > maxBody {
		return Message{}, ErrRejected
	}
	rest := make([]byte, size+32)
	if _, err := io.ReadFull(reader, rest); err != nil {
		return Message{}, err
	}
	mac := hmac.New(sha256.New, key)
	_, _ = mac.Write(header)
	_, _ = mac.Write(rest[:size])
	if !hmac.Equal(mac.Sum(nil), rest[size:]) {
		return Message{}, ErrRejected
	}
	message := Message{Type: header[1], Counter: binary.BigEndian.Uint64(header[2:]), Session: binary.BigEndian.Uint32(header[10:]), Body: append([]byte(nil), rest[:size]...)}
	if message.Counter != state.Expected {
		return Message{}, ErrRejected
	}
	state.Expected++
	return message, nil
}

func WriteMessage(writer io.Writer, key []byte, message Message) error {
	frame, err := Marshal(key, message)
	if err != nil {
		return err
	}
	_, err = writer.Write(frame)
	return err
}

// RejectedPath reports whether a connecting image is outside the fixed set.
func RejectedPath(path string, allowed []string) bool {
	if path == "" || len(path) > 32767 {
		return true
	}
	for _, item := range allowed {
		if item == path {
			return false
		}
	}
	return true
}
