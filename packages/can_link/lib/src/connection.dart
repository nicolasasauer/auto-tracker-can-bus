import 'dart:typed_data';

import 'messages.dart';

/// Eine bestehende Verbindung zum CAN-Leser (echt über BLE oder simuliert).
abstract interface class CanLinkConnection {
  /// Name für die Anzeige.
  String get name;

  Stream<MonitorMessage> get monitor;
  Stream<StatusMessage> get status;

  /// Diagnose (Buslast, Fehler, Neustarts, Pufferreserve), jede Sekunde.
  Stream<DiagnosticsMessage> get diagnostics;

  /// true, solange verbunden.
  Stream<bool> get connected;

  /// Befehl schicken, siehe [CanLinkCommands].
  Future<void> send(Uint8List command);

  Future<void> close();
}
