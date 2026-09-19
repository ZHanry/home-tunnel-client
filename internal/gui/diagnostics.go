package gui

import (
	"context"
	"net/http"
	"path/filepath"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/diagnostics"
)

func (server *Server) doctor(writer http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet && request.Method != http.MethodPost {
		writer.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	ctx, cancel := context.WithTimeout(request.Context(), 45*time.Second)
	defer cancel()
	report := diagnostics.Run(ctx, diagnostics.Options{StatePath: server.options.StatePath, AgentPath: server.options.AgentPath, ExpectedAgentHash: server.options.ExpectedAgentHash})
	if request.Method == http.MethodPost {
		destination := filepath.Join(updateDownloadDir(), "HomeTunnel-support-"+time.Now().UTC().Format("20060102T150405.000000000Z")+".zip")
		if err := diagnostics.WriteBundle(report, destination); err != nil {
			writeError(writer, 500, "无法保存诊断包 / Cannot save support bundle")
			return
		}
		writeJSON(writer, map[string]any{"path": destination, "report": report})
		return
	}
	writeJSON(writer, report)
}
