# CAN-Leser-Firmware (firmware/)

XIAO ESP32-C6 mit MCP2515, PlatformIO (Arduino, Plattform „pioarduino“). Aufbau, Pins, Konsole,
bekannte Grenzen: `README.md`. Konzept: `docs/CAN-KONZEPT.md`, Kapitel 5 (Sicherheit) und 8 (Firmware).

- `lib/can_core/src/` – plattformunabhängiger Kern (ID-Übersicht, Filter, Protokoll, Kopplungsfenster,
  Ringpuffer, Buslast). **Kein Arduino-Include**, damit er auf dem PC testbar bleibt.
- `src/` – ESP32-Teil: BLE (`ble_link`), Empfang (`CanReceiver`, `mcp2515_receiver`), Konsole, `main.cpp`.
- `include/config.h` – Pins.
- `test/` – Tests des Kerns mit `mini_test.h`, ohne Hardware.

## Regeln
- **Stufe 1: nur mithören.** Listen-Only, kein Code zum Senden auf den Bus, auch keine ACKs.
- Protokolländerungen immer zusammen mit `packages/can_link` (gleiche Beispielbytes in beiden Tests)
  und `docs/CAN-BLE-PROTOKOLL.md`.
- Neue Logik möglichst in `lib/can_core` mit Test, nicht in `src/`.

## Befehle
- Tests: `bash tool/check.sh firmware` (im Repo-Stamm).
- Bauen: `pio run -e xiao_esp32c6 -s` (`-s` = still). `pio` ist lokal nicht unbedingt installiert; die CI baut bei jedem PR.
