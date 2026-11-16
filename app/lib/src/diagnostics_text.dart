import 'package:can_link/can_link.dart';

/// Prozent mit Komma, eine Nachkommastelle.
String pct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} %';

String resetReasonText(ResetReason r) => switch (r) {
  ResetReason.powerOn => 'eingeschaltet',
  ResetReason.brownout => 'Spannungseinbruch',
  ResetReason.software => 'Neustart durch Firmware',
  ResetReason.panic => 'Absturz',
  ResetReason.watchdog => 'Watchdog',
  ResetReason.deepSleep => 'Aufwachen aus dem Tiefschlaf',
  ResetReason.external => 'Reset-Taste oder USB',
  ResetReason.other => 'sonstiges',
  ResetReason.unknown => 'unbekannt',
};

/// Ab dieser Buslast wird der MCP2515 mit seinen zwei Empfangspuffern knapp.
const loadWarnPct = 50.0;

/// Ab diesem Anteil des Zwischenpuffers ist die Reserve knapp.
const ringWarnShare = 0.5;

/// Hinweise zur Diagnose, leer wenn alles in Ordnung ist.
List<String> diagnosticsHints(DiagnosticsMessage d) => [
  if (d.errorEvents > 0 || d.rxErrorCounter > 0)
    'Empfangsfehler: Bitrate, vertauschte CAN-H/CAN-L-Leitungen oder ein '
        'Abschlusswiderstand zu viel? Bei wenig Verkehr sollten keine '
        'Fehler auftreten.',
  if (d.loadPeakPct >= loadWarnPct)
    'Buslast über ${pct(loadWarnPct)}: Die zwei Empfangspuffer des MCP2515 '
        'werden knapp. Der im ESP32-C6 eingebaute CAN-Controller hätte mehr '
        'Reserve.',
  if (d.ringMaxShare >= ringWarnShare)
    'Zwischenpuffer war zu ${pct(d.ringMaxShare * 100)} belegt: Die '
        'Hauptschleife des Lesers kommt kaum hinterher.',
  if (d.resetReason == ResetReason.brownout)
    'Letzter Neustart durch Spannungseinbruch, z. B. beim Motorstart. Die '
        'Versorgung braucht mehr Puffer.',
  if (d.resetReason == ResetReason.panic ||
      d.resetReason == ResetReason.watchdog)
    'Letzter Neustart durch ${resetReasonText(d.resetReason)}: ein Fehler '
        'in der Firmware.',
];
