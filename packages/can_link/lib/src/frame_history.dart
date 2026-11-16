import 'dart:typed_data';

import 'messages.dart';
import 'profile.dart';

/// Ein Punkt im Verlauf eines Signals.
typedef SignalSample = ({int tMs, int raw});

/// Merkt sich je CAN-ID die Nutzdaten der letzten Übersichten.
///
/// Gespeichert werden die Bytes, nicht die dekodierten Werte. So lässt sich
/// der Verlauf eines Signals auch rückwirkend zeichnen, wenn man Startbit,
/// Länge oder Faktor verändert.
class FrameHistory {
  /// [capacity] Übersichten je ID: 3000 sind 10 Minuten bei 200 ms.
  FrameHistory({this.capacity = 3000});

  final int capacity;
  final Map<int, _Ring> _rings = {};
  int? _firstTimeMs;
  int? _lastTimeMs;
  int _rebase = 0;

  /// Zeit der letzten Übersicht in ms seit der ersten.
  int nowMs = 0;

  void add(MonitorMessage message) {
    final last = _lastTimeMs;
    // Zeit läuft rückwärts: Leser neu gestartet, hinten anfügen.
    if (last != null && message.timeMs < last) _rebase += last - message.timeMs;
    _firstTimeMs ??= message.timeMs;
    _lastTimeMs = message.timeMs;
    nowMs = message.timeMs - _firstTimeMs! + _rebase;
    for (final r in message.records) {
      _rings
          .putIfAbsent(
            r.rawId & ~CanLinkProtocol.rtrFlag,
            () => _Ring(capacity),
          )
          .add(nowMs, r.data);
    }
  }

  /// Letzte Nutzdaten einer ID, null wenn sie noch nicht kam.
  Uint8List? latest(int rawId) => _rings[rawId]?.latest;

  /// Rohwerte eines Signals der letzten [windowMs] Millisekunden, älteste
  /// zuerst. Übersichten, die für das Signal zu kurz sind, fehlen.
  List<SignalSample> samples(int rawId, SignalDef signal, {int? windowMs}) {
    final ring = _rings[rawId];
    if (ring == null) return const [];
    final from = windowMs == null ? null : nowMs - windowMs;
    final out = <SignalSample>[];
    for (var i = 0; i < ring.count; i++) {
      final t = ring.timeAt(i);
      if (from != null && t < from) continue;
      final raw = signal.rawFrom(ring.dataAt(i));
      if (raw != null) out.add((tMs: t, raw: raw));
    }
    return out;
  }

  void clear() {
    _rings.clear();
    _firstTimeMs = null;
    _lastTimeMs = null;
    _rebase = 0;
    nowMs = 0;
  }
}

class _Ring {
  _Ring(this.capacity)
    : _data = Uint8List(capacity * 8),
      _length = Uint8List(capacity),
      _time = Int32List(capacity);

  final int capacity;
  final Uint8List _data;
  final Uint8List _length;
  final Int32List _time;
  int _head = 0;
  int count = 0;

  void add(int tMs, Uint8List data) {
    _data.setRange(_head * 8, _head * 8 + data.length, data);
    _length[_head] = data.length;
    _time[_head] = tMs;
    _head = (_head + 1) % capacity;
    if (count < capacity) count++;
  }

  int _slot(int i) => (_head - count + i) % capacity;

  int timeAt(int i) => _time[_slot(i)];

  Uint8List dataAt(int i) {
    final s = _slot(i);
    return Uint8List.sublistView(_data, s * 8, s * 8 + _length[s]);
  }

  Uint8List? get latest => count == 0 ? null : dataAt(count - 1);
}
