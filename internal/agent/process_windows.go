//go:build windows

package agent

import (
	"log"
	"os/exec"
	"sync"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// The console Agent is owned by the GUI/CLI supervisor and reports through its
// existing output handles. It must never allocate another console window.
func configureAgentProcess(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NO_WINDOW}
}

var supervisorJob = sync.OnceValue(func() windows.Handle {
	job, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		log.Printf("agent job object unavailable: %v", err)
		return 0
	}
	limits := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	limits.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	if _, err := windows.SetInformationJobObject(job, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&limits)), uint32(unsafe.Sizeof(limits))); err != nil {
		log.Printf("agent job object unavailable: %v", err)
		windows.CloseHandle(job)
		return 0
	}
	return job
})

// bindAgentToSupervisor ties the Agent's lifetime to this process: the job handle
// is never closed, so Windows ends the Agent when the supervisor exits or is
// killed. Without it a crashed GUI left a second tunnel running and the install
// directory locked.
func bindAgentToSupervisor(command *exec.Cmd) {
	job := supervisorJob()
	if job == 0 || command.Process == nil {
		return
	}
	process, err := windows.OpenProcess(windows.PROCESS_SET_QUOTA|windows.PROCESS_TERMINATE, false, uint32(command.Process.Pid))
	if err != nil {
		log.Printf("agent job assignment skipped: %v", err)
		return
	}
	defer windows.CloseHandle(process)
	if err := windows.AssignProcessToJobObject(job, process); err != nil {
		log.Printf("agent job assignment skipped: %v", err)
	}
}
