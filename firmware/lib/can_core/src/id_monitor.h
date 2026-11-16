// ID-Übersicht: fasst alle Botschaften je CAN-ID zusammen, damit über BLE
// nicht jede einzelne Botschaft geschickt werden muss
// (docs/CAN-BLE-PROTOKOLL.md, 2.1).
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "can_frame.h"

namespace can_core {

// Ein Eintrag der Übersicht, so wie er über BLE geht.
struct IdReport {
  uint32_t id = 0;
  uint8_t dlc = 0;
  uint8_t data[8] = {};
  uint8_t changed[8] = {};  // seit der letzten Übersicht geänderte Bits
  uint16_t frames = 0;      // Botschaften seit der letzten Übersicht
  uint16_t period_ms = 0;   // mittlerer Abstand, 0 = unbekannt
};

class IdMonitor {
 public:
  static constexpr size_t kCapacity = 256;

  // Eine empfangene Botschaft verbuchen. now_ms: Zeit seit Start.
  void onFrame(const CanFrame& frame, uint32_t now_ms);

  // Bis zu max Einträge mit neuen Botschaften in out schreiben und deren
  // Zähler zurücksetzen. Reihum: Wer beim letzten Mal nicht mehr
  // hineinpasste, kommt zuerst dran. Rückgabe: Anzahl Einträge.
  size_t collect(IdReport* out, size_t max);

  // Gibt es Einträge, die noch nicht gemeldet wurden?
  bool hasPending() const;

  void reset();

  size_t idCount() const { return count_; }
  uint32_t framesTotal() const { return frames_total_; }
  // Botschaften neuer IDs, die wegen voller Tabelle nicht erfasst wurden.
  uint32_t framesUntracked() const { return frames_untracked_; }

 private:
  struct Slot {
    uint32_t id;
    uint8_t dlc;
    uint8_t data[8];
    uint8_t changed[8];
    uint32_t pending;      // Botschaften seit letzter Meldung
    uint32_t last_ms;
    uint32_t period_ms;    // gleitender Mittelwert
  };

  Slot* find(uint32_t id);

  Slot slots_[kCapacity] = {};
  size_t count_ = 0;
  size_t cursor_ = 0;
  uint32_t frames_total_ = 0;
  uint32_t frames_untracked_ = 0;
};

}  // namespace can_core
