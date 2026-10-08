// HOMEDESK: 成功同步后的设备会话上报自己的远控 ID，不传递管理账号凭据。
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"
)

type directoryPublisher struct {
	mu       sync.Mutex
	next     time.Time
	client   *http.Client
	endpoint string
	metadata map[string]string
}

func newDirectoryPublisher(origin *url.URL, transport http.RoundTripper, device, id, server, key string) *directoryPublisher {
	if !regexp.MustCompile(`^[a-zA-Z0-9_-]{1,64}$`).MatchString(id) ||
		!regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(key) {
		return nil
	}
	server = strings.ToLower(strings.TrimSpace(server))
	if !strings.Contains(server, ":") {
		server += ":21116"
	}
	if !regexp.MustCompile(`^[a-z0-9.-]+:[0-9]{1,5}$`).MatchString(server) {
		return nil
	}
	return &directoryPublisher{
		endpoint: origin.ResolveReference(&url.URL{Path: "/api/v1/homedesk/devices/current"}).String(),
		client: &http.Client{Timeout: 6 * time.Second, Transport: transport,
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
		metadata: map[string]string{"device_id": device, "remote_id": id, "server": server,
			"key_sha256": key, "platform": runtime.GOOS},
	}
}

func (p *directoryPublisher) publish(token string) {
	if p == nil || !strings.HasPrefix(token, "Bearer ") {
		return
	}
	p.mu.Lock()
	if time.Now().Before(p.next) {
		p.mu.Unlock()
		return
	}
	p.next = time.Now().Add(30 * time.Second)
	p.mu.Unlock()
	// 独立短请求不阻塞隧道同步；父进程 Job 终止时整个助手立即结束。
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
		defer cancel()
		data, err := json.Marshal(p.metadata)
		if err != nil {
			return
		}
		request, err := http.NewRequestWithContext(ctx, http.MethodPut, p.endpoint, bytes.NewReader(data))
		if err != nil {
			return
		}
		request.Header.Set("Authorization", token)
		request.Header.Set("Content-Type", "application/json")
		response, err := p.client.Do(request)
		if err != nil {
			return
		}
		defer response.Body.Close()
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 8192))
	}()
}
