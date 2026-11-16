#include "mini_test.h"
#include "pairing_window.h"

using namespace can_core;

TEST(kopplung_ohne_fenster_abgelehnt) {
  PairingWindow w;
  const auto d = w.onPairingRequest(1000, 0, 4242);
  EXPECT(!d.allow);
  EXPECT_EQ(d.passkey, 4242u);
}

TEST(kopplung_im_fenster_mit_angezeigtem_code) {
  PairingWindow w;
  const uint32_t code = w.open(1000, 1234567);
  EXPECT_EQ(code, 234567u);
  const auto d = w.onPairingRequest(5000, 0, 999);
  EXPECT(d.allow);
  EXPECT_EQ(d.passkey, code);
}

TEST(kopplungsfenster_schliesst_nach_ablauf) {
  PairingWindow w;
  w.open(1000, 1, 120000);
  EXPECT(w.isOpen(120999));
  EXPECT(!w.isOpen(121000));
  EXPECT(!w.onPairingRequest(121000, 0, 7).allow);
}

TEST(kopplungsfenster_uebersteht_millis_ueberlauf) {
  PairingWindow w;
  w.open(0xFFFFFF00u, 1, 1000);
  EXPECT(w.isOpen(0xFFFFFF10u));
  EXPECT(w.isOpen(0x00000100u));
  EXPECT(!w.isOpen(0x00000400u));
}

TEST(kopplung_hoechstens_drei_geraete) {
  PairingWindow w;
  w.open(0, 1);
  EXPECT(w.onPairingRequest(10, 2, 0).allow);
  EXPECT(!w.onPairingRequest(10, PairingWindow::kMaxBonds, 0).allow);
}

TEST(kopplungsfenster_von_hand_schliessen) {
  PairingWindow w;
  w.open(0, 1);
  w.close();
  EXPECT(!w.isOpen(10));
}
