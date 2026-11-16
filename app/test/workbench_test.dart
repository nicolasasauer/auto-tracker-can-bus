import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:can_werkbank/src/ai_prompt.dart';
import 'package:can_werkbank/src/recorder.dart';
import 'package:can_werkbank/src/workbench.dart';
import 'package:flutter_test/flutter_test.dart';

MonitorMessage msg(int seq, int timeMs, List<int> data) => MonitorMessage(
  seq: seq,
  timeMs: timeMs,
  records: [IdRecord(rawId: 0x208, data: Uint8List.fromList(data))],
);

void main() {
  const rpm = SignalDef(name: 'engine_rpm', start: 0, length: 16);

  group('Profil des Peugeot 208 gegen erzeugte Botschaften', () {
    // Erzeugte Daten statt eines echten Mitschnitts: Ein Mitschnitt mit
    // Tempo, Lenkwinkel und Gierrate zeichnet die Strecke nach, und andere
    // IDs tragen die Fahrgestellnummer. Deshalb steht die erwartete Bitlage
    // hier noch einmal, unabhängig vom Profil, und ein eigener Kodierer
    // packt die Rohwerte. Weicht das Profil ab, passt der Wert nicht mehr.
    final profile = CanProfile.parse(
      File('assets/profiles/peugeot_208_2016.profile.json').readAsStringSync(),
    );

    // Name: (CAN-ID, Startbit ab MSB von Byte 0, Länge, vorzeichenbehaftet,
    // Faktor, Offset). Alle Signale sind Big Endian.
    const layout = {
      'engine_rpm': (0x208, 0, 16, false, 0.125, 0.0),
      'engine_torque_raw': (0x208, 16, 8, false, 1.0, 0.0),
      'accel_pedal_raw': (0x208, 24, 8, false, 1.0, 0.0),
      'brake_pedal': (0x208, 38, 1, false, 1.0, 0.0),
      'steering_angle': (0x305, 0, 16, true, 0.1, 0.0),
      'wheel_speed_fl': (0x30D, 0, 16, false, 0.01, 0.0),
      'wheel_speed_fr': (0x30D, 16, 16, false, 0.01, 0.0),
      'wheel_speed_rl': (0x30D, 32, 16, false, 0.01, 0.0),
      'wheel_speed_rr': (0x30D, 48, 16, false, 0.01, 0.0),
      'gear': (0x348, 0, 4, false, 1.0, 0.0),
      'vehicle_speed': (0x38D, 0, 16, false, 0.01, 0.0),
      'distance_counter': (0x38D, 16, 16, false, 0.1, 0.0),
      'yaw_rate': (0x3CD, 16, 16, true, 0.1, 0.0),
      'brake_pressure_raw': (0x3CD, 40, 12, false, 1.0, -550.0),
    };

    // Schreibt [raw] (Zweierkomplement bei negativen Werten) MSB zuerst ab
    // Bit [start]; Bit 0 ist das höchstwertige Bit von Byte 0.
    void put(Uint8List data, int start, int length, int raw) {
      final bits = raw & ((1 << length) - 1);
      for (var i = 0; i < length; i++) {
        final pos = start + i;
        final bit = (bits >> (length - 1 - i)) & 1;
        final mask = 1 << (7 - pos % 8);
        data[pos ~/ 8] = bit == 1
            ? data[pos ~/ 8] | mask
            : data[pos ~/ 8] & ~mask;
      }
    }

    test('alle Signale ergeben die erwarteten Werte', () {
      final random = Random(208);
      var checked = 0;
      for (var step = 0; step < 500; step++) {
        // Je CAN-ID eine Botschaft mit zufälligen Füllbytes, darüber die
        // Signale. Die ersten Schritte prüfen die Grenzen des Wertebereichs.
        final frames = <int, Uint8List>{};
        final expected = <String, double>{};
        for (final MapEntry(key: name, value: l) in layout.entries) {
          final (id, start, length, signed, factor, offset) = l;
          final data = frames.putIfAbsent(
            id,
            () => Uint8List.fromList([
              for (var i = 0; i < 8; i++) random.nextInt(256),
            ]),
          );
          final lo = signed ? -(1 << (length - 1)) : 0;
          final hi = signed ? (1 << (length - 1)) - 1 : (1 << length) - 1;
          final raw = switch (step) {
            0 => lo,
            1 => hi,
            2 => 0,
            _ => lo + random.nextInt(hi - lo + 1),
          };
          put(data, start, length, raw);
          expected[name] = raw * factor + offset;
        }
        for (final MapEntry(key: name, value: want) in expected.entries) {
          final ref = profile.signal(name);
          expect(ref, isNotNull, reason: '$name fehlt im Profil');
          final id = layout[name]!.$1;
          expect(ref!.message.id, id, reason: '$name: CAN-ID');
          final dlc = ref.message.dlc ?? 8;
          final data = Uint8List.sublistView(frames[id]!, 0, dlc);
          expect(
            ref.signal.valueFrom(data),
            closeTo(want, 1e-6),
            reason: '$name in Schritt $step',
          );
          checked++;
        }
      }
      expect(checked, 500 * layout.length);
    });

    test('Wegzähler: Differenz zum Start, über den Überlauf hinweg', () {
      final ref = profile.signal('distance_counter')!;
      final wrap = 65536 * ref.signal.factor;
      final random = Random(38);
      // Zähler kurz vor dem Überlauf, danach bis 30 m je Schritt.
      var counter = 65000;
      var driven = 0;
      double? first;
      var wrapped = false;
      for (var step = 0; step < 200; step++) {
        final data = Uint8List(7);
        put(data, 16, 16, counter % 65536);
        final value = ref.signal.valueFrom(data)!;
        first ??= value;
        expect(
          (value - first) % wrap,
          closeTo(driven / 10, 1e-6),
          reason: 'Schritt $step',
        );
        final add = random.nextInt(301);
        driven += add;
        counter += add;
        if (counter >= 65536) wrapped = true;
      }
      expect(wrapped, isTrue, reason: 'Überlauf nicht erreicht');
    });
  });

  group('Arbeitsstand', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('werkbank_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Profil und Pins überstehen einen Neustart', () async {
      final w = await Workbench.open(dir);
      w.saveSignal(0x208, rpm, dlc: 8);
      w.togglePin('engine_rpm');
      await w.saved;

      final again = await Workbench.open(dir);
      expect(again.profile.signal('engine_rpm')!.message.dlc, 8);
      expect(again.pinned, ['engine_rpm']);
    });

    test('kaputte Profildatei verhindert den Start nicht', () async {
      File('${dir.path}/profil.json').writeAsStringSync('{ kaputt');
      final w = await Workbench.open(dir);
      expect(w.profile.isEmpty, isTrue);
    });

    test('Mitschnitt landet als Datei im App-Ordner', () async {
      final w = await Workbench.open(dir);
      await w.recorder.start('Test');
      w.recorder
        ..add(msg(0, 0, [1, 2]))
        ..mark('Bremse')
        ..add(msg(1, 200, [1, 3]));
      final name = await w.recorder.stop();

      final list = await w.recordings.list();
      expect(list.single.name, name);
      final log = CanLog.parse(await w.recordings.read(name!));
      expect(log.messages.length, 2);
      expect(log.marks.single.text, 'Bremse');
      expect(File(w.recordings.pathOf(name)!).existsSync(), isTrue);

      await w.recordings.delete(name);
      expect(await w.recordings.list(), isEmpty);
    });
  });

  group('Pins und Umbenennen', () {
    test('Pin folgt dem neuen Namen, Löschen entfernt ihn', () {
      final w = Workbench()
        ..saveSignal(0x208, rpm)
        ..togglePin('engine_rpm')
        ..saveSignal(
          0x208,
          rpm.copyWith(name: 'drehzahl'),
          replaces: 'engine_rpm',
        );
      expect(w.pinned, ['drehzahl']);
      expect(w.pinnedSignals.single.signal.name, 'drehzahl');
      w.deleteSignal('drehzahl');
      expect(w.pinned, isEmpty);
    });

    test('neues Profil behält nur Pins auf vorhandene Signale', () {
      final w = Workbench()
        ..saveSignal(0x208, rpm)
        ..saveSignal(0x208, const SignalDef(name: 'b', start: 16, length: 8))
        ..togglePin('engine_rpm')
        ..togglePin('b')
        ..setProfile(const CanProfile().withSignal(0x208, rpm));
      expect(w.pinned, ['engine_rpm']);
    });
  });

  group('Teilen', () {
    test('Paket für die KI: Mitschnitt, Profil, Anleitung', () async {
      final shared = <ShareItem>[];
      final w = Workbench(share: (items) async => shared.addAll(items))
        ..saveSignal(0x208, rpm);
      await w.recorder.start('Test');
      w.recorder.add(msg(0, 0, [1, 2]));
      final name = (await w.recorder.stop())!;

      await w.shareForAi(name);
      expect(shared.map((i) => i.name), [
        name,
        'neu.profile.json',
        'KI-ANLEITUNG.md',
      ]);
      expect(shared[0].text, contains('0;208;2;01 02'));
      // Das geteilte Profil lässt sich wieder einlesen.
      expect(CanProfile.parse(shared[1].text!).signalCount, 1);
      expect(shared[2].text, contains(name));
    });

    // Das Beispiel in der Anleitung ist das, woran sich die KI hält. Es muss
    // selbst ein gültiges Profil sein.
    test('Beispielprofil in der Anleitung ist gültig', () {
      final text = aiInstructions(recording: 'a.csv', profile: 'p.json');
      final json = text.substring(
        text.indexOf('```json') + 7,
        text.indexOf('```', text.indexOf('```json') + 7),
      );
      expect(CanProfile.parse(json).signal('engine_rpm'), isNotNull);
    });
  });

  test('Mitschnitt im Speicher: neueste zuerst', () async {
    final store = MemoryRecordingStore();
    (await store.create('a.csv')).write(['x']);
    (await store.create('b.csv')).write(['y']);
    expect((await store.list()).map((r) => r.name), ['b.csv', 'a.csv']);
    expect(await store.read('a.csv'), 'x\n');
  });
}
