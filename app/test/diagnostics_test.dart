import 'package:can_link/can_link.dart';
import 'package:can_werkbank/src/bus_screen.dart';
import 'package:can_werkbank/src/diagnostics_screen.dart';
import 'package:can_werkbank/src/diagnostics_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DiagnosticsMessage diag({
  double load = 10,
  double peak = 20,
  int rec = 0,
  int errors = 0,
  int ringMax = 3,
  ResetReason reason = ResetReason.powerOn,
}) => DiagnosticsMessage(
  loadNowPct: load,
  loadAvgPct: load,
  loadPeakPct: peak,
  rxErrorCounter: rec,
  errorFlags: 0,
  errorEvents: errors,
  ringMaxFill: ringMax,
  ringCapacity: 512,
  resetReason: reason,
  bootCount: 4,
);

void main() {
  test('alles in Ordnung: keine Hinweise', () {
    expect(diagnosticsHints(diag()), isEmpty);
  });

  test('Hinweise je Problem', () {
    expect(diagnosticsHints(diag(errors: 1)).single, contains('Bitrate'));
    expect(diagnosticsHints(diag(rec: 8)).single, contains('Bitrate'));
    expect(diagnosticsHints(diag(peak: 50)).single, contains('MCP2515'));
    expect(diagnosticsHints(diag(peak: 49.9)), isEmpty);
    expect(diagnosticsHints(diag(ringMax: 256)).single, contains('50,0 %'));
    expect(
      diagnosticsHints(diag(reason: ResetReason.brownout)).single,
      contains('Spannungseinbruch'),
    );
    expect(
      diagnosticsHints(diag(reason: ResetReason.watchdog)).single,
      contains('Watchdog'),
    );
    expect(diagnosticsHints(diag(reason: ResetReason.software)), isEmpty);
  });

  test('Prozent mit Komma', () {
    expect(pct(12.34), '12,3 %');
    expect(pct(0), '0,0 %');
  });

  testWidgets('Diagnose-Seite zeigt Werte und Hinweise', (tester) async {
    final n = ValueNotifier<DiagnosticsMessage?>(null);
    await tester.pumpWidget(
      MaterialApp(home: DiagnosticsScreen(diagnostics: n)),
    );
    expect(find.textContaining('Noch keine Diagnose'), findsOneWidget);

    n.value = diag(
      load: 12.34,
      peak: 61,
      errors: 3,
      reason: ResetReason.brownout,
    );
    await tester.pump();
    expect(find.text('12,3 %'), findsNWidgets(2)); // aktuell und Mittel
    expect(find.text('61,0 %'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsNWidgets(3));
    // Neustarts stehen ganz unten.
    await tester.scrollUntilVisible(find.text('Letzter Grund'), 200);
    expect(find.text('Spannungseinbruch'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('aus der Sniff-Ansicht erreichbar, Last in der Statuszeile', (
    tester,
  ) async {
    final c = DemoConnection(interval: const Duration(days: 1));
    await tester.pumpWidget(MaterialApp(home: BusScreen(connection: c)));
    c.tick(200);
    await tester.pump();
    expect(find.textContaining('Last '), findsOneWidget);

    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnose'));
    await tester.pumpAndSettle();
    expect(find.text('Buslast'), findsOneWidget);
    expect(find.text('3 von 512'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('eingeschaltet'), 200);
    expect(find.text('eingeschaltet'), findsOneWidget);
  });
}
