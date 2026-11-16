// Buslast: Anteil der Zeit, in der der Bus Bits überträgt, in sekündlichen
// Fenstern. Gemeldet werden die letzte volle Sekunde, das Mittel der
// letzten 10 Sekunden und die höchste Sekunde seit dem Zurücksetzen.
#pragma once

#include <stdint.h>

namespace can_core {

class BusLoadMeter {
 public:
  static constexpr uint32_t kWindowSeconds = 10;

  explicit BusLoadMeter(uint32_t bitrate = 500000) : bitrate_(bitrate) {}

  // Bits einer empfangenen Botschaft (frameBitsOnBus) zum Zeitpunkt now_ms.
  void add(uint32_t bits, uint32_t now_ms);

  struct Stats {
    uint16_t now_centi;    // letzte volle Sekunde, in 0,01 %
    uint16_t avg_centi;    // Mittel der letzten 10 Sekunden
    uint16_t peak_centi;   // höchste Sekunde seit Zurücksetzen
  };
  // Schließt vergangene Sekunden ab, auch wenn nichts mehr kam.
  Stats stats(uint32_t now_ms);

  void reset();

 private:
  void advance(uint32_t second);
  uint16_t centi(uint32_t bits) const;

  uint32_t bitrate_;
  bool started_ = false;
  uint32_t second_ = 0;        // laufende Sekunde (now_ms / 1000)
  uint32_t current_bits_ = 0;  // Bits der laufenden Sekunde
  uint32_t window_[kWindowSeconds] = {};  // abgeschlossene Sekunden
  uint32_t filled_ = 0;        // wie viele davon gültig sind
  uint32_t last_bits_ = 0;
  uint32_t peak_bits_ = 0;
};

}  // namespace can_core
