// Ringpuffer für empfangene Botschaften zwischen der Lese-Aufgabe
// (Interrupt des CAN-Controllers, hohe Priorität) und der Hauptschleife.
//
// Genau ein Schreiber und genau ein Leser (single producer, single
// consumer), ohne Sperren: Der Schreiber ändert nur head_, der Leser nur
// tail_. So muss die Lese-Aufgabe nie auf die Hauptschleife warten.
#pragma once

#include <atomic>
#include <stddef.h>
#include <stdint.h>

#include "can_frame.h"

namespace can_core {

struct TimedFrame {
  CanFrame frame;
  uint32_t time_ms = 0;  // Empfangszeit (nicht Verarbeitungszeit)
};

template <size_t N>
class FrameRing {
  static_assert(N >= 2 && (N & (N - 1)) == 0, "N muss eine Zweierpotenz sein");

 public:
  // Schreiber. false, wenn voll; die Botschaft wird dann verworfen und
  // gezählt.
  bool push(const TimedFrame& item) {
    const uint32_t head = head_.load(std::memory_order_relaxed);
    const uint32_t tail = tail_.load(std::memory_order_acquire);
    if (head - tail >= N) {
      overflows_.fetch_add(1, std::memory_order_relaxed);
      return false;
    }
    items_[head & (N - 1)] = item;
    head_.store(head + 1, std::memory_order_release);
    // Höchststand merken (nur der Schreiber ändert ihn).
    const uint32_t fill = head + 1 - tail;
    if (fill > max_fill_.load(std::memory_order_relaxed)) {
      max_fill_.store(fill, std::memory_order_relaxed);
    }
    return true;
  }

  // Leser. false, wenn leer.
  bool pop(TimedFrame& out) {
    const uint32_t tail = tail_.load(std::memory_order_relaxed);
    const uint32_t head = head_.load(std::memory_order_acquire);
    if (tail == head) return false;
    out = items_[tail & (N - 1)];
    tail_.store(tail + 1, std::memory_order_release);
    return true;
  }

  size_t size() const {
    return head_.load(std::memory_order_acquire) -
           tail_.load(std::memory_order_acquire);
  }

  // Bisher verworfene Botschaften (Puffer voll).
  uint32_t overflows() const {
    return overflows_.load(std::memory_order_relaxed);
  }

  // Höchster Füllstand seit dem Start: zeigt, wie viel Reserve bleibt,
  // lange bevor etwas verloren geht.
  uint32_t maxFill() const { return max_fill_.load(std::memory_order_relaxed); }

  static constexpr size_t capacity() { return N; }

 private:
  TimedFrame items_[N];
  // Laufende Zähler; die Differenz bleibt auch über den Überlauf von
  // uint32_t richtig.
  std::atomic<uint32_t> head_{0};
  std::atomic<uint32_t> tail_{0};
  std::atomic<uint32_t> overflows_{0};
  std::atomic<uint32_t> max_fill_{0};
};

}  // namespace can_core
