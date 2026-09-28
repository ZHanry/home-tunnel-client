package desktop

import (
	"errors"
	"net"
	"net/url"
)

// Popup sizes are in 96-DPI pixels; the native side scales them.
const (
	popupRequestWidth  = 360
	popupRequestHeight = 224
	popupSessionWidth  = 320
	popupSessionHeight = 60
	popupMargin        = 12
)

type popupRect struct{ Left, Top, Right, Bottom int }

// approvalPopupURL points the popup at /popup.html on the same loopback origin
// as the main window. The desktop session stays in the fragment, which the
// browser never sends to the server, exactly as the main window does it.
func approvalPopupURL(main string) (string, error) {
	address, err := url.Parse(main)
	if err != nil || address.Scheme != "http" || address.User != nil {
		return "", errors.New("invalid desktop address")
	}
	if ip := net.ParseIP(address.Hostname()); ip == nil || !ip.IsLoopback() || address.Port() == "" {
		return "", errors.New("desktop address is not loopback")
	}
	address.Path, address.RawPath, address.RawQuery = "/popup.html", "", ""
	return address.String(), nil
}

func popupSize(mode string) (int, int) {
	if mode == "session" {
		return popupSessionWidth, popupSessionHeight
	}
	return popupRequestWidth, popupRequestHeight
}

func scaleForDPI(value int, dpi uint32) int {
	if dpi == 0 {
		dpi = 96
	}
	return (value*int(dpi) + 48) / 96
}

// popupBounds places a width x height window in the bottom-right corner of the
// work area (the desktop minus the taskbar), keeping it fully on screen.
func popupBounds(work popupRect, width, height, margin int) popupRect {
	availableWidth, availableHeight := work.Right-work.Left, work.Bottom-work.Top
	if availableWidth <= 0 || availableHeight <= 0 {
		return popupRect{Left: work.Left, Top: work.Top, Right: work.Left + width, Bottom: work.Top + height}
	}
	if margin*2 >= availableWidth || margin*2 >= availableHeight {
		margin = 0
	}
	width = min(width, availableWidth-margin*2)
	height = min(height, availableHeight-margin*2)
	left := work.Right - margin - width
	top := work.Bottom - margin - height
	return popupRect{Left: left, Top: top, Right: left + width, Bottom: top + height}
}
