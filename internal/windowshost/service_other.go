//go:build !windows

package windowshost

import "context"

type Surface struct {
	Installed         bool   `json:"installed"`
	Running           bool   `json:"running"`
	UnattendedEnabled bool   `json:"unattended_enabled"`
	SecureDesktop     string `json:"secure_desktop"`
	Detail            string `json:"detail"`
}

func Inspect(context.Context) Surface {
	return Surface{SecureDesktop: "unsupported", Detail: "此平台没有 Windows 系统服务。便携模式仍可使用已登录桌面。 / This platform has no Windows system service. Signed-in desktop control still works."}
}

func RequestEnable(context.Context, string, string) error { return ErrNotInstalled }
func RequestDisable(context.Context) error                { return nil }
