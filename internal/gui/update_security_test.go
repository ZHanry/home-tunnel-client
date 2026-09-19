package gui

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUpdateSemanticVersions(t *testing.T) {
	for _, c := range []struct {
		a, b string
		want int
	}{
		{"6.1.0", "6.1.1", -1}, {"6.10.0", "6.9.9", 1}, {"v7.0.0", "7.0.0+build.9", 0},
		{"7.0.0", "7.0.0-rc.1", 1}, {"7.0.0-alpha.9", "7.0.0-alpha.10", -1},
		{"7.0.0-alpha", "7.0.0-alpha.1", -1}, {"7.0.0-1", "7.0.0-alpha", -1},
	} {
		got, err := compareUpdateVersions(c.a, c.b)
		if err != nil || got != c.want {
			t.Errorf("%s vs %s: %d %v", c.a, c.b, got, err)
		}
	}
	for _, v := range []string{"", "7.0", "07.0.0", "7.0.0-01", "../7.0.0"} {
		if _, err := parseUpdateVersion(v); err == nil {
			t.Errorf("accepted %q", v)
		}
	}
}

func TestUpdateFailuresPreserveExistingFile(t *testing.T) {
	data := "complete archive"
	sum := sha256.Sum256([]byte(data))
	digest := hex.EncodeToString(sum[:])
	for _, c := range []struct {
		name           string
		status         int
		body, checksum string
		limit          int64
		length         string
	}{
		{"404", 404, "Not Found", digest, 100, ""},
		{"mismatch", 200, "tampered", digest, 100, ""},
		{"too large", 200, data, digest, 4, ""},
		{"truncated", 200, data, digest, 100, "50"},
		{"empty", 200, "", digest, 100, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if c.length != "" {
					w.Header().Set("Content-Length", c.length)
				}
				w.WriteHeader(c.status)
				_, _ = w.Write([]byte(c.body))
			}))
			defer upstream.Close()
			old := updateHTTPClient
			updateHTTPClient = upstream.Client()
			defer func() { updateHTTPClient = old }()
			dir := t.TempDir()
			dest := filepath.Join(dir, "archive.zip")
			if err := os.WriteFile(dest, []byte("previous"), 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := saveVerifiedUpdate(httptest.NewRequest("POST", "/", nil), upstream.URL, dest, c.checksum, c.limit); err == nil {
				t.Fatal("unsafe update succeeded")
			}
			got, _ := os.ReadFile(dest)
			if string(got) != "previous" {
				t.Fatal("existing file was modified")
			}
			files, _ := os.ReadDir(dir)
			if len(files) != 1 {
				t.Fatal("partial file was retained")
			}
		})
	}
}

func TestChecksumDownloadFailsClosed(t *testing.T) {
	for _, status := range []int{http.StatusNotFound, http.StatusServiceUnavailable, http.StatusOK} {
		upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(status); _, _ = w.Write([]byte("invalid")) }))
		old := updateHTTPClient
		updateHTTPClient = upstream.Client()
		if _, err := fetchChecksum(httptest.NewRequest("POST", "/", nil), upstream.URL, "file.zip"); err == nil {
			t.Fatalf("accepted checksum HTTP %d", status)
		}
		updateHTTPClient = old
		upstream.Close()
	}
	for _, address := range []string{"", "http://example.com/file", "https://user:password@example.com/file", "file:///tmp/update"} {
		if secureUpdateURL(address) == nil {
			t.Errorf("accepted %s", address)
		}
	}
}

func TestFailedReleaseCheckDoesNotClaimUpToDate(t *testing.T) {
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "unavailable", http.StatusServiceUnavailable) }))
	defer upstream.Close()
	oldURL, oldClient := githubLatestRelease, updateHTTPClient
	githubLatestRelease, updateHTTPClient = upstream.URL, upstream.Client()
	defer func() { githubLatestRelease, updateHTTPClient = oldURL, oldClient }()
	server := New(Options{LocalToken: testLocalToken, StatePath: filepath.Join(t.TempDir(), "state.json")})
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, trustedLocalRequest("GET", "/local/update", nil))
	if rec.Code != 502 || strings.Contains(rec.Body.String(), `"newer":false`) {
		t.Fatalf("misleading response: %d %s", rec.Code, rec.Body)
	}
}
