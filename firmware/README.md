# CAN-Leser – Firmware

Firmware für den Prototyp des CAN-Lesers: **Seeed Studio XIAO ESP32-C6** auf
dem **Seeed „XIAO CAN Bus Expansion Board“** (CAN-Controller MCP2515 über SPI,
Quarz 16 MHz). Konzept: [`docs/CAN-KONZEPT.md`](../docs/CAN-KONZEPT.md),
Protokoll zu den Apps: [`docs/CAN-BLE-PROTOKOLL.md`](../docs/CAN-BLE-PROTOKOLL.md).

**Stufe 1: nur mithören.** Der CAN-Controller läuft im Listen-Only-Modus und
sendet nichts auf den Bus, nicht einmal Bestätigungen (ACK). Die Firmware hat
keinen Code zum Senden.

## Was sie kann

- Alle Botschaften am OBD-Bus (500 kbit/s) lesen und **je CAN-ID
  zusammenfassen**: letzte Daten, geänderte Bits, Anzahl, Takt
- Die Übersicht alle 200 ms per **Bluetooth LE** an ein gekoppeltes Handy
  schicken (CAN-Werkbank)
- Filter für CAN-IDs, von der App aus einstellbar
- **Koppeln nur mit USB am PC:** Code auf der seriellen Konsole
- **Diagnose** jede Sekunde: Buslast (aktuell, Mittel 10 s, Spitze),
  Empfangsfehler, Höchststand des Zwischenpuffers, Grund des letzten
  Neustarts und Zahl der Starts (die Werkbank zeigt sie unter „Diagnose“)
- LED leuchtet, solange Botschaften kommen

## Aufbau und erster Test

1. **XIAO auf das CAN-Board stecken.**
2. **OBD-Kabel durchmessen.** Die Aderfarben des Kabels sind nicht
   verlässlich. Mit dem Durchgangsprüfer gegen die Buchse messen:
   Pin 6 = CAN-H, Pin 14 = CAN-L, Pin 4/5 = Masse, Pin 16 = +12 V.
   Nicht benutzte Adern isolieren.
3. **Abschlusswiderstand:** Auf diesem Board ist er ab Werk **nicht aktiv**
   (Lötpad P1 auf der Rückseite offen, laut Seeed-Wiki). Fürs Auto so lassen,
   der Bus dort ist schon abgeschlossen. Nur für einen Testbus am
   Schreibtisch P1 schließen. Gegenprobe mit dem Multimeter zwischen CAN-H
   und CAN-L an der Klemme (ohne Auto): kein Durchgang statt 120 Ω.
4. **Anschließen, zuerst ohne +12 V:** nur CAN-H, CAN-L und Masse an die
   Klemme (Reihenfolge auf dem Board: GND, CAN-H, CAN-L). Den XIAO per USB vom Laptop versorgen, der dabei auf Akku läuft.
   Die rote Ader (+12 V) bleibt isoliert: Das CAN-Board hat keinen
   12-V-Eingang. Dauerhafte Versorgung aus der Buchse (Pin 16) nur über einen
   eigenen Spannungsregler mit Schutzbeschaltung (Sicherung, Verpolschutz,
   TVS-Diode, Eingang bis 40 V), siehe `docs/CAN-KONZEPT.md`, Kapitel 7.
5. **Konsole öffnen** (115200 Baud) und `status` eingeben:
   - „CAN-Controller fehlt“: Board nicht richtig gesteckt oder falscher
     CS-Pin, siehe unten.
   - „still“: Es kommen keine Botschaften. Beim 208 I gut möglich, weil das
     BSI als Gateway vor der Buchse sitzt. Zündung an und Motor laufen lassen
     und erneut prüfen.
   - „Botschaften kommen“: Die LED leuchtet, die Werkbank zeigt die IDs.
   - **Empfangsfehler > 0** bei wenig Verkehr: falsche Bitrate, CAN-H und
     CAN-L vertauscht oder ein Abschlusswiderstand zu viel.
   - **Buslast:** Bis etwa 50 % reicht der MCP2515; darüber wird es mit
     seinen zwei Empfangspuffern knapp.
6. **Motor starten** und danach `status`: Steht als Grund
   „Spannungseinbruch“, hat der Leser den Start nicht überstanden (bei
   Versorgung aus der Buchse; über USB vom Laptop nicht zu erwarten).

## Bauen und flashen

Mit [PlatformIO](https://platformio.org/) (Kommandozeile oder die
Erweiterung für VS Code):

```bash
cd firmware
pio run -t upload          # bauen und über USB flashen
pio device monitor         # serielle Konsole
```

Die Plattform „pioarduino“ (Arduino-ESP32 3.x) und die Bibliotheken lädt
PlatformIO beim ersten Bau selbst. Die CI baut die Firmware bei jedem PR
(`.github/workflows/firmware.yml`) und hängt sie als Artefakt an.

## Serielle Konsole

| Befehl | Wirkung |
|---|---|
| `status` | Bus, Zähler, Interrupts, Buslast, Empfangsfehler, Pufferreserve, Neustarts, gekoppelte Geräte |
| `pair` | Kopplungsfenster für 2 Minuten öffnen und den Code anzeigen |
| `unpair` | alle gekoppelten Handys löschen |

**Handy koppeln:** Leser per USB an den PC, `pair` eingeben, in der
CAN-Werkbank „CAN-Leser suchen“ und verbinden, den angezeigten 6-stelligen
Code im Kopplungsdialog von Android eingeben. Ohne offenes Fenster lehnt der
Leser neue Handys ab. Höchstens 3 Handys.

## Pins

| Funktion | XIAO-Pin | |
|---|---|---|
| SPI SCK / MISO / MOSI | D8 / D9 / D10 | Standard-SPI des XIAO |
| MCP2515 Chip-Select | D7 | laut Seeed-Wiki, `include/config.h` |
| MCP2515 Interrupt (INT) | D6 | **unbekannt**, im Wiki nicht genannt; `include/config.h` |
| LED | eingebaut (GPIO 15, aktiv low) | |

Stimmt der INT-Pin nicht (oder ist er am Board gar nicht zum XIAO geführt),
läuft der Leser trotzdem, fragt dann aber nur jede Millisekunde nach (mehr
Verluste bei viel Verkehr). `status` zeigt in dem Fall
„Interrupts: 0“ trotz Botschaften und einen Hinweis.

## Tests

Der plattformunabhängige Kern (`lib/can_core`: ID-Übersicht, Filter,
Protokoll, Kopplungsfenster, Ringpuffer, Buslast) läuft auch auf dem PC:

```bash
./test/run_tests.sh
```

Braucht nur einen C++-Compiler. Den Ringpuffer zusätzlich auf Datenrennen
prüfen: `SANITIZE=0 CXX="g++ -fsanitize=thread" ./test/run_tests.sh`. `test/test_protocol.cpp` prüft dieselben
Beispielbytes wie `packages/can_link/test/protocol_test.dart`.

## Bekannte Grenzen

- Der **MCP2515 hat nur zwei Empfangspuffer.** Damit nichts verloren geht,
  holt eine eigene Aufgabe mit hoher Priorität die Botschaften ab, sobald
  der INT-Pin meldet, und legt sie mit Empfangszeit in einen Ringpuffer
  (512 Botschaften, gut 100 ms bei vollem Bus). BLE und Konsole laufen
  getrennt davon und dürfen sich Zeit lassen. Bei sehr hoher Buslast kann
  der MCP2515 trotzdem überlaufen; der Leser zählt das als „verloren“.
  Reicht das nicht: Der ESP32-C6 hat zwei eingebaute CAN-Controller (TWAI)
  mit großem Puffer. Dafür braucht es nur einen Transceiver (z. B.
  SN65HVD230-Modul) statt des MCP2515-Boards. Die Firmware kapselt den
  Empfang hinter `CanReceiver`, ein TWAI-Treiber lässt sich daneben stellen.
- Noch kein Schlafmodus, keine Spannungsmessung, kein Ringpuffer im Flash.
- Keine Abfragen (OBD-PIDs, UDS). Die kommen mit Stufe 2.

## Unterlagen der Teile

- Seeed-Wiki zum CAN-Board (Klemme GND/CAN-H/CAN-L, Chip-Select D7,
  Abschlusswiderstand P1): https://wiki.seeedstudio.com/xiao-can-bus-expansion/
- Schaltplan und Platine des Boards:
  https://files.seeedstudio.com/wiki/xiao_can_bus_board/CAN_DEV_XIAO.zip
- Datenblatt MCP2515:
  https://files.seeedstudio.com/wiki/xiao_can_bus_board/MCP2515-Stand-Alone-CAN-Controller-with-SPI-200018-708845.pdf
- Seeed Studio XIAO ESP32-C6: https://wiki.seeedstudio.com/xiao_esp32c6_getting_started/
