# Auto Tracker CAN-Bus

[English](README.md) · **Deutsch**

Ein kleiner **CAN-Leser für die OBD-II-Buchse** und die Android-App
**CAN-Werkbank**: CAN-Bus des Autos mithören, Botschaften live ansehen,
Signale (Drehzahl, Tempo, Lenkwinkel …) den Bits zuordnen und daraus ein
**Fahrzeugprofil** (JSON) machen. Ein erstes Profil für den Peugeot 208 I
(2016) liegt bei.

> **Nur mithören. Nutzung auf eigene Gefahr, ohne jede Gewähr.**
> Der CAN-Controller läuft im Listen-Only-Modus und sendet nichts auf den
> Bus, nicht einmal Bestätigungen (ACK); die Firmware enthält keinen Code
> zum Senden. Trotzdem gilt: Eingriffe am Fahrzeug, auch rein lesende,
> geschehen auf eigenes Risiko und können Fragen zur Garantie aufwerfen.
> Während der Fahrt nicht an Leser oder Handy hantieren. Für Schäden am
> Fahrzeug, an der Batterie oder sonstige Folgen übernimmt niemand eine
> Haftung (siehe [LICENSE](LICENSE)).

## Inhalt

| Ordner | Inhalt |
|---|---|
| [`firmware/`](firmware/) | Firmware für den Leser (PlatformIO, C++). Kern in `lib/can_core`, auf dem PC getestet. |
| [`app/`](app/) | CAN-Werkbank, Android-App (Flutter) |
| [`packages/can_link/`](packages/can_link/) | Dart-Paket: BLE-Protokoll, Profile, Simulation. In [`profiles/`](packages/can_link/profiles/) die Fahrzeugprofile. |
| [`docs/`](docs/) | [Konzept](docs/CAN-KONZEPT.md), [BLE-Protokoll](docs/CAN-BLE-PROTOKOLL.md), [Recherche Peugeot 208](docs/FAHRZEUG-PEUGEOT-208.md) |

## Hardware

| Teil | Hinweis |
|---|---|
| **Seeed Studio XIAO ESP32-C6** | Mikrocontroller mit Bluetooth LE |
| **Seeed „XIAO CAN Bus Expansion Board“** | CAN-Controller MCP2515 (SPI, Quarz 16 MHz) und Transceiver SN65HVD230, Schraubklemme GND / CAN-H / CAN-L |
| **OBD-II-Kabel mit offenen Adern** | Stecker für die Buchse im Auto |
| USB-C-Kabel, Laptop | zum Flashen und zur Versorgung beim ersten Test |

Den XIAO auf das CAN-Board stecken. Pins (siehe `firmware/include/config.h`):
SPI SCK/MISO/MOSI = D8/D9/D10, Chip-Select des MCP2515 = **D7**
(laut Seeed-Wiki), Interrupt = **D6** (angenommen; im Wiki nicht genannt.
Stimmt er nicht, fragt die Firmware jede Millisekunde ab und meldet das unter
`status`).

### Anschluss an die OBD-Buchse

| OBD-Pin | Belegung | an das CAN-Board |
|---|---|---|
| **6** | CAN-H (genormter OBD-Bus, 500 kbit/s) | Klemme CAN-H |
| **14** | CAN-L | Klemme CAN-L |
| **4 / 5** | Fahrzeug- / Signalmasse | Klemme GND |
| **16** | +12 V Dauerplus | **nicht anschließen**, Ader isolieren (siehe unten) |

1. **Kabel durchmessen.** Die Aderfarben sind nicht verlässlich. Mit dem
   Durchgangsprüfer gegen den Stecker messen. Nicht benutzte Adern isolieren.
2. **Abschlusswiderstand:** auf dem Board ab Werk **nicht aktiv** (Lötpad P1
   auf der Rückseite offen). Fürs Auto so lassen, der Bus dort ist schon
   abgeschlossen. Nur für einen Testbus am Schreibtisch P1 schließen.
   Gegenprobe ohne Auto: zwischen CAN-H und CAN-L an der Klemme kein
   Durchgang statt 120 Ω.
3. **Versorgung über USB.** Den XIAO per USB vom Laptop versorgen, der dabei
   auf Akku läuft. Das CAN-Board hat **keinen 12-V-Eingang**. Pin 16 erst
   anschließen, wenn ein eigener Spannungsregler mit Schutzbeschaltung
   dazwischen sitzt (Sicherung, Verpolschutz, TVS-Diode, Regler für
   Eingänge bis 40 V; das Bordnetz hat Einbrüche beim Start und Spitzen,
   siehe [Konzept, Kapitel 7](docs/CAN-KONZEPT.md#7-hardware)).
4. Zündung an, Konsole öffnen (siehe unten) und `status` eingeben. „still“
   heißt, an der Buchse kommt ohne Anfrage nichts an. Das ist bei vielen
   neueren Autos normal, weil ein Gateway vor der Buchse sitzt.

Mehr zu Aufbau, Konsole und bekannten Grenzen: [`firmware/README.md`](firmware/README.md)
(auf Deutsch).

## Firmware bauen und flashen

Mit [PlatformIO](https://platformio.org/) (Kommandozeile oder die Erweiterung
für VS Code). Die Plattform „pioarduino“ (Arduino-ESP32 3.x) und die
Bibliotheken lädt PlatformIO beim ersten Bau selbst.

```bash
pip install platformio
cd firmware
pio run -t upload          # bauen und über USB flashen
pio device monitor         # serielle Konsole, 115200 Baud
```

Fertige Firmware (`can-logger-xiao-esp32c6.bin`) liegt auch unter
[Releases](../../releases).

Kern-Tests ohne Hardware (nur ein C++-Compiler nötig):

```bash
bash tool/check.sh firmware
```

## Koppeln per Bluetooth (PIN)

Der Leser spricht nur mit **gekoppelten** Handys. Die Verbindung ist
verschlüsselt (LE Secure Connections mit Passkey). Neue Handys lassen sich
nur koppeln, solange der Leser per USB am PC hängt:

1. Leser per USB an den PC, Konsole öffnen (`pio device monitor`).
2. `pair` eingeben. Die Konsole zeigt einen zufälligen **6-stelligen Code**.
   Das Kopplungsfenster bleibt 2 Minuten offen.
3. In der CAN-Werkbank „CAN-Leser suchen“, verbinden und im
   Kopplungsdialog von Android den Code eingeben.

Danach verbindet sich das Handy ohne erneute Eingabe. Höchstens 3 Handys;
`unpair` auf der Konsole löscht alle. Einzelheiten:
[BLE-Protokoll, Kapitel 4](docs/CAN-BLE-PROTOKOLL.md#4-koppeln-und-sicherheit).

## CAN-Werkbank

**Installieren:** Die APK (arm64, für aktuelle Android-Handys) liegt unter
[Releases](../../releases). Herunterladen und installieren (Installation aus
unbekannten Quellen erlauben). Die App fragt nach den Bluetooth-Rechten.

**Selbst bauen** (Flutter 3.47.6, stable):

```bash
cd app
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Ohne eigenen Schlüssel signiert Gradle mit dem Debug-Schlüssel. Für den
eigenen Gebrauch reicht das. Die APKs unter „Releases“ tragen eine andere
Signatur und lassen sich deshalb nicht darüber installieren.

**Arbeiten mit der Werkbank:**

1. **Mithören:** Leser verbinden (oder „Simulation“ ohne Hardware). Die
   Sniff-Ansicht zeigt jede CAN-ID mit Bytes, Takt und Anzahl; geänderte
   Bytes leuchten auf. Genormte OBD-Anfragen und -Antworten erscheinen gleich
   mit Namen und Einheit.
2. **Signale zuordnen:** Eine CAN-ID antippen und im Bitraster die Bits eines
   Signals markieren, Faktor und Offset einstellen. „Faktor aus Sollwert“
   rechnet den Faktor aus dem Wert, den Tacho oder Bordcomputer gerade
   zeigen. Signale anpinnen und den Verlauf als Graph beobachten.
3. **Mitschnitt:** roter Punkt in der Sniff-Ansicht, dabei Marken setzen
   („Blinker links“). Später abspielen oder als Paket für eine KI-Analyse
   teilen.
4. **Profil exportieren:** Auf der Profil-Seite teilen oder als Datei
   speichern; importieren geht aus Datei oder Zwischenablage.

Beispielprofile im Menü der Profil-Seite: Peugeot 208 (2016) und Simulation.

## Eigene Profile beitragen

Profile sind JSON-Dateien im Format der Werkbank
([Konzept, Kapitel 9.1](docs/CAN-KONZEPT.md#91-arbeitsprofil); Code:
`packages/can_link/lib/src/profile.dart`):

```json
{
  "profile_id": "peugeot_208_2016_hs_can",
  "schema_version": 1,
  "vehicle": {"make": "Peugeot", "model": "208", "year": 2016},
  "messages": [
    {
      "id": "0x208", "name": "ENGINE_1", "dlc": 8,
      "signals": [
        {"name": "engine_rpm", "start": 0, "length": 16, "signed": false,
         "factor": 0.125, "offset": 0, "unit": "rpm", "confidence": "verified"}
      ]
    }
  ]
}
```

- `start`: Abstand vom höchstwertigen Bit von Byte 0 (0 = Byte 0 Bit 7),
  Signale sind Big Endian. Mit `"byte_order": "little"` gilt die Zählweise
  von DBC/Intel.
- `wert = roh × factor + offset`; `length` 1 bis 63.
- `confidence`: `verified` (am Auto oder an einem zweiten Signal
  gegengeprüft), `probable`, `guess`. Bitte ehrlich angeben.
- Unbekannte Felder (`note`, `cycle_ms`, `store`, `ignored` …) bleiben
  erhalten; `note` ist gut für die Herkunft eines Signals.

So geht's:

1. Profil in der Werkbank erstellen und exportieren.
2. Als `packages/can_link/profiles/<marke>_<modell>_<baujahr>_<bus>.json`
   ablegen und einen Pull Request öffnen. Im PR das Fahrzeug nennen
   (Modell, Baujahr, Motor) und wie die Signale geprüft wurden.
3. **Nichts Persönliches mitschicken:** keine Fahrgestellnummer (manche
   Autos senden sie im Klartext auf dem Bus, OBD Modus 09 PID 02),
   keine echten Mitschnitte, keine Kilometerstände, Orte oder Uhrzeiten
   in den Notizen.

## Lizenz

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE).

Verwendete Abhängigkeiten und ihre Lizenzen (geprüft für die Versionen in
`platformio.ini` und `app/pubspec.lock`):

| Abhängigkeit | Lizenz |
|---|---|
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) (BLE in der Firmware) | Apache-2.0 |
| [autowp-mcp2515](https://github.com/autowp/arduino-mcp2515) (MCP2515-Treiber) | MIT |
| [Arduino-ESP32](https://github.com/espressif/arduino-esp32) (Kern, über die Plattform [pioarduino](https://github.com/pioarduino/platform-espressif32)) | LGPL-2.1, ESP-IDF darunter Apache-2.0 |
| Flutter, Dart SDK | BSD-3-Clause |
| [universal_ble](https://pub.dev/packages/universal_ble) (Bluetooth LE in der App) | BSD-3-Clause |
| [file_picker](https://pub.dev/packages/file_picker) | MIT |
| [path_provider](https://pub.dev/packages/path_provider), [share_plus](https://pub.dev/packages/share_plus) | BSD-3-Clause |
| [clock](https://pub.dev/packages/clock) | Apache-2.0 |
| übrige indirekte Dart-Pakete | überwiegend BSD-3-Clause oder MIT; `material_color_utilities` Apache-2.0; `bluez` und `dbus` (nur Linux, über `universal_ble`) MPL-2.0 |

Die Lizenztexte liegen den jeweiligen Paketen bei.
