//go:build windows

package filedialog

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"unicode/utf16"
	"unicode/utf8"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	commonDialog   = windows.NewLazySystemDLL("comdlg32.dll")
	openFileDialog = commonDialog.NewProc("GetOpenFileNameW")
	saveFileDialog = commonDialog.NewProc("GetSaveFileNameW")
	dialogError    = commonDialog.NewProc("CommDlgExtendedError")
	dialogUser     = windows.NewLazySystemDLL("user32.dll")
	dialogParent   = dialogUser.NewProc("GetParent")
	dialogTimer    = dialogUser.NewProc("SetTimer")
	dialogSend     = dialogUser.NewProc("SendMessageW")
	dialogCOM      = windows.NewLazySystemDLL("ole32.dll")
	dialogCOMInit  = dialogCOM.NewProc("CoInitializeEx")
	dialogCOMClose = dialogCOM.NewProc("CoUninitialize")
	dialogHook     = windows.NewCallback(onDialogMessage)
	dialogs        = struct {
		sync.Mutex
		pending map[uintptr]context.Context
		windows map[uintptr]context.Context
	}{pending: map[uintptr]context.Context{}, windows: map[uintptr]context.Context{}}
)

// Layout follows OPENFILENAMEW, including the pointer-sized reserved fields.
type openFilename struct {
	Size                         uint32
	Owner, Instance              uintptr
	Filter, CustomFilter         *uint16
	MaxCustomFilter, FilterIndex uint32
	File                         *uint16
	MaxFile                      uint32
	FileTitle                    *uint16
	MaxFileTitle                 uint32
	InitialDir, Title            *uint16
	Flags                        uint32
	FileOffset, FileExtension    uint16
	DefaultExtension             *uint16
	CustomData, Hook             uintptr
	TemplateName                 *uint16
	Reserved                     uintptr
	ReservedSize, FlagsEx        uint32
}

func onDialogMessage(window, message, _, _ uintptr) uintptr {
	dialogs.Lock()
	switch message {
	case 0x0110: // WM_INITDIALOG runs on the locked caller's OS thread.
		if ctx := dialogs.pending[uintptr(windows.GetCurrentThreadId())]; ctx != nil {
			dialogs.windows[window] = ctx
			dialogTimer.Call(window, 1, 100, 0)
		}
	case 0x0002: // WM_DESTROY also removes the window's native timer.
		delete(dialogs.windows, window)
	case 0x0113: // WM_TIMER: close on this dialog's own message-loop thread.
		ctx := dialogs.windows[window]
		if ctx != nil && ctx.Err() != nil {
			dialogs.Unlock()
			parent, _, _ := dialogParent.Call(window)
			if parent != 0 {
				dialogSend.Call(parent, 0x0111, 2, 0)
			} // WM_COMMAND / IDCANCEL
			return 0
		}
	}
	dialogs.Unlock()
	return 0
}

func runDialog(ctx context.Context, suggested string, multiple bool) ([]string, error) {
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if strings.ContainsAny(suggested, "\\/\x00") || len(suggested) > 1020 || !utf8.ValidString(suggested) || len(utf16.Encode([]rune(suggested))) > 255 {
		return nil, errors.New("RD_FILE_NAME_INVALID")
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	initialized, _, _ := dialogCOMInit.Call(0, 2|4) // apartment thread; disable legacy OLE1 DDE
	if initialized != 0 && initialized != 1 {
		return nil, ErrUnavailable
	}
	defer dialogCOMClose.Call()
	buffer := make([]uint16, 65536)
	if suggested != "" {
		name, err := windows.UTF16FromString(suggested)
		if err != nil {
			return nil, errors.New("RD_FILE_NAME_INVALID")
		}
		copy(buffer, name)
	}
	title, _ := windows.UTF16PtrFromString("Home Tunnel · 选择远程会话文件 / Select session files")
	// Explorer, preserve working directory, existing parent, no Recent history,
	// and a cancellation hook. No path is read from a remote request.
	flags := uint32(0x00080000 | 0x00000008 | 0x00000800 | 0x02000000 | 0x00000020)
	procedure := saveFileDialog
	if multiple {
		flags |= 0x00000200 | 0x00001000
		procedure = openFileDialog
	}
	dialogs.Lock()
	id := uintptr(windows.GetCurrentThreadId())
	dialogs.pending[id] = ctx
	dialogs.Unlock()
	defer func() { dialogs.Lock(); delete(dialogs.pending, id); dialogs.Unlock() }()
	options := openFilename{File: &buffer[0], MaxFile: uint32(len(buffer)), Title: title, Flags: flags, CustomData: id, Hook: dialogHook}
	options.Size = uint32(unsafe.Sizeof(options))
	ok, _, _ := procedure.Call(uintptr(unsafe.Pointer(&options)))
	runtime.KeepAlive(buffer)
	runtime.KeepAlive(title)
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if ok == 0 {
		code, _, _ := dialogError.Call()
		if code == 0 {
			return nil, ErrCancelled
		}
		return nil, errors.New("RD_FILE_PICKER_FAILED")
	}
	var values []string
	for start, n := 0, 0; n < len(buffer); n++ {
		if buffer[n] != 0 {
			continue
		}
		if start == n {
			break
		}
		values = append(values, windows.UTF16ToString(buffer[start:n]))
		start = n + 1
	}
	if len(values) == 0 || len(values) > 65 {
		return nil, errors.New("RD_FILE_LIMIT")
	}
	if len(values) > 1 {
		parent := values[0]
		for n, name := range values[1:] {
			if filepath.Base(name) != name || name == "." || name == ".." {
				return nil, errors.New("RD_FILE_NAME_INVALID")
			}
			values[n] = filepath.Join(parent, name)
		}
		values = values[:len(values)-1]
	}
	for _, path := range values {
		if !filepath.IsAbs(path) || strings.HasPrefix(path, `\\`) {
			return nil, errors.New("RD_FILE_PATH_INVALID")
		}
		info, err := os.Lstat(path)
		if multiple {
			if err != nil || !info.Mode().IsRegular() {
				return nil, errors.New("RD_FILE_INVALID")
			}
		} else if !os.IsNotExist(err) {
			// Receiving a file must never replace an existing local entry.
			return nil, errors.New("RD_FILE_DESTINATION_EXISTS")
		}
	}
	return values, nil
}

func (Native) Sources(ctx context.Context) ([]string, error) { return runDialog(ctx, "", true) }
func (Native) Destination(ctx context.Context, name string) (string, error) {
	paths, err := runDialog(ctx, name, false)
	if err != nil {
		return "", err
	}
	if len(paths) != 1 {
		return "", errors.New("RD_FILE_PATH_INVALID")
	}
	return paths[0], nil
}
