package origin

import "testing"

func TestHTTPSCanonicalBrowserOrigin(t *testing.T) {
	for input, want := range map[string]string{"https://CONSOLE.example:443/admin": "https://console.example/admin", "https://[2001:0DB8:0:0::1]:443/admin": "https://[2001:db8::1]/admin", "https://console.example:0444/admin": "https://console.example:444/admin", "https://127.0.0.1:443/admin": "https://127.0.0.1/admin"} {
		actual, err := HTTPS(input)
		if err != nil || actual.String() != want {
			t.Fatalf("%q: %v %v", input, actual, err)
		}
	}
	for _, input := range []string{"http://console.example/admin", "https://user:pass@console.example", "https:console.example", "https://console.example:0", "https://console.example:", "https://[fe80::1%25zone]", "https://console.example/%61dmin", "https://127.1", "https://2130706433", "https://console.example\\@attacker.test"} {
		if _, err := HTTPS(input); err == nil {
			t.Errorf("unsafe address accepted: %s", input)
		}
	}
}
