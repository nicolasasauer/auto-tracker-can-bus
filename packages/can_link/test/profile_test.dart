import 'dart:convert';
import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

String profileJson(List<Map<String, Object?>> signals, {int dlc = 8}) =>
    jsonEncode({
      'profile_id': 'test',
      'schema_version': 1,
      'vehicle': {'make': 'Peugeot', 'model': '208', 'year': 2016},
      'messages': [
        {'id': '0x208', 'name': 'ENGINE_1', 'dlc': dlc, 'signals': signals},
      ],
    });

void main() {
  group('Dekodierung', () {
    // Werte von Hand nach dem Referenz-Decoder des Briefings gerechnet.
    test('Big Endian ohne Vorzeichen: Drehzahl 0x1F40 × 0,125', () {
      const rpm = SignalDef(
        name: 'engine_rpm',
        start: 0,
        length: 16,
        factor: 0.125,
      );
      expect(rpm.valueFrom(bytes([0x1F, 0x40, 0, 0, 0, 0, 0, 0])), 1000);
    });

    test('Big Endian mit Vorzeichen: Lenkwinkel 0xFF9C × 0,1 = −10', () {
      const angle = SignalDef(
        name: 'steering_angle',
        start: 0,
        length: 16,
        signed: true,
        factor: 0.1,
      );
      expect(
        angle.valueFrom(bytes([0xFF, 0x9C, 0, 0, 0, 0, 0])),
        closeTo(-10, 1e-9),
      );
      expect(angle.rawFrom(bytes([0x7F, 0xFF, 0, 0, 0, 0, 0])), 32767);
    });

    test('einzelnes Bit: Bremspedal an Bit 38 ist Byte 4 Bit 1', () {
      const brake = SignalDef(name: 'brake_pedal', start: 38, length: 1);
      expect(brake.rawFrom(bytes([0, 0, 0, 0, 0x02, 0, 0, 0])), 1);
      expect(
        brake.rawFrom(bytes([0xFF, 0xFF, 0xFF, 0xFF, 0xFD, 0xFF, 0xFF, 0xFF])),
        0,
      );
    });

    test('über Bytegrenzen mit Offset: Bremsdruck 0x226 − 550 = 0', () {
      const pressure = SignalDef(
        name: 'brake_pressure_raw',
        start: 40,
        length: 12,
        offset: -550,
      );
      expect(pressure.valueFrom(bytes([0, 0, 0, 0, 0, 0x22, 0x6F, 0])), 0);
    });

    test('halbes Byte: Gang in den oberen 4 Bit', () {
      const gear = SignalDef(name: 'gear', start: 0, length: 4);
      expect(gear.rawFrom(bytes([0x3F, 0, 0, 0, 0, 0, 0, 0])), 3);
    });

    test('Little Endian wie DBC/Intel', () {
      const word = SignalDef(
        name: 'w',
        start: 8,
        length: 16,
        byteOrder: SignalByteOrder.little,
      );
      expect(word.rawFrom(bytes([0, 0x34, 0x12, 0])), 0x1234);
      // Nicht an der Bytegrenze: Bits 4–11.
      const odd = SignalDef(
        name: 'o',
        start: 4,
        length: 8,
        byteOrder: SignalByteOrder.little,
      );
      expect(odd.rawFrom(bytes([0xA0, 0x0B])), 0xBA);
      expect(odd.bitPositions, [12, 13, 14, 15, 0, 1, 2, 3]);
    });

    test('zu kurze Botschaft ergibt keinen Wert', () {
      const s = SignalDef(name: 's', start: 48, length: 16);
      expect(s.rawFrom(bytes([1, 2, 3, 4, 5, 6, 7])), isNull);
    });

    test('Anzeige: Nachkommastellen nach dem Faktor, Komma, Einheit', () {
      const rpm = SignalDef(
        name: 'engine_rpm',
        start: 0,
        length: 16,
        factor: 0.125,
        unit: 'rpm',
      );
      expect(rpm.format(1000.5), '1000,500 rpm');
      const gear = SignalDef(name: 'gear', start: 0, length: 4);
      expect(gear.format(3), '3');
    });
  });

  group('Profil lesen', () {
    test('liest Signale und behält unbekannte Felder', () {
      final p = CanProfile.parse(
        profileJson([
          {
            'name': 'engine_rpm',
            'start': 0,
            'length': 16,
            'signed': false,
            'factor': 0.125,
            'offset': 0,
            'unit': 'rpm',
            'confidence': 'verified',
            'store': {'mode': 'sample', 'interval_s': 1},
          },
        ]),
      );
      expect(p.vehicleLabel, 'Peugeot 208 (2016)');
      final ref = p.signal('engine_rpm')!;
      expect(ref.message.rawId, 0x208);
      expect(ref.signal.confidence, SignalConfidence.verified);

      final again = jsonDecode(p.encode()) as Map<String, Object?>;
      final message = (again['messages']! as List).single as Map;
      final signal = (message['signals'] as List).single as Map;
      expect(signal['store'], {'mode': 'sample', 'interval_s': 1});
      expect(signal['factor'], 0.125);
      expect(signal['offset'], 0);
      expect(again['vehicle'], {
        'make': 'Peugeot',
        'model': '208',
        'year': 2016,
      });
    });

    test('findet das JSON in einer KI-Antwort mit Text drumherum', () {
      final json = profileJson([
        {'name': 'gear', 'start': 0, 'length': 4},
      ]);
      final p = CanProfile.parse(
        'Hier ist das Profil:\n```json\n$json\n```\nViel Erfolg!',
      );
      expect(p.signalCount, 1);
      expect(p.signal('gear')!.signal.confidence, SignalConfidence.guess);
    });

    test('meldet alle Fehler auf einmal', () {
      final json = profileJson(dlc: 7, [
        {'name': 'a', 'start': 48, 'length': 16},
        {'name': 'b', 'start': 0, 'length': 8},
        {'name': 'b', 'start': 8, 'length': 8},
        {'name': 'c', 'start': 0, 'length': 8, 'confidence': 'sicher'},
        {
          'name': 'd',
          'start': 0,
          'length': 8,
          'store': {'mode': 'immer'},
        },
        {'name': 'e', 'start': 0, 'length': 0},
      ]);
      expect(
        () => CanProfile.parse(json),
        throwsA(
          isA<ProfileFormatException>().having((e) => e.problems, 'problems', [
            contains('passt nicht in 7 Byte'),
            contains('confidence'),
            contains('store.mode'),
            contains('„length“ muss 1 bis'),
            contains('„b“ ist doppelt'),
          ]),
        ),
      );
    });

    test('lehnt falsche Schema-Version und Nicht-JSON ab', () {
      expect(
        () => CanProfile.parse('{"schema_version": 2, "messages": []}'),
        throwsA(isA<ProfileFormatException>()),
      );
      expect(
        () => CanProfile.parse('kein Profil'),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('29-Bit-ID bekommt das Erweitert-Bit', () {
      final p = CanProfile.parse(
        '{"schema_version":1,"messages":[{"id":"0x18DAF110","signals":[]}]}',
      );
      expect(p.messages.single.extended, isTrue);
      expect(p.messages.single.label, '18DAF110');
    });
  });

  group('Profil bearbeiten', () {
    const rpm = SignalDef(name: 'engine_rpm', start: 0, length: 16);

    test('legt Botschaft und Signal an, ersetzt am selben Platz', () {
      var p = const CanProfile().withSignal(0x208, rpm, dlc: 8);
      p = p.withSignal(0x208, const SignalDef(name: 'b', start: 16, length: 8));
      expect(p.messages.single.dlc, 8);

      p = p.withSignal(
        0x208,
        rpm.copyWith(name: 'drehzahl', factor: 0.125),
        replaces: 'engine_rpm',
      );
      expect(p.messages.single.signals.map((s) => s.name), ['drehzahl', 'b']);
      expect(p.signal('drehzahl')!.signal.factor, 0.125);
    });

    test('doppelter Name und zu langes Bitfeld werden abgelehnt', () {
      final p = const CanProfile().withSignal(0x208, rpm, dlc: 4);
      expect(
        () => p.withSignal(0x305, rpm),
        throwsA(isA<ProfileFormatException>()),
      );
      expect(
        () => p.withSignal(
          0x208,
          const SignalDef(name: 'x', start: 24, length: 16),
        ),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('Signal löschen', () {
      final p = const CanProfile()
          .withSignal(0x208, rpm)
          .withoutSignal('engine_rpm');
      expect(p.isEmpty, isTrue);
    });
  });
}
