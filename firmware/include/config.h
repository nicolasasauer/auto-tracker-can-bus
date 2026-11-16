// Pins und feste Einstellungen des Prototyps.
#pragma once

#include <Arduino.h>

namespace config {

// Firmwareversion, wird im Status an die Apps gemeldet.
constexpr uint8_t kFwMajor = 0;
constexpr uint8_t kFwMinor = 1;
constexpr uint8_t kFwPatch = 0;

// Seeed „XIAO CAN Bus Expansion Board“: MCP2515 über SPI (SCK D8, MISO D9,
// MOSI D10, Standardpins des XIAO), Quarz 16 MHz. Chip-Select D7 laut
// Seeed-Wiki (wiki.seeedstudio.com/xiao-can-bus-expansion). Stimmt er nicht, meldet
// die Konsole „CAN-Controller fehlt“.
#ifndef CAN_CS_PIN
#define CAN_CS_PIN D7
#endif
constexpr uint8_t kCanCsPin = CAN_CS_PIN;

// INT des MCP2515 (meldet neue Botschaften). Im Seeed-Wiki nicht genannt,
// D6 ist eine Annahme. Stimmt er nicht, läuft der Leser trotzdem (Abfrage
// jede Millisekunde, langsamer) und die Konsole meldet „Interrupts: 0“.
// -1 = ohne Interrupt.
#ifndef CAN_INT_PIN
#define CAN_INT_PIN D6
#endif
constexpr int kCanIntPin = CAN_INT_PIN;

// OBD-Bus: 500 kbit/s.
constexpr uint32_t kCanBitrate = 500000;

// Ohne Botschaften so lange gilt der Bus als „still“.
constexpr uint32_t kSilentAfterMs = 2000;

// Abstand der ID-Übersichten an die App (per BLE-Befehl änderbar).
constexpr uint16_t kDefaultReportIntervalMs = 200;

// Höchstens so viele Übersichts-Nachrichten pro Durchgang.
constexpr uint8_t kMaxNotificationsPerReport = 8;

// Verbindungen, die nicht binnen dieser Zeit verschlüsselt und
// authentifiziert sind, werden getrennt.
constexpr uint32_t kAuthTimeoutMs = 30000;

constexpr const char* kDeviceName = "CAN-Leser";

}  // namespace config
