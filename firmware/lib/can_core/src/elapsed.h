// Vergangene Zeit zwischen zwei millis()-Werten, die aus verschiedenen
// Aufgaben stammen können.
#pragma once

#include <stdint.h>

namespace can_core {

// Millisekunden von since_ms bis now_ms. Übersteht den Überlauf von millis()
// nach ca. 49 Tagen.
//
// Liegt since_ms knapp NACH now_ms, ist das Ergebnis 0. Das passiert, wenn
// eine Aufgabe „jetzt“ schon gelesen hat und eine andere den Startpunkt erst
// danach setzt. Die einfache Subtraktion liefe dann über und meldete rund
// 49 Tage. Gilt für Abstände bis ca. 24 Tage.
inline uint32_t elapsedMs(uint32_t now_ms, uint32_t since_ms) {
  const uint32_t diff = now_ms - since_ms;
  return diff > 0x7FFFFFFFu ? 0 : diff;
}

}  // namespace can_core
