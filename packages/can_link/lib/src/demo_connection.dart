import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'connection.dart';
import 'messages.dart';

/// Simulierter CAN-Leser zum Ausprobieren ohne Hardware und für Tests.
///
/// Die Botschaften sind erfunden: Sie ähneln einem Fahrzeug-Bus (Tempo und
/// Drehzahl, die sich ändern, ein Blinker-Bit, langsame Temperaturen, OBD-
/// Antworten), sind aber keine echten Peugeot-Daten.
class DemoConnection implements CanLinkConnection {
  DemoConnection({Duration interval = const Duration(milliseconds: 200)}) {
    _timer = Timer.periodic(interval, (_) => tick(interval.inMilliseconds));
    // Erste Daten sofort, damit die Ansicht nicht leer startet.
    scheduleMicrotask(() => tick(0));
  }

  @override
  String get name => 'Simulation';

  final _monitor = StreamController<MonitorMessage>.broadcast();
  final _status = StreamController<StatusMessage>.broadcast();
  final _diagnostics = StreamController<DiagnosticsMessage>.broadcast();
  final List<double> _loadWindow = [];
  double _loadPeak = 0;
  final _connected = StreamController<bool>.broadcast();
  late final Timer _timer;
  final _rnd = Random(1);

  int _timeMs = 0;
  int _seq = 0;
  int _frames = 0;
  final Map<int, Uint8List> _last = {};

  /// Zuletzt empfangene Befehle (für Tests).
  final List<Uint8List> sentCommands = [];

  @override
  Stream<MonitorMessage> get monitor => _monitor.stream;

  @override
  Stream<StatusMessage> get status => _status.stream;

  @override
  Stream<DiagnosticsMessage> get diagnostics => _diagnostics.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  /// Simulierte Zeit um [ms] weiterschalten und eine Übersicht schicken.
  void tick(int ms) {
    if (_monitor.isClosed) return;
    _timeMs += ms;
    final t = _timeMs / 1000.0;
    final speed = (50 + 30 * sin(t / 8)).clamp(0, 250).round();
    final rpm = (900 + speed * 35 + 100 * sin(t)).round();
    final blinker = (_timeMs ~/ 400).isEven ? 1 : 0;
    final coolant = (min(90, 20 + t / 2)).round() + 40;

    final records = <IdRecord>[
      _record(
        0x0B6,
        [
          rpm >> 5 & 0xFF,
          rpm << 3 & 0xFF,
          speed >> 8,
          speed & 0xFF,
          0,
          0,
          0,
          0,
        ],
        frames: max(1, ms ~/ 50),
        periodMs: 50,
      ),
      _record(
        0x128,
        [0x00, blinker << 2, 0x00, 0x00],
        frames: max(1, ms ~/ 100),
        periodMs: 100,
      ),
      if (_timeMs % 1000 < ms || ms == 0)
        _record(0x0F6, [
          0x88,
          coolant,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x20,
        ], periodMs: 500),
      _record(0x7E8, [
        0x03,
        0x41,
        0x0D,
        speed,
        0x55,
        0x55,
        0x55,
        0x55,
      ], periodMs: 200),
      if (_rnd.nextInt(10) == 0)
        _record(0x18DAF110 | CanLinkProtocol.extendedFlag, [0x02, 0x7E, 0x00]),
    ];
    for (final r in records) {
      _frames += r.frames;
    }
    // Wie die Firmware: über Bytes kodiert und wieder zerlegt.
    _monitor.add(
      decodeMonitor(
        encodeMonitor(
          MonitorMessage(
            seq: _seq++ & 0xFFFF,
            timeMs: _timeMs,
            records: records,
          ),
        ),
      ),
    );

    // Status bei jeder Übersicht (der Leser schickt ihn jede Sekunde).
    _status.add(
      StatusMessage(
        firmware: 'Simulation',
        mode: BusMode.listenOnly,
        state: BusState.ok,
        pairingOpen: false,
        usbHost: false,
        uptimeS: _timeMs ~/ 1000,
        framesTotal: _frames,
        framesDropped: 0,
        idsSeen: _last.length,
        supplyMv: 12600,
      ),
    );

    // Buslast grob geschätzt: etwa 120 Bit je Botschaft bei 500 kbit/s.
    if (ms > 0) {
      final frames = records.fold<int>(0, (sum, r) => sum + r.frames);
      final load = frames * 120 / (ms / 1000) / 500000 * 100;
      _loadWindow.add(load);
      if (_loadWindow.length > 50) _loadWindow.removeAt(0);
      _loadPeak = max(_loadPeak, load);
    }
    final avg = _loadWindow.isEmpty
        ? 0.0
        : _loadWindow.reduce((a, b) => a + b) / _loadWindow.length;
    _diagnostics.add(
      decodeDiagnostics(
        encodeDiagnostics(
          DiagnosticsMessage(
            loadNowPct: _loadWindow.isEmpty ? 0 : _loadWindow.last,
            loadAvgPct: avg,
            loadPeakPct: _loadPeak,
            rxErrorCounter: 0,
            errorFlags: 0,
            errorEvents: 0,
            ringMaxFill: 3,
            ringCapacity: 512,
            resetReason: ResetReason.powerOn,
            bootCount: 1,
          ),
        ),
      ),
    );
  }

  IdRecord _record(
    int rawId,
    List<int> bytes, {
    int frames = 1,
    int periodMs = 0,
  }) {
    final data = Uint8List.fromList(bytes);
    final previous = _last[rawId];
    final changed = Uint8List(8);
    if (previous != null) {
      for (var i = 0; i < data.length && i < previous.length; i++) {
        changed[i] = data[i] ^ previous[i];
      }
    }
    _last[rawId] = data;
    return IdRecord(
      rawId: rawId,
      data: data,
      changed: changed,
      frames: frames,
      periodMs: periodMs,
    );
  }

  @override
  Future<void> send(Uint8List command) async => sentCommands.add(command);

  @override
  Future<void> close() async {
    _timer.cancel();
    _connected.add(false);
    await _monitor.close();
    await _status.close();
    await _diagnostics.close();
    await _connected.close();
  }
}
