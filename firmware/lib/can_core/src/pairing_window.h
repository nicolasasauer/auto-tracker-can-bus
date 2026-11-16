// Kopplungsfenster: Neue Handys dürfen sich nur koppeln, solange es offen ist
// (docs/CAN-BLE-PROTOKOLL.md, Kapitel 4). Geöffnet wird es über die serielle
// Konsole am USB-Anschluss.
#pragma once

#include <stdint.h>

namespace can_core {

class PairingWindow {
 public:
  static constexpr uint32_t kDefaultDurationMs = 120000;
  static constexpr uint8_t kMaxBonds = 3;

  // random: Zufallszahl (auf dem ESP32 esp_random()).
  // Rückgabe: der 6-stellige Code, der auf der Konsole angezeigt wird.
  uint32_t open(uint32_t now_ms, uint32_t random,
                uint32_t duration_ms = kDefaultDurationMs);
  void close() { open_ = false; }
  bool isOpen(uint32_t now_ms) const;

  // Antwort auf eine Kopplungsanfrage.
  struct Decision {
    bool allow;
    uint32_t passkey;  // bei allow == false: geheimer Zufallscode
  };
  // bonds: Anzahl schon gespeicherter Geräte.
  Decision onPairingRequest(uint32_t now_ms, uint8_t bonds,
                            uint32_t random) const;

 private:
  bool open_ = false;
  uint32_t opened_ms_ = 0;
  uint32_t duration_ms_ = 0;
  uint32_t passkey_ = 0;
};

}  // namespace can_core
