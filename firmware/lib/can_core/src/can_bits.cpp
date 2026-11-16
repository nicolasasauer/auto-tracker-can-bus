#include "can_bits.h"

namespace can_core {

uint16_t canCrc15(const uint8_t* bits, size_t bit_count) {
  uint16_t crc = 0;
  for (size_t i = 0; i < bit_count; ++i) {
    const bool next = (bits[i] != 0) ^ ((crc >> 14) & 1);
    crc = static_cast<uint16_t>((crc << 1) & 0x7FFF);
    if (next) crc ^= 0x4599;
  }
  return crc;
}

namespace {

// Höchstlänge vom Startbit bis zum Ende der CRC ohne Füllbits:
// 29-Bit-ID mit 8 Byte: 54 + 64 = 118.
constexpr size_t kMaxBits = 128;

struct BitWriter {
  uint8_t bits[kMaxBits];
  size_t n = 0;
  void put(uint32_t value, int count) {
    for (int i = count - 1; i >= 0; --i) bits[n++] = (value >> i) & 1;
  }
};

}  // namespace

uint32_t frameBitsOnBus(const CanFrame& frame) {
  const bool extended = (frame.id & kExtendedFlag) != 0;
  const bool rtr = (frame.id & kRtrFlag) != 0;
  const uint32_t id = frame.id & kIdMask;
  const uint8_t dlc = frame.dlc > 8 ? 8 : frame.dlc;
  const uint8_t data_bytes = rtr ? 0 : dlc;

  BitWriter w;
  w.put(0, 1);  // Startbit
  if (extended) {
    w.put(id >> 18, 11);  // Basis-ID
    w.put(1, 1);          // SRR
    w.put(1, 1);          // IDE
    w.put(id, 18);        // Erweiterung
    w.put(rtr ? 1 : 0, 1);
    w.put(0, 2);  // r1, r0
  } else {
    w.put(id, 11);
    w.put(rtr ? 1 : 0, 1);
    w.put(0, 1);  // IDE
    w.put(0, 1);  // r0
  }
  w.put(frame.dlc & 0x0F, 4);
  for (uint8_t i = 0; i < data_bytes; ++i) w.put(frame.data[i], 8);
  w.put(canCrc15(w.bits, w.n), 15);

  // Füllbits vom Startbit bis zum Ende der CRC.
  uint32_t stuff = 0;
  uint8_t last = w.bits[0];
  int run = 1;
  for (size_t i = 1; i < w.n; ++i) {
    if (w.bits[i] == last) {
      if (++run == 5 && i + 1 < w.n) {
        // Ein Füllbit (entgegengesetzt) beginnt die nächste Folge.
        ++stuff;
        last = !last;
        run = 1;
      }
    } else {
      last = w.bits[i];
      run = 1;
    }
  }
  // Ein Füllbit wird auch nach dem letzten CRC-Bit eingefügt, wenn dort
  // fünf gleiche enden.
  if (run == 5) ++stuff;

  // CRC-Begrenzer, ACK-Feld (2), Rahmenende (7), Pause (3).
  return static_cast<uint32_t>(w.n) + stuff + 1 + 2 + 7 + 3;
}

}  // namespace can_core
