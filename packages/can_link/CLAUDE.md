# can_link (packages/can_link)

Gemeinsames Dart-Paket für die CAN-Werkbank und andere Apps. Dateiübersicht: `README.md` (kurz, lesen).

- **Protokoll:** `lib/src/messages.dart` muss zu `firmware/lib/can_core/src/protocol.*` passen.
  Beschreibung: `docs/CAN-BLE-PROTOKOLL.md`. `test/protocol_test.dart` und
  `firmware/test/test_protocol.cpp` prüfen **dieselben Beispielbytes**: beide zusammen ändern.
- **Profile:** Format in `docs/CAN-KONZEPT.md`, Kapitel 3, 4 und 9.1. `profiles/*.json` sind Assets.
  Herkunft der Signale des 208: `docs/FAHRZEUG-PEUGEOT-208.md`.
- **Speicherregeln und Sampler** (`profile_runtime.dart`, `signal_sampler.dart`): `store` im Profil,
  siehe `docs/CAN-KONZEPT.md`, Kapitel 9.4.
- Änderungen hier betreffen die Werkbank: `bash tool/check.sh link`, danach `werkbank`.
