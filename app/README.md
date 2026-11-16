# CAN-Werkbank

Begleit-App für den CAN-Leser (`firmware/`): Bus mithören, CAN-IDs und
OBD-Werte live ansehen, Signale zuordnen und Fahrzeugprofile erstellen.
Konzept: [`docs/CAN-KONZEPT.md`](../docs/CAN-KONZEPT.md), Kapitel 9.

- **Simulation:** funktioniert ohne Hardware.
- **CAN-Leser:** beim ersten Mal koppeln. Leser per USB an den PC, in der
  seriellen Konsole `pair` eingeben, den angezeigten Code im
  Kopplungsdialog des Handys eingeben (siehe
  [`docs/CAN-BLE-PROTOKOLL.md`](../docs/CAN-BLE-PROTOKOLL.md), Kapitel 4).
- **Profil:** Signale anlegen (in der Detailansicht einer CAN-ID Bits
  antippen), importieren und teilen. Beispiele im Menü der Profil-Seite:
  Peugeot 208 (2016) und Simulation.
- **Signale beobachten:** anpinnen, Verlauf als Graph, mit Bitlage und
  Faktor spielen.
- **Mitschnitt:** roter Punkt in der Sniff-Ansicht. Unter „Mitschnitte“
  teilen (auch als Paket für eine KI-Analyse) oder wieder abspielen.

Formate und Ablauf: Konzept, Kapitel 9.1 bis 9.3.

Icon: `tool/icon/generate_icon.mjs` erzeugt Android-Icon und PNGs (Aufruf im Skript).

Bauen: `flutter build apk --release --target-platform android-arm64`. Ohne
eigenen Schlüssel signiert Gradle mit dem Debug-Schlüssel (nur für den
eigenen Gebrauch). Die CI baut die APK bei jedem PR
(`.github/workflows/werkbank.yml`).
