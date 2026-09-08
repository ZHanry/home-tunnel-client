package gui

import (
	"io"
	"net/http"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/paths"
)

const UIAddress = "127.0.0.1:8788"

func ExistingUI() string {
	response, err := singletonRequest(http.MethodGet, "/local/ping")
	if err != nil {
		return ""
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 256))
	if response.StatusCode != http.StatusOK {
		return ""
	}
	return "http://" + UIAddress + "/"
}

func RequestShow() bool {
	if ExistingUI() == "" {
		return false
	}
	response, err := singletonRequest(http.MethodPost, "/local/show")
	if err != nil {
		return false
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 256))
	return response.StatusCode == http.StatusOK
}

func singletonRequest(method, path string) (*http.Response, error) {
	token, err := readLocalToken(paths.DesktopStatePath())
	if err != nil {
		return nil, err
	}
	request, err := http.NewRequest(method, "http://"+UIAddress+path, nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")
	client := &http.Client{
		Timeout:       800 * time.Millisecond,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
	}
	return client.Do(request)
}
