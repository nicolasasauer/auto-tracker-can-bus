import 'dart:io';

import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = CanProfile.parse(
    File('profiles/peugeot_208_2016_hs_can.json').readAsStringSync(),
  );
  const t0 = 1700000000000; // volle Sekunde

  test(
    'sample: je Sekunde Mittel und Maximum, offenes Fenster erst am Ende',
    () {
      final s = SignalSampler(profile);
      s.add(t0, {'engine_rpm': 1000});
      s.add(t0 + 400, {'engine_rpm': 2000});
      s.add(t0 + 1100, {'engine_rpm': 3000});
      final rows = s.drain();
      expect(rows, {
        DateTime.fromMillisecondsSinceEpoch(t0): {
          'engine_rpm': 1500,
          'engine_rpm.max': 2000,
        },
      });
      final rest = s.drain(all: true);
      expect(rest.values.single, {'engine_rpm': 3000, 'engine_rpm.max': 3000});
    },
  );

  test('on_change: nur neue Werte', () {
    final s = SignalSampler(profile);
    s.add(t0, {'gear': 1});
    s.add(t0 + 100, {'gear': 1});
    s.add(t0 + 2000, {'gear': 2});
    final rows = s.drain();
    expect(rows.length, 2);
    expect(rows[DateTime.fromMillisecondsSinceEpoch(t0 + 2000)], {'gear': 2});
  });

  test('deadband: erst ab 1 K Änderung und 10 s Abstand', () {
    final s = SignalSampler(profile);
    s.add(t0, {'coolant_temp': 20});
    s.add(t0 + 1000, {'coolant_temp': 25}); // zu früh
    s.add(t0 + 12000, {'coolant_temp': 20.5}); // zu wenig
    s.add(t0 + 13000, {'coolant_temp': 22});
    final values = s.drain().values.expand((r) => r.values).toList();
    expect(values, [20, 22]);
  });

  test('je Sekunde zählt der letzte Wert', () {
    final s = SignalSampler(profile);
    s.add(t0, {'gear': 1});
    s.add(t0 + 500, {'gear': 2});
    expect(s.drain().values.single, {'gear': 2});
  });

  test('counter: Meter seit Beginn, auch über den Überlauf', () {
    final s = SignalSampler(profile);
    s.add(t0, {'distance_counter': 6553.0});
    s.add(t0 + 1000, {'distance_counter': 6553.5}); // +0,5 m
    // Überlauf bei 6553,6 m: +1,1 m.
    s.add(t0 + 2000, {'distance_counter': 1.0});
    final rows = s.drain();
    expect(
      rows[DateTime.fromMillisecondsSinceEpoch(t0 + 2000)]!['distance_counter'],
      closeTo(1.6, 1e-6),
    );
  });

  test('ohne Regel: Mittel über 5 s, Schalter bei Änderung', () {
    final s = SignalSampler(profile);
    s.add(t0, {'steering_speed_raw': 2, 'turn_signal_left': 0});
    s.add(t0 + 3000, {'steering_speed_raw': 4, 'turn_signal_left': 1});
    s.add(t0 + 5000, {'steering_speed_raw': 9});
    final rows = s.drain();
    expect(rows[DateTime.fromMillisecondsSinceEpoch(t0)], {
      'steering_speed_raw': 3,
      'turn_signal_left': 0,
    });
    expect(rows[DateTime.fromMillisecondsSinceEpoch(t0 + 3000)], {
      'turn_signal_left': 1,
    });
  });

  test('Profil: Zähler werden gezählt, nicht gemittelt', () {
    StoreRule rule(String name) => profile.messages
        .expand((m) => m.signals)
        .firstWhere((s) => s.name == name)
        .store!;
    expect(rule('fuel_used_counter_raw').mode, StoreMode.counter);
    expect(rule('fuel_used_counter_raw').wrap, 256);
    expect(rule('distance_counter').mode, StoreMode.counter);
    expect(rule('distance_counter').wrap, 65536);
    expect(rule('odometer').mode, StoreMode.onChange);
  });

  test('Profil: Lenkwinkel je Sekunde mit Mittel, Minimum und Maximum', () {
    final rule = profile.messages
        .expand((m) => m.signals)
        .firstWhere((s) => s.name == 'steering_angle')
        .store!;
    expect(rule.mode, StoreMode.sample);
    expect(rule.intervalS, 1);
    expect(rule.agg, containsAll(['mean', 'min', 'max']));
    // Einlenken nach links und zurück innerhalb einer Sekunde bleibt
    // sichtbar, auch wenn das Mittel klein ist.
    final s = SignalSampler(profile);
    s.add(t0, {'steering_angle': 0});
    s.add(t0 + 300, {'steering_angle': 40});
    s.add(t0 + 600, {'steering_angle': -10});
    final rows = s.drain(all: true);
    expect(rows[DateTime.fromMillisecondsSinceEpoch(t0)], {
      'steering_angle': 10,
      'steering_angle.max': 40,
      'steering_angle.min': -10,
    });
  });

  test('Kraftstoffzähler: Schritte seit Beginn, auch über den Überlauf', () {
    final s = SignalSampler(profile);
    s.add(t0, {'fuel_used_counter_raw': 250});
    s.add(t0 + 1000, {'fuel_used_counter_raw': 254}); // +4
    s.add(t0 + 2000, {'fuel_used_counter_raw': 3}); // Überlauf: +5
    final rows = s.drain();
    expect(
      rows[DateTime.fromMillisecondsSinceEpoch(
        t0 + 2000,
      )]!['fuel_used_counter_raw'],
      9,
    );
  });

  test('neuer Abschnitt: Zähler zählen nicht über die Lücke', () {
    final s = SignalSampler(profile);
    s.add(t0, {'distance_counter': 100.0, 'engine_rpm': 1000});
    s.add(t0 + 1000, {'distance_counter': 110.0}); // +10 m
    s.startSegment();
    // Nach der Lücke steht der Zähler niedriger (z. B. 6,5 km weiter mit
    // Überlauf): ohne neuen Abschnitt kämen fast 6,5 km dazu.
    s.add(t0 + 60000, {'distance_counter': 50.0});
    s.add(t0 + 61000, {'distance_counter': 53.0}); // +3 m
    final rows = s.drain(all: true);
    DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(t0 + ms);
    expect(rows[at(1000)]!['distance_counter'], closeTo(10, 1e-6));
    // Ab dem neuen Abschnitt wieder ab 0.
    expect(rows[at(60000)]!['distance_counter'], 0);
    expect(rows[at(61000)]!['distance_counter'], closeTo(3, 1e-6));
    // Das offene Fenster vor der Lücke wurde geschlossen, nicht mit
    // Werten danach vermischt.
    expect(rows[at(0)]!['engine_rpm'], 1000);
  });

  test('Verbrauchszähler: Schritte seit Beginn über den Überlauf bei 256', () {
    final s = SignalSampler(profile);
    s.add(t0, {'fuel_used_counter_raw': 250});
    s.add(t0 + 1000, {'fuel_used_counter_raw': 4}); // +10
    s.add(t0 + 2000, {'fuel_used_counter_raw': 7}); // +3
    final rows = s.drain();
    expect(
      rows[DateTime.fromMillisecondsSinceEpoch(
        t0 + 2000,
      )]!['fuel_used_counter_raw'],
      13,
    );
  });
}
