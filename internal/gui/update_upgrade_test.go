package gui

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUpgradeSelectsCompletePackageForInstallation(t *testing.T) {
	var release githubRelease
	if err := json.Unmarshal([]byte(`{"tag_name":"v8.0.0","assets":[
		{"name":"HomeTunnel-Setup-8.0.0-x64.exe","browser_download_url":"https://example.com/setup"},
		{"name":"HomeTunnel-Windows-8.0.0-x64.zip","browser_download_url":"https://example.com/portable"},
		{"name":"home-tunnel-linux-8.0.0-amd64.tar.gz","browser_download_url":"https://example.com/linux-amd64"},
		{"name":"home-tunnel-linux-8.0.0-arm64.tar.gz","browser_download_url":"https://example.com/linux-arm64"},
		{"name":"home-tunnel-macos-8.0.0-amd64.tar.gz","browser_download_url":"https://example.com/macos-amd64"},
		{"name":"home-tunnel-macos-8.0.0-arm64.tar.gz","browser_download_url":"https://example.com/macos-arm64"},
		{"name":"home_tunnel_remote_host.exe","browser_download_url":"https://example.com/worker-only"},
		{"name":"SHA256SUMS.txt","browser_download_url":"https://example.com/checksums"}
	]}`), &release); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		platform, architecture string
		installed              bool
		want                   string
	}{
		{"windows", "amd64", true, "HomeTunnel-Setup-8.0.0-x64.exe"},
		{"windows", "amd64", false, "HomeTunnel-Windows-8.0.0-x64.zip"},
		{"windows", "arm64", false, ""},
		{"linux", "amd64", true, "home-tunnel-linux-8.0.0-amd64.tar.gz"},
		{"linux", "arm64", false, "home-tunnel-linux-8.0.0-arm64.tar.gz"},
		{"darwin", "amd64", true, "home-tunnel-macos-8.0.0-amd64.tar.gz"},
		{"darwin", "arm64", false, "home-tunnel-macos-8.0.0-arm64.tar.gz"},
		{"linux", "arm", false, ""},
		{"freebsd", "amd64", false, ""},
	} {
		name, address, sum := packageAssetFor(release, tc.platform, tc.architecture, tc.installed)
		if name != tc.want || (name != "" && (address == "" || sum == "")) {
			t.Fatalf("%s/%s installed=%v: %q %q %q", tc.platform, tc.architecture, tc.installed, name, address, sum)
		}
	}
}

func TestInstalledWindowsMarkerMustBeRegularFile(t *testing.T) {
	dir := t.TempDir()
	executable := filepath.Join(dir, "home-tunnel-gui.exe")
	marker := filepath.Join(dir, "unins000.exe")
	if windowsInstalledPackage(executable) || windowsInstalledPackage("") {
		t.Fatal("portable package was treated as installed")
	}
	if err := os.Mkdir(marker, 0700); err != nil {
		t.Fatal(err)
	}
	if windowsInstalledPackage(executable) {
		t.Fatal("directory was accepted as an installer marker")
	}
	if err := os.Remove(marker); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(marker, []byte("installer marker"), 0600); err != nil {
		t.Fatal(err)
	}
	if !windowsInstalledPackage(executable) {
		t.Fatal("installed package was treated as portable")
	}
}

func TestStableUpdaterNeverOptsIntoCandidateOrDowngrade(t *testing.T) {
	for _, tc := range []struct {
		name, current, tag string
		prerelease         bool
		wantStatus         int
		wantNewer          bool
	}{
		{"stable cannot opt into RC", "7.0.0", "v8.0.0-rc.1", true, 502, false},
		{"mislabeled candidate rejected", "7.0.0", "v8.0.0-rc.1", false, 502, false},
		{"candidate updates remain manual", "8.0.0-rc.1", "v8.0.0-rc.2", true, 502, false},
		{"RC does not downgrade to stable seven", "8.0.0-rc.1", "v7.0.0", false, 200, false},
		{"candidate reaches stable eight", "8.0.0-rc.2", "v8.0.0", false, 200, true},
		{"stable seven reaches stable eight", "7.0.0", "v8.0.0", false, 200, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_ = json.NewEncoder(w).Encode(map[string]any{"tag_name": tc.tag, "prerelease": tc.prerelease})
			}))
			defer upstream.Close()
			oldURL, oldClient := githubLatestRelease, updateHTTPClient
			githubLatestRelease, updateHTTPClient = upstream.URL, upstream.Client()
			defer func() { githubLatestRelease, updateHTTPClient = oldURL, oldClient }()
			server := New(Options{Version: tc.current, LocalToken: testLocalToken})
			rec := httptest.NewRecorder()
			server.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodGet, "/local/update", nil))
			if rec.Code != tc.wantStatus {
				t.Fatalf("check status %d: %s", rec.Code, rec.Body)
			}
			if tc.wantStatus == 200 {
				var result map[string]any
				if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
					t.Fatal(err)
				}
				if result["newer"] != tc.wantNewer || result["channel"] != "stable" || result["automatic_install"] != false {
					t.Fatalf("incorrect update policy: %v", result)
				}
			}
			if !tc.wantNewer {
				rec = httptest.NewRecorder()
				server.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPost, "/local/update/download", nil))
				if rec.Code != http.StatusConflict && rec.Code != http.StatusBadGateway {
					t.Fatalf("candidate/downgrade download was allowed: %d", rec.Code)
				}
			}
		})
	}
}

func TestVerifiedRedownloadReplacesOnlyCompletedDownload(t *testing.T) {
	content := []byte("complete verified package")
	digest := sha256.Sum256(content)
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write(content) }))
	defer upstream.Close()
	old := updateHTTPClient
	updateHTTPClient = upstream.Client()
	defer func() { updateHTTPClient = old }()
	dir := t.TempDir()
	destination := filepath.Join(dir, "package.zip")
	if err := os.WriteFile(destination, []byte("previous download"), 0600); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if _, err := saveVerifiedUpdate(httptest.NewRequest(http.MethodPost, "/", nil), upstream.URL, destination, hex.EncodeToString(digest[:]), 1024); err != nil {
			t.Fatal(err)
		}
	}
	actual, err := os.ReadFile(destination)
	if err != nil || string(actual) != string(content) {
		t.Fatal("verified retry lost the completed download")
	}
	files, err := os.ReadDir(dir)
	if err != nil || len(files) != 1 {
		t.Fatal("verified retry left partial downloads")
	}
}

func TestUpgradeInstructionsRequireActualQuitAndCompletePackage(t *testing.T) {
	for _, platform := range []string{"windows", "linux", "darwin"} {
		name := "package.zip"
		if platform != "windows" {
			name = "package.tar.gz"
		}
		hint := updateInstallHint(platform, name, "/download/"+name)
		for _, required := range []string{"退出程序", "远程会话", "释放输入", "完整", "保留", "/download/" + name} {
			if !strings.Contains(hint, required) {
				t.Fatalf("%s upgrade omitted %q: %s", platform, required, hint)
			}
		}
	}
}
