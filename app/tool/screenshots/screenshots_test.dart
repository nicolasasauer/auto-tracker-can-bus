// Erzeugt die Screenshots für die README nach docs/screenshots/.
//
//   cd app && flutter test tool/screenshots/screenshots_test.dart
//   (oder: bash tool/check.sh screenshots)
//
// Nur Simulation und Simulationsprofil: Die Botschaften sind erfunden,
// nichts stammt aus einer echten Fahrt. Liegt bewusst nicht unter test/,
// damit `flutter test` die Bilder nicht bei jedem Lauf neu schreibt.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:can_link/can_link.dart';
import 'package:can_werkbank/main.dart';
import 'package:can_werkbank/src/bus_screen.dart';
import 'package:can_werkbank/src/example_profiles.dart';
import 'package:can_werkbank/src/recordings_screen.dart';
import 'package:can_werkbank/src/workbench.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Handyformat 1 : 2 in logischen Pixeln; gespeichert mit [_pixelRatio].
const _logicalSize = Size(400, 800);
const _pixelRatio = 2.0;
final _outDir = Directory('../docs/screenshots');

Future<void> _loadFonts() async {
  // flutter_tester liegt unter <root>/bin/cache/artifacts/engine/<plattform>/.
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent.parent.parent.path;
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  // IDs und Bytes setzt die App in „monospace“. Ohne diese Schrift
  // erscheinen sie als Kästen; DejaVu liegt auf Ubuntu und Debian bereit.
  final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  if (mono.existsSync()) {
    final loader = FontLoader('monospace')
      ..addFont(Future.value(ByteData.sublistView(mono.readAsBytesSync())));
    await loader.load();
  }
}

/// Die Simulation tickt nur von Hand, damit jedes Bild gleich aussieht.
DemoConnection _simulation() =>
    DemoConnection(interval: const Duration(days: 1));

Workbench _workbench() {
  final w = Workbench()..setProfile(simulationProfile);
  w
    ..togglePin('engine_rpm')
    ..togglePin('vehicle_speed');
  return w;
}

void main() {
  final key = GlobalKey();

  setUpAll(() async {
    await _loadFonts();
    WidgetsApp.debugAllowBannerOverride = false;
  });
  tearDownAll(() => WidgetsApp.debugAllowBannerOverride = true);

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 500));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    _outDir.createSync(recursive: true);
    File('${_outDir.path}/$name.png').writeAsBytesSync(bytes!);
  }

  Future<void> setUp(WidgetTester tester) async {
    tester.view.physicalSize = _logicalSize * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);
  }

  testWidgets('Startseite', (tester) async {
    await setUp(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: CanWerkbankApp(workbench: _workbench()),
      ),
    );
    await shoot(tester, 'start');
  });

  testWidgets('Sniff-Ansicht, Bitraster, Signal', (tester) async {
    await setUp(tester);
    final connection = _simulation();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5)),
          home: BusScreen(connection: connection, workbench: _workbench()),
        ),
      ),
    );
    // Eine Minute Simulation, damit Takt, Zähler und Verläufe gefüllt sind.
    for (var i = 0; i < 300; i++) {
      connection.tick(200);
      if (i % 10 == 0) await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump();
    await shoot(tester, 'sniff');

    await tester.tap(find.text('0B6').first);
    await tester.pumpAndSettle();
    connection.tick(200);
    await tester.pump();
    await shoot(tester, 'bitraster');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('engine_rpm').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      connection.tick(200);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await shoot(tester, 'signal');
  });

  testWidgets('Mitschnitt für die KI teilen', (tester) async {
    await setUp(tester);
    final w = _workbench();
    // Feste Zeit statt der echten: Sie steht im Dateinamen des Mitschnitts.
    final connection = _simulation();
    final sub = connection.monitor.listen(w.recorder.add);
    await withClock(
      Clock.fixed(DateTime(2026, 1, 1, 10)),
      () => w.recorder.start(connection.name),
    );
    for (var i = 0; i < 300; i++) {
      connection.tick(200);
      if (i == 100) w.recorder.mark('Blinker links');
      await tester.pump();
    }
    await w.recorder.stop();
    // Nicht abwarten: Das Abmelden wird in der Testzeit nie fertig.
    unawaited(sub.cancel());
    // Beendet auch den Takt der Simulation (sonst bleibt ein Timer offen).
    unawaited(connection.close());
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5)),
          home: RecordingsScreen(workbench: w),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await shoot(tester, 'ki-teilen');
  });
}
