import 'package:can_link/can_link.dart';
import 'package:can_werkbank/src/bus_screen.dart';
import 'package:can_werkbank/src/example_profiles.dart';
import 'package:can_werkbank/src/profile_screen.dart';
import 'package:can_werkbank/src/recordings_screen.dart';
import 'package:can_werkbank/src/workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Die Simulation bei t = 0,4 s: Tempo 51 km/h, Drehzahl 2724.

Future<DemoConnection> pumpBus(WidgetTester tester, Workbench workbench) async {
  // Hoch wie ein Handy, damit die ganze Signal-Seite aufgebaut wird.
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = DemoConnection(interval: const Duration(days: 1));
  await tester.pumpWidget(
    MaterialApp(
      home: BusScreen(connection: c, workbench: workbench),
    ),
  );
  c.tick(200);
  c.tick(200);
  await tester.pump();
  return c;
}

String valueText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('signalwert'))).data!;

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets('Signale aus dem Profil stehen als Wert unter den Bytes', (
    tester,
  ) async {
    await pumpBus(tester, Workbench()..setProfile(simulationProfile));
    expect(find.text('MOTOR'), findsOneWidget);
    expect(
      find.text('engine_rpm = 2724 rpm · vehicle_speed = 51 km/h'),
      findsOneWidget,
    );
  });

  testWidgets('angepinntes Signal steht oben und öffnet den Verlauf', (
    tester,
  ) async {
    final w = Workbench()..setProfile(simulationProfile);
    await pumpBus(tester, w);
    expect(find.byKey(const ValueKey('pin-vehicle_speed')), findsNothing);

    w.togglePin('vehicle_speed');
    await tester.pump();
    final card = find.byKey(const ValueKey('pin-vehicle_speed'));
    expect(
      find.descendant(of: card, matching: find.text('51 km/h')),
      findsOneWidget,
    );

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(valueText(tester), '51 km/h');
    expect(find.text('Rohwert 51 (0x33)'), findsOneWidget);
    expect(find.text('max 51 km/h'), findsOneWidget);
    expect(find.byTooltip('Lösen'), findsOneWidget);
  });

  testWidgets('Bits wählen, Signal anlegen, mit dem Faktor spielen', (
    tester,
  ) async {
    final w = Workbench();
    final c = await pumpBus(tester, w);
    await tester.tap(find.text('0B6'));
    await tester.pumpAndSettle();

    // Bytes 2 und 3: das Tempo.
    await tester.tap(find.byKey(const ValueKey('bit-2-7')));
    await tester.tap(find.byKey(const ValueKey('bit-3-0')));
    await tester.pump();
    expect(find.text('Auswahl: Start 16, 16 Bit = 51'), findsOneWidget);

    await tester.tap(find.text('Signal anlegen'));
    await tester.pumpAndSettle();
    expect(find.text('Neues Signal'), findsOneWidget);
    expect(valueText(tester), '51');
    expect(find.text('Byte 2 Bit 7 (höchstwertig) bis Byte 3 Bit 0'), findsOne);

    // Der Faktor wirkt sofort, ohne zu speichern.
    await tester.enterText(field('Faktor'), '0,5');
    await tester.pump();
    expect(valueText(tester), '25,5');
    expect(w.profile.isEmpty, isTrue);

    await tester.tap(find.text('× 10'));
    await tester.pump();
    expect(valueText(tester), '255');

    // Bitfeld verschieben: ein Bit weiter rechts ist der doppelte Rohwert.
    await tester.tap(find.byTooltip('Startbit +1'));
    await tester.pump();
    expect(find.text('Rohwert 102 (0x66)'), findsOneWidget);
    await tester.tap(find.byTooltip('Startbit −1'));
    await tester.pump();

    // Sollwert vom Tacho: 102 bei Rohwert 51 ergibt Faktor 2.
    await tester.tap(find.text('Faktor aus Sollwert'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Sollwert'), '102');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(valueText(tester), '102');

    await tester.enterText(field('Name'), 'tempo');
    await tester.enterText(field('Einheit'), 'km/h');
    await tester.tap(find.byTooltip('Speichern'));
    await tester.pump();
    final saved = w.profile.signal('tempo')!;
    expect(saved.message.rawId, 0x0B6);
    expect(saved.message.dlc, 8);
    expect(saved.signal.start, 16);
    expect(saved.signal.length, 16);
    expect(saved.signal.factor, 2);

    // Neue Daten kommen an, auch auf dieser Seite.
    c.tick(4000);
    await tester.pump();
    expect(valueText(tester), isNot('102 km/h'));

    // Zurück ohne Nachfrage, das Signal steht in der Detailansicht.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('tempo'), findsOneWidget);
    expect(find.text('Bit 16, 16 Bit · × 2 · Vermutung'), findsOneWidget);
  });

  testWidgets('ungespeicherte Änderung: Nachfrage beim Verlassen', (
    tester,
  ) async {
    final w = Workbench()..setProfile(simulationProfile);
    await pumpBus(tester, w);
    w.togglePin('vehicle_speed');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pin-vehicle_speed')));
    await tester.pumpAndSettle();

    await tester.enterText(field('Faktor'), '3');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Änderungen verwerfen?'), findsOneWidget);
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    expect(find.text('Neues Signal'), findsNothing);
    expect(w.profile.signal('vehicle_speed')!.signal.factor, 1);
  });

  testWidgets('doppelter Name wird beim Speichern abgelehnt', (tester) async {
    final w = Workbench()..setProfile(simulationProfile);
    await pumpBus(tester, w);
    await tester.tap(find.text('128'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signal anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Name'), 'engine_rpm');
    await tester.tap(find.byTooltip('Speichern'));
    await tester.pump();
    expect(find.textContaining('gibt es schon'), findsOneWidget);
    expect(w.profile.signalCount, simulationProfile.signalCount);
  });

  testWidgets('Aufnahme mit Marke, danach als KI-Paket teilen', (tester) async {
    final shared = <ShareItem>[];
    final w = Workbench(share: (items) async => shared.addAll(items));
    final c = await pumpBus(tester, w);

    await tester.tap(find.byTooltip('Aufnehmen'));
    await tester.pump();
    c.tick(200);
    c.tick(200);
    await tester.pump();
    expect(find.textContaining('● Aufnahme 00:00'), findsOneWidget);

    await tester.tap(find.text('Marke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blinker links'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 Marken'), findsOneWidget);

    c.tick(200);
    await tester.tap(find.text('Stopp'));
    await tester.pump();
    // Der Hinweis fährt von unten herein.
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('● Aufnahme'), findsNothing);
    expect(find.textContaining('Mitschnitt gespeichert'), findsOneWidget);

    final name = (await w.recordings.list()).single.name;
    final log = CanLog.parse(await w.recordings.read(name));
    expect(log.source, 'Simulation');
    expect(log.messages.length, 3);
    expect(log.marks.single.text, 'Blinker links');

    await tester.tap(find.text('Für KI teilen'));
    await tester.pump();
    expect(shared.map((i) => i.name), [
      name,
      'neu.profile.json',
      'KI-ANLEITUNG.md',
    ]);
  });

  testWidgets('Aufnahme läuft beim Anhalten der Ansicht weiter', (
    tester,
  ) async {
    final w = Workbench();
    final c = await pumpBus(tester, w);
    await tester.tap(find.byTooltip('Aufnehmen'));
    await tester.pump();
    await tester.tap(find.byTooltip('Anhalten'));
    await tester.pump();
    c.tick(200);
    c.tick(200);
    await tester.pump();
    expect(w.recorder.durationMs, 200);
    expect(w.recorder.rows, greaterThan(4));
  });

  group('Profil-Seite', () {
    Future<Workbench> pumpProfile(WidgetTester tester, {String? picked}) async {
      final w = Workbench(pickText: () async => picked);
      await tester.pumpWidget(MaterialApp(home: ProfileScreen(workbench: w)));
      return w;
    }

    testWidgets('Datei importieren', (tester) async {
      final w = await pumpProfile(tester, picked: simulationProfile.encode());
      expect(find.textContaining('Noch keine Signale'), findsOneWidget);
      await tester.tap(find.text('Datei importieren'));
      await tester.pumpAndSettle();
      expect(w.profile.signalCount, 4);
      expect(find.text('0B6 · MOTOR'), findsOneWidget);
      expect(find.text('coolant_temp'), findsOneWidget);
      expect(find.textContaining('1 noch nicht geprüft'), findsOneWidget);
    });

    testWidgets('fehlerhaftes Profil: Fehler werden gezeigt, nichts ändert '
        'sich', (tester) async {
      final w = await pumpProfile(
        tester,
        picked:
            '{"schema_version":1,"messages":[{"id":"0x208","dlc":2,'
            '"signals":[{"name":"x","start":8,"length":16}]}]}',
      );
      await tester.tap(find.text('Datei importieren'));
      await tester.pumpAndSettle();
      expect(find.text('Profil nicht lesbar'), findsOneWidget);
      expect(find.textContaining('passt nicht in 2 Byte'), findsOneWidget);
      expect(w.profile.isEmpty, isTrue);
    });

    testWidgets('aus der Zwischenablage, mit Nachfrage vor dem Ersetzen', (
      tester,
    ) async {
      final w = await pumpProfile(tester);
      w.saveSignal(0x208, const SignalDef(name: 'alt', start: 0, length: 8));
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'Antwort der KI:\n${simulationProfile.encode()}'}
            : null,
      );
      await tester.tap(find.text('Aus Zwischenablage'));
      await tester.pumpAndSettle();
      expect(find.text('Aktuelles Profil ersetzen?'), findsOneWidget);
      await tester.tap(find.text('Ersetzen'));
      await tester.pumpAndSettle();
      expect(w.profile.signal('alt'), isNull);
      expect(w.profile.signalCount, 4);
    });

    testWidgets('Beispiel Peugeot 208 laden und ein Signal öffnen', (
      tester,
    ) async {
      final w = await pumpProfile(tester);
      await tester.tap(find.byTooltip('Anderes Profil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beispiel: Peugeot 208 (2016)'));
      await tester.pumpAndSettle();
      expect(find.text('Peugeot 208 (2016)'), findsOneWidget);
      expect(w.profile.signal('steering_angle')!.signal.signed, isTrue);

      await tester.tap(find.text('engine_rpm'));
      await tester.pumpAndSettle();
      expect(valueText(tester), 'keine Verbindung');
      expect(
        tester.widget<TextField>(field('Faktor')).controller!.text,
        '0,125',
      );
    });
  });

  testWidgets('Mitschnitt abspielen: Profil wirkt auf die Aufnahme', (
    tester,
  ) async {
    final w = Workbench()..setProfile(simulationProfile);
    final writer = CanLogWriter(start: DateTime(2026), source: 'Test');
    final demo = DemoConnection(interval: const Duration(days: 1));
    final lines = [...writer.header()];
    demo.monitor.listen((m) => lines.addAll(writer.add(m)));
    demo
      ..tick(200)
      ..tick(200);
    await tester.pump();
    await demo.close();
    (await w.recordings.create('fahrt.csv')).write(lines);

    await tester.pumpWidget(MaterialApp(home: RecordingsScreen(workbench: w)));
    await tester.pumpAndSettle();
    expect(find.text('fahrt.csv'), findsOneWidget);

    await tester.tap(find.text('fahrt.csv'));
    // Die Wiedergabe läuft in Echtzeit.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Wiedergabe'), findsOneWidget);
    expect(
      find.text('engine_rpm = 2724 rpm · vehicle_speed = 51 km/h'),
      findsOneWidget,
    );
  });
}
