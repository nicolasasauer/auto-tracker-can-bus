// Beispielnachrichten Byte für Byte. Dieselben Bytes prüft
// packages/can_link/test/protocol_test.dart auf der App-Seite.
#include "mini_test.h"
#include "protocol.h"

using namespace can_core;
using namespace can_core::protocol;

static const char* kMonitorVector =
    "01 01 02 01 45 23 01 00 02 "
    "E8 07 00 00 08 03 41 0D 32 00 00 00 00 00 00 00 FF 00 00 00 00 05 00 64 00 "
    "10 F1 DA 98 03 AA BB CC 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00";

static const char* kStatusVector =
    "02 01 00 01 00 00 00 03 10 0E 00 00 40 E2 01 00 07 00 00 00 2A 00 38 31";

TEST(monitor_beispielnachricht) {
  IdReport r[2];
  r[0].id = 0x7E8;
  r[0].dlc = 8;
  const uint8_t d0[8] = {0x03, 0x41, 0x0D, 0x32, 0, 0, 0, 0};
  memcpy(r[0].data, d0, 8);
  r[0].changed[3] = 0xFF;
  r[0].frames = 5;
  r[0].period_ms = 100;
  r[1].id = 0x18DAF110 | kExtendedFlag;
  r[1].dlc = 3;
  r[1].data[0] = 0xAA;
  r[1].data[1] = 0xBB;
  r[1].data[2] = 0xCC;
  r[1].frames = 1;

  uint8_t buf[64];
  const size_t len = encodeMonitor(0x0102, 0x00012345, r, 2, buf, sizeof(buf));
  EXPECT_EQ(len, kMonitorHeaderSize + 2 * kMonitorRecordSize);
  EXPECT_HEX(buf, len, kMonitorVector);
}

TEST(monitor_zu_kleiner_puffer) {
  IdReport r[2];
  uint8_t buf[58];
  EXPECT_EQ(encodeMonitor(1, 0, r, 2, buf, sizeof(buf)), 0u);
}

TEST(monitor_eintraege_je_mtu) {
  EXPECT_EQ(monitorRecordsForMtu(247), 9u);
  EXPECT_EQ(monitorRecordsForMtu(23), 0u);
  EXPECT_EQ(monitorRecordsForMtu(37), 1u);
}

TEST(status_beispielnachricht) {
  Status s;
  s.fw_major = 0;
  s.fw_minor = 1;
  s.fw_patch = 0;
  s.mode = BusMode::kListenOnly;
  s.state = BusState::kOk;
  s.pairing_open = true;
  s.usb_host = true;
  s.uptime_s = 3600;
  s.frames_total = 123456;
  s.frames_dropped = 7;
  s.ids_seen = 42;
  s.supply_mv = 12600;
  uint8_t buf[32];
  const size_t len = encodeStatus(s, buf, sizeof(buf));
  EXPECT_EQ(len, kStatusSize);
  EXPECT_HEX(buf, len, kStatusVector);
}

TEST(befehl_filter) {
  const uint8_t cmd[] = {0x11, 0x01, 0xE8, 0x07, 0, 0, 0xF8, 0x07, 0, 0};
  Command c;
  EXPECT(parseCommand(cmd, sizeof(cmd), c));
  EXPECT_EQ(c.filter_count, 1);
  EXPECT_EQ(c.filters[0].id, 0x7E8u);
  EXPECT_EQ(c.filters[0].mask, 0x7F8u);
}

TEST(befehl_filter_falsche_laenge) {
  const uint8_t cmd[] = {0x11, 0x02, 0xE8, 0x07, 0, 0, 0xF8, 0x07, 0, 0};
  Command c;
  EXPECT(!parseCommand(cmd, sizeof(cmd), c));
  const uint8_t zu_viele[] = {0x11, 0x09};
  EXPECT(!parseCommand(zu_viele, sizeof(zu_viele), c));
}

TEST(befehl_intervall_grenzen) {
  Command c;
  const uint8_t ok[] = {0x12, 0xC8, 0x00};  // 200 ms
  EXPECT(parseCommand(ok, sizeof(ok), c));
  EXPECT_EQ(c.interval_ms, 200);
  const uint8_t zu_kurz[] = {0x12, 0x63, 0x00};  // 99 ms
  EXPECT(!parseCommand(zu_kurz, sizeof(zu_kurz), c));
  const uint8_t zu_lang[] = {0x12, 0x89, 0x13};  // 5001 ms
  EXPECT(!parseCommand(zu_lang, sizeof(zu_lang), c));
}

TEST(befehl_unbekannt) {
  // Es gibt bewusst keinen Befehl zum Senden auf den Bus.
  Command c;
  const uint8_t senden[] = {0x20, 0xE0, 0x07, 0, 0};
  EXPECT(!parseCommand(senden, sizeof(senden), c));
  const uint8_t reset_mit_rest[] = {0x10, 0x00};
  EXPECT(!parseCommand(reset_mit_rest, sizeof(reset_mit_rest), c));
}

static const char* kDiagnosticsVector =
    "03 01 D2 04 E8 03 E1 10 05 01 70 11 01 00 25 00 00 02 02 00 11 00 00 00";

TEST(diagnose_beispielnachricht) {
  Diagnostics d;
  d.load_now_centi = 1234;
  d.load_avg_centi = 1000;
  d.load_peak_centi = 4321;
  d.rx_error_counter = 5;
  d.error_flags = 0x01;
  d.error_events = 70000;
  d.ring_max_fill = 37;
  d.ring_capacity = 512;
  d.reset_reason = ResetReason::kBrownout;
  d.boot_count = 17;
  uint8_t buf[32];
  const size_t len = encodeDiagnostics(d, buf, sizeof(buf));
  EXPECT_EQ(len, kDiagnosticsSize);
  EXPECT_HEX(buf, len, kDiagnosticsVector);
  EXPECT_EQ(encodeDiagnostics(d, buf, kDiagnosticsSize - 1), 0u);
}
