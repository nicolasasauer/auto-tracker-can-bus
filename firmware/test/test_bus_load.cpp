#include "bus_load.h"
#include "mini_test.h"

using namespace can_core;

TEST(buslast_volle_sekunde) {
  BusLoadMeter m(500000);
  // 1000 Botschaften à 125 Bit in Sekunde 0 = 125 000 Bit = 25 %
  for (int i = 0; i < 1000; ++i) m.add(125, static_cast<uint32_t>(i));
  // Sekunde 0 ist erst abgeschlossen, wenn Sekunde 1 läuft.
  EXPECT_EQ(m.stats(999).now_centi, 0);
  const auto s = m.stats(1000);
  EXPECT_EQ(s.now_centi, 2500);
  EXPECT_EQ(s.peak_centi, 2500);
  EXPECT_EQ(s.avg_centi, 2500);
}

TEST(buslast_mittel_ueber_zehn_sekunden) {
  BusLoadMeter m(500000);
  // Sekunde 0: 50 000 Bit (10 %), Sekunde 1: 150 000 Bit (30 %)
  m.add(50000, 0);
  m.add(150000, 1000);
  const auto s = m.stats(2000);
  EXPECT_EQ(s.now_centi, 3000);
  EXPECT_EQ(s.avg_centi, 2000);
  EXPECT_EQ(s.peak_centi, 3000);
}

TEST(buslast_ruhe_senkt_aktuell_und_mittel) {
  BusLoadMeter m(500000);
  m.add(250000, 0);  // 50 %
  // 20 s nichts: aktuell 0, Mittel 0 (Fenster nur noch leer), Spitze bleibt
  const auto s = m.stats(21000);
  EXPECT_EQ(s.now_centi, 0);
  EXPECT_EQ(s.avg_centi, 0);
  EXPECT_EQ(s.peak_centi, 5000);
}

TEST(buslast_mittel_nur_ueber_gefuellte_sekunden) {
  BusLoadMeter m(500000);
  m.add(100000, 5000);  // 20 % in der ersten gemessenen Sekunde
  const auto s = m.stats(6000);
  // Nur eine Sekunde gemessen: Mittel = 20 %, nicht 2 %
  EXPECT_EQ(s.avg_centi, 2000);
}

TEST(buslast_hoechstens_hundert_prozent) {
  BusLoadMeter m(500000);
  m.add(600000, 0);
  EXPECT_EQ(m.stats(1000).now_centi, 10000);
}

TEST(buslast_zuruecksetzen) {
  BusLoadMeter m(500000);
  m.add(250000, 0);
  m.stats(1000);
  m.reset();
  const auto s = m.stats(2000);
  EXPECT_EQ(s.peak_centi, 0);
  EXPECT_EQ(s.now_centi, 0);
}

TEST(buslast_verspaetete_botschaft_loescht_nichts) {
  // Eine Botschaft von 1999 ms wird erst verbucht, nachdem stats(2000)
  // schon Sekunde 1 abgeschlossen hat. Sie darf das Fenster nicht leeren.
  BusLoadMeter m(500000);
  m.add(100000, 500);   // Sekunde 0: 20 %
  m.add(100000, 1500);  // Sekunde 1: 20 %
  m.stats(2000);
  m.add(1000, 1999);    // verspätet
  const auto s = m.stats(2100);
  EXPECT_EQ(s.avg_centi, 2000);
  EXPECT_EQ(s.peak_centi, 2000);
}
