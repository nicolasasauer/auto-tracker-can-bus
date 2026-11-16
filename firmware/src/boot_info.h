// Neustartgrund und Zahl der Starts. Wichtig im Auto: Beim Motorstart
// bricht die Bordspannung kurz ein; ob der Leser das übersteht, zeigt sich
// hier (Grund „Spannungseinbruch“).
#pragma once

#include <stdint.h>

#include "protocol.h"

namespace boot_info {

// Einmal in setup() aufrufen: liest den Grund und zählt den Start im
// nichtflüchtigen Speicher (NVS) hoch.
void begin();

can_core::protocol::ResetReason resetReason();
uint32_t bootCount();
const char* resetReasonText(can_core::protocol::ResetReason r);

}  // namespace boot_info
