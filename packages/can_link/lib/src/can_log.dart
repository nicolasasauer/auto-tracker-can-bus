import 'dart:async';
import 'dart:typed_data';

import 'connection.dart';
import 'messages.dart';

/// Mitschnitt als Textdatei (CSV mit `;`), gedacht zum Teilen und für die
/// Auswertung am PC oder durch eine KI. Format: docs/CAN-KONZEPT.md,
/// Kapitel 9.2.
///
/// Der Leser schickt keine einzelnen Botschaften, sondern je CAN-ID eine
/// Übersicht (letzte Daten, geänderte Bits). Eine Zeile entsteht nur, wenn
/// sich bei einer ID etwas geändert hat; ihr Wert gilt bis zur nächsten Zeile
/// derselben ID.
abstract final class CanLogFormat {
  static const title = '# CAN-Werkbank Mitschnitt v1';
  static const columns = 't_ms;id;dlc;data;changed;frames;period_ms';

  /// Zeile mit einer Marke des Nutzers („Blinker links“).
  static const mark = 'MARK';

  /// Zeile mit der Zahl verlorener Übersichten (BLE).
  static const lost = 'LOST';
}

String _hexBytes(Uint8List bytes, int length) => [
  for (var i = 0; i < length; i++)
    bytes[i].toRadixString(16).toUpperCase().padLeft(2, '0'),
].join(' ');

/// Erzeugt die Zeilen eines Mitschnitts aus den Übersichten des Lesers.
class CanLogWriter {
  CanLogWriter({required this.start, required this.source});

  final DateTime start;

  /// Woher die Daten kommen (Name des Lesers).
  final String source;

  final Map<int, Uint8List> _last = {};
  int? _firstTimeMs;
  int? _lastTimeMs;
  int _rebase = 0;
  int? _lastSeq;

  /// Zeit der letzten Übersicht seit Beginn der Aufnahme.
  int durationMs = 0;

  /// Geschriebene Datenzeilen.
  int rows = 0;

  /// Verschiedene CAN-IDs in der Aufnahme.
  int get ids => _last.length;

  List<String> header() => [
    CanLogFormat.title,
    '# start=${start.toUtc().toIso8601String()}',
    '# quelle=$source',
    '# t_ms: Zeit seit Aufnahmebeginn in ms (Uhr des Lesers).',
    '# id: CAN-ID hex, 3 Stellen = 11 Bit, 8 Stellen = 29 Bit.',
    '# data: Nutzdaten hex, Byte 0 zuerst. Gilt bis zur naechsten Zeile '
        'derselben ID.',
    '# changed: Bits, die seit der vorigen Uebersicht gewechselt haben '
        '(auch kurz).',
    '# frames, period_ms: Botschaften seit der vorigen Uebersicht, '
        'mittlerer Abstand.',
    '# Zeilen entstehen nur bei Aenderung. MARK = Marke des Nutzers, '
        'LOST = verlorene Uebersichten.',
    CanLogFormat.columns,
  ];

  /// Zeilen zu dieser Übersicht; leer, wenn sich nichts geändert hat.
  List<String> add(MonitorMessage message) {
    final lines = <String>[];
    final lastTime = _lastTimeMs;
    // Zeit läuft rückwärts: Der Leser ist neu gestartet. Dort weiterzählen,
    // wo die Aufnahme stand.
    if (lastTime != null && message.timeMs < lastTime) {
      _rebase += lastTime - message.timeMs;
    }
    _firstTimeMs ??= message.timeMs;
    _lastTimeMs = message.timeMs;
    durationMs = message.timeMs - _firstTimeMs! + _rebase;

    final lastSeq = _lastSeq;
    if (lastSeq != null) {
      final gap = (message.seq - lastSeq - 1) & 0xFFFF;
      if (gap > 0 && gap < 0x8000) {
        lines.add('$durationMs;${CanLogFormat.lost};;$gap;;;');
      }
    }
    _lastSeq = message.seq;

    for (final r in message.records) {
      final key = r.rawId & ~CanLinkProtocol.rtrFlag;
      final previous = _last[key];
      final same =
          previous != null &&
          previous.length == r.data.length &&
          !Iterable<int>.generate(r.data.length)
              .any((i) => previous[i] != r.data[i]) &&
          r.changed.every((b) => b == 0);
      if (same) continue;
      _last[key] = r.data;
      rows++;
      lines.add(
        [
          durationMs,
          formatCanId(r.id, extended: r.extended),
          r.data.length,
          _hexBytes(r.data, r.data.length),
          _hexBytes(r.changed, r.data.length),
          r.frames,
          r.periodMs,
        ].join(';'),
      );
    }
    return lines;
  }

  /// Marke zum Zeitpunkt der letzten Übersicht.
  String mark(String text) {
    final clean = text.replaceAll(RegExp(r'\s*[;\r\n]+\s*'), ' ').trim();
    return '$durationMs;${CanLogFormat.mark};;$clean;;;';
  }
}

/// Eine Marke im Mitschnitt.
typedef CanLogMark = ({int tMs, String text});

/// Gelesener Mitschnitt: die Übersichten in zeitlicher Folge.
class CanLog {
  CanLog({
    required this.messages,
    required this.marks,
    required this.source,
    this.start,
  });

  final List<MonitorMessage> messages;
  final List<CanLogMark> marks;
  final String source;
  final DateTime? start;

  int get durationMs => messages.isEmpty ? 0 : messages.last.timeMs;

  /// Liest einen Mitschnitt. Wirft [FormatException] mit Zeilennummer.
  static CanLog parse(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty || lines.first.trim() != CanLogFormat.title) {
      throw const FormatException('Kein Mitschnitt der CAN-Werkbank.');
    }
    var source = '';
    DateTime? start;
    final marks = <CanLogMark>[];
    final messages = <MonitorMessage>[];
    var records = <IdRecord>[];
    int? currentT;
    var seq = 0;

    void flush() {
      if (currentT != null && records.isNotEmpty) {
        messages.add(
          MonitorMessage(
            seq: seq++ & 0xFFFF,
            timeMs: currentT,
            records: records,
          ),
        );
      }
      records = [];
    }

    for (final (n, rawLine) in lines.indexed) {
      final line = rawLine.trim();
      if (line.isEmpty || line == CanLogFormat.columns) continue;
      if (line.startsWith('#')) {
        if (line.startsWith('# quelle=')) source = line.substring(9);
        if (line.startsWith('# start=')) {
          start = DateTime.tryParse(line.substring(8));
        }
        continue;
      }
      final cells = line.split(';');
      final t = cells.length < 4 ? null : int.tryParse(cells[0]);
      if (t == null) throw FormatException('Zeile ${n + 1}: $line');
      if (cells[1] == CanLogFormat.mark) {
        marks.add((tMs: t, text: cells[3]));
        continue;
      }
      if (cells[1] == CanLogFormat.lost) continue;
      final id = int.tryParse(cells[1], radix: 16);
      final data = _parseBytes(cells[3]);
      final changed = cells.length > 4 ? _parseBytes(cells[4]) : Uint8List(0);
      if (id == null || data == null || changed == null || data.length > 8) {
        throw FormatException('Zeile ${n + 1}: $line');
      }
      if (t != currentT) {
        flush();
        currentT = t;
      }
      records.add(
        IdRecord(
          rawId: cells[1].length > 3 ? id | CanLinkProtocol.extendedFlag : id,
          data: data,
          changed: Uint8List(8)
            ..setRange(0, changed.length.clamp(0, 8), changed),
          frames: cells.length > 5 ? int.tryParse(cells[5]) ?? 1 : 1,
          periodMs: cells.length > 6 ? int.tryParse(cells[6]) ?? 0 : 0,
        ),
      );
    }
    flush();
    return CanLog(
      messages: messages,
      marks: marks,
      source: source,
      start: start,
    );
  }
}

Uint8List? _parseBytes(String text) {
  final parts = text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final out = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p, radix: 16);
    if (v == null || v < 0 || v > 255) return null;
    out.add(v);
  }
  return Uint8List.fromList(out);
}

/// Spielt einen Mitschnitt wie einen verbundenen Leser ab. So lässt sich ein
/// Profil am Schreibtisch gegen eine aufgenommene Fahrt prüfen.
class ReplayConnection implements CanLinkConnection {
  /// [speed] 1 = Echtzeit. [autoPlay] false: nur über [step] weiterschalten
  /// (Tests).
  ReplayConnection(
    this.log, {
    String? name,
    this.speed = 1,
    bool autoPlay = true,
  }) : name = name ?? 'Wiedergabe' {
    if (autoPlay) _schedule();
  }

  final CanLog log;
  final double speed;

  @override
  final String name;

  final _monitor = StreamController<MonitorMessage>.broadcast();
  final _status = StreamController<StatusMessage>.broadcast();
  final _diagnostics = StreamController<DiagnosticsMessage>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  Timer? _timer;
  int _next = 0;
  int _frames = 0;
  final Set<int> _ids = {};

  /// true, wenn alle Übersichten abgespielt sind.
  bool get finished => _next >= log.messages.length;

  @override
  Stream<MonitorMessage> get monitor => _monitor.stream;

  @override
  Stream<StatusMessage> get status => _status.stream;

  @override
  Stream<DiagnosticsMessage> get diagnostics => _diagnostics.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  void _schedule() {
    if (finished || _monitor.isClosed) return;
    final previous = _next == 0 ? 0 : log.messages[_next - 1].timeMs;
    final wait = (log.messages[_next].timeMs - previous) / speed;
    _timer = Timer(Duration(milliseconds: wait.round()), () {
      step();
      _schedule();
    });
  }

  /// Die nächste Übersicht schicken.
  void step() {
    if (finished || _monitor.isClosed) return;
    final m = log.messages[_next++];
    for (final r in m.records) {
      _frames += r.frames;
      _ids.add(r.rawId);
    }
    _monitor.add(m);
    _status.add(
      StatusMessage(
        firmware: 'Wiedergabe',
        mode: BusMode.listenOnly,
        state: finished ? BusState.silent : BusState.ok,
        pairingOpen: false,
        usbHost: false,
        uptimeS: m.timeMs ~/ 1000,
        framesTotal: _frames,
        framesDropped: 0,
        idsSeen: _ids.length,
        supplyMv: 0,
      ),
    );
  }

  @override
  Future<void> send(Uint8List command) async {}

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _monitor.close();
    await _status.close();
    await _diagnostics.close();
    await _connected.close();
  }
}
