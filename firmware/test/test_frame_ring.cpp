#include "frame_ring.h"
#include "mini_test.h"

using namespace can_core;

static TimedFrame item(uint32_t id, uint32_t t = 0) {
  TimedFrame f;
  f.frame.id = id;
  f.time_ms = t;
  return f;
}

TEST(ring_reihenfolge_bleibt) {
  FrameRing<8> r;
  for (uint32_t i = 1; i <= 5; ++i) EXPECT(r.push(item(i, i * 10)));
  EXPECT_EQ(r.size(), 5u);
  TimedFrame out;
  for (uint32_t i = 1; i <= 5; ++i) {
    EXPECT(r.pop(out));
    EXPECT_EQ(out.frame.id, i);
    EXPECT_EQ(out.time_ms, i * 10);
  }
  EXPECT(!r.pop(out));
}

TEST(ring_voll_verwirft_neue_und_zaehlt) {
  FrameRing<4> r;
  for (uint32_t i = 1; i <= 4; ++i) EXPECT(r.push(item(i)));
  EXPECT(!r.push(item(5)));
  EXPECT(!r.push(item(6)));
  EXPECT_EQ(r.overflows(), 2u);
  // Die alten bleiben erhalten, in der richtigen Reihenfolge.
  TimedFrame out;
  EXPECT(r.pop(out));
  EXPECT_EQ(out.frame.id, 1u);
  // Nach dem Abholen ist wieder Platz.
  EXPECT(r.push(item(7)));
  EXPECT_EQ(r.size(), 4u);
}

TEST(ring_ueber_viele_umlaeufe) {
  FrameRing<4> r;
  TimedFrame out;
  for (uint32_t i = 0; i < 1000; ++i) {
    EXPECT(r.push(item(i)));
    EXPECT(r.push(item(i + 100000)));
    EXPECT(r.pop(out));
    EXPECT_EQ(out.frame.id, i);
    EXPECT(r.pop(out));
    EXPECT_EQ(out.frame.id, i + 100000);
  }
  EXPECT_EQ(r.size(), 0u);
  EXPECT_EQ(r.overflows(), 0u);
}

TEST(ring_merkt_hoechststand) {
  FrameRing<8> r;
  TimedFrame out;
  EXPECT_EQ(r.maxFill(), 0u);
  for (uint32_t i = 0; i < 5; ++i) r.push(item(i));
  for (int i = 0; i < 5; ++i) r.pop(out);
  r.push(item(9));
  r.push(item(10));
  // Jetzt 2 drin, der Höchststand bleibt 5.
  EXPECT_EQ(r.size(), 2u);
  EXPECT_EQ(r.maxFill(), 5u);
}

#include <thread>

TEST(ring_schreiber_und_leser_gleichzeitig) {
  // Wie im Leser: eine Aufgabe schreibt, die Hauptschleife liest. Nichts
  // darf verloren gehen, doppelt kommen oder die Reihenfolge wechseln.
  static FrameRing<64> r;
  constexpr uint32_t kCount = 200000;
  std::thread producer([] {
    for (uint32_t i = 0; i < kCount;) {
      if (r.push(item(i))) ++i;  // bei vollem Puffer erneut versuchen
    }
  });
  uint32_t expected = 0;
  bool in_order = true;
  TimedFrame out;
  while (expected < kCount) {
    if (r.pop(out)) {
      if (out.frame.id != expected) in_order = false;
      ++expected;
    }
  }
  producer.join();
  EXPECT(in_order);
  EXPECT_EQ(expected, kCount);
  EXPECT(!r.pop(out));
}
