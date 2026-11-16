# CAN-Werkbank (app/)

Kleine Flutter-App (Android) zum Mithören des CAN-Busses und zum Erstellen von Fahrzeugprofilen.
Konzept: `docs/CAN-KONZEPT.md`, Kapitel 9 (9.1 Arbeitsprofil, 9.2 Mitschnitt, 9.3 Ablauf mit KI).

- `lib/src/workbench.dart` – Zustand der App; die Screens liegen daneben (`*_screen.dart`).
- Protokoll, Profile und Verbindung kommen aus `packages/can_link`; dort ändern, nicht hier nachbauen.
- Texte stehen hier fest im Code (nur Deutsch, keine ARB-Dateien).
- Tests mit erzeugten Botschaften, keine echten Mitschnitte (siehe `CLAUDE.md` im Stamm).
- Prüfen: `bash tool/check.sh werkbank`.
