#include "id_monitor.h"
#include "frame_filter.h"
#include "mini_test.h"

using namespace can_core;

static CanFrame frame(uint32_t id, uint8_t b0, uint8_t b1 = 0) {
  CanFrame f;
  f.id = id;
  f.dlc = 2;
  f.data[0] = b0;
  f.data[1] = b1;
  return f;
}

TEST(monitor_erste_botschaft_ohne_aenderung) {
  IdMonitor m;
  m.onFrame(frame(0x100, 0x12), 0);
  IdReport r[4];
  EXPECT_EQ(m.collect(r, 4), 1u);
  EXPECT_EQ(r[0].id, 0x100u);
  EXPECT_EQ(r[0].data[0], 0x12);
  EXPECT_EQ(r[0].changed[0], 0);
  EXPECT_EQ(r[0].frames, 1);
  EXPECT_EQ(r[0].period_ms, 0);
}

TEST(monitor_merkt_schnelle_wechsel) {
  // Bit 0 geht hin und zurück, danach bleibt der Wert gleich. Der Wechsel
  // muss trotzdem gemeldet werden.
  IdMonitor m;
  m.onFrame(frame(0x100, 0x00), 0);
  IdReport r[4];
  m.collect(r, 4);
  m.onFrame(frame(0x100, 0x01), 10);
  m.onFrame(frame(0x100, 0x00), 20);
  m.onFrame(frame(0x100, 0x00), 30);
  EXPECT_EQ(m.collect(r, 4), 1u);
  EXPECT_EQ(r[0].data[0], 0x00);
  EXPECT_EQ(r[0].changed[0], 0x01);
  EXPECT_EQ(r[0].frames, 3);
}

TEST(monitor_setzt_aenderungen_nach_meldung_zurueck) {
  IdMonitor m;
  m.onFrame(frame(0x100, 0x00), 0);
  m.onFrame(frame(0x100, 0xF0), 10);
  IdReport r[4];
  m.collect(r, 4);
  EXPECT_EQ(r[0].changed[0], 0xF0);
  m.onFrame(frame(0x100, 0xF0), 20);
  m.collect(r, 4);
  EXPECT_EQ(r[0].changed[0], 0);
  EXPECT(!m.hasPending());
}

TEST(monitor_mittlerer_abstand) {
  IdMonitor m;
  for (uint32_t t = 0; t <= 1000; t += 100) m.onFrame(frame(0x200, 1), t);
  IdReport r[1];
  m.collect(r, 1);
  EXPECT_EQ(r[0].period_ms, 100);
  EXPECT_EQ(r[0].frames, 11);
}

TEST(monitor_meldet_nur_neue_ids) {
  IdMonitor m;
  m.onFrame(frame(0x100, 1), 0);
  m.onFrame(frame(0x200, 1), 0);
  IdReport r[4];
  EXPECT_EQ(m.collect(r, 4), 2u);
  m.onFrame(frame(0x200, 2), 50);
  EXPECT_EQ(m.collect(r, 4), 1u);
  EXPECT_EQ(r[0].id, 0x200u);
}

TEST(monitor_reihum_wenn_nicht_alles_passt) {
  IdMonitor m;
  for (uint32_t id = 1; id <= 5; ++id) m.onFrame(frame(id, 0), 0);
  IdReport r[2];
  EXPECT_EQ(m.collect(r, 2), 2u);
  EXPECT_EQ(r[0].id, 1u);
  EXPECT_EQ(r[1].id, 2u);
  // ID 1 kommt wieder, darf aber 3–5 nicht verdrängen.
  m.onFrame(frame(1, 0), 10);
  EXPECT_EQ(m.collect(r, 2), 2u);
  EXPECT_EQ(r[0].id, 3u);
  EXPECT_EQ(r[1].id, 4u);
  EXPECT_EQ(m.collect(r, 2), 2u);
  EXPECT_EQ(r[0].id, 5u);
  EXPECT_EQ(r[1].id, 1u);
}

TEST(monitor_volle_tabelle) {
  IdMonitor m;
  for (uint32_t id = 0; id < IdMonitor::kCapacity + 3; ++id) {
    m.onFrame(frame(id, 0), 0);
  }
  EXPECT_EQ(m.idCount(), IdMonitor::kCapacity);
  EXPECT_EQ(m.framesUntracked(), 3u);
  EXPECT_EQ(m.framesTotal(), IdMonitor::kCapacity + 3);
}

TEST(monitor_unterscheidet_standard_und_erweitert) {
  IdMonitor m;
  m.onFrame(frame(0x100, 0), 0);
  m.onFrame(frame(0x100 | kExtendedFlag, 0), 0);
  EXPECT_EQ(m.idCount(), 2u);
}

TEST(filter_leer_laesst_alles_durch) {
  FrameFilter f;
  EXPECT(f.accepts(0x123));
  EXPECT(f.accepts(0x18DAF110 | kExtendedFlag));
}

TEST(filter_maske) {
  FrameFilter f;
  // OBD-Antworten 0x7E8–0x7EF
  EXPECT(f.add(0x7E8, 0x7F8 | kExtendedFlag));
  EXPECT(f.accepts(0x7E8));
  EXPECT(f.accepts(0x7EF));
  EXPECT(f.accepts(0x7E9 | kRtrFlag));
  EXPECT(!f.accepts(0x7E0));
  EXPECT(!f.accepts(0x7E8 | kExtendedFlag));
}

TEST(filter_rtr_bit_zaehlt_nicht) {
  FrameFilter f;
  EXPECT(f.add(0x123, 0xFFFFFFFF));
  EXPECT(f.accepts(0x123 | kRtrFlag));
  EXPECT(!f.accepts(0x124));
}

TEST(filter_hoechstens_acht) {
  FrameFilter f;
  for (int i = 0; i < 8; ++i) EXPECT(f.add(i, 0x7FF));
  EXPECT(!f.add(9, 0x7FF));
  EXPECT_EQ(f.size(), 8u);
}
