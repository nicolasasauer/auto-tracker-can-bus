# Auto Tracker CAN-Bus

[English](README.md) · **Deutsch**

Ein kleiner **CAN-Leser für die OBD-II-Buchse** zur Android-App
[**Auto Tracker**](https://play.google.com/store/apps/details?id=de.nicolasasauer.auto_tracker).
Der Leser hört den CAN-Bus des Autos mit und schickt die Werte per Bluetooth
an die App: Tempo, Drehzahl, Gang, Verbrauch, Kilometerstand und mehr, je
nach **Fahrzeugprofil** (JSON). Ein erstes Profil für den Peugeot 208 I
(2016) liegt bei.

Hier liegen Bauanleitung, Firmware und Fahrzeugprofile. Die Firmware lässt
sich **direkt im Browser flashen**, ohne Zusatzprogramme.

> **Nur mithören. Nutzung auf eigene Gefahr, ohne jede Gewähr.**
> Der CAN-Controller läuft im Listen-Only-Modus und sendet nichts auf den
> Bus, nicht einmal Bestätigungen (ACK); die Firmware enthält keinen Code
> zum Senden. Trotzdem gilt: Eingriffe am Fahrzeug, auch rein lesende,
> geschehen auf eigenes Risiko und können Fragen zur Garantie aufwerfen.
> Während der Fahrt nicht an Leser oder Handy hantieren. Für Schäden am
> Fahrzeug, an der Batterie oder sonstige Folgen übernimmt niemand eine
> Haftung (siehe [LICENSE](LICENSE)).

## Quickstart

1. **Teile besorgen und zusammenstecken:** siehe [Hardware](#hardware).
2. **Firmware flashen:** Leser per USB-C an den Computer, den
   [**Web-Flasher**](https://nicolasasauer.github.io/auto-tracker-can-bus/)
   in Chrome oder Edge öffnen und „Installieren“ klicken.
3. **Koppeln:** Auf derselben Seite „Kopplungscode holen“. Im Auto Tracker
   *Einstellungen → CAN-Leser (Beta)* einschalten, *CAN-Leser (OBD)* öffnen,
   „CAN-Leser suchen“, den Leser antippen und den Code eingeben.
4. **Ins Auto:** OBD-Kabel an die Klemme (Pin 6 → CAN-H, Pin 14 → CAN-L,
   Pin 4/5 → GND, Pin 16 **nicht**), siehe
   [Anschluss](#anschluss-an-die-obd-buchse). Zündung an: Die App zeigt die
   Werte live.
5. **Für ein Fahrzeug hinterlegen:** In *CAN-Leser (OBD)* den Leser einem
   Fahrzeug zuordnen. Während einer Fahrt verbindet sich die App dann selbst
   und speichert die Werte zur Fahrt.

## Inhalt

| Ordner | Inhalt |
|---|---|
| [`firmware/`](firmware/) | Firmware für den Leser (PlatformIO, C++). Kern in `lib/can_core`, auf dem PC getestet. |
| [`web/`](web/) | Web-Flasher: Firmware im Browser installieren und koppeln ([Seite](https://nicolasasauer.github.io/auto-tracker-can-bus/)) |
| [`packages/can_link/`](packages/can_link/) | Dart-Paket: BLE-Protokoll, Profile, Simulation. In [`profiles/`](packages/can_link/profiles/) die Fahrzeugprofile. |
| [`docs/`](docs/) | [Konzept](docs/CAN-KONZEPT.md), [BLE-Protokoll](docs/CAN-BLE-PROTOKOLL.md), [Recherche Peugeot 208](docs/FAHRZEUG-PEUGEOT-208.md) |

## Hardware

| Teil | Hinweis |
|---|---|
| **Seeed Studio XIAO ESP32-C6** | Mikrocontroller mit Bluetooth LE |
| **Seeed „XIAO CAN Bus Expansion Board“** | CAN-Controller MCP2515 (SPI, Quarz 16 MHz) und Transceiver SN65HVD230, Schraubklemme GND / CAN-H / CAN-L |
| **OBD-II-Kabel mit offenen Adern** | Stecker für die Buchse im Auto |
| USB-C-Kabel, Computer | zum Flashen und Koppeln; Laptop auf Akku auch zur Versorgung beim ersten Test |

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
3. **Versorgung über USB.** Den XIAO per USB versorgen (Laptop auf Akku oder
   USB-Netzteil im Auto). Das CAN-Board hat **keinen 12-V-Eingang**. Pin 16
   erst anschließen, wenn ein eigener Spannungsregler mit Schutzbeschaltung
   dazwischen sitzt (Sicherung, Verpolschutz, TVS-Diode, Regler für
   Eingänge bis 40 V; das Bordnetz hat Einbrüche beim Start und Spitzen,
   siehe [Konzept, Kapitel 7](docs/CAN-KONZEPT.md#7-hardware)).
4. Zündung an. Zeigt die App keine Werte: Im Web-Flasher „Kopplungscode
   holen“ und dann „Zustand anzeigen“ (oder auf der Konsole `status`).
   „still“ heißt, an der Buchse kommt ohne Anfrage nichts an. Das ist bei
   vielen neueren Autos normal, weil ein Gateway vor der Buchse sitzt.

Mehr zu Aufbau, Konsole und bekannten Grenzen: [`firmware/README.md`](firmware/README.md).

## Firmware flashen

**Im Browser (empfohlen):** [Web-Flasher](https://nicolasasauer.github.io/auto-tracker-can-bus/)
in Chrome oder Edge am Computer (Windows, macOS, Linux) öffnen, Leser per
USB-C anschließen, „Installieren“. Die Seite nimmt immer die Firmware des
neuesten Releases. Beim ersten Mal das Löschen bestätigen; bei einem Update
nicht löschen, dann bleibt die Kopplung erhalten. Handy, Firefox und Safari
können nicht auf USB-Geräte zugreifen.

**Mit esptool:** `can-logger-xiao-esp32c6-factory.bin` aus den
[Releases](../../releases) laden und
`esptool.py --chip esp32c6 write_flash 0x0 can-logger-xiao-esp32c6-factory.bin`.

**Selbst bauen** mit [PlatformIO](https://platformio.org/) (Kommandozeile
oder die Erweiterung für VS Code). Die Plattform „pioarduino“ und die
Bibliotheken lädt PlatformIO beim ersten Bau selbst.

```bash
pip install platformio
cd firmware
pio run -t upload          # bauen und über USB flashen
pio device monitor         # serielle Konsole, 115200 Baud
```

Kern-Tests ohne Hardware (nur ein C++-Compiler nötig):

```bash
bash tool/check.sh firmware
```

## Koppeln per Bluetooth (PIN)

Der Leser spricht nur mit **gekoppelten** Handys. Die Verbindung ist
verschlüsselt (LE Secure Connections mit Passkey). Neue Handys lassen sich
nur koppeln, solange der Leser per USB am Computer hängt:

1. Leser per USB an den Computer, im
   [Web-Flasher](https://nicolasasauer.github.io/auto-tracker-can-bus/)
   „Kopplungscode holen“. Alternativ eine serielle Konsole öffnen
   (`pio device monitor`, 115200 Baud) und `pair` eingeben. Es erscheint ein
   zufälliger **6-stelliger Code**; das Kopplungsfenster bleibt 2 Minuten
   offen.
2. Im Auto Tracker unter *CAN-Leser (OBD)* „CAN-Leser suchen“, den Leser
   antippen und im Kopplungsdialog von Android den Code eingeben.

Danach verbindet sich das Handy ohne erneute Eingabe. Höchstens 3 Handys;
`unpair` auf der Konsole löscht alle. Einzelheiten:
[BLE-Protokoll, Kapitel 4](docs/CAN-BLE-PROTOKOLL.md#4-koppeln-und-sicherheit).

## Im Auto Tracker

Der CAN-Leser ist im Auto Tracker als **Beta** für alle freigeschaltet:
*Einstellungen → CAN-Leser (Beta)* oder auf der Fahrzeugseite im Menü ⋮.
Dort:

- **Live-Werte** nach dem Fahrzeugprofil, Dashboard während der Fahrt
- **Fahrten mit CAN-Daten:** Verbrauch, Gang, Steigung, Kilometerstand
- **Mitschnitt** aller Botschaften, z. B. um ein neues Signal zu finden;
  „Für KI-Analyse teilen“ schickt Mitschnitt, Profil und eine Anleitung an
  die KI deiner Wahl. Ihre Antwort ist ein Profil, das sich in der App
  importieren und am Auto prüfen lässt. Achtung: Ein Mitschnitt kann die
  Fahrgestellnummer enthalten; die App bietet an, sie zu entfernen.
- **Profil** ansehen, bearbeiten, kopieren und importieren

## Eigene Profile beitragen

Profile sind JSON-Dateien im Arbeitsprofil-Format
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

1. Profil im Auto Tracker erstellen (Mitschnitt und KI, siehe oben), am Auto
   prüfen und auf der Profilseite kopieren.
2. Als `packages/can_link/profiles/<marke>_<modell>_<baujahr>_<bus>.json`
   ablegen und einen Pull Request öffnen. Im PR das Fahrzeug nennen
   (Modell, Baujahr, Motor) und wie die Signale geprüft wurden.
3. **Nichts Persönliches mitschicken:** keine Fahrgestellnummer (manche
   Autos senden sie im Klartext auf dem Bus, OBD Modus 09 PID 02),
   keine echten Mitschnitte, keine Kilometerstände, Orte oder Uhrzeiten
   in den Notizen.

## Frühere CAN-Werkbank

Bis v1.0.2 lag hier auch die Begleit-App **CAN-Werkbank** (Sniff-Ansicht,
Bits von Hand zuordnen, Simulation). Ihre Alltagsfunktionen stecken jetzt im
Auto Tracker, deshalb wird sie hier nicht mehr weiterentwickelt. Die alten
APKs stehen weiter unter [Releases](../../releases), der Quelltext in der
Git-Historie (Tag `v1.0.2`).

## Lizenz

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE).

Verwendete Abhängigkeiten und ihre Lizenzen:

| Abhängigkeit | Lizenz |
|---|---|
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) (BLE in der Firmware) | Apache-2.0 |
| [autowp-mcp2515](https://github.com/autowp/arduino-mcp2515) (MCP2515-Treiber) | MIT |
| [Arduino-ESP32](https://github.com/espressif/arduino-esp32) (Kern, über die Plattform [pioarduino](https://github.com/pioarduino/platform-espressif32)) | LGPL-2.1, ESP-IDF darunter Apache-2.0 |
| [ESP Web Tools](https://github.com/esphome/esp-web-tools) (Web-Flasher) | Apache-2.0 |
| Flutter, Dart SDK (`can_link`) | BSD-3-Clause |
| [universal_ble](https://pub.dev/packages/universal_ble) (Bluetooth LE in `can_link`) | BSD-3-Clause |
| [clock](https://pub.dev/packages/clock) | Apache-2.0 |

Die Lizenztexte liegen den jeweiligen Paketen bei.
