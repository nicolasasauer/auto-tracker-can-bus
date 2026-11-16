// Software-Filter für CAN-IDs (BLE-Befehl 0x11).
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace can_core {

class FrameFilter {
 public:
  static constexpr size_t kMaxEntries = 8;

  // Ohne Einträge passt jede Botschaft.
  void clear() { count_ = 0; }

  // false, wenn schon kMaxEntries Einträge da sind.
  bool add(uint32_t id, uint32_t mask);

  // id im Format des Protokolls (mit Erweitert-Bit); das RTR-Bit zählt nicht.
  bool accepts(uint32_t id) const;

  size_t size() const { return count_; }

 private:
  struct Entry {
    uint32_t id;
    uint32_t mask;
  };
  Entry entries_[kMaxEntries] = {};
  size_t count_ = 0;
};

}  // namespace can_core
