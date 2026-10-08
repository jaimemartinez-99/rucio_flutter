#include "../../third_party/audioplayers_windows/windows/event_stream_handler.h"

#include <atomic>
#include <future>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

using flutter::EncodableValue;

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

struct Events {
  DWORD thread = GetCurrentThreadId();
  bool wrongThread = false;
  int destroyed = 0;
  std::vector<int> values;
  std::vector<std::string> errors;
  std::vector<std::string> details;
};

class RecordingSink : public flutter::EventSink<EncodableValue> {
 public:
  explicit RecordingSink(Events& events) : events_(events) {}
  ~RecordingSink() override { events_.destroyed++; }

 protected:
  void SuccessInternal(const EncodableValue* value) override {
    events_.wrongThread |= GetCurrentThreadId() != events_.thread;
    events_.values.push_back(std::get<int>(*value));
  }

  void ErrorInternal(const std::string& code,
                     const std::string& message,
                     const EncodableValue* details) override {
    events_.wrongThread |= GetCurrentThreadId() != events_.thread;
    events_.errors.push_back(code + ":" + message);
    events_.details.push_back(details ? std::get<std::string>(*details) : "");
  }

  void EndOfStreamInternal() override {}

 private:
  Events& events_;
};

void Pump() {
  MSG message;
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
}

template <typename Condition>
void PumpUntil(Condition condition) {
  const auto deadline = GetTickCount64() + 5000;
  while (!condition()) {
    Pump();
    Check(GetTickCount64() < deadline, "Timed out waiting for platform events");
    std::this_thread::yield();
  }
}

void Listen(EventStreamHandler<>& handler, Events& events) {
  Check(!handler.OnListen(nullptr, std::make_unique<RecordingSink>(events)),
        "Could not start event listener");
}

void TestThreadAndErrorCopies() {
  Events events;
  EventStreamHandler<> handler;
  Listen(handler, events);
  std::thread worker([&] {
    for (int index = 0; index < 500; index++) {
      handler.Success(std::make_unique<EncodableValue>(index));
    }
    EncodableValue details("original details");
    handler.Error("code", "message", &details);
    details = EncodableValue("changed after queueing");
    handler.Error("code", "without details");
  });
  worker.join();
  Check(events.values.empty() && events.errors.empty(),
        "Audio worker delivered events before the platform loop ran");
  PumpUntil([&] { return events.values.size() == 500 && events.errors.size() == 2; });
  Check(!events.wrongThread, "Events were delivered on a non-platform thread");
  for (int index = 0; index < 500; index++) {
    Check(events.values[index] == index, "Event order changed");
  }
  Check(events.errors[0] == "code:message", "Error metadata changed");
  Check(events.details[0] == "original details", "Error details were not copied");
  Check(events.details[1].empty(), "Unexpected details on error");
}

void TestCancelAndResubscribe() {
  Events oldEvents;
  Events newEvents;
  EventStreamHandler<> handler;
  Listen(handler, oldEvents);
  std::thread worker([&] { handler.Success(std::make_unique<EncodableValue>(1)); });
  worker.join();
  Check(!handler.OnCancel(nullptr), "Could not cancel listener");
  Check(oldEvents.destroyed == 1, "Cancellation leaked the event sink");
  handler.Success(std::make_unique<EncodableValue>(2));
  Listen(handler, newEvents);
  handler.Success(std::make_unique<EncodableValue>(3));
  PumpUntil([&] { return newEvents.values.size() == 1; });
  Check(oldEvents.values.empty(), "Cancelled listener received a pending event");
  Check(newEvents.values[0] == 3, "Old event leaked into a new subscription");
  Check(!newEvents.wrongThread, "Resubscribed event used the wrong thread");
}

void TestDestructionWithPendingEvents() {
  Events events;
  auto handler = std::make_unique<EventStreamHandler<>>();
  Listen(*handler, events);
  std::thread worker([&] {
    for (int index = 0; index < 100; index++) {
      handler->Success(std::make_unique<EncodableValue>(index));
    }
  });
  worker.join();
  handler.reset();
  Pump();
  Check(events.destroyed == 1, "Destruction leaked the event sink");
  Check(events.values.empty(), "Destroyed handler delivered pending events");
}

void TestConcurrentProducers() {
  Events events;
  EventStreamHandler<> handler;
  Listen(handler, events);
  std::vector<std::thread> workers;
  for (int worker = 0; worker < 4; worker++) {
    workers.emplace_back([&, worker] {
      for (int index = 0; index < 1000; index++) {
        handler.Success(std::make_unique<EncodableValue>(worker * 1000 + index));
      }
    });
  }
  PumpUntil([&] { return events.values.size() == 4000; });
  for (auto& worker : workers) worker.join();
  Check(!events.wrongThread, "Concurrent producer delivered on its own thread");
  int last[] = {-1, -1, -1, -1};
  for (const int value : events.values) {
    const int worker = value / 1000;
    Check(value % 1000 == ++last[worker], "Concurrent events lost their order");
  }
}

void TestCancelWhileProducerRuns() {
  Events events;
  EventStreamHandler<> handler;
  Listen(handler, events);
  std::promise<void> firstQueued;
  std::promise<void> cancelled;
  auto ready = firstQueued.get_future();
  auto release = cancelled.get_future();
  std::thread worker([&] {
    handler.Success(std::make_unique<EncodableValue>(1));
    firstQueued.set_value();
    release.wait();
    for (int index = 0; index < 100; index++) {
      handler.Success(std::make_unique<EncodableValue>(index));
    }
  });
  ready.wait();
  handler.OnCancel(nullptr);
  cancelled.set_value();
  worker.join();
  Pump();
  Check(events.destroyed == 1 && events.values.empty(),
        "Worker delivered after cancellation");
}

int main() {
  try {
    TestThreadAndErrorCopies();
    TestCancelAndResubscribe();
    TestDestructionWithPendingEvents();
    TestConcurrentProducers();
    TestCancelWhileProducerRuns();
    std::cout << "Windows audio events: 5 tests passed" << std::endl;
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
