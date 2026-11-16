// Länge einer CAN-Botschaft auf dem Bus in Bit, für die Buslast.
//
// Gezählt wird genau wie auf der Leitung: Startbit, Kennung, Steuerbits,
// Daten, CRC, die Füllbits (nach fünf gleichen Bits fügt CAN ein
// entgegengesetztes ein), CRC- und ACK-Begrenzer, Rahmenende und die
// Pause bis zur nächsten Botschaft (3 Bit). Klassisches CAN, kein CAN FD.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "can_frame.h"

namespace can_core {

// CRC-15 nach CAN (Polynom 0x4599) über die ersten bit_count Bits von
// bits (ein Bit je Eintrag, 0 oder 1).
uint16_t canCrc15(const uint8_t* bits, size_t bit_count);

// Bitlänge der Botschaft auf dem Bus, einschließlich Füllbits und Pause.
// Ohne Füllbits: 47 + 8·n Bit (11-Bit-ID), 67 + 8·n Bit (29-Bit-ID).
uint32_t frameBitsOnBus(const CanFrame& frame);

}  // namespace can_core
