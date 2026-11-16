import 'dart:typed_data';

/// Genormte OBD-II-PIDs (Service 01, SAE J1979) mit Name, Einheit und
/// Umrechnung. Damit erkennt die Werkbank OBD-Anfragen und -Antworten auf dem
/// Bus und zeigt sie gleich lesbar an.
class Obd2Pid {
  const Obd2Pid(this.pid, this.name, this.unit, this.bytes, this.decode);

  final int pid;
  final String name;
  final String unit;

  /// Anzahl Datenbytes (A, B, …) in der Antwort.
  final int bytes;
  final double Function(List<int> d) decode;
}

int _u16(List<int> d) => d[0] << 8 | d[1];

final List<Obd2Pid> obd2Pids = [
  Obd2Pid(0x04, 'Motorlast', '%', 1, (d) => d[0] * 100 / 255),
  Obd2Pid(0x05, 'Kühlmitteltemperatur', '°C', 1, (d) => d[0] - 40.0),
  Obd2Pid(0x0B, 'Saugrohrdruck', 'kPa', 1, (d) => d[0].toDouble()),
  Obd2Pid(0x0C, 'Drehzahl', '1/min', 2, (d) => _u16(d) / 4),
  Obd2Pid(0x0D, 'Geschwindigkeit', 'km/h', 1, (d) => d[0].toDouble()),
  Obd2Pid(0x0F, 'Ansauglufttemperatur', '°C', 1, (d) => d[0] - 40.0),
  Obd2Pid(0x10, 'Luftmasse', 'g/s', 2, (d) => _u16(d) / 100),
  Obd2Pid(0x11, 'Drosselklappe', '%', 1, (d) => d[0] * 100 / 255),
  Obd2Pid(0x1F, 'Zeit seit Motorstart', 's', 2, (d) => _u16(d).toDouble()),
  Obd2Pid(0x2F, 'Tankfüllstand', '%', 1, (d) => d[0] * 100 / 255),
  Obd2Pid(0x33, 'Luftdruck', 'kPa', 1, (d) => d[0].toDouble()),
  Obd2Pid(0x42, 'Steuergerätespannung', 'V', 2, (d) => _u16(d) / 1000),
  Obd2Pid(0x46, 'Außentemperatur', '°C', 1, (d) => d[0] - 40.0),
  Obd2Pid(0x5C, 'Öltemperatur', '°C', 1, (d) => d[0] - 40.0),
  Obd2Pid(0x5E, 'Kraftstoffverbrauch', 'L/h', 2, (d) => _u16(d) / 20),
  Obd2Pid(
    0xA6,
    'Kilometerstand',
    'km',
    4,
    (d) => (d[0] << 24 | d[1] << 16 | d[2] << 8 | d[3]) / 10,
  ),
];

final Map<int, Obd2Pid> _byPid = {for (final p in obd2Pids) p.pid: p};

Obd2Pid? obd2Pid(int pid) => _byPid[pid];

/// Was eine Botschaft im OBD-Sinne ist.
sealed class ObdFrame {
  const ObdFrame(this.pid);
  final int pid;
  Obd2Pid? get info => obd2Pid(pid);
}

/// Anfrage eines Testers (z. B. `7DF 02 01 0D`).
class ObdRequest extends ObdFrame {
  const ObdRequest(super.pid);
}

/// Antwort eines Steuergeräts (z. B. `7E8 03 41 0D 32` = 50 km/h).
class ObdResponse extends ObdFrame {
  const ObdResponse(super.pid, this.payload);
  final List<int> payload;

  /// Umgerechneter Wert, null bei unbekannter PID oder zu wenig Daten.
  double? get value {
    final p = info;
    if (p == null || payload.length < p.bytes) return null;
    return p.decode(payload);
  }

  /// PIDs 0x00, 0x20, 0x40, …: Bitmaske der unterstützten PIDs.
  List<int>? get supportedPids {
    if (pid % 0x20 != 0 || payload.length < 4) return null;
    final result = <int>[];
    for (var i = 0; i < 32; i++) {
      if (payload[i ~/ 8] & (0x80 >> (i % 8)) != 0) result.add(pid + i + 1);
    }
    return result;
  }
}

// 11 Bit: Anfragen an alle (7DF) oder ein Steuergerät (7E0–7E7), Antworten
// von 7E8–7EF. 29 Bit: Anfragen 18DB33F1 bzw. 18DAxxF1, Antworten 18DAF1xx.
bool _isRequestId(int id, bool extended) => extended
    ? (id & 0xFFFF00FF) == 0x18DB00F1 || (id & 0xFFFF00FF) == 0x18DA00F1
    : id == 0x7DF || (id >= 0x7E0 && id <= 0x7E7);

bool _isResponseId(int id, bool extended) =>
    extended ? (id & 0xFFFFFF00) == 0x18DAF100 : id >= 0x7E8 && id <= 0x7EF;

/// Erkennt OBD-II-Anfragen und -Antworten (Service 01, Einzel-Botschaft nach
/// ISO-TP). Alles andere: null.
ObdFrame? parseObdFrame(
  int id, {
  required bool extended,
  required Uint8List data,
}) {
  if (data.length < 3) return null;
  final pci = data[0];
  // Einzel-Botschaft: oberes Halbbyte 0, unteres = Länge 1–7.
  if (pci >> 4 != 0) return null;
  final len = pci & 0x0F;
  if (len < 2 || len > 7 || len + 1 > data.length) return null;
  final service = data[1];
  final pid = data[2];
  if (service == 0x01 && _isRequestId(id, extended)) return ObdRequest(pid);
  if (service == 0x41 && _isResponseId(id, extended)) {
    return ObdResponse(pid, data.sublist(3, 1 + len));
  }
  return null;
}
