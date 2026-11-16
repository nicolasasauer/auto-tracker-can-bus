import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

MonitorMessage msg(int timeMs, int rawId, List<int> data) => MonitorMessage(
  seq: 0,
  timeMs: timeMs,
  records: [IdRecord(rawId: rawId, data: Uint8List.fromList(data))],
);

void main() {
  const high = SignalDef(name: 'h', start: 0, length: 8);
  const low = SignalDef(name: 'l', start: 8, length: 8);

  test('Verlauf lässt sich mit geändertem Startbit neu auswerten', () {
    final h = FrameHistory()
      ..add(msg(1000, 0x208, [1, 10]))
      ..add(msg(1200, 0x208, [2, 20]));
    expect(h.samples(0x208, high), [(tMs: 0, raw: 1), (tMs: 200, raw: 2)]);
    expect(h.samples(0x208, low).map((s) => s.raw), [10, 20]);
    expect(h.latest(0x208), [2, 20]);
    expect(h.samples(0x305, high), isEmpty);
  });

  test('Zeitfenster und Ringgröße', () {
    final h = FrameHistory(capacity: 3);
    for (var i = 0; i < 5; i++) {
      h.add(msg(i * 200, 0x208, [i, 0]));
    }
    // Nur die letzten drei bleiben.
    expect(h.samples(0x208, high).map((s) => s.raw), [2, 3, 4]);
    expect(h.samples(0x208, high, windowMs: 200).map((s) => s.raw), [3, 4]);
  });

  test('zu kurze Übersichten fehlen im Verlauf', () {
    final h = FrameHistory()
      ..add(msg(0, 0x208, [1]))
      ..add(msg(200, 0x208, [2, 20]));
    expect(h.samples(0x208, low), [(tMs: 200, raw: 20)]);
  });

  test('Neustart des Lesers: Zeit läuft weiter', () {
    final h = FrameHistory()
      ..add(msg(5000, 0x208, [1, 0]))
      ..add(msg(5200, 0x208, [2, 0]))
      ..add(msg(100, 0x208, [3, 0]));
    expect(h.samples(0x208, high).map((s) => s.tMs), [0, 200, 200]);
  });
}
