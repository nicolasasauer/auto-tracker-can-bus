// Plattformunabhängige CAN-Botschaft. Wird von Treiber, ID-Übersicht und
// Protokoll gemeinsam genutzt und läuft auch auf dem PC (Unit-Tests).
#pragma once

#include <stdint.h>

namespace can_core {

// Bits im ID-Feld, wie im BLE-Protokoll (docs/CAN-BLE-PROTOKOLL.md, 2.1).
constexpr uint32_t kIdMask = 0x1FFFFFFFu;
constexpr uint32_t kExtendedFlag = 0x80000000u;
constexpr uint32_t kRtrFlag = 0x40000000u;

struct CanFrame {
  uint32_t id = 0;  // CAN-ID plus kExtendedFlag / kRtrFlag
  uint8_t dlc = 0;  // 0–8
  uint8_t data[8] = {0, 0, 0, 0, 0, 0, 0, 0};
};

}  // namespace can_core
