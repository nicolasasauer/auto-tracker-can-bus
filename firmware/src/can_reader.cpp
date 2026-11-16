#include "can_reader.h"

#include <Arduino.h>

#include <atomic>

namespace can_reader {
namespace {

// Über dem BLE-Host (NimBLE, configMAX_PRIORITIES - 4) und der
// Arduino-Schleife (1), unter dem Bluetooth-Controller.
constexpr UBaseType_t kPriority = configMAX_PRIORITIES - 3;
// Notbetrieb ohne Interrupt (INT-Pin falsch oder am Board nicht geführt):
// spätestens nach einem Systemtakt (1 ms) nachsehen.
constexpr TickType_t kPollTicks = 1;
// Fehlerzustand nicht bei jeder Botschaft lesen (kostet SPI-Zeit).
constexpr uint32_t kErrorCheckMs = 100;

CanReceiver* g_receiver = nullptr;
TaskHandle_t g_task = nullptr;
Ring g_ring;
std::atomic<uint32_t> g_overflows{0};
std::atomic<uint32_t> g_error_events{0};
std::atomic<uint8_t> g_rx_errors{0};
std::atomic<uint8_t> g_error_flags{0};
std::atomic<uint32_t> g_interrupts{0};
std::atomic<uint8_t> g_error{static_cast<uint8_t>(can_core::protocol::BusState::kOk)};

void IRAM_ATTR onInterrupt() {
  g_interrupts.fetch_add(1, std::memory_order_relaxed);
  BaseType_t woken = pdFALSE;
  vTaskNotifyGiveFromISR(g_task, &woken);
  portYIELD_FROM_ISR(woken);
}

void run(void*) {
  uint32_t last_error_check = 0;
  for (;;) {
    ulTaskNotifyTake(pdTRUE, kPollTicks);
    // Leeren, bis nichts mehr da ist. Danach geht INT wieder auf High,
    // und die nächste Botschaft löst eine neue Flanke aus.
    can_core::TimedFrame item;
    while (g_receiver->read(item.frame)) {
      item.time_ms = millis();
      g_ring.push(item);  // voll: wird im Ring gezählt
    }
    const CanReceiver::Events events = g_receiver->takeEvents();
    if (events.overflows > 0) {
      g_overflows.fetch_add(events.overflows, std::memory_order_relaxed);
    }
    if (events.error_events > 0) {
      g_error_events.fetch_add(events.error_events, std::memory_order_relaxed);
    }

    const uint32_t now = millis();
    if (now - last_error_check >= kErrorCheckMs) {
      last_error_check = now;
      const CanReceiver::Health h = g_receiver->health();
      g_error.store(static_cast<uint8_t>(h.state), std::memory_order_relaxed);
      g_rx_errors.store(h.rx_error_counter, std::memory_order_relaxed);
      g_error_flags.store(h.error_flags, std::memory_order_relaxed);
    }
  }
}

}  // namespace

void start(CanReceiver* receiver, int int_pin) {
  g_receiver = receiver;
  xTaskCreate(run, "can_reader", 4096, nullptr, kPriority, &g_task);
  if (int_pin >= 0) {
    // INT des MCP2515 ist aktiv low (Open-Drain-fähig): Pull-up schadet nicht.
    pinMode(int_pin, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(int_pin), onInterrupt, FALLING);
  }
}

Ring& ring() { return g_ring; }

uint32_t controllerOverflows() {
  return g_overflows.load(std::memory_order_relaxed);
}

uint32_t errorEvents() {
  return g_error_events.load(std::memory_order_relaxed);
}

uint8_t rxErrorCounter() { return g_rx_errors.load(std::memory_order_relaxed); }

uint8_t errorFlags() { return g_error_flags.load(std::memory_order_relaxed); }

can_core::protocol::BusState errorState() {
  return static_cast<can_core::protocol::BusState>(
      g_error.load(std::memory_order_relaxed));
}

uint32_t interruptCount() {
  return g_interrupts.load(std::memory_order_relaxed);
}

}  // namespace can_reader
