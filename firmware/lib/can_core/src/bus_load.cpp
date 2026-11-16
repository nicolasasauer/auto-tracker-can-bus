#include "bus_load.h"

namespace can_core {

void BusLoadMeter::advance(uint32_t second) {
  if (!started_) {
    started_ = true;
    second_ = second;
    return;
  }
  // Verspätet verbuchte Botschaft (Zeitstempel aus einer schon
  // abgeschlossenen Sekunde): zählt zur laufenden Sekunde. Ohne diese
  // Prüfung liefe second - second_ über und leerte das ganze Fenster.
  if (second <= second_) return;
  // Sekunden zwischen second_ und second abschließen. Nach langer Ruhe
  // reichen kWindowSeconds leere Sekunden, mehr ändert nichts.
  uint32_t steps = second - second_;
  if (steps > kWindowSeconds + 1) steps = kWindowSeconds + 1;
  for (uint32_t i = 0; i < steps; ++i) {
    const uint32_t bits = i == 0 ? current_bits_ : 0;
    window_[(second_ + i) % kWindowSeconds] = bits;
    if (filled_ < kWindowSeconds) ++filled_;
    last_bits_ = bits;
    if (bits > peak_bits_) peak_bits_ = bits;
  }
  if (steps > 0) current_bits_ = 0;
  second_ = second;
}

void BusLoadMeter::add(uint32_t bits, uint32_t now_ms) {
  advance(now_ms / 1000);
  current_bits_ += bits;
}

uint16_t BusLoadMeter::centi(uint32_t bits) const {
  // bits / bitrate · 10000, gerundet, höchstens 100,00 %.
  const uint64_t v = (static_cast<uint64_t>(bits) * 10000 + bitrate_ / 2) / bitrate_;
  return static_cast<uint16_t>(v > 10000 ? 10000 : v);
}

BusLoadMeter::Stats BusLoadMeter::stats(uint32_t now_ms) {
  advance(now_ms / 1000);
  Stats s{};
  s.now_centi = centi(last_bits_);
  s.peak_centi = centi(peak_bits_);
  if (filled_ > 0) {
    uint64_t sum = 0;
    for (uint32_t i = 0; i < kWindowSeconds; ++i) sum += window_[i];
    s.avg_centi = centi(static_cast<uint32_t>(sum / filled_));
  }
  return s;
}

void BusLoadMeter::reset() {
  started_ = false;
  current_bits_ = 0;
  filled_ = 0;
  last_bits_ = 0;
  peak_bits_ = 0;
  for (uint32_t& w : window_) w = 0;
}

}  // namespace can_core
