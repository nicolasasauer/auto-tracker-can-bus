import 'package:can_link/can_link.dart';
import 'package:flutter/services.dart';

/// Profil des Peugeot 208 (2016) aus der ersten Auswertung am Auto.
Future<CanProfile> loadPeugeot208Profile() async => CanProfile.parse(
  await rootBundle.loadString('assets/profiles/peugeot_208_2016.profile.json'),
);

/// Profil zu den erfundenen Botschaften der Simulation ([DemoConnection]),
/// zum Ausprobieren ohne Auto.
const simulationProfile = CanProfile(
  profileId: 'simulation',
  messages: [
    MessageDef(
      rawId: 0x0B6,
      name: 'MOTOR',
      dlc: 8,
      signals: [
        SignalDef(
          name: 'engine_rpm',
          start: 0,
          length: 13,
          unit: 'rpm',
          confidence: SignalConfidence.verified,
        ),
        SignalDef(
          name: 'vehicle_speed',
          start: 16,
          length: 16,
          unit: 'km/h',
          confidence: SignalConfidence.verified,
        ),
      ],
    ),
    MessageDef(
      rawId: 0x128,
      name: 'BLINKER',
      dlc: 4,
      signals: [
        SignalDef(
          name: 'turn_signal',
          start: 13,
          length: 1,
          confidence: SignalConfidence.verified,
        ),
      ],
    ),
    MessageDef(
      rawId: 0x0F6,
      name: 'TEMPERATUR',
      dlc: 8,
      signals: [
        SignalDef(
          name: 'coolant_temp',
          start: 8,
          length: 8,
          offset: -40,
          unit: '°C',
          confidence: SignalConfidence.probable,
        ),
      ],
    ),
  ],
);
