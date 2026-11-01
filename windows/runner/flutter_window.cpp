#include "flutter_window.h"

#include <optional>
#include <iostream>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project, bool startup_probe)
    : project_(project), startup_probe_(startup_probe) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  if (startup_probe_) std::cerr << "Converto startup probe: engine initialized\n";
  RegisterPlugins(flutter_controller_->engine());
  if (startup_probe_) std::cerr << "Converto startup probe: plugins registered\n";
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (startup_probe_) {
      std::cerr << "Converto startup probe: first Flutter frame\n";
      // Close via the normal window lifecycle. Exiting the message loop here
      // tears down COM before plugins and the Flutter controller are disposed.
      PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    } else {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      const auto dpi = GetDpiForWindow(hwnd);
      RECT bounds = {0, 0, MulDiv(780, static_cast<int>(dpi), 96), MulDiv(600, static_cast<int>(dpi), 96)};
      AdjustWindowRectExForDpi(&bounds, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi);
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      limits->ptMinTrackSize.x = bounds.right - bounds.left;
      limits->ptMinTrackSize.y = bounds.bottom - bounds.top;
      return 0;
    }
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
