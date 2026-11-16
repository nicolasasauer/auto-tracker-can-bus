import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'connection.dart';
import 'messages.dart';
import 'uuids.dart';

/// Ein gefundener CAN-Leser.
class CanLinkDevice {
  const CanLinkDevice(this.id, this.name, this.rssi);
  final String id;
  final String name;
  final int? rssi;
}

/// Verbindung zum echten CAN-Leser über Bluetooth LE.
///
/// Koppeln: Der Leser verlangt eine verschlüsselte, authentifizierte
/// Verbindung. Beim ersten Mal zeigt Android den Kopplungsdialog; den Code
/// gibt der Leser auf seiner seriellen Konsole aus (`pair`). Danach verbindet
/// sich das Handy ohne Eingabe. Die Kopplung gilt für das ganze Handy, also
/// auch für andere Apps mit diesem Paket.
class BleCanLinkConnection implements CanLinkConnection {
  BleCanLinkConnection._(this._deviceId, this.name);

  final String _deviceId;
  @override
  final String name;

  final _monitor = StreamController<MonitorMessage>.broadcast();
  final _status = StreamController<StatusMessage>.broadcast();
  final _diagnostics = StreamController<DiagnosticsMessage>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];

  /// Nach CAN-Lesern suchen. Liefert die bisher gefundenen Geräte.
  static Stream<List<CanLinkDevice>> scan() {
    final found = <String, CanLinkDevice>{};
    late final StreamController<List<CanLinkDevice>> controller;
    StreamSubscription<BleDevice>? sub;
    controller = StreamController<List<CanLinkDevice>>(
      onListen: () async {
        try {
          await UniversalBle.requestPermissions();
          sub = UniversalBle.scanStream.listen((d) {
            found[d.deviceId] = CanLinkDevice(
              d.deviceId,
              d.name ?? 'CAN-Leser',
              d.rssi,
            );
            controller.add(found.values.toList());
          });
          await UniversalBle.startScan(
            scanFilter: ScanFilter(withServices: [CanLinkUuids.service]),
          );
        } catch (e, st) {
          controller.addError(e, st);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        await UniversalBle.stopScan();
      },
    );
    return controller.stream;
  }

  static Future<BleCanLinkConnection> connect(CanLinkDevice device) async {
    await UniversalBle.stopScan();
    final c = BleCanLinkConnection._(device.id, device.name);
    await c._open();
    return c;
  }

  Future<void> _open() async {
    _subs.add(UniversalBle.connectionStream(_deviceId).listen(_connected.add));
    await UniversalBle.connect(_deviceId);
    // Kopplung (fragt beim ersten Mal nach dem Code des Lesers).
    if (await UniversalBle.isPaired(_deviceId) != true) {
      await UniversalBle.pair(_deviceId);
    }
    await UniversalBle.discoverServices(_deviceId);
    try {
      await UniversalBle.requestMtu(_deviceId, 247);
    } catch (_) {
      // Nicht jede Plattform kann das; der Leser schickt dann weniger
      // Einträge je Nachricht.
    }
    _subs.add(
      UniversalBle.characteristicValueStream(
        _deviceId,
        CanLinkUuids.monitor,
      ).listen((bytes) => _tryAdd(_monitor, () => decodeMonitor(bytes))),
    );
    _subs.add(
      UniversalBle.characteristicValueStream(
        _deviceId,
        CanLinkUuids.status,
      ).listen((bytes) => _tryAdd(_status, () => decodeStatus(bytes))),
    );
    await UniversalBle.subscribeNotifications(
      _deviceId,
      CanLinkUuids.service,
      CanLinkUuids.monitor,
    );
    await UniversalBle.subscribeNotifications(
      _deviceId,
      CanLinkUuids.service,
      CanLinkUuids.status,
    );
    // Ältere Firmware hat kein Diagnose-Merkmal; dann bleibt es leer.
    try {
      _subs.add(
        UniversalBle.characteristicValueStream(
          _deviceId,
          CanLinkUuids.diagnostics,
        ).listen(
          (bytes) => _tryAdd(_diagnostics, () => decodeDiagnostics(bytes)),
        ),
      );
      await UniversalBle.subscribeNotifications(
        _deviceId,
        CanLinkUuids.service,
        CanLinkUuids.diagnostics,
      );
    } catch (_) {}
    final first = await UniversalBle.read(
      _deviceId,
      CanLinkUuids.service,
      CanLinkUuids.status,
    );
    _tryAdd(_status, () => decodeStatus(first));
  }

  void _tryAdd<T>(StreamController<T> controller, T Function() decode) {
    try {
      controller.add(decode());
    } on CanLinkFormatException catch (e) {
      controller.addError(e);
    }
  }

  @override
  Stream<MonitorMessage> get monitor => _monitor.stream;

  @override
  Stream<StatusMessage> get status => _status.stream;

  @override
  Stream<DiagnosticsMessage> get diagnostics => _diagnostics.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> send(Uint8List command) => UniversalBle.write(
    _deviceId,
    CanLinkUuids.service,
    CanLinkUuids.control,
    command,
  );

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await UniversalBle.disconnect(_deviceId);
    } catch (_) {}
    await _monitor.close();
    await _status.close();
    await _diagnostics.close();
    await _connected.close();
  }
}
