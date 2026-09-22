package main

import (
	"context"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/desktop"
	"github.com/ZHanry/home-tunnel-client/internal/gui"
	"github.com/ZHanry/home-tunnel-client/internal/model"
	"github.com/ZHanry/home-tunnel-client/internal/paths"
	"github.com/ZHanry/home-tunnel-client/internal/remoteengine"
	"github.com/ZHanry/home-tunnel-client/internal/remotehost"
	statepkg "github.com/ZHanry/home-tunnel-client/internal/state"
)

var (
	version                  = model.Version
	agentVersion             = model.Version
	expectedAgentSHA256      = "development"
	expectedRemoteHostSHA256 = ""
)

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.LUTC)
	if gui.RequestShow() {
		return
	}
	statePath := paths.DesktopStatePath()
	agentPath := paths.DesktopAgentPath()
	if err := os.MkdirAll(filepath.Dir(statePath), 0o700); err != nil {
		log.Fatal(err)
	}
	// GUI builds do not have console handles. Keep diagnostics in a private file
	// instead of asking Windows to allocate a terminal for the managed child.
	log.SetOutput(io.Discard)
	logPath := filepath.Join(filepath.Dir(statePath), "desktop.log")
	if info, err := os.Stat(logPath); err == nil && info.Size() > 4*1024*1024 {
		_ = os.Remove(logPath + ".previous")
		_ = os.Rename(logPath, logPath+".previous")
	}
	if logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600); err == nil {
		log.SetOutput(logFile)
		defer logFile.Close()
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	var remoteEngine remotehost.HostEngine
	if runtime.GOOS == "windows" && expectedRemoteHostSHA256 != "" {
		if executable, err := os.Executable(); err == nil {
			worker, err := remoteengine.New(ctx, remoteengine.Options{
				ExecutablePath: filepath.Join(filepath.Dir(executable), "home_tunnel_remote_host.exe"),
				ExpectedSHA256: expectedRemoteHostSHA256,
			})
			if err != nil {
				log.Print("verified remote desktop worker unavailable: ", err)
			} else {
				remoteEngine = worker
				defer worker.Shutdown()
			}
		}
	}
	server := gui.New(gui.Options{
		Version:           version,
		StatePath:         statePath,
		AgentPath:         agentPath,
		ExpectedAgentHash: expectedAgentSHA256,
		AgentVersion:      agentVersion,
		RemoteEngine:      remoteEngine,
	})
	listener, err := gui.ListenLoopback()
	if err != nil {
		if gui.RequestShow() {
			return
		}
		log.Fatal(err)
	}
	cleanupSession, err := server.PublishLocalSession()
	if err != nil {
		listener.Close()
		log.Fatal("cannot prepare the private desktop session")
	}
	defer cleanupSession()
	server.Attach(ctx)
	server.SetQuit(stop)
	host := &desktop.Host{}
	server.SetShow(host.Show)
	if state, err := (statepkg.Store{Path: statePath}).Load(); err == nil && state.Enrolled() {
		server.StartAgent(ctx)
	}
	httpServer := &http.Server{
		Handler: server.Handler(), ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 * 1024,
	}
	go func() {
		if err := httpServer.Serve(listener); err != nil && err != http.ErrServerClosed {
			log.Print(err)
		}
	}()
	url := "http://" + gui.UIAddress + "/#session=" + server.LocalToken()
	log.Printf("Home Tunnel GUI %s window http://%s/", version, gui.UIAddress)
	go func() {
		<-ctx.Done()
		desktop.Quit()
	}()
	runErr := desktop.Run(url, host, stop)
	server.StopAgent()
	cleanupSession()
	shutdown, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdown)
	if runErr != nil {
		log.Fatal(runErr)
	}
}
