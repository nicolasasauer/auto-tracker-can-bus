import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

ObdFrame? parse(int id, List<int> data, {bool extended = false}) =>
    parseObdFrame(id, extended: extended, data: Uint8List.fromList(data));

void main() {
  test('Antwort Geschwindigkeit', () {
    final f = parse(0x7E8, [0x03, 0x41, 0x0D, 0x32, 0x55, 0x55, 0x55, 0x55]);
    expect(f, isA<ObdResponse>());
    final r = f! as ObdResponse;
    expect(r.info!.name, 'Geschwindigkeit');
    expect(r.value, 50);
  });

  test('Antwort Drehzahl (2 Byte)', () {
    final r = parse(0x7E8, [0x04, 0x41, 0x0C, 0x1A, 0xF8]) as ObdResponse;
    expect(r.value, 1726); // (0x1A * 256 + 0xF8) / 4
  });

  test('Antwort Kilometerstand (4 Byte)', () {
    final r =
        parse(0x7E8, [0x06, 0x41, 0xA6, 0x00, 0x01, 0xE2, 0x40]) as ObdResponse;
    expect(r.value, 12345.6);
  });

  test('Antwort Tankfüllstand', () {
    final r = parse(0x7E9, [0x03, 0x41, 0x2F, 0x80]) as ObdResponse;
    expect(r.value, closeTo(50.2, 0.1));
  });

  test('Anfrage an alle Steuergeräte', () {
    final f = parse(0x7DF, [0x02, 0x01, 0x0D, 0, 0, 0, 0, 0]);
    expect(f, isA<ObdRequest>());
    expect(f!.pid, 0x0D);
  });

  test('29-Bit-Antwort und -Anfrage', () {
    expect(
      parse(0x18DAF110, [0x03, 0x41, 0x0D, 0x32], extended: true),
      isA<ObdResponse>(),
    );
    expect(
      parse(0x18DB33F1, [0x02, 0x01, 0x0D], extended: true),
      isA<ObdRequest>(),
    );
    // Antwort-Kennung an falscher ID: keine OBD-Botschaft.
    expect(parse(0x18DA10F1, [0x03, 0x41, 0x0D, 0x32], extended: true), isNull);
  });

  test('Unterstützte PIDs aus der Bitmaske', () {
    // BE 1F A8 13: üblicher Wert eines Benziners
    final r =
        parse(0x7E8, [0x06, 0x41, 0x00, 0xBE, 0x1F, 0xA8, 0x13]) as ObdResponse;
    expect(
      r.supportedPids,
      containsAllInOrder([0x01, 0x03, 0x04, 0x05, 0x06, 0x07]),
    );
    expect(r.supportedPids, contains(0x0D));
    expect(r.supportedPids, contains(0x20));
    expect(r.supportedPids, isNot(contains(0x02)));
  });

  test('Keine OBD-Botschaften', () {
    // Gleiche Bytes an einer anderen ID
    expect(parse(0x0B6, [0x03, 0x41, 0x0D, 0x32]), isNull);
    // Mehrteilige Antwort (ISO-TP First Frame)
    expect(
      parse(0x7E8, [0x10, 0x14, 0x49, 0x02, 0x01, 0x56, 0x46, 0x33]),
      isNull,
    );
    // Folge-Botschaft (ISO-TP Consecutive Frame), zufällig mit 41 0D
    expect(parse(0x7E8, [0x23, 0x41, 0x0D, 0x32]), isNull);
    // Länge größer als die Botschaft
    expect(parse(0x7E8, [0x07, 0x41, 0x0D]), isNull);
    // Unbekannte PID: erkannt, aber ohne Wert
    final r = parse(0x7E8, [0x03, 0x41, 0xFE, 0x01]) as ObdResponse;
    expect(r.value, isNull);
  });
}
