import 'package:can_link/can_link.dart';
import 'package:can_werkbank/src/bus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DemoConnection> pumpBus(WidgetTester tester) async {
  // Simulation ohne eigenen Takt: Der Test schaltet von Hand weiter.
  final c = DemoConnection(interval: const Duration(days: 1));
  await tester.pumpWidget(MaterialApp(home: BusScreen(connection: c)));
  c.tick(200);
  c.tick(200);
  await tester.pump();
  return c;
}

void main() {
  testWidgets('zeigt CAN-IDs und erkannte OBD-Werte', (tester) async {
    await pumpBus(tester);
    expect(find.text('0B6'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('7E8'), findsOneWidget);
    expect(find.textContaining('OBD: Geschwindigkeit ='), findsOneWidget);
    expect(find.textContaining('nur mithören'), findsOneWidget);
  });

  testWidgets('geänderte Bytes leuchten auf und verblassen', (tester) async {
    await pumpBus(tester);
    expect(find.byKey(const ValueKey('geaendert')), findsWidgets);
    await tester.pump(highlightDuration + const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('geaendert')), findsNothing);
  });

  testWidgets('Suche nach CAN-ID', (tester) async {
    await pumpBus(tester);
    await tester.enterText(find.byType(TextField), '7e');
    await tester.pump();
    expect(find.text('7E8'), findsOneWidget);
    expect(find.text('0B6'), findsNothing);
  });

  testWidgets('Anhalten friert die Ansicht ein', (tester) async {
    final c = await pumpBus(tester);
    await tester.tap(find.byTooltip('Anhalten'));
    await tester.pump();
    final before = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    c.tick(5000);
    await tester.pump();
    final after = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    // Nur die Statuszeile darf sich ändern, die ID-Liste nicht.
    expect(
      after.where((t) => t != null && t.contains('×')),
      before.where((t) => t != null && t.contains('×')),
    );
  });

  // Der Fehler: Nach dem Anhalten stand „Übersichten verloren (BLE)“ in der
  // Statuszeile, obwohl nichts verloren ging.
  testWidgets('Anhalten zählt nicht als BLE-Verlust', (tester) async {
    final c = await pumpBus(tester);
    await tester.tap(find.byTooltip('Anhalten'));
    await tester.pump();
    c.tick(200);
    c.tick(200);
    await tester.pump();
    await tester.tap(find.byTooltip('Weiter'));
    await tester.pump();
    c.tick(200);
    await tester.pump();
    expect(find.textContaining('Botschaften'), findsWidgets);
    expect(find.textContaining('Übersichten verloren'), findsNothing);
  });

  testWidgets('Änderungssuche zeigt nur, was sich seit der Markierung ändert', (
    tester,
  ) async {
    final c = await pumpBus(tester);
    // Bis zur vollen Sekunde: Dann kommt auch die langsame ID 0F6.
    c.tick(600);
    await tester.pump();
    expect(find.text('0F6'), findsOneWidget);
    await tester.tap(find.byTooltip('Änderungen suchen'));
    await tester.pump();
    expect(
      find.textContaining('Seit der Markierung hat sich nichts geändert'),
      findsOneWidget,
    );
    expect(find.text('128'), findsNothing);

    // 400 ms weiter: Der Blinker (128) wechselt, 0F6 kommt nicht.
    c.tick(400);
    await tester.pump();
    expect(find.text('128'), findsOneWidget);
    expect(find.text('0F6'), findsNothing);
    expect(find.textContaining('Änderungen seit'), findsOneWidget);

    await tester.tap(find.text('Beenden'));
    await tester.pump();
    expect(find.text('0F6'), findsOneWidget);
    expect(find.textContaining('Änderungen seit'), findsNothing);
  });

  testWidgets(
    'Detailansicht zeigt bei Änderungssuche die Bits seit Markierung',
    (tester) async {
      final c = await pumpBus(tester);
      await tester.tap(find.byTooltip('Änderungen suchen'));
      await tester.pump();
      c.tick(400);
      await tester.pump();
      await tester.tap(find.text('128'));
      await tester.pumpAndSettle();
      expect(find.textContaining('seit der Markierung'), findsOneWidget);
    },
  );

  testWidgets('Zurücksetzen leert die Ansicht und schickt den Befehl', (
    tester,
  ) async {
    final c = await pumpBus(tester);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zurücksetzen'));
    await tester.pumpAndSettle();
    expect(c.sentCommands.single, CanLinkCommands.resetStats());
    expect(find.text('Noch keine Botschaften.'), findsOneWidget);
  });

  testWidgets('Detailansicht mit Bitraster', (tester) async {
    await pumpBus(tester);
    await tester.tap(find.text('128'));
    await tester.pumpAndSettle();
    expect(find.text('CAN-ID 128'), findsOneWidget);
    expect(find.text('Byte 0'), findsOneWidget);
    expect(find.text('Byte 3'), findsOneWidget);
  });
}
