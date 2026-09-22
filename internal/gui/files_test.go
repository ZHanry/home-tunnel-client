package gui

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLocalFileActionsRejectCallerSuppliedPaths(t *testing.T) {
	s := New(Options{LocalToken: testLocalToken})
	for _, body := range []string{`{"action":"send","paths":["C:/private.txt"]}`, `{"action":"receive","path":"C:/overwrite.txt"}`, `{"action":"send"} {"action":"cancel"}`} {
		rec := httptest.NewRecorder()
		s.Handler().ServeHTTP(rec, trustedLocalRequest(http.MethodPost, "/local/remote/files", strings.NewReader(body)))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("unsafe file request accepted: %d", rec.Code)
		}
	}
}
