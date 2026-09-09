package gui

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/api"
)

func TestClientErrorsPreserveRecoveryCodeWithoutReflectingSecrets(t *testing.T) {
	response := httptest.NewRecorder()
	writeClientError(response, &api.Error{StatusCode: 409, Code: "PORT_POOL_EXHAUSTED", Message: "reflected-sensitive-token"})
	if response.Code != 409 || !strings.Contains(response.Body.String(), "PORT_POOL_EXHAUSTED") {
		t.Fatalf("missing recoverable code: %s", response.Body.String())
	}
	if strings.Contains(response.Body.String(), "reflected-sensitive-token") {
		t.Fatal("remote error content leaked to the UI")
	}
}
