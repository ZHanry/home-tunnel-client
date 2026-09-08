package gui

import (
	"crypto/subtle"
	"mime"
	"net"
	"net/http"
	"net/url"
	"strings"
)

// A loopback listener alone does not stop a hostile website or DNS rebinding.
// Only literal-loopback Host values and same-origin browser requests are accepted.
// Native singleton probes have no Origin; their mutation requests use JSON.
func protectLocalUI(next http.Handler, token string) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("X-Frame-Options", "DENY")
		writer.Header().Set("Content-Security-Policy", "frame-ancestors 'none'; base-uri 'none'; object-src 'none'")
		writer.Header().Set("X-Content-Type-Options", "nosniff")
		writer.Header().Set("Referrer-Policy", "no-referrer")
		writer.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
		writer.Header().Set("Cache-Control", "no-store")
		host, port, err := net.SplitHostPort(request.Host)
		if err != nil || port == "" || (host != "127.0.0.1" && host != "::1") {
			http.Error(writer, "local UI requires a literal loopback address", http.StatusForbidden)
			return
		}
		peer, _, err := net.SplitHostPort(request.RemoteAddr)
		if err != nil || !net.ParseIP(peer).IsLoopback() {
			http.Error(writer, "local UI requires a loopback connection", http.StatusForbidden)
			return
		}
		if origin := request.Header.Get("Origin"); origin != "" {
			parsed, parseErr := url.Parse(origin)
			if parseErr != nil || parsed.Scheme != "http" || parsed.Host != request.Host || parsed.User != nil || parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
				http.Error(writer, "cross-origin local UI requests are forbidden", http.StatusForbidden)
				return
			}
		}
		if site := request.Header.Get("Sec-Fetch-Site"); site != "" && site != "same-origin" && site != "none" {
			http.Error(writer, "cross-site local UI requests are forbidden", http.StatusForbidden)
			return
		}
		if request.Method == http.MethodOptions {
			http.Error(writer, "cross-origin preflight is not supported", http.StatusForbidden)
			return
		}
		if strings.HasPrefix(request.URL.Path, "/local/") {
			expected := "Bearer " + token
			if token == "" || subtle.ConstantTimeCompare([]byte(request.Header.Get("Authorization")), []byte(expected)) != 1 {
				writeError(writer, http.StatusUnauthorized, "desktop session authorization is required; open the installed client")
				return
			}
		}
		if strings.HasPrefix(request.URL.Path, "/local/") && request.Method != http.MethodGet && request.Method != http.MethodHead {
			contentType, _, parseErr := mime.ParseMediaType(request.Header.Get("Content-Type"))
			if parseErr != nil || contentType != "application/json" {
				http.Error(writer, "local UI mutations require JSON", http.StatusUnsupportedMediaType)
				return
			}
		}
		next.ServeHTTP(writer, request)
	})
}
