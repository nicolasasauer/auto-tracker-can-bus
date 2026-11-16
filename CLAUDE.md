# Hinweise für Claude

## Projekt
CAN-Leser am OBD-Stecker (Seeed XIAO ESP32-C6 + XIAO CAN Bus Expansion Board, MCP2515) und die
Android-App **CAN-Werkbank** (Flutter): CAN-Bus mithören, Signale zuordnen, Fahrzeugprofile erstellen.
Öffentliches Repository, Lizenz MIT.
Sprache von UI, Doku, Kommentaren und Commits: Deutsch. Nur `README.md` zusätzlich auf Englisch
(`README.de.md` auf Deutsch, beide zusammen ändern).

## Aufbau
- `app/` – CAN-Werkbank (Flutter, nur Android). Eigene `CLAUDE.md`.
- `packages/can_link/` – Dart-Paket: BLE-Protokoll, Profile, Simulation, Sampler. `profiles/` = Fahrzeugprofile (JSON).
- `firmware/` – Firmware (PlatformIO, C++). Der Kern `lib/can_core` läuft auch auf dem PC. Eigene `CLAUDE.md`.
- `docs/` – `CAN-KONZEPT.md` (Profilformat Kapitel 3, 4, 9.1), `CAN-BLE-PROTOKOLL.md`, `FAHRZEUG-PEUGEOT-208.md`.
  Erst die Überschriften suchen (`^#`), dann nur das Kapitel lesen.
- `.github/workflows/` – `werkbank.yml`, `firmware.yml`, `release.yml`.

## Befehle
    bash tool/check.sh werkbank                      # Werkbank: Analyse + Tests
    bash tool/check.sh werkbank test/foo_test.dart   # nur diese Tests
    bash tool/check.sh link                          # can_link
    bash tool/check.sh firmware                      # Kern-Tests der Firmware (nur C++-Compiler nötig)
    bash tool/check.sh alle
    bash tool/check.sh screenshots                   # README-Bilder neu (nur Simulation), dann einchecken
    cd firmware && pio run -e xiao_esp32c6 -s        # Firmware bauen

- `flutter test` nie ohne `--reporter failures-only`.
- Flutter-Version wie in der CI: 3.47.6, stable.

## Tests
- Jeder neue oder geänderte Test bekommt eine **Gegenprobe**: ohne die Änderung rot, mit ihr grün. Im PR festhalten.
- Protokolländerungen: `packages/can_link/test/protocol_test.dart` und `firmware/test/test_protocol.cpp`
  prüfen dieselben Beispielbytes; beide zusammen mit `docs/CAN-BLE-PROTOKOLL.md` ändern.

## Git
- Änderungen über Pull Requests auf `main`. PR-Beschreibung: `## Was hat sich geändert`, dann `## Tests` (mit Gegenproben).

## Release
- Auslöser: Tag `v*` pushen (`v0.2.0`; mit Bindestrich wie `v0.2.0-beta1` als Vorabversion).
- `release.yml` läuft im Environment **`release`** (Settings → Environments):
  - Deployment branches and tags: nur Tags `v*`.
  - Required reviewers: der Besitzer (Freigabe jedes Laufs); „Allow administrators to bypass“ aus.
  - Secrets nur dort, nicht als Repo-Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
    optional `KEY_PASSWORD`.
- Fremde Actions in `release.yml` sind auf Commit-SHAs festgelegt. Beim Aktualisieren SHA und
  Versionskommentar zusammen ändern (`git ls-remote --tags https://github.com/<owner>/<action>.git`).

## No-Gos
- **Nie auf den CAN-Bus senden.** Die Firmware hört nur mit (Listen-Only, auch keine ACKs). Kein Code, der
  Botschaften sendet, keinen Befehl zum Umschalten in einen aktiven Modus.
- **Keine echten Mitschnitte einchecken**, schon gar nicht mit Fahrgestellnummer: Beim Peugeot 208 senden
  `0x492`, `0x4B2` und `0x4D2` die FIN im Klartext, dazu OBD-Antworten Modus 09 PID 02. Auch Tempo,
  Lenkwinkel und Gierrate zusammen zeichnen die gefahrene Strecke nach. Tests nutzen erzeugte Daten.
- Keine Kilometerstände, Orte, Uhrzeiten oder Namen aus echten Fahrten in Profile, Doku oder Tests.
- **Auch PR-Beschreibungen, Kommentare, Commit-Nachrichten und Branch-Namen sind öffentlich.** Darin
  nichts Privates: keine entfernten Werte zitieren (etwa „Kilometerstand X entfernt“), keine Verweise auf
  private Repos, Apps, Rechner oder Schlüssel. Fragen und Prüfpunkte für den Besitzer gehören in den Chat.
- Keine Signaturschlüssel oder Passwörter einchecken. Release-APKs nur mit dem Schlüssel aus den
  Repo-Secrets; ohne Schlüssel bricht `release.yml` ab. Das nicht umgehen.
- **Keine eigenen Runner (`self-hosted`)**: Das Repository ist öffentlich, fremde PRs könnten Code darauf
  ausführen. Workflows laufen auf `ubuntu-latest`; keine Secrets in `pull_request`-Workflows,
  kein `pull_request_target`.
