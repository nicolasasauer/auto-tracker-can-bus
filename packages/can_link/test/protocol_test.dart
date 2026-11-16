import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dieselben Bytes prüft die Firmware in
/// firmware/can_logger/test/test_protocol.cpp.
const monitorVector =
    '01 01 02 01 45 23 01 00 02 '
    'E8 07 00 00 08 03 41 0D 32 00 00 00 00 00 00 00 FF 00 00 00 00 05 00 64 00 '
    '10 F1 DA 98 03 AA BB CC 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00';

const diagnosticsVector =
    '03 01 D2 04 E8 03 E1 10 05 01 70 11 01 00 25 00 00 02 02 00 11 00 00 00';

const statusVector =
    '02 01 00 01 00 00 00 03 10 0E 00 00 40 E2 01 00 07 00 00 00 2A 00 38 31';

Uint8List bytes(String hex) => Uint8List.fromList(
  hex
      .split(' ')
      .where((s) => s.isNotEmpty)
      .map((s) => int.parse(s, radix: 16))
      .toList(),
);

String hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');

void main() {
  test('Übersicht: Beispielnachricht der Firmware zerlegen', () {
    final m = decodeMonitor(bytes(monitorVector));
    expect(m.seq, 0x0102);
    expect(m.timeMs, 0x00012345);
    expect(m.records, hasLength(2));

    final obd = m.records[0];
    expect(obd.id, 0x7E8);
    expect(obd.extended, isFalse);
    expect(obd.data, [0x03, 0x41, 0x0D, 0x32, 0, 0, 0, 0]);
    expect(obd.changed, [0, 0, 0, 0xFF, 0, 0, 0, 0]);
    expect(obd.frames, 5);
    expect(obd.periodMs, 100);

    final ext = m.records[1];
    expect(ext.id, 0x18DAF110);
    expect(ext.extended, isTrue);
    expect(ext.data, [0xAA, 0xBB, 0xCC]);
    expect(ext.frames, 1);
    expect(ext.periodMs, 0);
  });

  test('Übersicht: kodieren ergibt dieselben Bytes wie die Firmware', () {
    final m = decodeMonitor(bytes(monitorVector));
    expect(hex(encodeMonitor(m)), monitorVector);
  });

  test('Übersicht: falsche Länge wird abgelehnt', () {
    final b = bytes(monitorVector);
    expect(
      () => decodeMonitor(Uint8List.sublistView(b, 0, b.length - 1)),
      throwsA(isA<CanLinkFormatException>()),
    );
    expect(
      () =>
          decodeMonitor(Uint8List.fromList([0x01, 0x02, 0, 0, 0, 0, 0, 0, 0])),
      throwsA(isA<CanLinkFormatException>()),
      reason: 'unbekannte Protokollversion',
    );
  });

  test('Status: Beispielnachricht der Firmware zerlegen', () {
    final s = decodeStatus(bytes(statusVector));
    expect(s.firmware, '0.1.0');
    expect(s.mode, BusMode.listenOnly);
    expect(s.state, BusState.ok);
    expect(s.pairingOpen, isTrue);
    expect(s.usbHost, isTrue);
    expect(s.uptimeS, 3600);
    expect(s.framesTotal, 123456);
    expect(s.framesDropped, 7);
    expect(s.idsSeen, 42);
    expect(s.supplyMv, 12600);
  });

  test('Status: Kopplungsfenster und USB getrennt', () {
    final nurUsb = bytes(statusVector)..[7] = 0x02;
    expect(decodeStatus(nurUsb).usbHost, isTrue);
    expect(decodeStatus(nurUsb).pairingOpen, isFalse);
    final nurFenster = bytes(statusVector)..[7] = 0x01;
    expect(decodeStatus(nurFenster).usbHost, isFalse);
    expect(decodeStatus(nurFenster).pairingOpen, isTrue);
  });

  test('Status: unbekannter Buszustand', () {
    final b = bytes(statusVector)..[6] = 9;
    expect(decodeStatus(b).state, BusState.unknown);
  });

  test('Befehle wie in der Firmware erwartet', () {
    expect(hex(CanLinkCommands.resetStats()), '10');
    expect(
      hex(CanLinkCommands.setFilter([(id: 0x7E8, mask: 0x7F8)])),
      '11 01 E8 07 00 00 F8 07 00 00',
    );
    expect(hex(CanLinkCommands.setInterval(200)), '12 C8 00');
    expect(() => CanLinkCommands.setInterval(99), throwsRangeError);
    expect(
      () => CanLinkCommands.setFilter(List.filled(9, (id: 0, mask: 0))),
      throwsArgumentError,
    );
  });

  test('CAN-ID als Text', () {
    expect(formatCanId(0x0B6, extended: false), '0B6');
    expect(formatCanId(0x18DAF110, extended: true), '18DAF110');
  });

  test('Diagnose: Beispielnachricht der Firmware zerlegen', () {
    final d = decodeDiagnostics(bytes(diagnosticsVector));
    expect(d.loadNowPct, 12.34);
    expect(d.loadAvgPct, 10.0);
    expect(d.loadPeakPct, 43.21);
    expect(d.rxErrorCounter, 5);
    expect(d.errorFlags, 0x01);
    expect(d.errorEvents, 70000);
    expect(d.ringMaxFill, 37);
    expect(d.ringCapacity, 512);
    expect(d.resetReason, ResetReason.brownout);
    expect(d.bootCount, 17);
  });

  test('Diagnose: kodieren ergibt dieselben Bytes wie die Firmware', () {
    final d = decodeDiagnostics(bytes(diagnosticsVector));
    expect(hex(encodeDiagnostics(d)), diagnosticsVector);
  });

  test('Diagnose: unbekannter Neustartgrund, falscher Typ', () {
    final b = bytes(diagnosticsVector)..[18] = 200;
    expect(decodeDiagnostics(b).resetReason, ResetReason.other);
    expect(
      () => decodeDiagnostics(bytes(statusVector)),
      throwsA(isA<CanLinkFormatException>()),
    );
  });
}
