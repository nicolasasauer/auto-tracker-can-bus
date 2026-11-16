#include "mcp2515_receiver.h"

#include <Arduino.h>
#include <SPI.h>
#include <string.h>

#include "mcp2515_rx.h"

using can_core::CanFrame;
using can_core::protocol::BusState;

namespace {

// SPI-Befehle „READ RX BUFFER“ ab RXBnSIDH. Der MCP2515 löscht das
// Empfangs-Flag (RXnIF) selbst, sobald CS wieder auf High geht.
constexpr uint8_t kReadRx0 = 0x90;
constexpr uint8_t kReadRx1 = 0x94;
// Bits im Ergebnis von getStatus() (in der Bibliothek privat).
constexpr uint8_t kStatRx0If = 0x01;
constexpr uint8_t kStatRx1If = 0x02;
// Wie die Bibliothek (MCP2515::DEFAULT_SPI_CLOCK, dort privat).
constexpr uint32_t kSpiClock = 10000000;

}  // namespace

Mcp2515Receiver::Mcp2515Receiver(uint8_t cs_pin)
    : mcp_(cs_pin), cs_pin_(cs_pin) {}

bool Mcp2515Receiver::begin(uint32_t bitrate) {
  if (bitrate != 500000) return false;  // Prototyp: nur OBD-Bus
  if (mcp_.reset() != MCP2515::ERROR_OK) return false;
  if (mcp_.setBitrate(CAN_500KBPS, MCP_16MHZ) != MCP2515::ERROR_OK) {
    return false;
  }
  return mcp_.setListenOnlyMode() == MCP2515::ERROR_OK;
}

bool Mcp2515Receiver::read(CanFrame& out) {
  struct can_frame f;
  const MCP2515::ERROR rc = mcp_.readMessage(&f);
  // ERROR_FAIL kommt nur bei DLC 9–15 (im klassischen CAN erlaubt, 8
  // Datenbytes). Die Bibliothek gibt den Puffer dann nicht frei: Ohne
  // eigenes Auslesen bliebe er belegt und der Empfang stünde bis zum
  // Neustart.
  if (rc == MCP2515::ERROR_FAIL) return readOversized(out);
  if (rc != MCP2515::ERROR_OK) return false;
  if (f.can_id & CAN_EFF_FLAG) {
    out.id = (f.can_id & CAN_EFF_MASK) | can_core::kExtendedFlag;
  } else {
    out.id = f.can_id & CAN_SFF_MASK;
  }
  if (f.can_id & CAN_RTR_FLAG) out.id |= can_core::kRtrFlag;
  out.dlc = f.can_dlc > 8 ? 8 : f.can_dlc;
  memset(out.data, 0, sizeof(out.data));
  memcpy(out.data, f.data, out.dlc);
  return true;
}

bool Mcp2515Receiver::readOversized(CanFrame& out) {
  // Derselbe Puffer, den readMessage() eben abgelehnt hat (RXB0 zuerst).
  const uint8_t stat = mcp_.getStatus();
  uint8_t instruction;
  if (stat & kStatRx0If) {
    instruction = kReadRx0;
  } else if (stat & kStatRx1If) {
    instruction = kReadRx1;
  } else {
    return false;
  }
  uint8_t raw[can_core::kMcp2515RxBufferSize];
  SPI.beginTransaction(SPISettings(kSpiClock, MSBFIRST, SPI_MODE0));
  digitalWrite(cs_pin_, LOW);
  SPI.transfer(instruction);
  for (uint8_t& b : raw) b = SPI.transfer(0x00);
  digitalWrite(cs_pin_, HIGH);  // gibt den Puffer frei (löscht RXnIF)
  SPI.endTransaction();
  can_core::decodeMcp2515RxBuffer(raw, out);
  return true;
}

CanReceiver::Events Mcp2515Receiver::takeEvents() {
  Events e;
  const uint8_t flags = mcp_.getErrorFlags();
  if (flags & MCP2515::EFLG_RX0OVR) ++e.overflows;
  if (flags & MCP2515::EFLG_RX1OVR) ++e.overflows;
  if (e.overflows > 0) mcp_.clearRXnOVRFlags();
  // Fehler-Interrupts quittieren. Sonst bleibt INT nach einem Überlauf
  // dauerhaft low, es gibt keine neue Flanke mehr, und der Leser fällt
  // unbemerkt in den langsamen Abfragebetrieb zurück. Die Empfangs-
  // Interrupts (RXnIF) bleiben unberührt, die löscht readMessage().
  // MERRF: Der Controller hat eine fehlerhafte Botschaft erkannt (falsche
  // Bitrate, Störungen, Verkabelung). Das Flag bleibt bis zum Quittieren
  // stehen; gezählt wird also höchstens ein Ereignis je Abholung.
  const uint8_t irq = mcp_.getInterrupts();
  if (irq & MCP2515::CANINTF_ERRIF) mcp_.clearERRIF();
  if (irq & MCP2515::CANINTF_MERRF) {
    ++e.error_events;
    mcp_.clearMERR();
  }
  return e;
}

CanReceiver::Health Mcp2515Receiver::health() {
  Health h;
  h.error_flags = mcp_.getErrorFlags();
  h.rx_error_counter = mcp_.errorCountRX();
  if (h.error_flags & MCP2515::EFLG_TXBO) {
    h.state = BusState::kBusOff;
  } else if (h.error_flags &
             (MCP2515::EFLG_RXEP | MCP2515::EFLG_TXEP | MCP2515::EFLG_EWARN)) {
    h.state = BusState::kError;
  }
  return h;
}
