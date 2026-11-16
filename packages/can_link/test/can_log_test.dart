import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

IdRecord rec(int rawId, List<int> data, {List<int>? changed}) => IdRecord(
  rawId: rawId,
  data: Uint8List.fromList(data),
  changed: changed == null
      ? null
      : (Uint8List(8)..setRange(0, changed.length, changed)),
  frames: 20,
  periodMs: 10,
);

MonitorMessage msg(int seq, int timeMs, List<IdRecord> records) =>
    MonitorMessage(seq: seq, timeMs: timeMs, records: records);

CanLogWriter writer() =>
    CanLogWriter(start: DateTime.utc(2026, 11, 13, 10), source: 'Test');

void main() {
  test('schreibt nur Änderungen, Zeit ab Aufnahmebeginn', () {
    final w = writer();
    expect(
      w.add(
        msg(7, 5000, [
          rec(0x208, [0x1F, 0x40]),
          rec(0x18DAF110 | CanLinkProtocol.extendedFlag, [0x02]),
        ]),
      ),
      ['0;208;2;1F 40;00 00;20;10', '0;18DAF110;1;02;00;20;10'],
    );
    // Gleiche Daten, keine geänderten Bits: keine Zeile.
    expect(
      w.add(
        msg(8, 5200, [
          rec(0x208, [0x1F, 0x40]),
        ]),
      ),
      isEmpty,
    );
    expect(
      w.add(
        msg(9, 5400, [
          rec(0x208, [0x1F, 0x48], changed: [0, 8]),
        ]),
      ),
      ['400;208;2;1F 48;00 08;20;10'],
    );
    expect(w.rows, 3);
    expect(w.ids, 2);
    expect(w.durationMs, 400);
  });

  // Ein Bit, das zwischen zwei Übersichten kurz wechselt und zurückfällt,
  // steht nur in „changed“. Auch das ist eine Änderung.
  test('kurzer Wechsel ohne neue Daten wird trotzdem geschrieben', () {
    final w = writer()
      ..add(
        msg(0, 0, [
          rec(0x128, [0x00]),
        ]),
      );
    expect(
      w.add(
        msg(1, 200, [
          rec(0x128, [0x00], changed: [0x04]),
        ]),
      ),
      ['200;128;1;00;04;20;10'],
    );
  });

  test('verlorene Übersichten und Neustart des Lesers', () {
    final w = writer()
      ..add(
        msg(0, 1000, [
          rec(0x208, [1]),
        ]),
      );
    final lines = w.add(
      msg(3, 1600, [
        rec(0x208, [2]),
      ]),
    );
    expect(lines.first, '600;LOST;;2;;;');
    // Leser startet neu: Seine Uhr beginnt vorn, die Aufnahme zählt weiter.
    w.add(
      msg(0, 100, [
        rec(0x208, [3]),
      ]),
    );
    expect(w.durationMs, 600);
  });

  test('Marke ohne Strichpunkt und Zeilenumbruch', () {
    final w = writer()
      ..add(msg(0, 0, []))
      ..add(msg(1, 250, []));
    expect(w.mark('Blinker; links\n'), '250;MARK;;Blinker links;;;');
  });

  test('Mitschnitt lesen ergibt dieselben Übersichten', () {
    final w = writer();
    final lines = [
      ...w.header(),
      ...w.add(
        msg(0, 0, [
          rec(0x208, [0x1F, 0x40]),
          rec(0x18DAF110 | CanLinkProtocol.extendedFlag, [0x02]),
        ]),
      ),
      w.mark('Start'),
      ...w.add(
        msg(1, 200, [
          rec(0x208, [0x1F, 0x48], changed: [0, 8]),
        ]),
      ),
    ];
    final log = CanLog.parse(lines.join('\r\n'));
    expect(log.source, 'Test');
    expect(log.start, DateTime.utc(2026, 11, 13, 10));
    expect(log.marks, [(tMs: 0, text: 'Start')]);
    expect(log.messages.map((m) => m.timeMs), [0, 200]);
    expect(log.messages[0].records[1].extended, isTrue);
    final r = log.messages[1].records.single;
    expect(r.rawId, 0x208);
    expect(r.data, [0x1F, 0x48]);
    expect(r.changed, [0, 8, 0, 0, 0, 0, 0, 0]);
    expect(r.frames, 20);
    expect(r.periodMs, 10);
    expect(log.durationMs, 200);
  });

  test('fremde Datei und kaputte Zeile werden abgelehnt', () {
    expect(() => CanLog.parse('a;b;c'), throwsFormatException);
    expect(
      () => CanLog.parse('${CanLogFormat.title}\n0;208;2;ZZ;;1;0'),
      throwsFormatException,
    );
  });

  test('Wiedergabe schickt die Übersichten der Reihe nach', () async {
    final w = writer();
    final text = [
      ...w.header(),
      ...w.add(
        msg(0, 0, [
          rec(0x208, [1]),
        ]),
      ),
      ...w.add(
        msg(1, 200, [
          rec(0x208, [2]),
        ]),
      ),
    ].join('\n');
    final c = ReplayConnection(CanLog.parse(text), autoPlay: false);
    final seen = <int>[];
    c.monitor.listen((m) => seen.add(m.records.single.data[0]));
    c.step();
    c.step();
    c.step();
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2]);
    expect(c.finished, isTrue);
    await c.close();
  });
}
