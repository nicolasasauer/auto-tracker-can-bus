// Treiber-Schnittstelle für den CAN-Empfang (CAN-KONZEPT.md, Kapitel 8).
//
// Stufe 1: Es gibt bewusst KEINE Methode zum Senden. Der Controller läuft im
// Listen-Only-Modus und schickt nicht einmal Bestätigungen (ACK) auf den Bus.
#pragma once

#include <stdint.h>

#include "can_frame.h"
#include "protocol.h"

class CanReceiver {
 public:
  virtual ~CanReceiver() = default;

  // Controller starten, nur mithören. false, wenn er nicht antwortet.
  virtual bool begin(uint32_t bitrate) = 0;

  // Nächste Botschaft, false wenn keine da ist.
  virtual bool read(can_core::CanFrame& out) = 0;

  // Ereignisse seit dem letzten Aufruf; quittiert sie im Controller.
  struct Events {
    uint32_t overflows = 0;     // Empfangspuffer übergelaufen
    uint32_t error_events = 0;  // fehlerhafte Botschaften erkannt
  };
  virtual Events takeEvents() = 0;

  // Zustand des Controllers.
  struct Health {
    // Fehlerzustand (ohne „still“, das weiß der Aufrufer)
    can_core::protocol::BusState state = can_core::protocol::BusState::kOk;
    uint8_t rx_error_counter = 0;  // REC, 0–255
    uint8_t error_flags = 0;       // controllerspezifisch (MCP2515: EFLG)
  };
  virtual Health health() = 0;
};
