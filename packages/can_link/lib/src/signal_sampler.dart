import 'dart:math' as math;

import 'profile.dart';
import 'profile_runtime.dart';

/// Verdichtet Live-Werte nach den Speicherregeln des Profils zu Zeilen je
/// Sekunde, wie sie in die Datenbank kommen.
///
/// - `sample`: je Fenster Mittel (Schlüssel = Name), Maximum (`name.max`),
///   Minimum (`name.min`); nur `max` gewählt: Name = Maximum.
/// - `on_change`: jeder neue Wert.
/// - `deadband`: neuer Wert, wenn er sich um `delta` geändert hat und
///   `min_interval_s` vergangen ist.
/// - `counter`: Summe der Schritte seit Beginn des Abschnitts (Überlauf
///   berücksichtigt), einmal je Sekunde; z. B. gefahrene Meter. Ein neuer
///   Abschnitt ([startSegment]) beginnt wieder bei 0.
///
/// Signale ohne Regel im Profil: Schalter (1 Bit) bei jeder Änderung,
/// alle anderen als Mittel über [defaultIntervalS] Sekunden. So lässt sich
/// jedes importierte Profil ohne Nacharbeit aufzeichnen.
class SignalSampler {
  SignalSampler(CanProfile profile, {this.defaultIntervalS = 5})
    : _signals = {
        for (final m in profile.messages)
          for (final s in m.signals) s.name: s,
      };

  final Map<String, SignalDef> _signals;
  final double defaultIntervalS;

  StoreRule _rule(SignalDef s) =>
      s.store ??
      (s.isFlag
          ? const StoreRule(mode: StoreMode.onChange)
          : StoreRule(mode: StoreMode.sample, intervalS: defaultIntervalS));
  final Map<String, _State> _state = {};

  /// Fertige Werte je Sekunde (ms seit 1970, auf die Sekunde abgerundet).
  final Map<int, Map<String, double>> _rows = {};

  /// Werte zur Zeit [timeMs] (ms seit 1970) übernehmen.
  void add(int timeMs, Map<String, double> values) {
    for (final MapEntry(key: name, value: v) in values.entries) {
      final s = _signals[name];
      if (s == null) continue;
      final rule = _rule(s);
      final st = _state.putIfAbsent(name, _State.new);
      switch (rule.mode) {
        case StoreMode.sample:
          final windowMs = math.max(1, (rule.intervalS * 1000).round());
          final window = timeMs ~/ windowMs * windowMs;
          if (st.window != null && st.window != window) _close(s, st);
          st.window = window;
          st.sum += v;
          st.count++;
          st.max = math.max(st.max, v);
          st.min = math.min(st.min, v);
        case StoreMode.onChange:
          if (st.last != v) _put(timeMs, name, v);
          st.last = v;
        case StoreMode.deadband:
          final due =
              st.last == null ||
              ((v - st.last!).abs() >= rule.delta &&
                  timeMs - st.lastMs >= rule.minIntervalS * 1000);
          if (due) {
            _put(timeMs, name, v);
            st.last = v;
            st.lastMs = timeMs;
          }
        case StoreMode.counter:
          if (st.last case final prev?) {
            final wrap = (rule.wrap ?? 0) * s.factor;
            var step = v - prev;
            if (step < 0 && wrap > 0) step += wrap;
            if (step >= 0) st.sum += step;
          }
          st.last = v;
          final second = timeMs ~/ 1000;
          if (st.window != second) {
            st.window = second;
            _put(timeMs, name, st.sum);
          } else {
            _rows[second * 1000]![name] = st.sum;
          }
      }
    }
  }

  /// Beginn eines neuen Abschnitts, z. B. nach einem Verbindungsabbruch.
  ///
  /// Offene Fenster werden geschlossen (keine Mittel über die Lücke),
  /// Zähler beginnen wieder bei 0 (über eine Lücke ist die Differenz
  /// nicht eindeutig, weil der Rohwert überlaufen kann), und `on_change`
  /// bzw. `deadband` schreiben den ersten Wert danach in jedem Fall, damit
  /// jeder Abschnitt mit einem bekannten Stand beginnt.
  void startSegment() {
    for (final MapEntry(key: name, value: st) in _state.entries) {
      final s = _signals[name]!;
      switch (_rule(s).mode) {
        case StoreMode.sample:
          _close(s, st);
          st.window = null;
        case StoreMode.counter:
          st
            ..last = null
            ..sum = 0
            ..window = null;
        case StoreMode.onChange:
        case StoreMode.deadband:
          st.last = null;
      }
    }
  }

  void _close(SignalDef s, _State st) {
    if (st.count == 0 || st.window == null) return;
    final agg = _rule(s).agg;
    final at = st.window!;
    if (agg.contains('mean')) {
      _put(at, s.name, st.sum / st.count);
      if (agg.contains('max')) _put(at, '${s.name}.max', st.max);
    } else if (agg.contains('max')) {
      _put(at, s.name, st.max);
    }
    if (agg.contains('min')) _put(at, '${s.name}.min', st.min);
    st
      ..sum = 0
      ..count = 0
      ..max = double.negativeInfinity
      ..min = double.infinity;
  }

  void _put(int timeMs, String key, double v) =>
      (_rows[timeMs ~/ 1000 * 1000] ??= {})[key] = v;

  /// Fertige Zeilen abholen. [all]: auch offene Fenster schließen (Ende der
  /// Fahrt oder der Verbindung).
  Map<DateTime, Map<String, double>> drain({bool all = false}) {
    if (all) {
      for (final MapEntry(key: name, value: st) in _state.entries) {
        final s = _signals[name]!;
        if (_rule(s).mode == StoreMode.sample) {
          _close(s, st);
          st.window = null;
        }
      }
    }
    final out = {
      for (final MapEntry(:key, :value) in _rows.entries)
        DateTime.fromMillisecondsSinceEpoch(key): value,
    };
    _rows.clear();
    return out;
  }
}

class _State {
  int? window;
  double sum = 0;
  int count = 0;
  double max = double.negativeInfinity;
  double min = double.infinity;
  double? last;
  int lastMs = 0;
}
