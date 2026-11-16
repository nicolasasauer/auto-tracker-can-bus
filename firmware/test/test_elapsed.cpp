#include "elapsed.h"
#include "mini_test.h"

using namespace can_core;

TEST(vergangene_zeit_normal) {
  EXPECT_EQ(elapsedMs(5000, 1000), 4000u);
  EXPECT_EQ(elapsedMs(1000, 1000), 0u);
}

// Der Fehler: Die Hauptschleife liest die Zeit, danach setzt der BLE-Task
// den Verbindungsbeginn. now - since lief über (ca. 49 Tage) und die frische
// Verbindung galt als abgelaufen.
TEST(vergangene_zeit_startpunkt_juenger_als_jetzt) {
  EXPECT_EQ(elapsedMs(1000, 1001), 0u);
  EXPECT_EQ(elapsedMs(1000, 1250), 0u);
}

TEST(vergangene_zeit_uebersteht_millis_ueberlauf) {
  EXPECT_EQ(elapsedMs(5, 0xFFFFFFF0u), 21u);
  // Startpunkt knapp nach dem Überlauf, „jetzt“ noch davor.
  EXPECT_EQ(elapsedMs(0xFFFFFFF0u, 5), 0u);
}
