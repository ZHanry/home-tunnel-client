// HOMEDESK: 覆盖实际公共配置形状、服务器边界与单次登记发送状态。
package main

import (
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"net/http"
	"net/url"
	"testing"
)

func TestPublicConfigurationDerivesAPIInsteadOfRequiringAbsentField(t *testing.T) {
	origin, _ := url.Parse("https://control.example.invalid")
	profile := model.Profile{PublicBaseURL: origin.String(), FRPSHost: origin.Hostname(), FRPSPort: 7000,
		FRPSTLSCertificatePEM: "synthetic certificate"}
	if validateProfile(profile, origin) != nil {
		t.Fatal("合法公共配置没有 api_base_url 也应通过")
	}
	for _, change := range []func(*model.Profile){
		func(p *model.Profile) { p.PublicBaseURL = "https://other.example.invalid" },
		func(p *model.Profile) { p.FRPSHost = "other.example.invalid" },
		func(p *model.Profile) { p.FRPSTLSCertificatePEM = "" },
		func(p *model.Profile) { p.FRPSPort = 0 },
	} {
		invalid := profile
		change(&invalid)
		if validateProfile(invalid, origin) == nil {
			t.Fatal("不应允许扩大端点或取消证书")
		}
	}
}

func TestRejectedOriginDoesNotBecomeUnknownDeviceRegistration(t *testing.T) {
	origin, _ := url.Parse("https://control.example.invalid")
	guard := &guardedTransport{origin: origin, transport: http.DefaultTransport.(*http.Transport).Clone()}
	request, _ := http.NewRequest(http.MethodPost, "https://other.example.invalid/api/v1/auth/enroll", nil)
	if _, err := guard.RoundTrip(request); err == nil {
		t.Fatal("必须拒绝外部 origin")
	}
	if guard.enrollmentPosted.Load() {
		t.Fatal("被拒绝的请求不能误计为已发送登记")
	}
}
