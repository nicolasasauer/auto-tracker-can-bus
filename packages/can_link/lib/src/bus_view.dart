import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'messages.dart';
import 'obd2.dart';

/// Zustand einer CAN-ID in der Sniff-Ansicht.
class IdState {
  IdState(this.rawId, this.firstSeen)
    : data = Uint8List(0),
      lastSeen = firstSeen;

  final int rawId;
  final DateTime firstSeen;

  int get id => rawId & CanLinkProtocol.idMask;
  bool get extended => rawId & CanLinkProtocol.extendedFlag != 0;
  String get label => formatCanId(id, extended: extended);

  Uint8List data;
  DateTime lastSeen;
  int frames = 0;
  int periodMs = 0;

  /// Wann sich welches Byte zuletzt geändert hat (null = nie).
  final List<DateTime?> byteChangedAt = List.filled(8, null);

  /// Alle Bits, die sich seit Beginn der Aufzeichnung je geändert haben.
  /// Hilft beim Eingrenzen: Bits, die nie wechseln, sind meist uninteressant.
  final Uint8List changedEver = Uint8List(8);

  /// Bits, die sich seit der Markierung geändert haben ([BusView.mark]).
  /// Ohne Markierung alle 0.
  final Uint8List changedSinceMark = Uint8List(8);

  /// Die ID kam erst nach der Markierung zum ersten Mal.
  bool newSinceMark = false;

  /// Hat sich seit der Markierung etwas getan?
  bool get changedAfterMark =>
      newSinceMark || changedSinceMark.any((b) => b != 0);

  /// OBD-Deutung, falls es eine OBD-Anfrage oder -Antwort ist.
  ObdFrame? obd;
}

/// Sammelt die Übersichten des Lesers zu einer Tabelle je CAN-ID.
/// Das ist das Modell hinter der Sniff-Ansicht der Werkbank; andere Apps
/// können es genauso nutzen.
class BusView extends ChangeNotifier {
  final Map<int, IdState> _ids = {};
  int? _lastSeq;

  /// Verlorene Übersichts-Nachrichten (Lücken in der laufenden Nummer).
  int lostMessages = 0;

  bool _paused = false;

  /// Angehalten: Die Tabelle bleibt stehen, neue Übersichten werden
  /// verworfen. Ihre laufende Nummer zählt trotzdem mit, damit das Anhalten
  /// nicht wie ein Verlust aussieht.
  bool get paused => _paused;
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    notifyListeners();
  }

  DateTime? _markedAt;

  /// Zeitpunkt der Markierung, null ohne Markierung.
  DateTime? get markedAt => _markedAt;
  bool get marked => _markedAt != null;

  /// Änderungssuche: Ab jetzt merken, welche Bits sich ändern und welche IDs
  /// neu dazukommen. Ablauf: markieren, am Auto etwas tun (Blinker, Bremse),
  /// dann zeigt [changedSinceMark] die Kandidaten. Erneutes Markieren fängt
  /// von vorn an.
  ///
  /// Der Leser meldet Änderungen je Übersicht. Die erste Übersicht nach der
  /// Markierung kann deshalb noch Änderungen aus dem Abstand davor enthalten
  /// (üblich 200 ms).
  void mark() {
    _markedAt = clock.now();
    _resetMarks();
    notifyListeners();
  }

  /// Änderungssuche beenden.
  void clearMark() {
    _markedAt = null;
    _resetMarks();
    notifyListeners();
  }

  void _resetMarks() {
    for (final s in _ids.values) {
      s.changedSinceMark.fillRange(0, 8, 0);
      s.newSinceMark = false;
    }
  }

  /// IDs, bei denen sich seit der Markierung etwas getan hat, sortiert wie
  /// [ids]. Leer ohne Markierung.
  List<IdState> get changedSinceMark =>
      marked ? ids.where((s) => s.changedAfterMark).toList() : const [];

  /// Alle bekannten IDs, nach ID sortiert (11 Bit vor 29 Bit).
  List<IdState> get ids {
    final list = _ids.values.toList()
      ..sort(
        (a, b) => a.extended == b.extended
            ? a.id.compareTo(b.id)
            : (a.extended ? 1 : -1),
      );
    return list;
  }

  IdState? operator [](int rawId) => _ids[rawId];

  void add(MonitorMessage message) {
    final last = _lastSeq;
    if (last != null) {
      final gap = (message.seq - last - 1) & 0xFFFF;
      // Sehr große Lücken: Leser neu gestartet, keine Verluste.
      if (gap > 0 && gap < 0x8000) lostMessages += gap;
    }
    _lastSeq = message.seq;

    // Erst nach der laufenden Nummer: Anhalten ist kein Verlust.
    if (_paused) return;

    final now = clock.now();
    final marking = marked;
    for (final r in message.records) {
      final state = _ids.putIfAbsent(
        r.rawId & ~CanLinkProtocol.rtrFlag,
        () => IdState(r.rawId, now)..newSinceMark = marking,
      );
      state.data = r.data;
      state.lastSeen = now;
      state.frames += r.frames;
      state.periodMs = r.periodMs;
      for (var i = 0; i < 8; i++) {
        if (r.changed[i] != 0) {
          state.byteChangedAt[i] = now;
          state.changedEver[i] |= r.changed[i];
          if (marking) state.changedSinceMark[i] |= r.changed[i];
        }
      }
      state.obd = parseObdFrame(r.id, extended: r.extended, data: r.data);
    }
    notifyListeners();
  }

  void clear() {
    _ids.clear();
    _lastSeq = null;
    _markedAt = null;
    lostMessages = 0;
    notifyListeners();
  }
}
