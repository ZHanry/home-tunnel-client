package remote

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"hash"
	"io"
	"os"
	"strings"
	"sync"
	"unicode/utf8"
)

const MaxTextBytes = 65536
const MaxFileChunkBytes = 16384
const MaxParallelFiles = 2
const MaxFileBytes uint64 = 8589934592
const MaxBatchBytes uint64 = 34359738368
const MaxBatchFiles = 64

// ClipboardText is called only after an explicit per-session read/write grant.
// It preserves text exactly (including newlines), rejects invalid UTF-8 and does
// not access the system clipboard or apply remote data automatically.
func ClipboardText(data []byte, expectedSHA256 string) (string, error) {
	if len(data) > MaxTextBytes || !utf8.Valid(data) {
		return "", errors.New("RD_CLIPBOARD_INVALID")
	}
	digest := sha256.Sum256(data)
	if !validSHA256(expectedSHA256) || hex.EncodeToString(digest[:]) != expectedSHA256 {
		return "", errors.New("RD_TRANSFER_HASH_MISMATCH")
	}
	return string(data), nil
}

func validSHA256(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size && strings.ToLower(value) == value
}

func safeLeaf(name string) bool {
	if !utf8.ValidString(name) || len(name) == 0 || len(name) > 240 || name == "." || name == ".." || strings.ContainsAny(name, `/\:`) || strings.TrimRight(name, ". ") != name {
		return false
	}
	for _, char := range name {
		if char < 32 || char == 127 {
			return false
		}
	}
	stem := strings.ToUpper(strings.SplitN(name, ".", 2)[0])
	if stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" || stem == "CLOCK$" {
		return false
	}
	if len(stem) == 4 && (strings.HasPrefix(stem, "COM") || strings.HasPrefix(stem, "LPT")) && stem[3] >= '1' && stem[3] <= '9' {
		return false
	}
	return true
}

type FileOffer struct {
	ID, Name, SHA256 string
	Size             uint64
}

type incomingFile struct {
	offer   FileOffer
	file    *os.File
	partial string
	count   uint64
	hash    hash.Hash
}

// FileReceiver is scoped to one session and one directory explicitly selected
// by the receiving user. Its Root handle prevents peer paths escaping that tree.
// No files are executed, opened, or copied to a clipboard after completion.
type FileReceiver struct {
	mu            sync.Mutex
	root          *os.Root
	maximum       uint64
	incoming      map[string]*incomingFile
	seen          map[string]bool
	closed        bool
	acceptedBytes uint64
	acceptedFiles int
}

func NewFileReceiver(selectedDirectory string, maximumFileBytes uint64) (*FileReceiver, error) {
	if maximumFileBytes == 0 || maximumFileBytes > MaxFileBytes {
		return nil, errors.New("file size policy is required")
	}
	root, err := os.OpenRoot(selectedDirectory)
	if err != nil {
		return nil, err
	}
	return &FileReceiver{root: root, maximum: maximumFileBytes, incoming: make(map[string]*incomingFile), seen: make(map[string]bool)}, nil
}

// Accept is invoked by an explicit receiver UI action, not by the untrusted offer handler.
func (receiver *FileReceiver) Accept(offer FileOffer) error {
	receiver.mu.Lock()
	defer receiver.mu.Unlock()
	if receiver.closed {
		return errors.New("RD_SESSION_CLOSED")
	}
	if len(offer.ID) != 32 || !safeLeaf(offer.Name) || (offer.SHA256 != "" && !validSHA256(offer.SHA256)) || offer.Size > receiver.maximum {
		return errors.New("RD_FILE_OFFER_INVALID")
	}
	if raw, err := hex.DecodeString(offer.ID); err != nil || len(raw) != 16 {
		return errors.New("RD_FILE_OFFER_INVALID")
	}
	if receiver.seen[offer.ID] {
		return errors.New("RD_TRANSFER_DUPLICATE")
	}
	if len(receiver.incoming) >= MaxParallelFiles {
		return errors.New("RD_TRANSFER_LIMIT")
	}
	if receiver.acceptedFiles >= MaxBatchFiles || offer.Size > MaxBatchBytes-receiver.acceptedBytes {
		return errors.New("RD_TRANSFER_LIMIT")
	}
	if _, err := receiver.root.Lstat(offer.Name); err == nil || !errors.Is(err, os.ErrNotExist) {
		return errors.New("RD_FILE_EXISTS")
	}
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil {
		return err
	}
	partial := ".home-tunnel-rd-" + hex.EncodeToString(random[:]) + ".part"
	file, err := receiver.root.OpenFile(partial, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	receiver.incoming[offer.ID] = &incomingFile{offer: offer, file: file, partial: partial, hash: sha256.New()}
	receiver.seen[offer.ID] = true
	receiver.acceptedBytes += offer.Size
	receiver.acceptedFiles++
	return nil
}

func (receiver *FileReceiver) Chunk(id string, offset uint64, data []byte) error {
	receiver.mu.Lock()
	defer receiver.mu.Unlock()
	transfer := receiver.incoming[id]
	if receiver.closed || transfer == nil {
		return errors.New("RD_TRANSFER_NOT_ACCEPTED")
	}
	if len(data) == 0 || len(data) > MaxFileChunkBytes || offset != transfer.count || uint64(len(data)) > transfer.offer.Size-transfer.count {
		return errors.New("RD_TRANSFER_CHUNK_INVALID")
	}
	count, err := transfer.file.Write(data)
	if err != nil || count != len(data) {
		receiver.cancelLocked(id)
		if err != nil {
			return err
		}
		return io.ErrShortWrite
	}
	_, _ = transfer.hash.Write(data)
	transfer.count += uint64(count)
	return nil
}

func (receiver *FileReceiver) Complete(id string, size uint64, sha256 string) error {
	receiver.mu.Lock()
	defer receiver.mu.Unlock()
	transfer := receiver.incoming[id]
	if receiver.closed || transfer == nil {
		return errors.New("RD_TRANSFER_NOT_ACCEPTED")
	}
	if size != transfer.offer.Size || transfer.count != size || !validSHA256(sha256) || hex.EncodeToString(transfer.hash.Sum(nil)) != sha256 || (transfer.offer.SHA256 != "" && transfer.offer.SHA256 != sha256) {
		receiver.cancelLocked(id)
		return errors.New("RD_TRANSFER_HASH_MISMATCH")
	}
	if err := transfer.file.Sync(); err != nil {
		receiver.cancelLocked(id)
		return err
	}
	if err := transfer.file.Close(); err != nil {
		receiver.cancelLocked(id)
		return err
	}
	// Link is an atomic no-replace publish: a concurrent existing target is never
	// overwritten. Filesystems without hard links return an explicit error; no unsafe fallback.
	if err := receiver.root.Link(transfer.partial, transfer.offer.Name); err != nil {
		receiver.cancelLocked(id)
		return err
	}
	if err := receiver.root.Remove(transfer.partial); err != nil {
		delete(receiver.incoming, id)
		return err
	}
	delete(receiver.incoming, id)
	return nil
}

func (receiver *FileReceiver) cancelLocked(id string) {
	if transfer := receiver.incoming[id]; transfer != nil {
		_ = transfer.file.Close()
		_ = receiver.root.Remove(transfer.partial)
		delete(receiver.incoming, id)
	}
}

func (receiver *FileReceiver) Cancel(id string) {
	receiver.mu.Lock()
	defer receiver.mu.Unlock()
	receiver.cancelLocked(id)
}

func (receiver *FileReceiver) Close() error {
	receiver.mu.Lock()
	defer receiver.mu.Unlock()
	if receiver.closed {
		return nil
	}
	for id := range receiver.incoming {
		receiver.cancelLocked(id)
	}
	receiver.closed = true
	return receiver.root.Close()
}
