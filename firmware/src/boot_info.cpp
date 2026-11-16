#include "boot_info.h"

#include <Preferences.h>
#include <esp_system.h>

namespace boot_info {
namespace {

using can_core::protocol::ResetReason;

ResetReason g_reason = ResetReason::kUnknown;
uint32_t g_boots = 0;

ResetReason map(esp_reset_reason_t r) {
  switch (r) {
    case ESP_RST_POWERON: return ResetReason::kPowerOn;
    case ESP_RST_BROWNOUT: return ResetReason::kBrownout;
    case ESP_RST_SW: return ResetReason::kSoftware;
    case ESP_RST_PANIC: return ResetReason::kPanic;
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT: return ResetReason::kWatchdog;
    case ESP_RST_DEEPSLEEP: return ResetReason::kDeepSleep;
    case ESP_RST_EXT:
    case ESP_RST_USB: return ResetReason::kExternal;
    case ESP_RST_UNKNOWN: return ResetReason::kUnknown;
    default: return ResetReason::kOther;
  }
}

}  // namespace

void begin() {
  g_reason = map(esp_reset_reason());
  Preferences prefs;
  if (prefs.begin("can_logger", false)) {
    g_boots = prefs.getUInt("boots", 0) + 1;
    prefs.putUInt("boots", g_boots);
    prefs.end();
  }
}

ResetReason resetReason() { return g_reason; }

uint32_t bootCount() { return g_boots; }

const char* resetReasonText(ResetReason r) {
  switch (r) {
    case ResetReason::kPowerOn: return "eingeschaltet";
    case ResetReason::kBrownout: return "Spannungseinbruch";
    case ResetReason::kSoftware: return "Neustart durch Firmware";
    case ResetReason::kPanic: return "Absturz";
    case ResetReason::kWatchdog: return "Watchdog";
    case ResetReason::kDeepSleep: return "Tiefschlaf";
    case ResetReason::kExternal: return "Reset-Taste/USB";
    case ResetReason::kOther: return "sonstiges";
    case ResetReason::kUnknown: break;
  }
  return "unbekannt";
}

}  // namespace boot_info
