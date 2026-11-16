import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:can_werkbank/src/obd_text.dart';
import 'package:flutter_test/flutter_test.dart';

String text(int id, List<int> data) => obdText(
  parseObdFrame(id, extended: false, data: Uint8List.fromList(data))!,
);

void main() {
  test('Antwort mit Wert und Einheit', () {
    expect(
      text(0x7E8, [0x03, 0x41, 0x0D, 0x32]),
      'OBD: Geschwindigkeit = 50 km/h',
    );
    expect(
      text(0x7E8, [0x04, 0x41, 0x42, 0x31, 0x38]),
      'OBD: Steuergerätespannung = 12,6 V',
    );
  });

  test('Anfrage', () {
    expect(text(0x7DF, [0x02, 0x01, 0x2F]), 'OBD-Anfrage: Tankfüllstand');
  });

  test('Unbekannte PID und unterstützte PIDs', () {
    expect(text(0x7E8, [0x03, 0x41, 0xFE, 0x00]), 'OBD-Antwort: PID FE');
    expect(
      text(0x7E8, [0x06, 0x41, 0x00, 0x80, 0x00, 0x00, 0x01]),
      'OBD: unterstützte PIDs 01 20',
    );
  });
}
