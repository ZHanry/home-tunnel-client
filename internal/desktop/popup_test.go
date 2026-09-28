package desktop

import "testing"

func TestPopupBoundsSitInTheBottomRightOfTheWorkArea(t *testing.T) {
	for _, tc := range []struct {
		name string
		work popupRect
		w, h int
		want popupRect
	}{
		// 1920x1080 with a 48px taskbar at the bottom.
		{"bottom taskbar", popupRect{0, 0, 1920, 1032}, 360, 224, popupRect{1548, 796, 1908, 1020}},
		// Taskbar on the right leaves the work area narrower.
		{"right taskbar", popupRect{0, 0, 1860, 1080}, 360, 224, popupRect{1488, 844, 1848, 1068}},
		// Taskbar at the top shifts the origin.
		{"top taskbar", popupRect{0, 40, 1366, 768}, 320, 60, popupRect{1034, 696, 1354, 756}},
		// A secondary monitor left of the primary gives negative coordinates.
		{"offset origin", popupRect{-1280, 0, 0, 984}, 360, 224, popupRect{-372, 748, -12, 972}},
		// Tiny work areas clamp the size instead of leaving the screen.
		{"tiny", popupRect{0, 0, 300, 200}, 360, 224, popupRect{12, 12, 288, 188}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := popupBounds(tc.work, tc.w, tc.h, popupMargin)
			if got != tc.want {
				t.Fatalf("got %+v, want %+v", got, tc.want)
			}
			if got.Left < tc.work.Left || got.Top < tc.work.Top || got.Right > tc.work.Right || got.Bottom > tc.work.Bottom {
				t.Fatalf("popup leaves the work area: %+v", got)
			}
		})
	}
	if got := popupBounds(popupRect{}, 360, 224, popupMargin); got.Right-got.Left != 360 || got.Bottom-got.Top != 224 {
		t.Fatalf("empty work area: %+v", got)
	}
}

func TestPopupSizeAndScale(t *testing.T) {
	if w, h := popupSize("request"); w != 360 || h != 224 {
		t.Fatalf("request size %dx%d", w, h)
	}
	if w, h := popupSize("session"); w != 320 || h != 60 {
		t.Fatalf("session size %dx%d", w, h)
	}
	for _, tc := range []struct {
		value int
		dpi   uint32
		want  int
	}{{360, 96, 360}, {360, 0, 360}, {360, 144, 540}, {224, 120, 280}, {12, 168, 21}} {
		if got := scaleForDPI(tc.value, tc.dpi); got != tc.want {
			t.Fatalf("scale %d at %d dpi = %d, want %d", tc.value, tc.dpi, got, tc.want)
		}
	}
}

func TestApprovalPopupURLKeepsSessionInFragment(t *testing.T) {
	got, err := approvalPopupURL("http://127.0.0.1:47831/#session=abc123")
	if err != nil || got != "http://127.0.0.1:47831/popup.html#session=abc123" {
		t.Fatalf("got %q, %v", got, err)
	}
	for _, bad := range []string{"https://127.0.0.1:47831/#session=x", "http://example.com:47831/#session=x", "http://127.0.0.1/#session=x", "http://user@127.0.0.1:1/", "::"} {
		if _, err := approvalPopupURL(bad); err == nil {
			t.Fatalf("accepted %q", bad)
		}
	}
}
