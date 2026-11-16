// BLE-Verbindung zu den Apps (docs/CAN-BLE-PROTOKOLL.md).
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "pairing_window.h"
#include "protocol.h"

namespace ble_link {

// window: entscheidet, ob sich ein neues Handy koppeln darf.
void begin(can_core::PairingWindow* window);

// Regelmäßig aus loop() aufrufen (trennt nicht authentifizierte Verbindungen).
void poll(uint32_t now_ms);

// Ist ein gekoppeltes Handy verschlüsselt verbunden?
bool secureClientConnected();

// Wie viele Einträge passen bei der aktuellen MTU in eine Übersicht?
size_t monitorRecordCapacity();

void sendMonitor(const uint8_t* data, size_t len);
void updateStatus(const uint8_t* data, size_t len);
void updateDiagnostics(const uint8_t* data, size_t len);

// Nächster Befehl aus der App, false wenn keiner wartet.
bool takeCommand(can_core::protocol::Command& out);

// Gespeicherte Kopplungen.
int bondCount();
void deleteAllBonds();

}  // namespace ble_link
