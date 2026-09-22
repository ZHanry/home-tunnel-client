package remote

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func digest(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }

func TestTextTransferIntegrityAndUnicode(t *testing.T) {
	data := []byte("你好 😀\nsecond line")
	text, err := ClipboardText(data, digest(data))
	if err != nil || text != string(data) {
		t.Fatal(text, err)
	}
	for _, bad := range [][]byte{{0xff}, []byte(strings.Repeat("x", MaxTextBytes+1))} {
		if _, err := ClipboardText(bad, digest(bad)); err == nil {
			t.Fatal("invalid text accepted")
		}
	}
	if _, err := ClipboardText(data, digest([]byte("different"))); err == nil {
		t.Fatal("hash mismatch accepted")
	}
}

func TestFileTransferDoesNotOverwriteOrEscape(t *testing.T) {
	directory := t.TempDir()
	receiver, err := NewFileReceiver(directory, 1024)
	if err != nil {
		t.Fatal(err)
	}
	defer receiver.Close()
	data := []byte("verified content")
	offer := FileOffer{ID: strings.Repeat("a", 32), Name: "result.txt", Size: uint64(len(data)), SHA256: digest(data)}
	for _, name := range []string{"../escape", `..\escape`, "/absolute", "file:stream", "NUL.txt", "COM1", "trailing.", "trailing ", "a\x00b"} {
		bad := offer
		bad.Name = name
		if err := receiver.Accept(bad); err == nil {
			t.Fatalf("dangerous filename accepted %q", name)
		}
	}
	if err := receiver.Accept(offer); err != nil {
		t.Fatal(err)
	}
	if err := receiver.Chunk(offer.ID, 1, data); err == nil {
		t.Fatal("out-of-order chunk accepted")
	}
	if err := receiver.Chunk(offer.ID, 0, data); err != nil {
		t.Fatal(err)
	}
	if err := receiver.Chunk(offer.ID, 0, data); err == nil {
		t.Fatal("replayed chunk accepted")
	}
	if err := receiver.Complete(offer.ID, offer.Size, offer.SHA256); err != nil {
		t.Fatal(err)
	}
	stored, err := os.ReadFile(filepath.Join(directory, offer.Name))
	if err != nil || string(stored) != string(data) {
		t.Fatal("completed file differs", err)
	}
	offer.ID = strings.Repeat("b", 32)
	if err := receiver.Accept(offer); err == nil {
		t.Fatal("existing file accepted")
	}
}

func TestFailedAndCancelledTransfersRemovePartialFiles(t *testing.T) {
	directory := t.TempDir()
	receiver, err := NewFileReceiver(directory, 1024)
	if err != nil {
		t.Fatal(err)
	}
	for n, id := range []string{strings.Repeat("a", 32), strings.Repeat("b", 32)} {
		offer := FileOffer{id, string(rune('a'+n)) + ".txt", digest([]byte("expected")), 8}
		if err := receiver.Accept(offer); err != nil {
			t.Fatal(err)
		}
		if err := receiver.Chunk(id, 0, []byte("tampered")); err != nil {
			t.Fatal(err)
		}
		if n == 0 {
			if err := receiver.Complete(id, offer.Size, offer.SHA256); err == nil {
				t.Fatal("corrupt transfer committed")
			}
		}
	}
	if err := receiver.Close(); err != nil {
		t.Fatal(err)
	}
	items, err := os.ReadDir(directory)
	if err != nil || len(items) != 0 {
		t.Fatal("partial data survived session close", items, err)
	}
}
