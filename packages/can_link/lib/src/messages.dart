import 'dart:typed_data';

/// Nachrichten und Befehle des BLE-Protokolls, Version 1
/// (docs/CAN-BLE-PROTOKOLL.md). Das Gegenstück in C++ liegt in
/// firmware/can_logger/lib/can_core/src/protocol.cpp.
abstract final class CanLinkProtocol {
  static const version = 1;
  static const typeMonitor = 0x01;
  static const typeStatus = 0x02;
  static const typeDiagnostics = 0x03;
  static const cmdResetStats = 0x10;
  static const cmdSetFilter = 0x11;
  static const cmdSetInterval = 0x12;

  static const monitorHeaderSize = 9;
  static const monitorRecordSize = 25;
  static const statusSize = 24;
  static const diagnosticsSize = 24;

  static const extendedFlag = 0x80000000;
  static const rtrFlag = 0x40000000;
  static const idMask = 0x1FFFFFFF;
}

typedef _P = CanLinkProtocol;

/// Ein Eintrag der Übersicht: Zusammenfassung aller Botschaften einer CAN-ID
/// seit der letzten Übersicht.
class IdRecord {
  IdRecord({
    required this.rawId,
    required this.data,
    Uint8List? changed,
    this.frames = 1,
    this.periodMs = 0,
  }) : changed = changed ?? Uint8List(8);

  /// ID-Feld wie im Protokoll: CAN-ID plus Erweitert- und RTR-Bit.
  final int rawId;

  /// Nutzdaten in der gesendeten Länge (0–8 Byte).
  final Uint8List data;

  /// Seit der letzten Übersicht geänderte Bits, immer 8 Byte.
  final Uint8List changed;

  final int frames;

  /// Mittlerer Abstand der Botschaften in ms, 0 = unbekannt.
  final int periodMs;

  int get id => rawId & CanLinkProtocol.idMask;
  bool get extended => rawId & CanLinkProtocol.extendedFlag != 0;
  bool get rtr => rawId & CanLinkProtocol.rtrFlag != 0;
}

class MonitorMessage {
  MonitorMessage({
    required this.seq,
    required this.timeMs,
    required this.records,
  });

  /// Laufende Nummer (16 Bit). Lücken bedeuten verlorene Nachrichten.
  final int seq;

  /// Zeit seit Start des Lesers in ms.
  final int timeMs;
  final List<IdRecord> records;
}

enum BusMode { listenOnly, active }

enum BusState { ok, silent, error, busOff, noController, unknown }

class StatusMessage {
  const StatusMessage({
    required this.firmware,
    required this.mode,
    required this.state,
    required this.pairingOpen,
    required this.usbHost,
    required this.uptimeS,
    required this.framesTotal,
    required this.framesDropped,
    required this.idsSeen,
    required this.supplyMv,
  });

  /// z. B. „0.1.0“
  final String firmware;
  final BusMode mode;
  final BusState state;
  final bool pairingOpen;
  final bool usbHost;
  final int uptimeS;
  final int framesTotal;
  final int framesDropped;
  final int idsSeen;

  /// Versorgungsspannung in mV, 0 = unbekannt.
  final int supplyMv;
}

/// Grund des letzten Neustarts des Lesers.
enum ResetReason {
  unknown,
  powerOn,
  brownout,
  software,
  panic,
  watchdog,
  deepSleep,
  external,
  other,
}

/// Diagnose des Lesers (Typ 0x03), jede Sekunde.
class DiagnosticsMessage {
  const DiagnosticsMessage({
    required this.loadNowPct,
    required this.loadAvgPct,
    required this.loadPeakPct,
    required this.rxErrorCounter,
    required this.errorFlags,
    required this.errorEvents,
    required this.ringMaxFill,
    required this.ringCapacity,
    required this.resetReason,
    required this.bootCount,
  });

  /// Buslast der letzten vollen Sekunde in Prozent.
  final double loadNowPct;

  /// Mittel der letzten 10 Sekunden.
  final double loadAvgPct;

  /// Höchste Sekunde seit dem Zurücksetzen.
  final double loadPeakPct;

  /// Empfangsfehlerzähler des CAN-Controllers (0–255).
  final int rxErrorCounter;

  /// Fehler-Flags des Controllers (MCP2515: Register EFLG).
  final int errorFlags;

  /// Fehlerhafte Botschaften seit dem Start bzw. Zurücksetzen.
  final int errorEvents;

  /// Höchster Füllstand des Zwischenpuffers im Leser.
  final int ringMaxFill;
  final int ringCapacity;

  final ResetReason resetReason;

  /// Starts seit dem ersten Flashen.
  final int bootCount;

  /// Anteil des Zwischenpuffers, der höchstens belegt war (0–1).
  double get ringMaxShare => ringCapacity == 0 ? 0 : ringMaxFill / ringCapacity;
}

/// Fehler beim Zerlegen einer Nachricht.
class CanLinkFormatException implements Exception {
  CanLinkFormatException(this.message);
  final String message;
  @override
  String toString() => 'CanLinkFormatException: $message';
}

/// Zerlegt eine Übersicht (Typ 0x01).
MonitorMessage decodeMonitor(Uint8List bytes) {
  if (bytes.length < _P.monitorHeaderSize) {
    throw CanLinkFormatException('Übersicht zu kurz: ${bytes.length} Byte');
  }
  if (bytes[0] != _P.typeMonitor) {
    throw CanLinkFormatException('kein Übersichts-Typ: ${bytes[0]}');
  }
  if (bytes[1] != _P.version) {
    throw CanLinkFormatException('unbekannte Protokollversion ${bytes[1]}');
  }
  final view = ByteData.sublistView(bytes);
  final n = bytes[8];
  if (bytes.length != _P.monitorHeaderSize + n * _P.monitorRecordSize) {
    throw CanLinkFormatException(
      'Länge ${bytes.length} passt nicht zu $n Einträgen',
    );
  }
  final records = <IdRecord>[];
  for (var i = 0; i < n; i++) {
    final o = _P.monitorHeaderSize + i * _P.monitorRecordSize;
    final dlc = bytes[o + 4];
    if (dlc > 8) throw CanLinkFormatException('Datenlänge $dlc');
    records.add(
      IdRecord(
        rawId: view.getUint32(o, Endian.little),
        data: Uint8List.fromList(bytes.sublist(o + 5, o + 5 + dlc)),
        changed: Uint8List.fromList(bytes.sublist(o + 13, o + 21)),
        frames: view.getUint16(o + 21, Endian.little),
        periodMs: view.getUint16(o + 23, Endian.little),
      ),
    );
  }
  return MonitorMessage(
    seq: view.getUint16(2, Endian.little),
    timeMs: view.getUint32(4, Endian.little),
    records: records,
  );
}

/// Kodiert eine Übersicht. Wird von der Simulation und in Tests gebraucht;
/// der Leser selbst kodiert in C++.
Uint8List encodeMonitor(MonitorMessage m) {
  final out = Uint8List(
    _P.monitorHeaderSize + m.records.length * _P.monitorRecordSize,
  );
  final view = ByteData.sublistView(out);
  out[0] = _P.typeMonitor;
  out[1] = _P.version;
  view.setUint16(2, m.seq & 0xFFFF, Endian.little);
  view.setUint32(4, m.timeMs & 0xFFFFFFFF, Endian.little);
  out[8] = m.records.length;
  for (var i = 0; i < m.records.length; i++) {
    final r = m.records[i];
    final o = _P.monitorHeaderSize + i * _P.monitorRecordSize;
    view.setUint32(o, r.rawId, Endian.little);
    out[o + 4] = r.data.length;
    out.setRange(o + 5, o + 5 + r.data.length, r.data);
    out.setRange(o + 13, o + 21, r.changed);
    view.setUint16(o + 21, r.frames.clamp(0, 0xFFFF), Endian.little);
    view.setUint16(o + 23, r.periodMs.clamp(0, 0xFFFF), Endian.little);
  }
  return out;
}

/// Zerlegt eine Statusnachricht (Typ 0x02).
StatusMessage decodeStatus(Uint8List bytes) {
  if (bytes.length < _P.statusSize) {
    throw CanLinkFormatException('Status zu kurz: ${bytes.length} Byte');
  }
  if (bytes[0] != _P.typeStatus) {
    throw CanLinkFormatException('kein Status-Typ: ${bytes[0]}');
  }
  if (bytes[1] != _P.version) {
    throw CanLinkFormatException('unbekannte Protokollversion ${bytes[1]}');
  }
  final view = ByteData.sublistView(bytes);
  return StatusMessage(
    firmware: '${bytes[2]}.${bytes[3]}.${bytes[4]}',
    mode: bytes[5] == 1 ? BusMode.active : BusMode.listenOnly,
    state: bytes[6] < BusState.unknown.index
        ? BusState.values[bytes[6]]
        : BusState.unknown,
    pairingOpen: bytes[7] & 0x01 != 0,
    usbHost: bytes[7] & 0x02 != 0,
    uptimeS: view.getUint32(8, Endian.little),
    framesTotal: view.getUint32(12, Endian.little),
    framesDropped: view.getUint32(16, Endian.little),
    idsSeen: view.getUint16(20, Endian.little),
    supplyMv: view.getUint16(22, Endian.little),
  );
}

/// Zerlegt eine Diagnose-Nachricht (Typ 0x03).
DiagnosticsMessage decodeDiagnostics(Uint8List bytes) {
  if (bytes.length < _P.diagnosticsSize) {
    throw CanLinkFormatException('Diagnose zu kurz: ${bytes.length} Byte');
  }
  if (bytes[0] != _P.typeDiagnostics) {
    throw CanLinkFormatException('kein Diagnose-Typ: ${bytes[0]}');
  }
  if (bytes[1] != _P.version) {
    throw CanLinkFormatException('unbekannte Protokollversion ${bytes[1]}');
  }
  final view = ByteData.sublistView(bytes);
  final reason = bytes[18];
  return DiagnosticsMessage(
    loadNowPct: view.getUint16(2, Endian.little) / 100,
    loadAvgPct: view.getUint16(4, Endian.little) / 100,
    loadPeakPct: view.getUint16(6, Endian.little) / 100,
    rxErrorCounter: bytes[8],
    errorFlags: bytes[9],
    errorEvents: view.getUint32(10, Endian.little),
    ringMaxFill: view.getUint16(14, Endian.little),
    ringCapacity: view.getUint16(16, Endian.little),
    resetReason: reason < ResetReason.values.length
        ? ResetReason.values[reason]
        : ResetReason.other,
    bootCount: view.getUint32(20, Endian.little),
  );
}

/// Kodiert eine Diagnose-Nachricht (Simulation, Tests).
Uint8List encodeDiagnostics(DiagnosticsMessage d) {
  final out = Uint8List(_P.diagnosticsSize);
  final view = ByteData.sublistView(out);
  int centi(double pct) => (pct * 100).round().clamp(0, 10000);
  out[0] = _P.typeDiagnostics;
  out[1] = _P.version;
  view.setUint16(2, centi(d.loadNowPct), Endian.little);
  view.setUint16(4, centi(d.loadAvgPct), Endian.little);
  view.setUint16(6, centi(d.loadPeakPct), Endian.little);
  out[8] = d.rxErrorCounter;
  out[9] = d.errorFlags;
  view.setUint32(10, d.errorEvents, Endian.little);
  view.setUint16(14, d.ringMaxFill, Endian.little);
  view.setUint16(16, d.ringCapacity, Endian.little);
  out[18] = d.resetReason.index;
  view.setUint32(20, d.bootCount, Endian.little);
  return out;
}

/// Ein Filtereintrag: passt, wenn `(id & mask) == (filterId & mask)`.
/// Beide im Format von [IdRecord.rawId] (mit Erweitert-Bit).
typedef CanIdFilter = ({int id, int mask});

abstract final class CanLinkCommands {
  static Uint8List resetStats() =>
      Uint8List.fromList([CanLinkProtocol.cmdResetStats]);

  /// Höchstens 8 Einträge. Leere Liste: alles durchlassen.
  static Uint8List setFilter(List<CanIdFilter> filters) {
    if (filters.length > 8) {
      throw ArgumentError.value(filters.length, 'filters', 'höchstens 8');
    }
    final out = Uint8List(2 + filters.length * 8);
    final view = ByteData.sublistView(out);
    out[0] = CanLinkProtocol.cmdSetFilter;
    out[1] = filters.length;
    for (var i = 0; i < filters.length; i++) {
      view.setUint32(2 + i * 8, filters[i].id, Endian.little);
      view.setUint32(6 + i * 8, filters[i].mask, Endian.little);
    }
    return out;
  }

  /// Abstand der Übersichten, 100–5000 ms.
  static Uint8List setInterval(int ms) {
    if (ms < 100 || ms > 5000) {
      throw RangeError.range(ms, 100, 5000, 'ms');
    }
    final out = Uint8List(3);
    out[0] = CanLinkProtocol.cmdSetInterval;
    ByteData.sublistView(out).setUint16(1, ms, Endian.little);
    return out;
  }
}

/// CAN-ID als Hex-Text: 3 Stellen für 11 Bit, 8 Stellen für 29 Bit.
String formatCanId(int id, {required bool extended}) => extended
    ? id.toRadixString(16).toUpperCase().padLeft(8, '0')
    : id.toRadixString(16).toUpperCase().padLeft(3, '0');
