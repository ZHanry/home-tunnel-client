package gui

import (
	"errors"
	"net/http"

	"github.com/ZHanry/home-tunnel-client/internal/api"
)

// Do not forward remote messages which may reflect credentials. Preserve the
// machine-readable code so the UI can explain recovery and version conflicts.
func writeClientError(writer http.ResponseWriter, err error) {
	var remote *api.Error
	if !errors.As(err, &remote) {
		writeError(writer, http.StatusBadGateway, "无法连接服务器，请检查网络后重试")
		return
	}
	messages := map[string]string{
		"CLIENT_RAW_TUNNELS_DISABLED": "管理员尚未允许普通用户自行创建 TCP/UDP 连接",
		"TCP_TUNNELS_DISABLED":        "服务端未开放 TCP 端口，请联系管理员",
		"UDP_TUNNELS_DISABLED":        "服务端未开放 UDP 端口，请联系管理员",
		"PORT_POOL_EXHAUSTED":         "服务端可用公网端口已分配完，请联系管理员扩容",
		"VERSION_CONFLICT":            "连接已被修改，请读取最新版本后重试",
		"VALIDATION_ERROR":            "请检查连接类型、名称、本地地址和端口",
		"SUBDOMAIN_CONFLICT":          "访问子域名已被使用，请换一个名称",
		"OWNERSHIP_MISMATCH":          "连接或设备不存在",
		"DEVICE_REVOKED":              "设备已被撤销，请重新登录",
		"USER_DISABLED":               "账号已被停用，请联系管理员",
	}
	message := messages[remote.Code]
	if message == "" {
		message = "服务器未能完成操作，请刷新后重试"
	}
	writer.Header().Set("Content-Type", "application/json")
	writer.WriteHeader(remote.StatusCode)
	writeJSON(writer, map[string]string{"message": message, "error_code": remote.Code})
}
