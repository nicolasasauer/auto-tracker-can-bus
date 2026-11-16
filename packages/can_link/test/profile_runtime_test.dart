import 'dart:io';
import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);

void main() {
  final profile = CanProfile.parse(
    File('profiles/peugeot_208_2016_hs_can.json').readAsStringSync(),
  );
  SignalDef sig(String name) => profile.signal(name)!.signal;

  test('Peugeot-Profil vollständig gelesen', () {
    expect(profile.title, 'Peugeot 208 (2016)');
    expect(profile.messages, hasLength(19));
    expect(profile.messages.expand((m) => m.signals), hasLength(57));
    expect(profile.message(0x208)!.name, 'ENGINE_1');
    expect(sig('engine_rpm').store!.agg, ['mean', 'max']);
    expect(sig('engine_torque_raw').store, isNull);
    expect(profile.ignoredIds, contains(0x608));
    expect(sig('engine_rpm').confidence, SignalConfidence.verified);
    expect(sig('shift_up_hint').confidence, SignalConfidence.guess);
  });

  test('Bits ab dem höchsten Bit von Byte 0 (wie in den Notizen)', () {
    // 0x412 B0 = 0010 0100: Bit5 Bremse, Bit2 Rückwärtsgang, Bit3 aus.
    final body = b([0x24, 0, 0, 0, 0, 0x5A, 0, 0]);
    expect(sig('brake_switch').valueFrom(body), 1);
    expect(sig('reverse_gear').valueFrom(body), 1);
    expect(sig('parking_brake').valueFrom(body), 0);
    expect(sig('coolant_temp_2').valueFrom(body), 50);
    // 0x348 B4 Bit3: kein Gang.
    expect(sig('no_gear_flag').valueFrom(b([0, 0, 0, 0, 0x08, 0, 0, 0])), 1);
  });

  test('mehrere Bytes, Vorzeichen, Faktor und Offset', () {
    expect(sig('engine_rpm').valueFrom(b([0x1B, 0x58, 0, 0, 0, 0, 0, 0])), 875);
    // −100 × 0,1 = −10 deg (rechts).
    expect(
      sig('steering_angle').valueFrom(b([0xFF, 0x9C, 0, 0, 0, 0, 0])),
      -10,
    );
    // Nullpunkt 175 im Stand.
    expect(sig('long_accel').valueFrom(b([0, 0, 0, 0, 175, 0, 0])), 0);
    expect(
      sig('odometer').valueFrom(b([0, 0, 0, 0, 0x01, 0xE2, 0x40, 0])),
      123456,
    );
    // 15-Bit-Feld ab Bit 0, der Zähler ab Bit 1.
    expect(
      sig('wheel_pulse_fl').rawFrom(b([0x12, 0x34, 0, 0, 0, 0, 0, 0])),
      2330,
    );
  });

  test('zu kurze Nutzdaten: kein Wert', () {
    expect(sig('odometer').valueFrom(b([0, 0, 0, 0, 1])), isNull);
  });

  test('Decoder: letzte Werte je Signal, unbekannte IDs gemerkt', () {
    final d = ProfileDecoder(profile);
    final changed = d.add(
      MonitorMessage(
        seq: 1,
        timeMs: 500,
        records: [
          IdRecord(rawId: 0x38D, data: b([0x13, 0x88, 0, 0, 175, 0, 0x77])),
          IdRecord(rawId: 0x228, data: b([0, 0, 0, 1])),
          IdRecord(rawId: 0x0B6, data: b([1, 2])),
        ],
      ),
    );
    expect(changed, isTrue);
    expect(d.values['vehicle_speed']!.value, closeTo(50, 1e-9));
    expect(d.values['vehicle_speed']!.timeMs, 500);
    expect(d.unknownIds, {0x0B6});
  });

  test('Kodieren ist das Gegenstück zum Dekodieren', () {
    for (final (name, v) in [
      ('steering_angle', -12.3),
      ('wheel_pulse_rl', 1234.0),
      ('long_accel', 1.2),
      ('brake_pressure_raw', 100.0),
    ]) {
      final data = Uint8List(8);
      sig(name).encodeInto(data, v);
      expect(sig(name).valueFrom(data), closeTo(v, 0.05), reason: name);
    }
  });

  test('Simulation nach Profil: Decoder liest Tempo und Gang', () async {
    final demo = ProfileDemoConnection(
      profile,
      interval: const Duration(hours: 1),
    );
    final d = ProfileDecoder(profile);
    final sub = demo.monitor.listen(d.add);
    demo.tick(6000);
    await Future<void>.delayed(Duration.zero);
    expect(d.values['vehicle_speed']!.value, closeTo(35 + 20 * 0.8415, 0.01));
    expect(d.values['gear']!.value, 3);
    expect(d.unknownIds, isEmpty);
    await sub.cancel();
    await demo.close();
  });

  test('Kodieren auch für Little Endian (wie DBC/Intel)', () {
    const s = SignalDef(
      name: 'x',
      start: 4,
      length: 12,
      byteOrder: SignalByteOrder.little,
      factor: 0.5,
    );
    final data = Uint8List(4);
    s.encodeInto(data, 1000.5);
    expect(s.valueFrom(data), 1000.5);
    // Niederwertigstes Bit ab Byte 0 Bit 4: 2001 = 0x7D1.
    expect(data.sublist(0, 2), [0x10, 0x7D]);
  });
}
