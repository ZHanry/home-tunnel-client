//go:build windows

package windowshost

import (
	"context"
	"errors"
	"path/filepath"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

type Surface struct {
	Installed         bool   `json:"installed"`
	Running           bool   `json:"running"`
	UnattendedEnabled bool   `json:"unattended_enabled"`
	SecureDesktop     string `json:"secure_desktop"`
	Detail            string `json:"detail"`
}

const portableDetail = "未安装系统服务，当前为便携或每用户模式。锁屏、登录前和 UAC 安全桌面不可用。 / No system service is installed. Portable mode cannot control the lock screen, sign-in, or UAC desktop."

func queryInstalledStatus() (svc.Status, error) {
	manager, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return svc.Status{}, err
	}
	defer windows.CloseServiceHandle(manager)
	name, _ := windows.UTF16PtrFromString(ServiceName)
	handle, err := windows.OpenService(manager, name, windows.SERVICE_QUERY_STATUS)
	if err != nil {
		return svc.Status{}, err
	}
	defer windows.CloseServiceHandle(handle)
	return (&mgr.Service{Name: ServiceName, Handle: handle}).Query()
}
func queryInstalledConfiguration() (mgr.Config, error) {
	manager, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return mgr.Config{}, err
	}
	defer windows.CloseServiceHandle(manager)
	name, _ := windows.UTF16PtrFromString(ServiceName)
	handle, err := windows.OpenService(manager, name, windows.SERVICE_QUERY_CONFIG)
	if err != nil {
		return mgr.Config{}, err
	}
	defer windows.CloseServiceHandle(handle)
	return (&mgr.Service{Name: ServiceName, Handle: handle}).Config()
}

func Inspect(ctx context.Context) Surface {
	status, err := queryInstalledStatus()
	if err != nil {
		return Surface{SecureDesktop: "unavailable", Detail: portableDetail}
	}
	surface := Surface{Installed: true, Running: status.State == svc.Running, SecureDesktop: "unavailable"}
	if !surface.Running {
		surface.Detail = "系统服务已安装但没有运行。 / The installed service is not running."
		return surface
	}
	probe, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	response, err := Control(probe, ControlRequest{Operation: "status"})
	if err == nil {
		surface = response.Surface
		if surface.Detail == "" {
			if surface.UnattendedEnabled {
				surface.Detail = "已启用绑定控制端的无人值守访问。 / Unattended access is enabled for the bound controller."
			} else {
				surface.Detail = "系统服务可用，无人值守尚未开启。 / Service available; unattended access is off."
			}
		}
	} else {
		surface.Detail = "无法读取系统服务的端点状态。 / Cannot read the service endpoint state."
	}
	return surface
}

func RequestEnable(ctx context.Context, controllerID, thumbprint string) error {
	if !ValidEndpointID(controllerID) || !ValidThumbprint(thumbprint) {
		return ErrIdentity
	}
	_, err := Control(ctx, ControlRequest{Operation: "enable_unattended", ControllerID: controllerID, Thumbprint: thumbprint})
	return err
}
func RequestDisable(ctx context.Context) error {
	_, err := Control(ctx, ControlRequest{Operation: "disable_unattended"})
	return err
}

func protectedServicePath(programFiles string) (string, error) {
	path := filepath.Join(programFiles, "Home Tunnel", ServiceBinary)
	plan, err := PlanInstall(Layout{Scope: "per-machine", ServiceRequested: true, ProgramFiles: programFiles, ExePath: path})
	if err != nil || !plan.RegisterService {
		return "", ErrRejected
	}
	return path, nil
}

func Install(programFiles string) error {
	path, err := protectedServicePath(programFiles)
	if err != nil {
		return err
	}
	if path != filepath.Join(CurrentProgramFiles(), "Home Tunnel", ServiceBinary) {
		return ErrRejected
	}
	if err = protectInstalledPackage(); err != nil {
		return err
	}
	manager, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	config := mgr.Config{DisplayName: "Home Tunnel Host", Description: "Home Tunnel session host. Unattended access stays off until an administrator binds a controller.", StartType: mgr.StartAutomatic, ServiceType: windows.SERVICE_WIN32_OWN_PROCESS, BinaryPathName: windows.EscapeArg(path), ServiceStartName: "LocalSystem"}
	if existing, openErr := manager.OpenService(ServiceName); openErr == nil {
		defer existing.Close()
		previous, configErr := existing.Config()
		if configErr != nil || (previous.BinaryPathName != path && previous.BinaryPathName != windows.EscapeArg(path)) ||
			(previous.ServiceStartName != "" && previous.ServiceStartName != "LocalSystem") {
			return ErrRejected
		}
		return existing.UpdateConfig(config)
	}
	service, err := manager.CreateService(ServiceName, path, config)
	if err != nil {
		return err
	}
	defer service.Close()
	return nil
}

func control(name string, run func(*mgr.Service) error) error {
	manager, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	service, err := manager.OpenService(name)
	if err != nil {
		if name == ServiceName {
			return ErrNotInstalled
		}
		return err
	}
	defer service.Close()
	return run(service)
}

func Start() error {
	return control(ServiceName, func(service *mgr.Service) error { return service.Start() })
}
func Stop() error {
	return control(ServiceName, func(service *mgr.Service) error {
		state, err := service.Query()
		if err != nil {
			return err
		}
		if state.State == svc.Stopped {
			return nil
		}
		if state.State != svc.StopPending {
			if _, err = service.Control(svc.Stop); err != nil {
				return err
			}
		}
		until := time.Now().Add(20 * time.Second)
		for time.Now().Before(until) {
			state, err = service.Query()
			if err != nil {
				return err
			}
			if state.State == svc.Stopped {
				return nil
			}
			time.Sleep(100 * time.Millisecond)
		}
		return errors.New("service stop timed out")
	})
}
func Restart() error {
	if err := Stop(); err != nil && !errors.Is(err, ErrNotInstalled) {
		return err
	}
	return Start()
}
func Uninstall() error {
	if err := Stop(); err != nil && !errors.Is(err, ErrNotInstalled) {
		return err
	}
	return control(ServiceName, func(service *mgr.Service) error {
		return service.Delete()
	})
}

func CurrentProgramFiles() string {
	path, _ := windows.KnownFolderPath(windows.FOLDERID_ProgramFilesX64, 0)
	return path
}
