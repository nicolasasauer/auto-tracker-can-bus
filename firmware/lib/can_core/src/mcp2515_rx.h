// Rohinhalt eines Empfangspuffers des MCP2515 in eine CanFrame umsetzen.
//
// Gebraucht für Botschaften mit DLC 9–15: Die MCP2515-Bibliothek lehnt sie
// ab und gibt den Puffer nicht frei. Der Treiber liest den Puffer dann selbst
// aus (src/mcp2515_receiver.cpp) und wertet ihn hier aus.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "can_frame.h"

namespace can_core {

// SIDH, SIDL, EID8, EID0, DLC, D0–D7 (Register RXBnSIDH bis RXBnD7).
constexpr size_t kMcp2515RxBufferSize = 13;

// raw: kMcp2515RxBufferSize Bytes. DLC 9–15 ergibt 8 Datenbytes, wie im
// klassischen CAN festgelegt.
void decodeMcp2515RxBuffer(const uint8_t* raw, CanFrame& out);

}  // namespace can_core
