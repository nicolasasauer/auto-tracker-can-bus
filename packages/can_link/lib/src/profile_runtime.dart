import 'dart:typed_data';

import 'messages.dart';
import 'profile.dart';

/// Was eine App zur Laufzeit aus einem [CanProfile] braucht:
/// Speicherregeln, Kodieren (Simulation), Dekodieren der Übersichten.

/// Art der Speicherung eines Signals (Profilfeld `store.mode`).
enum StoreMode { sample, onChange, deadband, counter }

/// Speicherregel aus dem Profil: wie oft und wie verdichtet ein Signal in
/// die Datenbank kommt. Live angezeigt wird es unabhängig davon so oft,
/// wie es der Leser liefert.
class StoreRule {
  const StoreRule({
    required this.mode,
    this.intervalS = 1,
    this.agg = const ['mean'],
    this.delta = 0,
    this.minIntervalS = 0,
    this.wrap,
  });

  factory StoreRule.fromJson(Map<String, Object?> j) => StoreRule(
    mode: switch (j['mode']) {
      'on_change' => StoreMode.onChange,
      'deadband' => StoreMode.deadband,
      'counter' => StoreMode.counter,
      _ => StoreMode.sample,
    },
    intervalS: (j['interval_s'] as num? ?? 1).toDouble(),
    agg: [
      for (final a in j['agg'] as List? ?? const ['mean']) '$a',
    ],
    delta: (j['delta'] as num? ?? 0).toDouble(),
    minIntervalS: (j['min_interval_s'] as num? ?? 0).toDouble(),
    wrap: (j['wrap'] as num?)?.toInt(),
  );

  final StoreMode mode;

  /// `sample`: Länge eines Fensters in Sekunden.
  final double intervalS;

  /// `sample`: `mean`, `max`, `min` je Fenster.
  final List<String> agg;

  /// `deadband`: so viel Änderung, bevor wieder gespeichert wird.
  final double delta;
  final double minIntervalS;

  /// `counter`: Überlauf des Rohwerts (z. B. 65536).
  final int? wrap;
}

extension SignalRuntime on SignalDef {
  /// Speicherregel aus `store`; `null` = keine im Profil.
  StoreRule? get store => switch (extra['store']) {
    final Map<Object?, Object?> m => StoreRule.fromJson(
      m.cast<String, Object?>(),
    ),
    _ => null,
  };

  /// Ein Bit breit: Schalter oder Merker.
  bool get isFlag => length == 1;

  /// Schreibt [value] (umgerechnet) in [data]; Gegenstück zu [valueFrom],
  /// für Simulation und Tests. Zu große Werte werden abgeschnitten.
  void encodeInto(Uint8List data, double value) {
    var raw = ((value - offset) / factor).round();
    // Niederwertigstes Bit zuerst, Positionen vom höchst- zum
    // niederwertigsten Bit.
    for (final p in bitPositions.reversed) {
      final byte = p >> 3;
      final shift = 7 - p % 8;
      data[byte] = (data[byte] & ~(1 << shift)) | ((raw & 1) << shift);
      raw >>= 1;
    }
  }
}

extension ProfileRuntime on CanProfile {
  /// Titel für die Anzeige: Fahrzeug, sonst die Kennung.
  String get title => vehicleLabel.isEmpty ? profileId : vehicleLabel;

  /// Bekannte, aber bedeutungslose IDs aus `ignored` (Zähler, Prüfsummen).
  Set<int> get ignoredIds => {
    for (final i in extra['ignored'] as List? ?? const [])
      if (i is Map && i['id'] is String)
        ?int.tryParse(
          (i['id'] as String).toLowerCase().replaceFirst('0x', ''),
          radix: 16,
        ),
  };

  /// Takt einer Botschaft laut `cycle_ms`.
  static int? cycleMs(MessageDef m) => (m.extra['cycle_ms'] as num?)?.toInt();

  /// Mitgeliefertes Profil des Peugeot 208 als Asset dieses Pakets.
  static const peugeot208Asset =
      'packages/can_link/profiles/peugeot_208_2016_hs_can.json';
}

/// Ein dekodierter Wert mit dem Zeitpunkt (ms des Lesers), zu dem er kam.
class SignalValue {
  const SignalValue(this.value, this.timeMs);
  final double value;
  final int timeMs;
}

/// Hält den zuletzt gesehenen Wert jedes Signals aus den Übersichten des
/// CAN-Lesers.
class ProfileDecoder {
  ProfileDecoder(this.profile) : _ignored = profile.ignoredIds;

  final CanProfile profile;
  final Set<int> _ignored;
  final Map<String, SignalValue> values = {};

  /// IDs auf dem Bus, die das Profil nicht kennt (weder Signal noch
  /// ignoriert); Hinweis auf ein anderes Auto oder Lücken im Profil.
  final Set<int> unknownIds = {};

  /// Signale einer Übersicht als Name → Wert.
  Map<String, double> decode(MonitorMessage m) => {
    for (final r in m.records)
      if (!r.rtr)
        for (final s
            in profile.message(r.rawId)?.signals ?? const <SignalDef>[])
          s.name: ?s.valueFrom(r.data),
  };

  /// Übersicht übernehmen; liefert, ob sich ein Wert geändert hat.
  bool add(MonitorMessage m) {
    var changed = false;
    for (final r in m.records) {
      if (r.rtr) continue;
      final message = profile.message(r.rawId);
      if (message == null) {
        if (!r.extended && !_ignored.contains(r.id)) unknownIds.add(r.id);
        continue;
      }
      for (final s in message.signals) {
        final v = s.valueFrom(r.data);
        if (v == null) continue;
        if (values[s.name]?.value != v) changed = true;
        values[s.name] = SignalValue(v, m.timeMs);
      }
    }
    return changed;
  }

  void clear() {
    values.clear();
    unknownIds.clear();
  }
}
