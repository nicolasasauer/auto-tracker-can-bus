#include "mcp2515_rx.h"

#include <string.h>

namespace can_core {

namespace {

constexpr uint8_t kSidlSrr = 0x10;   // RTR einer Standard-Botschaft
constexpr uint8_t kSidlIde = 0x08;   // erweiterte ID
constexpr uint8_t kDlcRtr = 0x40;    // RTR einer erweiterten Botschaft
constexpr uint8_t kDlcMask = 0x0F;

}  // namespace

void decodeMcp2515RxBuffer(const uint8_t* raw, CanFrame& out) {
  const uint8_t sidh = raw[0];
  const uint8_t sidl = raw[1];
  const uint8_t dlc_reg = raw[4];

  uint32_t id = (static_cast<uint32_t>(sidh) << 3) | (sidl >> 5);
  bool rtr;
  if (sidl & kSidlIde) {
    id = (id << 2) | (sidl & 0x03);
    id = (id << 8) | raw[2];
    id = (id << 8) | raw[3];
    id |= kExtendedFlag;
    rtr = (dlc_reg & kDlcRtr) != 0;
  } else {
    rtr = (sidl & kSidlSrr) != 0;
  }
  if (rtr) id |= kRtrFlag;

  // DLC 9–15: 8 Datenbytes.
  const uint8_t dlc_field = dlc_reg & kDlcMask;
  const uint8_t dlc = dlc_field > 8 ? 8 : dlc_field;
  out.id = id;
  out.dlc = dlc;
  memset(out.data, 0, sizeof(out.data));
  memcpy(out.data, raw + 5, dlc);
}

}  // namespace can_core
