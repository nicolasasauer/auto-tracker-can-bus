import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

IdRecord rec(int rawId, List<int> data, {List<int>? changed, int frames = 1}) =>
    IdRecord(
      rawId: rawId,
      data: Uint8List.fromList(data),
      changed: changed == null ? null : Uint8List.fromList(changed),
      frames: frames,
    );

MonitorMessage msg(int seq, List<IdRecord> records) =>
    MonitorMessage(seq: seq, timeMs: 0, records: records);

void main() {
  test('sammelt IDs, sortiert 11 Bit vor 29 Bit', () {
    final v = BusView();
    v.add(
      msg(0, [
        rec(0x200, [1]),
        rec(0x100 | CanLinkProtocol.extendedFlag, [2]),
        rec(0x0B6, [3]),
      ]),
    );
    expect(v.ids.map((s) => s.label), ['0B6', '200', '00000100']);
  });

  test('zählt Botschaften und merkt sich geänderte Bytes', () {
    final t0 = DateTime(2026, 11, 6, 12);
    final v = BusView();
    withClock(Clock.fixed(t0), () {
      v.add(
        msg(0, [
          rec(0x100, [0, 0], frames: 3),
        ]),
      );
    });
    withClock(Clock.fixed(t0.add(const Duration(seconds: 1))), () {
      v.add(
        msg(1, [
          rec(0x100, [0, 4], changed: [0, 4, 0, 0, 0, 0, 0, 0], frames: 2),
        ]),
      );
    });
    withClock(Clock.fixed(t0.add(const Duration(seconds: 2))), () {
      v.add(
        msg(2, [
          rec(0x100, [0, 5], changed: [0, 1, 0, 0, 0, 0, 0, 0]),
        ]),
      );
    });
    withClock(Clock.fixed(t0.add(const Duration(seconds: 3))), () {
      v.add(
        msg(3, [
          rec(0x100, [0, 5], changed: [0, 0, 0, 0, 0, 0, 0, 0]),
        ]),
      );
    });
    final s = v[0x100]!;
    expect(s.frames, 7);
    expect(s.data, [0, 5]);
    expect(s.byteChangedAt[0], isNull);
    expect(s.byteChangedAt[1], t0.add(const Duration(seconds: 2)));
    expect(s.changedEver[1], 5, reason: 'alle je geänderten Bits');
    expect(s.lastSeen, t0.add(const Duration(seconds: 3)));
  });

  test('erkennt OBD-Antworten', () {
    final v = BusView();
    v.add(
      msg(0, [
        rec(0x7E8, [0x03, 0x41, 0x0D, 0x32]),
      ]),
    );
    expect((v[0x7E8]!.obd! as ObdResponse).value, 50);
  });

  test('zählt verlorene Nachrichten, auch über den Überlauf', () {
    final v = BusView();
    v.add(msg(0xFFFE, []));
    v.add(msg(0x0001, [])); // 0xFFFF und 0x0000 fehlen
    expect(v.lostMessages, 2);
    v.add(msg(0x0002, []));
    expect(v.lostMessages, 2);
  });

  test('Neustart des Lesers zählt nicht als Verlust', () {
    final v = BusView();
    v.add(msg(500, []));
    v.add(msg(0, []));
    expect(v.lostMessages, 0);
  });

  test('benachrichtigt die Ansicht', () {
    final v = BusView();
    var calls = 0;
    v.addListener(() => calls++);
    v.add(
      msg(0, [
        rec(0x100, [1]),
      ]),
    );
    v.clear();
    expect(calls, 2);
    expect(v.ids, isEmpty);
  });

  // Der Fehler: Die Ansicht ließ beim Anhalten die Übersichten ganz aus. Beim
  // Weiterlaufen sah das wie eine Lücke aus und zählte als BLE-Verlust.
  test('Anhalten zählt nicht als Verlust und friert die Tabelle ein', () {
    final v = BusView();
    v.add(
      msg(0, [
        rec(0x100, [1], frames: 2),
      ]),
    );
    v.paused = true;
    v.add(
      msg(1, [
        rec(0x100, [9], changed: [8, 0, 0, 0, 0, 0, 0, 0], frames: 5),
        rec(0x200, [7]),
      ]),
    );
    v.add(msg(2, []));
    expect(v[0x100]!.data, [1], reason: 'eingefroren');
    expect(v[0x100]!.frames, 2);
    expect(v[0x200], isNull);
    v.paused = false;
    v.add(
      msg(3, [
        rec(0x100, [9]),
      ]),
    );
    expect(v.lostMessages, 0);
    expect(v[0x100]!.data, [9]);
  });

  test('echte Lücke während des Anhaltens zählt weiter als Verlust', () {
    final v = BusView();
    v.add(msg(0, []));
    v.paused = true;
    v.add(msg(3, [])); // 1 und 2 fehlen
    v.paused = false;
    v.add(msg(4, []));
    expect(v.lostMessages, 2);
  });

  group('Änderungssuche', () {
    test('ohne Markierung gilt nichts als geändert', () {
      final v = BusView();
      v.add(
        msg(0, [
          rec(0x100, [1], changed: [1, 0, 0, 0, 0, 0, 0, 0]),
        ]),
      );
      expect(v.marked, isFalse);
      expect(v.changedSinceMark, isEmpty);
    });

    test('zeigt nur IDs und Bits, die sich seit der Markierung ändern', () {
      final t0 = DateTime(2026, 11, 10, 12);
      final v = BusView();
      v.add(
        msg(0, [
          rec(0x100, [0, 0], changed: [0xFF, 0, 0, 0, 0, 0, 0, 0]),
          rec(0x200, [0]),
          rec(0x300, [0]),
        ]),
      );
      withClock(Clock.fixed(t0), v.mark);
      expect(v.marked, isTrue);
      expect(v.markedAt, t0);
      expect(
        v.changedSinceMark,
        isEmpty,
        reason: 'frühere Änderungen zählen nicht',
      );

      v.add(
        msg(1, [
          rec(0x100, [0, 4], changed: [0, 4, 0, 0, 0, 0, 0, 0]),
          rec(0x200, [0]),
        ]),
      );
      v.add(
        msg(2, [
          rec(0x100, [0, 5], changed: [0, 1, 0, 0, 0, 0, 0, 0]),
          rec(0x200, [0]),
        ]),
      );
      expect(v.changedSinceMark.map((s) => s.label), ['100']);
      final s = v[0x100]!;
      expect(s.changedSinceMark, [0, 5, 0, 0, 0, 0, 0, 0]);
      expect(s.changedEver[0], 0xFF, reason: '„je geändert“ bleibt unberührt');
      expect(s.newSinceMark, isFalse);
    });

    test('neue IDs nach der Markierung zählen als geändert', () {
      final v = BusView();
      v.add(
        msg(0, [
          rec(0x100, [0]),
        ]),
      );
      v.mark();
      v.add(
        msg(1, [
          rec(0x100, [0]),
          rec(0x400, [1]),
        ]),
      );
      expect(v.changedSinceMark.map((s) => s.label), ['400']);
      expect(v[0x400]!.newSinceMark, isTrue);
    });

    test('neu markieren und beenden setzen zurück', () {
      final v = BusView();
      v.add(
        msg(0, [
          rec(0x100, [0]),
        ]),
      );
      v.mark();
      v.add(
        msg(1, [
          rec(0x100, [1], changed: [1, 0, 0, 0, 0, 0, 0, 0]),
          rec(0x400, [1]),
        ]),
      );
      expect(v.changedSinceMark, hasLength(2));
      v.mark();
      expect(v.changedSinceMark, isEmpty);
      v.add(
        msg(2, [
          rec(0x400, [3], changed: [2, 0, 0, 0, 0, 0, 0, 0]),
        ]),
      );
      expect(v.changedSinceMark.map((s) => s.label), ['400']);
      expect(v[0x400]!.newSinceMark, isFalse);
      v.clearMark();
      expect(v.marked, isFalse);
      expect(v.changedSinceMark, isEmpty);
      expect(v[0x400]!.changedSinceMark, List.filled(8, 0));
    });

    test('Zurücksetzen beendet die Markierung', () {
      final v = BusView();
      v.mark();
      v.clear();
      expect(v.marked, isFalse);
    });
  });
}
