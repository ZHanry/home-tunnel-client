// HOMEDESK: 主窗口自己的托盘图标；不启动服务或独立进程，不影响远控会话生命周期。
// 通知区域与重建消息约定：https://learn.microsoft.com/windows/win32/shell/taskbar
#pragma once
#include <windows.h>
#include <shellapi.h>
#include <strsafe.h>
#include "homedesk_brand.h"
#include "resource.h"

class HomeDeskWindowTray {
 public:
  void Enable(HWND window) {
    window_ = window;
    enabled_ = true;
    AddIcon();
  }

  bool Minimize() {
    if (!enabled_ || !window_ || !AddIcon()) return false;
    ShowWindow(window_, SW_HIDE);
    return true;
  }

  void Remove() {
    if (visible_) {
      auto data = Data();
      Shell_NotifyIconW(NIM_DELETE, &data);
      visible_ = false;
    }
  }

  bool Handle(UINT message, WPARAM wparam, LPARAM lparam) {
    if (!enabled_) return false;
    // Taskbar/system minimization must retain the taskbar entry. Only the
    // explicit homedeskMinimizeToTray request may hide the main window.
    if (message == WM_SHOWWINDOW && wparam) AddIcon();
    if (message == taskbar_created_) {
      visible_ = false;
      if (!AddIcon()) Restore();
      return false;
    }
    if (message != kMessage) return false;
    const auto event = LOWORD(lparam);
    if (event == WM_LBUTTONUP || event == NIN_SELECT || event == NIN_KEYSELECT) {
      Restore();
    } else if (event == WM_CONTEXTMENU || event == WM_RBUTTONUP) {
      POINT position;
      if (GetCursorPos(&position)) {
        auto menu = CreatePopupMenu();
        if (menu) {
          AppendMenuW(menu, MF_STRING, 1, L"\u6253\u5f00 " HOMEDESK_APP_NAME_WIDE);
          SetForegroundWindow(window_);
          const auto selected = TrackPopupMenu(menu,
              TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
              position.x, position.y, 0, window_, nullptr);
          DestroyMenu(menu);
          if (selected == 1) Restore();
          PostMessageW(window_, WM_NULL, 0, 0);
        }
      }
    }
    return true;
  }

 private:
  static constexpr UINT kMessage = WM_APP + 91;
  HWND window_ = nullptr;
  bool enabled_ = false;
  bool visible_ = false;
  const UINT taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");

  NOTIFYICONDATAW Data() const {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = window_;
    data.uID = 1;
    return data;
  }

  bool AddIcon() {
    if (visible_) return true;
    auto data = Data();
    data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
    data.uCallbackMessage = kMessage;
    data.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
    StringCchCopyW(data.szTip, ARRAYSIZE(data.szTip), HOMEDESK_APP_NAME_WIDE);
    if (!data.hIcon || !Shell_NotifyIconW(NIM_ADD, &data)) return false;
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
    visible_ = true;
    return true;
  }

  void Restore() {
    ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(window_);
  }
};
