// Kodierung der BLE-Nachrichten (docs/CAN-BLE-PROTOKOLL.md).
// Das Gegenstück in Dart liegt in packages/can_link.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "id_monitor.h"

namespace can_core {
namespace protocol {

constexpr uint8_t kVersion = 1;

constexpr uint8_t kTypeMonitor = 0x01;
constexpr uint8_t kTypeStatus = 0x02;
constexpr uint8_t kTypeDiagnostics = 0x03;

constexpr uint8_t kCmdResetStats = 0x10;
constexpr uint8_t kCmdSetFilter = 0x11;
constexpr uint8_t kCmdSetInterval = 0x12;

constexpr size_t kMonitorHeaderSize = 9;
constexpr size_t kMonitorRecordSize = 25;
constexpr size_t kStatusSize = 24;
constexpr size_t kDiagnosticsSize = 24;

constexpr uint16_t kIntervalMinMs = 100;
constexpr uint16_t kIntervalMaxMs = 5000;

// Wie viele Einträge passen bei dieser MTU in eine Übersicht?
// (ATT-Kopf: 3 Byte)
size_t monitorRecordsForMtu(uint16_t mtu);

// Übersicht kodieren. Rückgabe: Länge, 0 wenn cap zu klein.
size_t encodeMonitor(uint16_t seq, uint32_t time_ms, const IdReport* records,
                     size_t n, uint8_t* out, size_t cap);

enum class BusMode : uint8_t { kListenOnly = 0, kActive = 1 };
enum class BusState : uint8_t {
  kOk = 0,
  kSilent = 1,
  kError = 2,
  kBusOff = 3,
  kNoController = 4,
};

struct Status {
  uint8_t fw_major = 0;
  uint8_t fw_minor = 0;
  uint8_t fw_patch = 0;
  BusMode mode = BusMode::kListenOnly;
  BusState state = BusState::kSilent;
  bool pairing_open = false;
  bool usb_host = false;
  uint32_t uptime_s = 0;
  uint32_t frames_total = 0;
  uint32_t frames_dropped = 0;
  uint16_t ids_seen = 0;
  uint16_t supply_mv = 0;
};

// Status kodieren. Rückgabe: Länge (kStatusSize), 0 wenn cap zu klein.
size_t encodeStatus(const Status& status, uint8_t* out, size_t cap);

// Grund des letzten Neustarts (vereinfacht aus esp_reset_reason()).
enum class ResetReason : uint8_t {
  kUnknown = 0,
  kPowerOn = 1,     // Strom eingeschaltet
  kBrownout = 2,    // Spannungseinbruch (z. B. Motorstart)
  kSoftware = 3,    // Neustart durch die Firmware
  kPanic = 4,       // Absturz
  kWatchdog = 5,    // Watchdog
  kDeepSleep = 6,   // Aufwachen aus dem Tiefschlaf
  kExternal = 7,    // Reset-Taste bzw. -Pin, USB
  kOther = 8,
};

struct Diagnostics {
  // Buslast in 0,01 % (siehe BusLoadMeter)
  uint16_t load_now_centi = 0;
  uint16_t load_avg_centi = 0;
  uint16_t load_peak_centi = 0;
  // Empfangsfehlerzähler des CAN-Controllers (REC, 0–255) und seine
  // Fehler-Flags (beim MCP2515 das Register EFLG)
  uint8_t rx_error_counter = 0;
  uint8_t error_flags = 0;
  // Fehlerhafte Botschaften seit dem Start (beim MCP2515: MERRF)
  uint32_t error_events = 0;
  // Höchster Füllstand des Ringpuffers und seine Größe
  uint16_t ring_max_fill = 0;
  uint16_t ring_capacity = 0;
  ResetReason reset_reason = ResetReason::kUnknown;
  // Starts seit dem ersten Flashen
  uint32_t boot_count = 0;
};

// Diagnose kodieren. Rückgabe: kDiagnosticsSize, 0 wenn cap zu klein.
size_t encodeDiagnostics(const Diagnostics& d, uint8_t* out, size_t cap);

struct FilterEntry {
  uint32_t id;
  uint32_t mask;
};

struct Command {
  uint8_t type = 0;
  // kCmdSetFilter
  uint8_t filter_count = 0;
  FilterEntry filters[8] = {};
  // kCmdSetInterval
  uint16_t interval_ms = 0;
};

// Befehl prüfen und zerlegen. false bei unbekanntem oder ungültigem Befehl.
bool parseCommand(const uint8_t* data, size_t len, Command& out);

}  // namespace protocol
}  // namespace can_core
