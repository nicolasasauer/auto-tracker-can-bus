#include "pairing_window.h"

namespace can_core {

uint32_t PairingWindow::open(uint32_t now_ms, uint32_t random,
                             uint32_t duration_ms) {
  open_ = true;
  opened_ms_ = now_ms;
  duration_ms_ = duration_ms;
  passkey_ = random % 1000000u;
  return passkey_;
}

bool PairingWindow::isOpen(uint32_t now_ms) const {
  // Subtraktion statt Vergleich der Endzeit: übersteht den Überlauf von
  // millis() nach ca. 49 Tagen.
  return open_ && (now_ms - opened_ms_) < duration_ms_;
}

PairingWindow::Decision PairingWindow::onPairingRequest(
    uint32_t now_ms, uint8_t bonds, uint32_t random) const {
  if (isOpen(now_ms) && bonds < kMaxBonds) {
    return {true, passkey_};
  }
  // Ein Code, den nie jemand zu sehen bekommt: Die Kopplung scheitert.
  return {false, random % 1000000u};
}

}  // namespace can_core
