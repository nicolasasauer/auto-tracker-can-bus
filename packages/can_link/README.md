# can_link

Gemeinsame Schnittstelle zum CAN-Leser (`firmware/`). Genutzt von der
CAN-Werkbank (`app/`); andere Apps können es genauso einbinden.

- `messages.dart`: BLE-Protokoll (Nachrichten zerlegen, Befehle kodieren),
  beschrieben in [`docs/CAN-BLE-PROTOKOLL.md`](../../docs/CAN-BLE-PROTOKOLL.md)
- `obd2.dart`: genormte OBD-II-PIDs, Erkennen von OBD-Anfragen und -Antworten
- `bus_view.dart`: Tabelle je CAN-ID für die Sniff-Ansicht
- `ble_connection.dart`: Verbindung über Bluetooth LE (`universal_ble`)
- `demo_connection.dart`: Simulation ohne Hardware
- `profile_runtime.dart`: was eine App zur Laufzeit zusätzlich zum Profil
  (`profile.dart`) braucht: Speicherregeln (`store`), Kodieren für die
  Simulation, `ProfileDecoder` mit dem letzten Wert je Signal
- `signal_sampler.dart`: verdichtet Live-Werte nach den Speicherregeln
- `profile_demo_connection.dart`: Simulation nach einem Profil
- `profiles/`: Fahrzeugprofile als Assets, in Apps unter
  `packages/can_link/profiles/…` (z. B. `peugeot_208_2016_hs_can.json`,
  an einem 208 mitgehört)

Tests: `flutter test`. `test/protocol_test.dart` prüft dieselben Beispielbytes
wie die Firmware-Tests.
