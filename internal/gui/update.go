package gui

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/model"
)

var githubLatestRelease = "https://api.github.com/repos/ZHanry/home-tunnel-client/releases/latest"

var updateHTTPClient = &http.Client{
	Timeout: 5 * time.Minute,
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 10 {
			return fmt.Errorf("too many redirects")
		}
		return secureUpdateURL(req.URL.String())
	},
}

type githubRelease struct {
	TagName    string `json:"tag_name"`
	HTMLURL    string `json:"html_url"`
	Draft      bool   `json:"draft"`
	Prerelease bool   `json:"prerelease"`
	Assets     []struct {
		Name string `json:"name"`
		URL  string `json:"browser_download_url"`
	} `json:"assets"`
}

func currentVersion(options Options) string {
	if options.Version != "" && options.Version != "development" {
		return options.Version
	}
	return model.Version
}

func secureUpdateURL(value string) error {
	u, err := url.Parse(value)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil {
		return fmt.Errorf("更新地址必须使用 HTTPS")
	}
	return nil
}

func updateResponse(request *http.Request, address string) (*http.Response, error) {
	if err := secureUpdateURL(address); err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(request.Context(), http.MethodGet, address, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "HomeTunnel-GUI/"+model.Version)
	req.Header.Set("Accept", "application/vnd.github+json")
	resp, err := updateHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	if err = secureUpdateURL(resp.Request.URL.String()); err != nil {
		resp.Body.Close()
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("更新服务器返回 HTTP %d", resp.StatusCode)
	}
	return resp, nil
}

func boundedUpdateBody(request *http.Request, address string, limit int64) ([]byte, error) {
	resp, err := updateResponse(request, address)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(body)) > limit {
		return nil, fmt.Errorf("更新响应超过大小限制")
	}
	return body, nil
}

func fetchLatestRelease(request *http.Request) (githubRelease, error) {
	var payload githubRelease
	body, err := boundedUpdateBody(request, githubLatestRelease, 2<<20)
	if err != nil {
		return payload, err
	}
	if err = json.Unmarshal(body, &payload); err != nil {
		return payload, err
	}
	version, err := parseUpdateVersion(payload.TagName)
	if err != nil || payload.Draft || payload.Prerelease || len(version.pre) > 0 {
		return payload, fmt.Errorf("发布信息不是有效的正式版本")
	}
	if payload.HTMLURL != "" {
		if err = secureUpdateURL(payload.HTMLURL); err != nil {
			return payload, err
		}
	}
	return payload, nil
}

func packageAsset(release githubRelease) (name, address, checksumURL string) {
	executable, _ := os.Executable()
	return packageAssetFor(release, runtime.GOOS, runtime.GOARCH, windowsInstalledPackage(executable))
}

// Inno Setup installs its uninstaller alongside the GUI. A portable directory
// has no such marker and must keep using the complete portable bundle.
func windowsInstalledPackage(executable string) bool {
	if executable == "" {
		return false
	}
	info, err := os.Lstat(filepath.Join(filepath.Dir(executable), "unins000.exe"))
	return err == nil && info.Mode().IsRegular()
}

func packageAssetFor(release githubRelease, platform, architecture string, installed bool) (name, address, checksumURL string) {
	latest := strings.TrimPrefix(release.TagName, "v")
	if _, err := parseUpdateVersion(release.TagName); err != nil {
		return "", "", ""
	}
	want := ""
	switch platform {
	case "windows":
		if architecture != "amd64" {
			return "", "", ""
		}
		want = "HomeTunnel-Windows-" + latest + "-x64.zip"
		if installed {
			want = "HomeTunnel-Setup-" + latest + "-x64.exe"
		}
	case "linux", "darwin":
		if architecture != "amd64" && architecture != "arm64" {
			return "", "", ""
		}
		if platform == "darwin" {
			platform = "macos"
		}
		want = "home-tunnel-" + platform + "-" + latest + "-" + architecture + ".tar.gz"
	}
	if want == "" {
		return "", "", ""
	}
	var specific, manifest string
	seen := make(map[string]bool)
	for _, asset := range release.Assets {
		if seen[asset.Name] {
			return "", "", ""
		}
		seen[asset.Name] = true
		switch asset.Name {
		case want:
			name, address = asset.Name, asset.URL
		case want + ".sha256":
			specific = asset.URL
		case "SHA256SUMS.txt":
			manifest = asset.URL
		}
	}
	if specific != "" {
		return name, address, specific
	}
	return name, address, manifest
}

func (server *Server) update(writer http.ResponseWriter, request *http.Request) {
	current := currentVersion(server.options)
	release, err := fetchLatestRelease(request)
	if err != nil {
		writeError(writer, http.StatusBadGateway, "检查更新失败："+err.Error())
		return
	}
	comparison, err := compareUpdateVersions(release.TagName, current)
	if err != nil {
		writeError(writer, http.StatusBadGateway, err.Error())
		return
	}
	name, address, checksumURL := packageAsset(release)
	writeJSON(writer, map[string]any{
		"current": current, "latest": strings.TrimPrefix(release.TagName, "v"),
		"newer": comparison > 0, "url": release.HTMLURL, "asset": name,
		"download_url": address, "checksum_url": checksumURL,
		"channel": "stable", "automatic_install": false,
	})
}

func (server *Server) downloadUpdate(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	release, err := fetchLatestRelease(request)
	if err != nil {
		writeError(writer, http.StatusBadGateway, "无法读取 GitHub Release："+err.Error())
		return
	}
	comparison, err := compareUpdateVersions(release.TagName, currentVersion(server.options))
	if err != nil || comparison <= 0 {
		writeError(writer, http.StatusConflict, "没有更新的正式版本")
		return
	}
	name, address, checksumURL := packageAsset(release)
	if address == "" {
		writeError(writer, http.StatusNotFound, "当前系统没有对应的更新包，请打开 Release 页面手动下载")
		return
	}
	// A missing, unavailable or ambiguous checksum must never permit a download.
	expected, err := fetchChecksum(request, checksumURL, name)
	if err != nil {
		writeError(writer, http.StatusBadGateway, err.Error())
		return
	}
	destinationDir := updateDownloadDir()
	if err = os.MkdirAll(destinationDir, 0o755); err != nil {
		writeError(writer, http.StatusInternalServerError, err.Error())
		return
	}
	destination := filepath.Join(destinationDir, name)
	actual, err := saveVerifiedUpdate(request, address, destination, expected, 256<<20)
	if err != nil {
		writeError(writer, http.StatusBadGateway, err.Error())
		return
	}
	hint := updateInstallHint(runtime.GOOS, name, destination)
	writeJSON(writer, map[string]any{"path": destination, "sha256": actual, "verified": true, "hint": hint,
		"channel": "stable", "automatic_install": false})
}

func updateInstallHint(platform, name, destination string) string {
	prefix := fmt.Sprintf("完整更新包已保存并校验：%s。先在界面或托盘选择「退出程序」，结束远程会话并释放输入；关闭窗口仍会在后台运行。", destination)
	if platform == "windows" && strings.HasSuffix(name, ".exe") {
		return prefix + "备份原安装目录及用户数据后运行完整安装程序。保留上一版本完整安装包供失败时恢复。"
	}
	if platform == "windows" {
		return prefix + "将完整 ZIP 解压到新目录，再从新目录启动；保留旧完整目录和用户数据备份供恢复。"
	}
	return prefix + "将完整归档解压到新目录。系统安装版按包内说明运行 install.sh --upgrade；便携运行请保留目录结构并从新目录启动。保留旧完整包和用户数据备份供恢复。"
}

func saveVerifiedUpdate(request *http.Request, address, destination, expected string, limit int64) (string, error) {
	resp, err := updateResponse(request, address)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.ContentLength > limit {
		return "", fmt.Errorf("更新包超过大小限制")
	}
	file, err := os.CreateTemp(filepath.Dir(destination), ".home-tunnel-*.part")
	if err != nil {
		return "", err
	}
	defer func() { file.Close(); _ = os.Remove(file.Name()) }()
	sum := sha256.New()
	size, err := io.Copy(io.MultiWriter(file, sum), io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return "", err
	}
	if size == 0 || size > limit || (resp.ContentLength >= 0 && size != resp.ContentLength) {
		return "", fmt.Errorf("更新包大小不完整或超过限制")
	}
	actual := hex.EncodeToString(sum.Sum(nil))
	if !strings.EqualFold(expected, actual) {
		return "", fmt.Errorf("SHA-256 与发布清单不一致，下载已拒绝")
	}
	if err = file.Sync(); err != nil {
		return "", err
	}
	if err = file.Close(); err != nil {
		return "", err
	}
	if err = replaceVerifiedDownload(file.Name(), destination); err != nil {
		return "", err
	}
	return actual, nil
}

func updateDownloadDir() string {
	if dir := strings.TrimSpace(os.Getenv("HOME_TUNNEL_DOWNLOAD_DIR")); dir != "" {
		return dir
	}
	home, _ := os.UserHomeDir()
	if runtime.GOOS == "windows" && os.Getenv("USERPROFILE") != "" {
		home = os.Getenv("USERPROFILE")
	}
	return filepath.Join(home, "Downloads")
}

func parseChecksum(text, assetName string) string {
	var result string
	for _, line := range strings.Split(text, "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 || strings.TrimPrefix(fields[1], "*") != assetName {
			continue
		}
		decoded, err := hex.DecodeString(fields[0])
		if err != nil || len(decoded) != sha256.Size || result != "" {
			return ""
		}
		result = strings.ToLower(fields[0])
	}
	return result
}

func fetchChecksum(request *http.Request, checksumURL, assetName string) (string, error) {
	if checksumURL == "" {
		return "", fmt.Errorf("发布缺少 SHA-256 校验清单")
	}
	body, err := boundedUpdateBody(request, checksumURL, 1<<20)
	if err != nil {
		return "", fmt.Errorf("无法获取校验清单：%w", err)
	}
	digest := parseChecksum(string(body), assetName)
	if digest == "" {
		return "", fmt.Errorf("校验清单缺少唯一有效的文件名及 SHA-256")
	}
	return digest, nil
}
