import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'connection.dart';
import 'messages.dart';
import 'profile.dart';
import 'profile_runtime.dart';

/// Simulierter CAN-Leser, der Botschaften nach einem Fahrzeugprofil schickt:
/// Tempo, Drehzahl und Gang ändern sich wie bei einer ruhigen Stadtfahrt,
/// der Rest bleibt auf plausiblen Werten. Erfundene Werte, keine Aufnahme.
class ProfileDemoConnection implements CanLinkConnection {
  ProfileDemoConnection(
    this.profile, {
    Duration interval = const Duration(milliseconds: 250),
  }) {
    _timer = Timer.periodic(interval, (_) => tick(interval.inMilliseconds));
    scheduleMicrotask(() => tick(0));
  }

  final CanProfile profile;

  @override
  String get name => 'Simulation (${profile.title})';

  final _monitor = StreamController<MonitorMessage>.broadcast();
  final _status = StreamController<StatusMessage>.broadcast();
  final _diagnostics = StreamController<DiagnosticsMessage>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  late final Timer _timer;
  int _timeMs = 0;
  int _seq = 0;
  double _distanceM = 0;

  @override
  Stream<MonitorMessage> get monitor => _monitor.stream;
  @override
  Stream<StatusMessage> get status => _status.stream;
  @override
  Stream<DiagnosticsMessage> get diagnostics => _diagnostics.stream;
  @override
  Stream<bool> get connected => _connected.stream;

  /// Werte zur Zeit [t] in Sekunden, je Signalname.
  Map<String, double> valuesAt(double t) {
    final speed = max(0.0, 35 + 20 * sin(t / 6));
    final gear = speed < 1
        ? 0
        : (speed < 15
              ? 1
              : speed < 30
              ? 2
              : 3);
    final rpmPerKmh = switch (gear) {
      1 => 120.0,
      2 => 72.2,
      _ => 51.0,
    };
    return {
      'vehicle_speed': speed,
      'vehicle_speed_esp': speed,
      'wheel_speed_fl': speed,
      'wheel_speed_fr': speed,
      'wheel_speed_rl': speed,
      'wheel_speed_rr': speed,
      'engine_rpm': gear == 0 ? 850 : speed * rpmPerKmh,
      'gear': gear.toDouble(),
      'accel_pedal_raw': max(0, 20 + 20 * cos(t / 6)).roundToDouble(),
      'steering_angle': 30 * sin(t / 3),
      'coolant_temp': min(90.0, 20 + t / 4).roundToDouble(),
      'coolant_temp_2': min(90.0, 20 + t / 4).roundToDouble(),
      'fuel_level_raw': 74,
      'odometer': 123456 + (_distanceM / 1000).floorToDouble(),
      'distance_counter': (_distanceM * 10 % 65536) / 10,
      'battery_voltage': 14.2,
      'ambient_temp': 11.5,
      'long_accel': 20 / 6 * cos(t / 6) / 3.6,
      'idle_speed_target': 848,
    };
  }

  void tick(int ms) {
    if (_monitor.isClosed) return;
    _timeMs += ms;
    final t = _timeMs / 1000.0;
    final values = valuesAt(t);
    _distanceM += (values['vehicle_speed']! / 3.6) * ms / 1000;
    final records = <IdRecord>[];
    for (final m in profile.messages) {
      final data = Uint8List(m.dlc ?? 8);
      for (final s in m.signals) {
        if (values[s.name] case final v?) s.encodeInto(data, v);
      }
      records.add(
        IdRecord(
          rawId: m.rawId,
          data: data,
          frames: max(1, ms ~/ (ProfileRuntime.cycleMs(m) ?? 100)),
          periodMs: ProfileRuntime.cycleMs(m) ?? 0,
        ),
      );
    }
    _monitor.add(
      MonitorMessage(seq: _seq++ & 0xFFFF, timeMs: _timeMs, records: records),
    );
    _status.add(
      StatusMessage(
        firmware: 'Simulation',
        mode: BusMode.listenOnly,
        state: BusState.ok,
        pairingOpen: false,
        usbHost: false,
        uptimeS: _timeMs ~/ 1000,
        framesTotal: _seq * records.length,
        framesDropped: 0,
        idsSeen: records.length,
        supplyMv: 14200,
      ),
    );
  }

  @override
  Future<void> send(Uint8List command) async {}

  @override
  Future<void> close() async {
    if (_monitor.isClosed) return;
    _timer.cancel();
    _connected.add(false);
    await _monitor.close();
    await _status.close();
    await _diagnostics.close();
    await _connected.close();
  }
}
