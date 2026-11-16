// CAN-Leser, Stufe 1: nur mithören.
//
// Liest alle Botschaften am OBD-Bus, fasst sie je CAN-ID zusammen und schickt
// die Übersicht per BLE an ein gekoppeltes Handy. Gesendet wird auf dem Bus
// nichts. Bedienung über die serielle Konsole: siehe README.md.
#include <Arduino.h>

#include "ble_link.h"
#include "boot_info.h"
#include "bus_load.h"
#include "can_bits.h"
#include "can_reader.h"
#include "config.h"
#include "frame_filter.h"
#include "id_monitor.h"
#include "mcp2515_receiver.h"
#include "pairing_window.h"
#include "protocol.h"

using can_core::BusLoadMeter;
using can_core::CanFrame;
using can_core::FrameFilter;
using can_core::IdMonitor;
using can_core::IdReport;
using can_core::PairingWindow;
namespace protocol = can_core::protocol;

namespace {

CanReceiver* g_can = nullptr;
bool g_can_ok = false;
IdMonitor g_monitor;
FrameFilter g_filter;
PairingWindow g_pairing;
BusLoadMeter g_load(config::kCanBitrate);

// Bei „Zurücksetzen“ gemerkte Zählerstände (die Zähler selbst laufen in
// der Lese-Aufgabe weiter).
uint32_t g_dropped_base = 0;
uint32_t g_error_events_base = 0;
uint32_t g_last_frame_ms = 0;
bool g_any_frame = false;
uint16_t g_report_interval_ms = config::kDefaultReportIntervalMs;
uint32_t g_last_report_ms = 0;
uint32_t g_last_status_ms = 0;
uint16_t g_seq = 0;

char g_line[64];
size_t g_line_len = 0;

bool usbHost() { return static_cast<bool>(Serial); }

protocol::BusState busState(uint32_t now) {
  if (!g_can_ok) return protocol::BusState::kNoController;
  const auto error = can_reader::errorState();
  if (error != protocol::BusState::kOk) return error;
  if (!g_any_frame || now - g_last_frame_ms > config::kSilentAfterMs) {
    return protocol::BusState::kSilent;
  }
  return protocol::BusState::kOk;
}

const char* busStateText(protocol::BusState s) {
  switch (s) {
    case protocol::BusState::kOk: return "Botschaften kommen";
    case protocol::BusState::kSilent: return "still (keine Botschaften)";
    case protocol::BusState::kError: return "Fehler (Warnung/passiv)";
    case protocol::BusState::kBusOff: return "Bus aus (bus-off)";
    case protocol::BusState::kNoController: return "CAN-Controller fehlt";
  }
  return "?";
}

uint32_t droppedTotal() {
  return can_reader::controllerOverflows() + can_reader::ring().overflows();
}

uint32_t framesDropped() { return droppedTotal() - g_dropped_base; }

protocol::Diagnostics currentDiagnostics(uint32_t now) {
  protocol::Diagnostics d;
  const BusLoadMeter::Stats load = g_load.stats(now);
  d.load_now_centi = load.now_centi;
  d.load_avg_centi = load.avg_centi;
  d.load_peak_centi = load.peak_centi;
  d.rx_error_counter = can_reader::rxErrorCounter();
  d.error_flags = can_reader::errorFlags();
  d.error_events = can_reader::errorEvents() - g_error_events_base;
  d.ring_max_fill = static_cast<uint16_t>(can_reader::ring().maxFill());
  d.ring_capacity = static_cast<uint16_t>(can_reader::Ring::capacity());
  d.reset_reason = boot_info::resetReason();
  d.boot_count = boot_info::bootCount();
  return d;
}

protocol::Status currentStatus(uint32_t now) {
  protocol::Status s;
  s.fw_major = config::kFwMajor;
  s.fw_minor = config::kFwMinor;
  s.fw_patch = config::kFwPatch;
  s.mode = protocol::BusMode::kListenOnly;
  s.state = busState(now);
  s.pairing_open = g_pairing.isOpen(now);
  s.usb_host = usbHost();
  s.uptime_s = now / 1000;
  s.frames_total = g_monitor.framesTotal();
  s.frames_dropped = framesDropped();
  s.ids_seen = static_cast<uint16_t>(g_monitor.idCount());
  s.supply_mv = 0;  // Spannungsteiler kommt mit der eigenen Platine
  return s;
}

void sendReports(uint32_t now) {
  const size_t capacity = ble_link::monitorRecordCapacity();
  if (capacity == 0) return;
  IdReport records[16];
  const size_t per_message = capacity < 16 ? capacity : 16;
  uint8_t buf[protocol::kMonitorHeaderSize + 16 * protocol::kMonitorRecordSize];
  for (uint8_t i = 0; i < config::kMaxNotificationsPerReport; ++i) {
    const size_t n = g_monitor.collect(records, per_message);
    if (n == 0) return;
    const size_t len =
        protocol::encodeMonitor(g_seq++, now, records, n, buf, sizeof(buf));
    ble_link::sendMonitor(buf, len);
  }
}

void handleCommand(const protocol::Command& cmd) {
  switch (cmd.type) {
    case protocol::kCmdResetStats:
      g_monitor.reset();
      g_dropped_base = droppedTotal();
      g_error_events_base = can_reader::errorEvents();
      g_load.reset();
      break;
    case protocol::kCmdSetFilter:
      g_filter.clear();
      for (uint8_t i = 0; i < cmd.filter_count; ++i) {
        g_filter.add(cmd.filters[i].id, cmd.filters[i].mask);
      }
      g_monitor.reset();
      break;
    case protocol::kCmdSetInterval:
      g_report_interval_ms = cmd.interval_ms;
      break;
  }
}

void printStatus(uint32_t now) {
  const protocol::Status s = currentStatus(now);
  Serial.printf("Firmware %u.%u.%u, nur mithoeren\n", s.fw_major, s.fw_minor,
                s.fw_patch);
  Serial.printf("Bus: %s\n", busStateText(s.state));
  Serial.printf("Botschaften: %lu, verloren: %lu, IDs: %u\n",
                static_cast<unsigned long>(s.frames_total),
                static_cast<unsigned long>(s.frames_dropped), s.ids_seen);
  const uint32_t irqs = can_reader::interruptCount();
  Serial.printf("Interrupts: %lu, Puffer: %u von %u\n",
                static_cast<unsigned long>(irqs),
                static_cast<unsigned>(can_reader::ring().size()),
                static_cast<unsigned>(can_reader::Ring::capacity()));
  if (config::kCanIntPin >= 0 && irqs == 0 && s.frames_total > 0) {
    Serial.printf("  Keine Interrupts trotz Botschaften: INT-Pin %d stimmt "
                  "nicht? Leser fragt jede ms ab (langsamer). Pin in "
                  "include/config.h pruefen.\n", config::kCanIntPin);
  }
  const protocol::Diagnostics d = currentDiagnostics(now);
  Serial.printf("Buslast: %u,%02u %% (Mittel 10 s: %u,%02u %%, Spitze: %u,%02u %%)\n",
                d.load_now_centi / 100, d.load_now_centi % 100,
                d.load_avg_centi / 100, d.load_avg_centi % 100,
                d.load_peak_centi / 100, d.load_peak_centi % 100);
  Serial.printf("Empfangsfehler: Zaehler %u, fehlerhafte Botschaften %lu, Flags 0x%02X\n",
                d.rx_error_counter, static_cast<unsigned long>(d.error_events),
                d.error_flags);
  if (d.error_events > 0 || d.rx_error_counter > 0) {
    Serial.println("  Fehler bei wenig Verkehr: Bitrate, CAN-H/CAN-L vertauscht "
                   "oder Abschlusswiderstand zu viel?");
  }
  Serial.printf("Puffer hoechstens: %u von %u\n", d.ring_max_fill, d.ring_capacity);
  Serial.printf("Start Nr. %lu, Grund: %s\n", static_cast<unsigned long>(d.boot_count),
                boot_info::resetReasonText(d.reset_reason));
  Serial.printf("Handy verbunden: %s, gekoppelte Geraete: %d\n",
                ble_link::secureClientConnected() ? "ja" : "nein",
                ble_link::bondCount());
  Serial.printf("Kopplungsfenster: %s\n", s.pairing_open ? "offen" : "zu");
}

void printHelp() {
  Serial.println("Befehle:");
  Serial.println("  status   Zustand anzeigen");
  Serial.println("  pair     Kopplungsfenster fuer 2 Minuten oeffnen");
  Serial.println("  unpair   alle gekoppelten Handys loeschen");
  Serial.println("  help     diese Hilfe");
}

void handleLine(const char* line, uint32_t now) {
  if (strcmp(line, "pair") == 0) {
    const uint32_t code = g_pairing.open(now, esp_random());
    Serial.printf("Kopplungsfenster offen (2 Minuten). Code: %06lu\n",
                  static_cast<unsigned long>(code));
    Serial.println("Am Handy in der CAN-Werkbank verbinden und den Code eingeben.");
  } else if (strcmp(line, "unpair") == 0) {
    ble_link::deleteAllBonds();
    g_pairing.close();
    Serial.println("Alle Kopplungen geloescht.");
  } else if (strcmp(line, "status") == 0) {
    printStatus(now);
  } else if (line[0] != '\0') {
    printHelp();
  }
}

void pollConsole(uint32_t now) {
  while (Serial.available() > 0) {
    const int c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      g_line[g_line_len] = '\0';
      handleLine(g_line, now);
      g_line_len = 0;
    } else if (g_line_len + 1 < sizeof(g_line)) {
      g_line[g_line_len++] = static_cast<char>(c);
    }
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  boot_info::begin();
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);  // LED aus (aktiv low)

  g_can = new Mcp2515Receiver(config::kCanCsPin);
  g_can_ok = g_can->begin(config::kCanBitrate);
  if (g_can_ok) can_reader::start(g_can, config::kCanIntPin);

  ble_link::begin(&g_pairing);

  delay(1500);  // Zeit für den seriellen Monitor
  Serial.println();
  Serial.println("CAN-Leser (Stufe 1: nur mithoeren)");
  if (!g_can_ok) {
    Serial.printf("CAN-Controller antwortet nicht (CS-Pin %u). Steckt das "
                  "CAN-Board? CS-Pin in include/config.h pruefen.\n",
                  config::kCanCsPin);
  }
  printHelp();
}

void loop() {
  // Botschaften aus dem Ringpuffer der Lese-Aufgabe übernehmen. Die
  // Empfangszeit stammt von dort, Verzögerungen hier verfälschen den Takt
  // also nicht.
  can_core::TimedFrame item;
  while (can_reader::ring().pop(item)) {
    g_any_frame = true;
    g_last_frame_ms = item.time_ms;
    // Buslast über alle Botschaften, unabhängig vom Filter.
    g_load.add(can_core::frameBitsOnBus(item.frame), item.time_ms);
    if (g_filter.accepts(item.frame.id)) g_monitor.onFrame(item.frame, item.time_ms);
  }
  // Erst nach dem Leeren: Keine übernommene Botschaft ist dann jünger als
  // now (sonst liefe now - g_last_frame_ms über).
  const uint32_t now = millis();

  // LED leuchtet, solange Botschaften kommen.
  digitalWrite(LED_BUILTIN,
               g_any_frame && now - g_last_frame_ms < 200 ? LOW : HIGH);

  protocol::Command cmd;
  while (ble_link::takeCommand(cmd)) handleCommand(cmd);

  pollConsole(now);
  ble_link::poll(now);

  if (now - g_last_report_ms >= g_report_interval_ms) {
    g_last_report_ms = now;
    sendReports(now);
  }
  if (now - g_last_status_ms >= 1000) {
    g_last_status_ms = now;
    uint8_t buf[protocol::kStatusSize];
    const size_t len = protocol::encodeStatus(currentStatus(now), buf, sizeof(buf));
    ble_link::updateStatus(buf, len);
    uint8_t diag[protocol::kDiagnosticsSize];
    const size_t diag_len =
        protocol::encodeDiagnostics(currentDiagnostics(now), diag, sizeof(diag));
    ble_link::updateDiagnostics(diag, diag_len);
  }

  // Die Hauptschleife darf sich Zeit lassen: Empfangen tut die
  // Lese-Aufgabe, der Ringpuffer fasst gut 100 ms bei vollem Bus.
  delay(2);
}
