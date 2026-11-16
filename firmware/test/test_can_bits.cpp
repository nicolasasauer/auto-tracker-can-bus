// Bitlänge von CAN-Botschaften. Die erwarteten Werte stammen aus einer
// unabhängigen Python-Umsetzung, die die Füllbits tatsächlich in den
// Bitstrom einfügt (statt sie nur zu zählen).
#include "can_bits.h"
#include "mini_test.h"

using namespace can_core;

static CanFrame f(uint32_t id, uint8_t dlc, std::initializer_list<uint8_t> data) {
  CanFrame fr;
  fr.id = id;
  fr.dlc = dlc;
  size_t i = 0;
  for (uint8_t b : data) fr.data[i++] = b;
  return fr;
}

TEST(crc15_pruefwert_der_norm) {
  // CRC-15/CAN über "123456789" ergibt 0x059E.
  uint8_t bits[72];
  const char* text = "123456789";
  for (int c = 0; c < 9; ++c) {
    for (int b = 0; b < 8; ++b) bits[c * 8 + b] = (text[c] >> (7 - b)) & 1;
  }
  EXPECT_EQ(canCrc15(bits, 72), 0x059E);
}

TEST(bitlaenge_beispiele) {
  EXPECT_EQ(frameBitsOnBus(f(0x000, 8, {0, 0, 0, 0, 0, 0, 0, 0})), 127u);
  EXPECT_EQ(frameBitsOnBus(f(0x7FF, 8, {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF})), 126u);
  EXPECT_EQ(frameBitsOnBus(f(0x000, 0, {})), 53u);
  EXPECT_EQ(frameBitsOnBus(f(0x7E8, 8, {0x03, 0x41, 0x0D, 0x32, 0x55, 0x55, 0x55, 0x55})), 116u);
  EXPECT_EQ(frameBitsOnBus(f(0x0B6, 8, {0x1A, 0xF8, 0, 0x32, 0, 0, 0, 0})), 121u);
  EXPECT_EQ(frameBitsOnBus(f(0x555, 8, {0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55})), 112u);
}

TEST(bitlaenge_sonderfaelle_fuellbits) {
  // CRC endet mit fünf gleichen Bits: dort kommt noch ein Füllbit.
  EXPECT_EQ(frameBitsOnBus(f(0x7A8, 8, {0x52, 0xFF, 0xFF, 0x0D, 0x00, 0x85, 0xFF, 0xFF})), 121u);
  // Ein Füllbit zählt zur nächsten Folge: 00000 [1] 1111 braucht ein
  // weiteres Füllbit.
  EXPECT_EQ(frameBitsOnBus(f(0x740, 8, {0xF0, 0xFF, 0x00, 0x99, 0xF0, 0xF0, 0x00, 0xFF})), 121u);
}

TEST(bitlaenge_29_bit_und_rtr) {
  EXPECT_EQ(frameBitsOnBus(f(0x18DAF110 | kExtendedFlag, 3, {0xAA, 0xBB, 0xCC})), 92u);
  EXPECT_EQ(frameBitsOnBus(f(0x18DB33F1 | kExtendedFlag, 8, {0x02, 0x01, 0x0D, 0, 0, 0, 0, 0})), 142u);
  EXPECT_EQ(frameBitsOnBus(f(0x1FFFFFFF | kExtendedFlag, 8,
                             {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF})), 149u);
  // RTR: DLC 8, aber keine Daten auf dem Bus
  EXPECT_EQ(frameBitsOnBus(f(0x123 | kRtrFlag, 8, {})), 48u);
}

TEST(bitlaenge_in_den_grenzen_der_norm) {
  // 8 Datenbytes, 11-Bit-ID: ohne Füllbits 111, höchstens 135 Bit.
  uint32_t seed = 1;
  for (int i = 0; i < 5000; ++i) {
    CanFrame fr;
    seed = seed * 1103515245u + 12345u;
    fr.id = (seed >> 8) & 0x7FF;
    fr.dlc = 8;
    for (int b = 0; b < 8; ++b) {
      seed = seed * 1103515245u + 12345u;
      fr.data[b] = static_cast<uint8_t>(seed >> 16);
    }
    const uint32_t bits = frameBitsOnBus(fr);
    EXPECT(bits >= 111 && bits <= 135);
  }
}
