package gui

import (
	"errors"
	"net/http"
	"net/url"
	"strings"

	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

var errConsoleURL = errors.New("invalid console URL")

// openBrowser hands a validated console URL to the user's default browser.
// Tests replace it; production uses the platform implementation.
var openBrowser = openSystemBrowser

// consoleURL derives the web console address from the signed-in server origin.
// The page never supplies a URL, so only the configured origin can be opened.
func consoleURL(base, section string) (string, error) {
	address, err := url.Parse(base)
	if err != nil || address.Host == "" || address.User != nil || address.Opaque != "" || (address.Scheme != "http" && address.Scheme != "https") {
		return "", errConsoleURL
	}
	if address.Hostname() == "" || strings.ContainsAny(address.Host, "\\\"'<>^`{|} \t\r\n") {
		return "", errConsoleURL
	}
	result := url.URL{Scheme: address.Scheme, Host: strings.ToLower(address.Host), Path: "/"}
	switch section {
	case "":
	case "remote":
		result.Path, result.Fragment = "/admin", "remote"
	default:
		return "", errConsoleURL
	}
	opened := result.String()
	// Defence in depth for the platform launcher: a rebuilt URL never contains
	// characters that a command interpreter or URL handler could reinterpret.
	for _, char := range opened {
		if char <= ' ' || char >= 0x7f || strings.ContainsRune("\"'<>\\^`{|}%&", char) {
			return "", errConsoleURL
		}
	}
	return opened, nil
}

func (server *Server) openConsole(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	request.Body = http.MaxBytesReader(writer, request.Body, 256)
	var body struct {
		Section string `json:"section"`
	}
	if err := readJSON(request, &body); err != nil {
		writeError(writer, http.StatusBadRequest, "控制台地址无效")
		return
	}
	state, err := (statepkg.Store{Path: server.options.StatePath}).Load()
	if err != nil || !state.Enrolled() {
		writeError(writer, http.StatusUnauthorized, "请先登录")
		return
	}
	address, err := consoleURL(state.Profile.PublicBaseURL, body.Section)
	if err != nil {
		writeError(writer, http.StatusBadRequest, "控制台地址无效")
		return
	}
	if err := openBrowser(address); err != nil {
		writeError(writer, http.StatusServiceUnavailable, "无法打开默认浏览器")
		return
	}
	writeJSON(writer, map[string]bool{"ok": true})
}
