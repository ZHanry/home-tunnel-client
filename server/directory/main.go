// HomeDesk 账号设备目录：复用 home-tunnel 会话，只保存设备自报的远控地址。
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var uuidPattern = regexp.MustCompile(`^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$`)
var remotePattern = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,64}$`)
var serverPattern = regexp.MustCompile(`^[a-zA-Z0-9.-]+:[0-9]{1,5}$`)
var digestPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type identity struct {
	ID            string  `json:"id"`
	DeviceID      *string `json:"device_id"`
	NativeRemote  bool    `json:"native_remote"`
	PasswordState string  `json:"password_state"`
}
type entry struct {
	UserID    string    `json:"user_id,omitempty"`
	DeviceID  string    `json:"device_id"`
	RemoteID  string    `json:"remote_id"`
	Server    string    `json:"server"`
	KeySHA256 string    `json:"key_sha256"`
	Platform  string    `json:"platform"`
	LastSeen  time.Time `json:"last_seen"`
	Online    bool      `json:"online"`
}
type directory struct {
	mu      sync.Mutex
	records map[string]entry
	file    string
	control string
	client  *http.Client
	slots   chan struct{}
}

func newDirectory(control, file string) (*directory, error) {
	u, err := url.Parse(control)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return nil, errors.New("控制服务地址无效")
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	d := &directory{records: map[string]entry{}, file: file, control: strings.TrimRight(control, "/"),
		client: &http.Client{Timeout: 5 * time.Second, Transport: transport,
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
	d.slots = make(chan struct{}, 32)
	if file != "" {
		data, err := os.ReadFile(file)
		if err == nil {
			if len(data) > 16*1024*1024 || json.Unmarshal(data, &d.records) != nil {
				return nil, errors.New("目录数据损坏")
			}
			if d.records == nil {
				return nil, errors.New("目录数据无效")
			}
		} else if !errors.Is(err, os.ErrNotExist) {
			return nil, err
		}
	}
	return d, nil
}

func reply(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func failure(w http.ResponseWriter, status int, code string) {
	reply(w, status, map[string]string{"error_code": code, "message": "设备目录请求未完成，请刷新或重新登录。"})
}
func (d *directory) upstream(ctx context.Context, token, path string, target any) int {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, d.control+"/api/v1"+path, nil)
	if err != nil {
		return 502
	}
	req.Header.Set("Authorization", token)
	req.Header.Set("Accept", "application/json")
	response, err := d.client.Do(req)
	if err != nil {
		return 502
	}
	defer response.Body.Close()
	if response.StatusCode == 401 || response.StatusCode == 403 {
		return 401
	}
	if response.StatusCode != 200 {
		return 502
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 1024*1024+1))
	if err != nil || len(body) > 1024*1024 || json.Unmarshal(body, target) != nil {
		return 502
	}
	return 200
}
func (d *directory) authenticate(r *http.Request) (identity, string, int) {
	token := r.Header.Get("Authorization")
	var who identity
	if !strings.HasPrefix(token, "Bearer ") || len(token) < 23 || len(token) > 4096 || strings.ContainsAny(strings.TrimPrefix(token, "Bearer "), " \r\n\t") {
		return who, "", 401
	}
	status := d.upstream(r.Context(), token, "/auth/me", &who)
	if status != 200 {
		return who, "", status
	}
	if !uuidPattern.MatchString(who.ID) || who.NativeRemote || who.PasswordState == "must_change" {
		return who, "", 403
	}
	if who.DeviceID != nil && !uuidPattern.MatchString(*who.DeviceID) {
		return who, "", 403
	}
	return who, token, 200
}

func (d *directory) save(records map[string]entry) error {
	if d.file == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(d.file), 0700); err != nil {
		return err
	}
	payload, err := json.Marshal(records)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(d.file), ".directory-")
	if err != nil {
		return err
	}
	name := f.Name()
	defer os.Remove(name)
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(payload)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(name, d.file)
}
func (d *directory) publish(w http.ResponseWriter, r *http.Request, who identity) {
	if who.DeviceID == nil {
		failure(w, 403, "DEVICE_SESSION_REQUIRED")
		return
	}
	var value entry
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&value) != nil || decoder.Decode(&struct{}{}) != io.EOF ||
		value.DeviceID != *who.DeviceID || !remotePattern.MatchString(value.RemoteID) ||
		!serverPattern.MatchString(value.Server) || !digestPattern.MatchString(value.KeySHA256) ||
		(value.Platform != "windows" && value.Platform != "linux" && value.Platform != "darwin") || value.UserID != "" {
		failure(w, 400, "DEVICE_METADATA_INVALID")
		return
	}
	_, portText, err := net.SplitHostPort(value.Server)
	port, parseErr := strconv.Atoi(portText)
	if err != nil || parseErr != nil || port < 1 || port > 65535 {
		failure(w, 400, "DEVICE_METADATA_INVALID")
		return
	}
	value.UserID = who.ID
	value.LastSeen = time.Now().UTC()
	value.Online = false
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, old := range d.records {
		if old.DeviceID != value.DeviceID && old.RemoteID == value.RemoteID && old.Server == value.Server && old.KeySHA256 == value.KeySHA256 {
			failure(w, 409, "REMOTE_ID_ALREADY_BOUND")
			return
		}
	}
	if old, ok := d.records[value.DeviceID]; ok && old.UserID != value.UserID {
		failure(w, 409, "DEVICE_OWNER_MISMATCH")
		return
	}
	next := make(map[string]entry, len(d.records)+1)
	for key, old := range d.records {
		next[key] = old
	}
	next[value.DeviceID] = value
	if len(next) > 10000 || d.save(next) != nil {
		failure(w, 503, "DIRECTORY_STORAGE_FAILED")
		return
	}
	d.records = next
	reply(w, 200, map[string]any{"device_id": value.DeviceID, "registered": true})
}
func (d *directory) list(w http.ResponseWriter, r *http.Request, who identity, token string) {
	if who.DeviceID != nil {
		failure(w, 403, "ACCOUNT_SESSION_REQUIRED")
		return
	}
	allowed := map[string]bool{}
	for page := 1; page <= 100; page++ {
		var result struct {
			Items []struct {
				ID     string `json:"id"`
				Status string `json:"status"`
			} `json:"items"`
			TotalPages int `json:"total_pages"`
		}
		status := d.upstream(r.Context(), token, fmt.Sprintf("/client/devices?page=%d&page_size=100", page), &result)
		if status != 200 {
			failure(w, status, "ACCOUNT_DIRECTORY_UNAVAILABLE")
			return
		}
		if result.TotalPages < 1 || result.TotalPages > 100 || len(result.Items) > 100 {
			failure(w, 502, "DIRECTORY_RESPONSE_INVALID")
			return
		}
		for _, device := range result.Items {
			if !uuidPattern.MatchString(device.ID) || allowed[device.ID] {
				failure(w, 502, "DIRECTORY_RESPONSE_INVALID")
				return
			}
			if device.Status != "revoked" {
				allowed[device.ID] = true
			}
		}
		if page >= result.TotalPages {
			break
		}
	}
	items := []entry{}
	d.mu.Lock()
	for id, value := range d.records {
		if value.UserID == who.ID && allowed[id] {
			value.UserID = ""
			value.Online = time.Since(value.LastSeen) < 90*time.Second
			items = append(items, value)
		}
	}
	d.mu.Unlock()
	sort.Slice(items, func(i, j int) bool { return items[i].DeviceID < items[j].DeviceID })
	reply(w, 200, map[string]any{"items": items, "version": 1})
}
func (d *directory) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/health" && r.Method == http.MethodGet {
		reply(w, 200, map[string]bool{"healthy": true})
		return
	}
	if r.URL.Path != "/api/v1/homedesk/devices" && r.URL.Path != "/api/v1/homedesk/devices/current" {
		failure(w, 404, "NOT_FOUND")
		return
	}
	if !((r.Method == http.MethodGet && r.URL.Path == "/api/v1/homedesk/devices") || (r.Method == http.MethodPut && strings.HasSuffix(r.URL.Path, "/current"))) {
		failure(w, 405, "METHOD_NOT_ALLOWED")
		return
	}
	select {
	case d.slots <- struct{}{}:
		defer func() { <-d.slots }()
	default:
		failure(w, 503, "DIRECTORY_BUSY")
		return
	}
	who, token, status := d.authenticate(r)
	if status != 200 {
		failure(w, status, "AUTH_REQUIRED")
		return
	}
	if r.Method == http.MethodPut {
		d.publish(w, r, who)
	} else {
		d.list(w, r, who, token)
	}
}
func main() {
	if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
		client := &http.Client{Timeout: 3 * time.Second}
		response, err := client.Get("http://127.0.0.1:8080/health")
		if err != nil {
			os.Exit(1)
		}
		response.Body.Close()
		if response.StatusCode != 200 {
			os.Exit(1)
		}
		return
	}
	control := os.Getenv("HOMEDESK_CONTROL_CENTER")
	file := os.Getenv("HOMEDESK_DIRECTORY_FILE")
	if file == "" {
		file = "/data/directory.json"
	}
	d, err := newDirectory(control, file)
	if err != nil {
		log.Fatal("目录配置或存储初始化失败")
	}
	address := os.Getenv("HOMEDESK_DIRECTORY_LISTEN")
	if address == "" {
		address = ":8080"
	}
	s := &http.Server{Addr: address, Handler: d, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	log.Fatal(s.ListenAndServe())
}
