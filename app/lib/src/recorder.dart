import 'dart:io';

import 'package:can_link/can_link.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// Ein gespeicherter Mitschnitt.
typedef RecordingInfo = ({String name, int bytes, DateTime modified});

/// Ablage der Mitschnitte: Dateien im App-Ordner, in Tests im Speicher.
abstract interface class RecordingStore {
  /// Neuen Mitschnitt anlegen und zum Schreiben öffnen.
  Future<RecordingSink> create(String name);

  /// Neueste zuerst.
  Future<List<RecordingInfo>> list();

  Future<String> read(String name);
  Future<void> delete(String name);

  /// Pfad der Datei zum Teilen, null wenn es keine Datei gibt.
  String? pathOf(String name);
}

abstract interface class RecordingSink {
  void write(Iterable<String> lines);

  /// Bisher Geschriebenes sichern.
  Future<void> flush();
}

class MemoryRecordingStore implements RecordingStore {
  final Map<String, StringBuffer> _texts = {};

  @override
  Future<RecordingSink> create(String name) async =>
      _MemorySink(_texts[name] = StringBuffer());

  @override
  Future<List<RecordingInfo>> list() async => [
    for (final e in _texts.entries.toList().reversed)
      (name: e.key, bytes: e.value.length, modified: clock.now()),
  ];

  @override
  Future<String> read(String name) async => _texts[name]!.toString();

  @override
  Future<void> delete(String name) async => _texts.remove(name);

  @override
  String? pathOf(String name) => null;
}

class _MemorySink implements RecordingSink {
  _MemorySink(this._buffer);
  final StringBuffer _buffer;

  @override
  void write(Iterable<String> lines) {
    for (final l in lines) {
      _buffer.writeln(l);
    }
  }

  @override
  Future<void> flush() async {}
}

class FileRecordingStore implements RecordingStore {
  FileRecordingStore(this.directory);

  final Directory directory;

  File _file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  @override
  Future<RecordingSink> create(String name) async {
    await directory.create(recursive: true);
    return _FileSink(_file(name));
  }

  @override
  Future<List<RecordingInfo>> list() async {
    if (!await directory.exists()) return const [];
    final out = <RecordingInfo>[];
    await for (final f in directory.list()) {
      if (f is! File || !f.path.endsWith('.csv')) continue;
      final stat = await f.stat();
      out.add((
        name: f.uri.pathSegments.last,
        bytes: stat.size,
        modified: stat.modified,
      ));
    }
    return out..sort((a, b) => b.name.compareTo(a.name));
  }

  @override
  Future<String> read(String name) => _file(name).readAsString();

  @override
  Future<void> delete(String name) => _file(name).delete();

  @override
  String? pathOf(String name) => _file(name).path;
}

/// Hängt gesammelte Zeilen an die Datei an. Die Schreibvorgänge laufen
/// nacheinander, damit sich nichts überholt.
class _FileSink implements RecordingSink {
  _FileSink(this._file);

  final File _file;
  final StringBuffer _buffer = StringBuffer();
  Future<void> _pending = Future.value();

  @override
  void write(Iterable<String> lines) {
    for (final l in lines) {
      _buffer.writeln(l);
    }
  }

  @override
  Future<void> flush() {
    if (_buffer.isEmpty) return _pending;
    final text = _buffer.toString();
    _buffer.clear();
    return _pending = _pending.then(
      (_) => _file.writeAsString(text, mode: FileMode.append, flush: true),
    );
  }
}

/// Nimmt die Übersichten des Lesers als Mitschnitt auf ([CanLogWriter]).
class Recorder extends ChangeNotifier {
  Recorder(this.store);

  final RecordingStore store;

  /// So oft wird während der Aufnahme auf die Platte geschrieben. Stürzt die
  /// App ab, fehlt höchstens dieser Abschnitt.
  static const flushEveryMs = 2000;

  CanLogWriter? _writer;
  RecordingSink? _sink;
  String? _name;
  int _flushedAtMs = 0;
  int _marks = 0;

  bool get recording => _writer != null;
  String? get name => _name;
  int get rows => _writer?.rows ?? 0;
  int get ids => _writer?.ids ?? 0;
  int get durationMs => _writer?.durationMs ?? 0;
  int get marks => _marks;

  /// Aufnahme beginnen. [source] ist der Name des Lesers.
  Future<void> start(String source) async {
    if (recording) return;
    final now = clock.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name =
        'mitschnitt_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.csv';
    final sink = await store.create(name);
    final writer = CanLogWriter(start: now, source: source);
    sink.write(writer.header());
    _sink = sink;
    _writer = writer;
    _name = name;
    _flushedAtMs = 0;
    _marks = 0;
    notifyListeners();
  }

  void add(MonitorMessage message) {
    final writer = _writer;
    if (writer == null) return;
    _sink!.write(writer.add(message));
    if (writer.durationMs - _flushedAtMs >= flushEveryMs) {
      _flushedAtMs = writer.durationMs;
      _sink!.flush();
    }
    notifyListeners();
  }

  /// Marke setzen, z. B. „Blinker links“.
  void mark(String text) {
    final writer = _writer;
    if (writer == null) return;
    _sink!.write([writer.mark(text)]);
    _marks++;
    notifyListeners();
  }

  /// Aufnahme beenden. Gibt den Namen des Mitschnitts zurück.
  Future<String?> stop() async {
    final sink = _sink;
    if (sink == null) return null;
    final name = _name;
    _writer = null;
    _sink = null;
    notifyListeners();
    await sink.flush();
    return name;
  }
}
