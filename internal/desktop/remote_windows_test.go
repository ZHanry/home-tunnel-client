//go:build windows

package desktop

import (
	"reflect"
	"testing"
	"unsafe"

	"github.com/jchv/go-webview2/pkg/edge"
	"golang.org/x/sys/windows"
)

func registrationFixture(t *testing.T, removeFails bool) (*remoteScriptRegistration, *[]string) {
	t.Helper()
	view, core, pending, id, generation, revision, poisoned := remoteView, remoteCore, remotePending, remoteScriptID, remoteGeneration, remoteCloseRevision, remotePoisoned
	navigate, present := navigateRemoteDocument, presentRemoteDocument
	t.Cleanup(func() {
		remoteView, remoteCore, remotePending, remoteScriptID, remoteGeneration, remoteCloseRevision, remotePoisoned = view, core, pending, id, generation, revision, poisoned
		navigateRemoteDocument, presentRemoteDocument = navigate, present
	})
	events := []string{}
	remoteView = &edge.Chromium{}
	remoteCore = &remoteCoreWebView2{vtbl: &remoteCoreVtbl{
		RemoveScriptToExecuteOnDocumentCreated: edge.NewComProc(func(_ *remoteCoreWebView2, id *uint16) uintptr {
			name := windows.UTF16PtrToString(id)
			events = append(events, "remove:"+name)
			if removeFails && name == "old" {
				return 0x80004005
			}
			return 0
		}),
	}}
	navigateRemoteDocument = func(address string) { events = append(events, "navigate:"+address) }
	presentRemoteDocument = func() { events = append(events, "show") }
	remoteScriptID, remoteGeneration, remoteCloseRevision, remotePoisoned = "old", 7, 0, false
	next := &remoteScriptRegistration{generation: 9, address: "about:blank", script: "fixture-script", adding: true, result: make(chan error, 1)}
	remotePending = next
	return next, &events
}

func TestRemoteRegistrationCancellationOnlyRemovesNewScript(t *testing.T) {
	pending, events := registrationFixture(t, false)
	cancelRemoteRegistration(pending)
	remoteScriptAdded(&scriptHandler, 0, windows.StringToUTF16Ptr("new"))
	if remoteGeneration != 7 || remoteScriptID != "old" || remotePending != nil || remotePoisoned {
		t.Fatal("cancel damaged the healthy registration")
	}
	if !reflect.DeepEqual(*events, []string{"remove:new"}) {
		t.Fatal(*events)
	}
	if err := <-pending.result; err == nil {
		t.Fatal("cancel reported success")
	}
}

func TestRemoteRegistrationFailurePreservesLivePage(t *testing.T) {
	pending, events := registrationFixture(t, false)
	remoteScriptAdded(&scriptHandler, 0x80004005, nil)
	if remoteGeneration != 7 || remoteScriptID != "old" || len(*events) != 0 {
		t.Fatal("failed replacement touched the live page")
	}
	if err := <-pending.result; err == nil {
		t.Fatal("failed registration reported success")
	}
}

func TestRemoteRegistrationImmediateAddFailurePreservesLivePage(t *testing.T) {
	pending, events := registrationFixture(t, false)
	pending.adding = false
	remoteCore.vtbl.AddScriptToExecuteOnDocumentCreated = edge.NewComProc(func(_ *remoteCoreWebView2, code *uint16, _ *remoteScriptHandler) uintptr {
		if windows.UTF16PtrToString(code) != "fixture-script" {
			t.Error("wrong registration script")
		}
		return 0x80004005
	})
	registerRemoteScript()
	if remoteGeneration != 7 || remoteScriptID != "old" || remotePending != nil || len(*events) != 0 || pending.script != "" {
		t.Fatal("immediate AddScript failure damaged live page or retained script")
	}
	if err := <-pending.result; err == nil {
		t.Fatal("immediate failure reported success")
	}
}

func TestRemoteRegistrationRemovalFailureDoesNotReplaceLivePage(t *testing.T) {
	pending, events := registrationFixture(t, true)
	remoteScriptAdded(&scriptHandler, 0, windows.StringToUTF16Ptr("new"))
	if remoteGeneration != 7 || remoteScriptID != "old" || !remotePoisoned {
		t.Fatal("unsafe renderer was reused")
	}
	if !reflect.DeepEqual(*events, []string{"remove:old", "remove:new"}) {
		t.Fatal(*events)
	}
	if err := <-pending.result; err == nil {
		t.Fatal("remove failure reported success")
	}
}

func TestRemoteRegistrationCommitsOnlyAfterRemovingOldScript(t *testing.T) {
	pending, events := registrationFixture(t, false)
	remoteScriptAdded(&scriptHandler, 0, windows.StringToUTF16Ptr("new"))
	if remoteGeneration != 9 || remoteScriptID != "new" || remotePending != nil {
		t.Fatal("replacement did not become live")
	}
	if !reflect.DeepEqual(*events, []string{"remove:old", "navigate:about:blank", "show"}) {
		t.Fatal(*events)
	}
	if err := <-pending.result; err != nil {
		t.Fatal(err)
	}
}

func TestRemoteCloseCancelsPendingAndRemovesLiveRegistration(t *testing.T) {
	pending, events := registrationFixture(t, false)
	if !clearRemoteWindow() {
		t.Fatal("close failed")
	}
	if remoteGeneration != 0 || remoteScriptID != "" || pending.phase.Load() != 1 || remoteCloseRevision != 1 {
		t.Fatal("close left authority active")
	}
	remoteScriptAdded(&scriptHandler, 0, windows.StringToUTF16Ptr("new"))
	if !reflect.DeepEqual(*events, []string{"remove:old", "navigate:about:blank", "remove:new"}) {
		t.Fatal(*events)
	}
	if err := <-pending.result; err == nil {
		t.Fatal("closed pending request reported success")
	}
}

func TestRemoteScriptHandlerIUnknownAndOfficialIID(t *testing.T) {
	for _, value := range []string{"{00000000-0000-0000-C000-000000000046}", "{B99369F3-9B11-47B5-BC6F-8E7895FCEA17}"} {
		iid, _ := windows.GUIDFromString(value)
		var result *remoteScriptHandler
		if hr := remoteScriptQueryInterface(&scriptHandler, &iid, &result); hr != 0 || result != &scriptHandler {
			t.Fatalf("QueryInterface rejected %s", value)
		}
	}
	iid := windows.GUID{}
	var result *remoteScriptHandler
	if hr := remoteScriptQueryInterface(&scriptHandler, &iid, &result); hr != 0x80004002 || result != nil {
		t.Fatal("accepted unrelated interface")
	}
	// The pinned dependency and Microsoft WebView2.h place AddScript at 27,
	// RemoveScript at 28, after the IUnknown three-member prefix.
	if unsafe.Offsetof(remoteCoreVtbl{}.AddScriptToExecuteOnDocumentCreated) != 27*unsafe.Sizeof(uintptr(0)) || unsafe.Offsetof(remoteCoreVtbl{}.RemoveScriptToExecuteOnDocumentCreated) != 28*unsafe.Sizeof(uintptr(0)) {
		t.Fatal("WebView2 COM prefix layout changed")
	}
}
