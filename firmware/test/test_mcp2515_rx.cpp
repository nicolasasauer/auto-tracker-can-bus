#include "mcp2515_rx.h"
#include "mini_test.h"

using namespace can_core;

namespace {

// Rohinhalt eines Empfangspuffers: SIDH, SIDL, EID8, EID0, DLC, D0–D7.
struct Raw {
  uint8_t b[kMcp2515RxBufferSize];
};

Raw rawFrame(uint8_t sidh, uint8_t sidl, uint8_t eid8, uint8_t eid0,
             uint8_t dlc_reg) {
  Raw r{{sidh, sidl, eid8, eid0, dlc_reg, 1, 2, 3, 4, 5, 6, 7, 8}};
  return r;
}

}  // namespace

// Der Fehler: Die MCP2515-Bibliothek lehnt DLC 9–15 ab und gibt den Puffer
// nicht frei. Im klassischen CAN heißt DLC 9–15: 8 Datenbytes.
TEST(mcp2515_dlc_ueber_acht_sind_acht_bytes) {
  for (uint8_t dlc = 9; dlc <= 15; ++dlc) {
    const Raw r = rawFrame(0x24, 0x60, 0, 0, dlc);  // ID 0x123
    CanFrame f;
    decodeMcp2515RxBuffer(r.b, f);
    EXPECT_EQ(f.id, 0x123u);
    EXPECT_EQ(f.dlc, 8);
    for (int i = 0; i < 8; ++i) EXPECT_EQ(f.data[i], i + 1);
  }
}

TEST(mcp2515_kurze_botschaft_nur_dlc_bytes) {
  const Raw r = rawFrame(0xFF, 0xE0, 0, 0, 3);  // ID 0x7FF
  CanFrame f;
  decodeMcp2515RxBuffer(r.b, f);
  EXPECT_EQ(f.id, 0x7FFu);
  EXPECT_EQ(f.dlc, 3);
  EXPECT_EQ(f.data[2], 3);
  EXPECT_EQ(f.data[3], 0);
  EXPECT_EQ(f.data[7], 0);
}

TEST(mcp2515_erweiterte_id) {
  // 0x18DAF110: Basis-ID 0x636, Erweiterung 0x2F110
  const Raw r = rawFrame(0xC6, 0xCA, 0xF1, 0x10, 15);
  CanFrame f;
  decodeMcp2515RxBuffer(r.b, f);
  EXPECT_EQ(f.id, 0x18DAF110u | kExtendedFlag);
  EXPECT_EQ(f.dlc, 8);
}

TEST(mcp2515_rtr_standard_und_erweitert) {
  // Standard: SRR-Bit in SIDL. Die Bits für die Erweiterung zählen nicht.
  Raw r = rawFrame(0x24, 0x60 | 0x10, 0xAA, 0xBB, 2);
  CanFrame f;
  decodeMcp2515RxBuffer(r.b, f);
  EXPECT_EQ(f.id, 0x123u | kRtrFlag);
  // Erweitert: RTR-Bit im DLC-Register; SRR in SIDL zählt dann nicht.
  r = rawFrame(0xC6, 0xCA | 0x10, 0xF1, 0x10, 0x40 | 2);
  decodeMcp2515RxBuffer(r.b, f);
  EXPECT_EQ(f.id, 0x18DAF110u | kExtendedFlag | kRtrFlag);
  EXPECT_EQ(f.dlc, 2);
  r = rawFrame(0xC6, 0xCA | 0x10, 0xF1, 0x10, 2);
  decodeMcp2515RxBuffer(r.b, f);
  EXPECT_EQ(f.id, 0x18DAF110u | kExtendedFlag);
}
