// CAN-Empfang über einen MCP2515 (Seeed XIAO CAN Bus Expansion Board).
#pragma once

#include <mcp2515.h>

#include "can_receiver.h"

class Mcp2515Receiver : public CanReceiver {
 public:
  explicit Mcp2515Receiver(uint8_t cs_pin);

  bool begin(uint32_t bitrate) override;
  bool read(can_core::CanFrame& out) override;
  Events takeEvents() override;
  Health health() override;

 private:
  // Botschaft mit DLC 9–15 selbst aus dem Empfangspuffer lesen.
  bool readOversized(can_core::CanFrame& out);

  MCP2515 mcp_;
  uint8_t cs_pin_;
};
