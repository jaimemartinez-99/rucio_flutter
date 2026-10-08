#pragma once

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_stream_handler.h>

#include <deque>
#include <memory>
#include <mutex>
#include <string>

template <typename T = flutter::EncodableValue>
class EventStreamHandler : public flutter::StreamHandler<T> {
 public:
  EventStreamHandler() = default;

  ~EventStreamHandler() override { Close(); }

  void Success(std::unique_ptr<T> data) {
    Queue({std::move(data), {}, {}, nullptr});
  }

  void Error(const std::string& code,
             const std::string& message,
             const T* details = nullptr) {
    Queue({nullptr, code, message,
           details ? std::make_unique<T>(*details) : nullptr});
  }

 protected:
  std::unique_ptr<flutter::StreamHandlerError<T>> OnListenInternal(
      const T* arguments,
      std::unique_ptr<flutter::EventSink<T>>&& events) override {
    Close();
    HWND window = CreateWindowExW(0, L"STATIC", L"Audiorucio audio events", 0,
                                  0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                  GetModuleHandleW(nullptr), nullptr);
    if (!window) {
      return std::make_unique<flutter::StreamHandlerError<T>>(
          "WindowsAudioError", "Failed to create platform event dispatcher",
          nullptr);
    }
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    auto previousProc = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
        window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&WindowProc)));
    if (!previousProc) {
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      DestroyWindow(window);
      return std::make_unique<flutter::StreamHandlerError<T>>(
          "WindowsAudioError", "Failed to attach platform event dispatcher",
          nullptr);
    }
    std::lock_guard<std::mutex> lock(m_mutex);
    m_window = window;
    m_previousProc = previousProc;
    m_sink = std::move(events);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<T>> OnCancelInternal(
      const T* arguments) override {
    Close();
    return nullptr;
  }

 private:
  struct PendingEvent {
    std::unique_ptr<T> data;
    std::string errorCode;
    std::string errorMessage;
    std::unique_ptr<T> errorDetails;
  };

  static constexpr UINT kDispatch = WM_APP + 1;
  std::mutex m_mutex;
  HWND m_window = nullptr;
  WNDPROC m_previousProc = nullptr;
  bool m_scheduled = false;
  std::deque<PendingEvent> m_pending;
  std::shared_ptr<flutter::EventSink<T>> m_sink;

  void Queue(PendingEvent event) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_window || !m_sink) return;
    m_pending.push_back(std::move(event));
    if (!m_scheduled) {
      m_scheduled = PostMessageW(m_window, kDispatch, 0, 0) != FALSE;
      if (!m_scheduled) m_pending.clear();
    }
  }

  void Drain() {
    for (;;) {
      PendingEvent event;
      std::shared_ptr<flutter::EventSink<T>> sink;
      {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_pending.empty()) {
          m_scheduled = false;
          return;
        }
        event = std::move(m_pending.front());
        m_pending.pop_front();
        sink = m_sink;
      }
      if (!sink) continue;
      if (event.data) {
        sink->Success(*event.data);
      } else if (event.errorDetails) {
        sink->Error(event.errorCode, event.errorMessage, *event.errorDetails);
      } else {
        sink->Error(event.errorCode, event.errorMessage);
      }
    }
  }

  void Close() {
    HWND window;
    WNDPROC previousProc;
    {
      std::lock_guard<std::mutex> lock(m_mutex);
      window = m_window;
      previousProc = m_previousProc;
      m_window = nullptr;
      m_previousProc = nullptr;
      m_sink.reset();
      m_pending.clear();
      m_scheduled = false;
    }
    if (window) {
      SetWindowLongPtrW(window, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(previousProc));
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      DestroyWindow(window);
    }
  }

  static LRESULT CALLBACK WindowProc(HWND window,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam) {
    auto* handler = reinterpret_cast<EventStreamHandler*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == kDispatch && handler) {
      handler->Drain();
      return 0;
    }
    if (handler && handler->m_previousProc) {
      return CallWindowProcW(handler->m_previousProc, window, message, wparam,
                             lparam);
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }
};
