// Lese-Aufgabe: holt Botschaften so schnell wie möglich aus dem
// CAN-Controller und legt sie mit Empfangszeit in einen Ringpuffer. Die
// Hauptschleife (BLE, Konsole) verarbeitet sie später; ein paar
// Millisekunden Verzögerung dort kosten keine Botschaften.
//
// Der MCP2515 hat nur zwei Empfangspuffer. Ohne schnelles Leeren gehen
// Botschaften schon bei mäßigem Verkehr verloren. Deshalb:
//  - Der INT-Pin des MCP2515 weckt die Aufgabe per Interrupt sofort.
//  - Die Aufgabe läuft mit hoher Priorität (über der Hauptschleife und dem
//    BLE-Host, unter dem Bluetooth-Controller).
//  - Kommt kein Interrupt (Pin falsch oder nicht verbunden), fragt sie
//    trotzdem jede Millisekunde nach. Die Konsole weist dann darauf hin.
#pragma once

#include <stdint.h>

#include "can_receiver.h"
#include "frame_ring.h"

namespace can_reader {

using Ring = can_core::FrameRing<512>;

// int_pin: INT des CAN-Controllers, oder -1 für reinen Abfragebetrieb.
void start(CanReceiver* receiver, int int_pin);

// Ringpuffer; nur die Hauptschleife darf pop() aufrufen.
Ring& ring();

// Überläufe des Controllers (Empfangspuffer) seit dem Start.
uint32_t controllerOverflows();

// Fehlerhafte Botschaften, die der Controller seit dem Start gemeldet hat.
uint32_t errorEvents();

// Zustand des Controllers, zuletzt (alle 100 ms) von der Aufgabe gelesen.
can_core::protocol::BusState errorState();
uint8_t rxErrorCounter();
uint8_t errorFlags();

// Anzahl Interrupts seit dem Start (0 trotz Botschaften = INT-Pin falsch).
uint32_t interruptCount();

}  // namespace can_reader
