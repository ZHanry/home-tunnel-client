package diagnostics

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/api"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/state"
)

type Check struct {
	Name      string `json:"name"`
	Status    string `json:"status"`
	Message   string `json:"message"`
	LatencyMS int64  `json:"latency_ms"`
}
type Report struct {
	Version           string    `json:"version"`
	OS                string    `json:"os"`
	Architecture      string    `json:"architecture"`
	CreatedAt         time.Time `json:"created_at"`
	CredentialStorage string    `json:"credential_storage"`
	Enrolled          bool      `json:"enrolled"`
	Connections       int       `json:"connections"`
	ConfigVersion     int64     `json:"config_version"`
	AppliedVersion    int64     `json:"applied_version"`
	Checks            []Check   `json:"checks"`
}
type Options struct {
	StatePath, Server, AgentPath, ExpectedAgentHash string
	HTTPClient                                      *http.Client
}

// Reports contain only allowlisted fields and fixed explanations. Credentials,
// IDs, hostnames, URLs, paths and raw remote errors never enter a support bundle.
func Run(ctx context.Context, options Options) Report {
	report := Report{Version: model.Version, OS: runtime.GOOS, Architecture: runtime.GOARCH, CreatedAt: time.Now().UTC(), CredentialStorage: state.CredentialProtection(), Checks: []Check{}}
	add := func(name, status, message string, start time.Time) {
		report.Checks = append(report.Checks, Check{name, status, message, time.Since(start).Milliseconds()})
	}
	started := time.Now()
	local, err := (state.Store{Path: options.StatePath}).Load()
	if err != nil {
		add("state", "fail", "Cannot unlock or read local state. Use the original OS account or enroll again.", started)
		return report
	}
	report.Enrolled = local.Enrolled()
	report.Connections = len(local.CachedConnections)
	report.ConfigVersion = local.LastConfigVersion
	report.AppliedVersion = local.AppliedConfigVersion
	add("state", "pass", "Local state is readable; secret fields are excluded from this report.", started)
	address := options.Server
	if address == "" {
		address = local.Profile.PublicBaseURL
	}
	if address == "" {
		add("server", "warning", "No server configured. Supply --server or enroll this device.", time.Now())
		return report
	}
	parsed, err := url.Parse(address)
	if err != nil || parsed.Scheme != "https" || parsed.Hostname() == "" || parsed.User != nil {
		add("server", "fail", "Configure a valid HTTPS server origin.", time.Now())
		return report
	}
	started = time.Now()
	dnsCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	_, err = net.DefaultResolver.LookupHost(dnsCtx, parsed.Hostname())
	cancel()
	if err != nil {
		add("dns", "fail", "Server DNS lookup failed; check DNS and the configured server address.", started)
	} else {
		add("dns", "pass", "Server DNS resolves.", started)
	}
	started = time.Now()
	httpsCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	profile, err := api.Discover(httpsCtx, address, options.HTTPClient)
	cancel()
	if err != nil {
		add("https_discovery", "fail", "HTTPS discovery failed. Check certificate trust, server origin and reverse-proxy routing.", started)
		profile = local.Profile
	} else {
		add("https_discovery", "pass", "HTTPS certificate and same-origin service discovery succeeded.", started)
	}
	if profile.FRPSHost != "" && profile.FRPSPort > 0 {
		started = time.Now()
		dialer := net.Dialer{Timeout: 3 * time.Second}
		connection, dialErr := dialer.DialContext(ctx, "tcp", net.JoinHostPort(profile.FRPSHost, strconv.Itoa(profile.FRPSPort)))
		if dialErr != nil {
			add("frps_port", "fail", "FRPS TCP port is unreachable. Check firewall, port publishing and the FRPS service.", started)
		} else {
			connection.Close()
			add("frps_port", "pass", "FRPS TCP port accepts connections. This check does not authenticate a tunnel.", started)
		}
		block, _ := pem.Decode([]byte(profile.FRPSTLSCertificatePEM))
		if block == nil {
			add("frps_trust", "warning", "No pinned FRPS certificate is configured; upgrade the server trust configuration.", time.Now())
		} else {
			cert, certErr := x509.ParseCertificate(block.Bytes)
			if certErr != nil || time.Now().Before(cert.NotBefore) || time.Now().After(cert.NotAfter) {
				add("frps_trust", "fail", "The configured FRPS trust certificate is invalid or expired.", time.Now())
			} else {
				add("frps_trust", "pass", "Configured FRPS trust material is parseable and within its validity period.", time.Now())
			}
		}
	}
	if local.Enrolled() && profile.APIBaseURL != "" && strings.TrimRight(profile.APIBaseURL, "/") == strings.TrimRight(local.Profile.APIBaseURL, "/") {
		started = time.Now()
		client, clientErr := api.New(profile.APIBaseURL, options.HTTPClient)
		if clientErr == nil {
			authCtx, cancelAuth := context.WithTimeout(ctx, 8*time.Second)
			_, clientErr = client.DeviceLogin(authCtx, local.DeviceID, local.DeviceCredential)
			if clientErr == nil {
				_, clientErr = client.ListConnections(authCtx)
				_ = client.CloseSession(authCtx)
			}
			cancelAuth()
		}
		if clientErr != nil {
			add("authentication", "fail", "Device authentication or resource access failed. Check account, device status and required password changes.", started)
		} else {
			add("authentication", "pass", "Device credentials and connection access are valid.", started)
		}
	} else {
		add("authentication", "warning", "No enrolled credentials match this server; authentication was not tested.", time.Now())
	}
	if options.AgentPath != "" {
		started = time.Now()
		file, openErr := os.Open(options.AgentPath)
		if openErr != nil {
			add("agent_integrity", "fail", "Managed Agent binary is missing or unreadable. Reinstall the official package.", started)
		} else {
			hash := sha256.New()
			_, hashErr := io.Copy(hash, file)
			file.Close()
			if len(options.ExpectedAgentHash) != 64 {
				add("agent_integrity", "warning", "This build has no pinned Agent digest.", started)
			} else if hashErr != nil || !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), options.ExpectedAgentHash) {
				add("agent_integrity", "fail", "Managed Agent SHA-256 does not match this release.", started)
			} else {
				add("agent_integrity", "pass", "Managed Agent matches the release digest.", started)
			}
		}
	}
	targets := local.CachedConnections
	if len(targets) > 50 {
		targets = targets[:50]
		add("target_limit", "warning", "Only the first 50 local targets were probed. Inspect remaining connections separately.", time.Now())
	}
	results := make([]Check, len(targets))
	sem := make(chan struct{}, 4)
	var group sync.WaitGroup
	for i, target := range targets {
		group.Add(1)
		go func(index int, target model.Connection) {
			defer group.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			results[index] = probeLocal(ctx, index, target)
		}(i, target)
	}
	group.Wait()
	report.Checks = append(report.Checks, results...)
	return report
}

func probeLocal(ctx context.Context, index int, target model.Connection) (result Check) {
	started := time.Now()
	result = Check{Name: fmt.Sprintf("local_target_%d", index+1)}
	defer func() { result.LatencyMS = time.Since(started).Milliseconds() }()
	if target.ProxyType == "udp" {
		result.Status = "manual"
		result.Message = "UDP requires an application-level probe from an external network; a socket open is not proof of reachability."
		return result
	}
	if target.LocalPort < 1 || target.LocalPort > 65535 || target.LocalHost == "" {
		result.Status = "fail"
		result.Message = "Local target host or port is invalid."
		return result
	}
	probeCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	address := net.JoinHostPort(target.LocalHost, strconv.Itoa(target.LocalPort))
	dialer := net.Dialer{Timeout: 3 * time.Second}
	connection, err := dialer.DialContext(probeCtx, "tcp", address)
	if err != nil {
		result.Status = "fail"
		result.Message = "Local target port is unreachable. Start the application and verify its listening address."
		return result
	}
	connection.Close()
	result.Status = "pass"
	result.Message = "Local TCP target accepts connections. Verify application authentication separately."
	if target.ProxyType == "http" || target.ProxyType == "" {
		scheme := target.LocalScheme
		if scheme != "http" && scheme != "https" {
			result.Status = "fail"
			result.Message = "Local HTTP scheme is invalid."
			return result
		}
		request, reqErr := http.NewRequestWithContext(probeCtx, http.MethodHead, (&url.URL{Scheme: scheme, Host: address, Path: "/"}).String(), nil)
		if reqErr != nil {
			result.Status = "fail"
			result.Message = "Local HTTP target is invalid."
			return result
		}
		transport := &http.Transport{Proxy: nil}
		defer transport.CloseIdleConnections()
		client := &http.Client{Timeout: 3 * time.Second, Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
		response, httpErr := client.Do(request)
		if httpErr != nil {
			result.Status = "fail"
			result.Message = "Local HTTP request failed; verify scheme and certificate trust."
			return result
		}
		response.Body.Close()
		result.Message = fmt.Sprintf("Local HTTP target replied with status %d; no credentials were supplied.", response.StatusCode)
		if response.StatusCode >= 500 {
			result.Status = "warning"
		}
	}
	result.LatencyMS = time.Since(started).Milliseconds()
	return result
}

func WriteBundle(report Report, destination string) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(destination), ".support-*.part")
	if err != nil {
		return err
	}
	defer func() { file.Close(); _ = os.Remove(file.Name()) }()
	archive := zip.NewWriter(file)
	entry, err := archive.Create("diagnostics.json")
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(entry)
	encoder.SetIndent("", "  ")
	if err = encoder.Encode(report); err != nil {
		return err
	}
	entry, err = archive.Create("README.txt")
	if err != nil {
		return err
	}
	if _, err = io.WriteString(entry, "Home Tunnel support bundle\nContains fixed diagnostic results and version counters only. No credentials, tokens, server URLs, hostnames, paths, service names or raw logs are included. UDP and end-to-end application access require a separate manual test.\n"); err != nil {
		return err
	}
	if err = archive.Close(); err != nil {
		return err
	}
	if err = file.Sync(); err != nil {
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), destination)
}
