import 'package:can_link/can_link.dart';

String _hex(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');

String _number(double v) => v == v.roundToDouble()
    ? v.toStringAsFixed(0)
    : v.toStringAsFixed(1).replaceAll('.', ',');

/// Lesbare Beschreibung einer OBD-Anfrage oder -Antwort.
String obdText(ObdFrame frame) {
  final info = frame.info;
  final name = info?.name ?? 'PID ${_hex(frame.pid)}';
  switch (frame) {
    case ObdRequest():
      return 'OBD-Anfrage: $name';
    case ObdResponse():
      final supported = frame.supportedPids;
      if (supported != null) {
        return 'OBD: unterstützte PIDs ${supported.map(_hex).join(' ')}';
      }
      final value = frame.value;
      if (value == null) return 'OBD-Antwort: $name';
      return 'OBD: $name = ${_number(value)} ${info!.unit}';
  }
}
