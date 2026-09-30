package desktop

import (
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"strings"
	"testing"
)

func TestRemoteHandoffScriptRejectsUntrustedLaunch(t *testing.T) {
	launch := model.RemoteWindowLaunch{URL: "https://CONSOLE.example:443/admin?nativeRemote=1#remote", HandoffCode: strings.Repeat("S", 43), WindowID: "12345678-1234-1234-1234-123456789abc"}
	script, err := remoteHandoffScript(launch)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(script, `"origin":"https://console.example"`) || !strings.Contains(script, `"url":"https://console.example/admin?nativeRemote=1#remote"`) {
		t.Fatal("browser address not canonicalized")
	}
	for _, url := range []string{"http://console.example/admin", "https://user:secret@console.example/admin", "https://console.example/elsewhere", "https://console.example/%61dmin", "https:console.example/admin"} {
		bad := launch
		bad.URL = url
		if _, err := remoteHandoffScript(bad); err == nil {
			t.Fatalf("unsafe launch accepted: %s", url)
		}
	}
	for _, code := range []string{"", strings.Repeat("A", 42), `</script>`, strings.Repeat("A", 44)} {
		bad := launch
		bad.HandoffCode = code
		if _, err := remoteHandoffScript(bad); err == nil {
			t.Fatal("invalid code accepted")
		}
	}
}
