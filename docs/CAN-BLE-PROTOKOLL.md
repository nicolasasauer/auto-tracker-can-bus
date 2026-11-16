# CAN-Leser – BLE-Protokoll

Schnittstelle zwischen der Firmware (`firmware/`) und den Apps. Apps nutzen
sie über das Dart-Paket `packages/can_link`, allen voran die CAN-Werkbank
(Sniffing, Profile). Ergänzt [`CAN-KONZEPT.md`](CAN-KONZEPT.md).

Stand: **Protokollversion 1**, Stufe 1 (nur mithören). Neue Nachrichten oder
Felder bekommen eine neue Versionsnummer; ältere Apps ignorieren unbekannte
Nachrichtentypen.

## 1. GATT-Dienst

| Name | UUID | Eigenschaften | Inhalt |
|---|---|---|---|
| Dienst „CAN-Leser“ | `e7cec12e-2ee5-4284-ad6a-0703c3a17296` | – | wird beworben, die Apps suchen danach |
| Status | `ee9f0489-a96e-4e62-b798-0f9d1a820508` | lesen, benachrichtigen | Nachricht `0x02` |
| Übersicht | `386e5ff1-e339-49e5-bd0d-1d6deb060a3b` | benachrichtigen | Nachricht `0x01` |
| Steuerung | `d12d8602-4d4b-456b-a672-ff97e3b2a4ca` | schreiben | Befehle `0x10`–`0x12` |
| Diagnose | `73314b58-7edf-4e94-b961-75569ead600f` | lesen, benachrichtigen | Nachricht `0x03`, jede Sekunde (ab Firmware mit Diagnose; ältere haben das Merkmal nicht) |

Alle Merkmale verlangen eine **verschlüsselte und authentifizierte**
Verbindung (gekoppeltes Gerät, siehe Kapitel 4). Die Firmware schickt
Benachrichtigungen nur an solche Verbindungen.

Zahlen sind **Little Endian**. Die Firmware fordert eine MTU von 247 an.

## 2. Nachrichten vom Leser

### 2.1 `0x01` Übersicht je CAN-ID

Die Firmware sieht jede Botschaft, schickt aber nur alle 200 ms (einstellbar)
eine Zusammenfassung je CAN-ID. Enthalten sind nur IDs, von denen seit der
letzten Übersicht etwas kam. Passen nicht alle in eine Nachricht, kommen die
übrigen in weiteren Nachrichten (reihum, keine ID wird ausgehungert).

| Byte | Typ | Inhalt |
|---|---|---|
| 0 | u8 | Typ `0x01` |
| 1 | u8 | Protokollversion `1` |
| 2 | u16 | laufende Nummer (Lücken = verlorene Nachrichten) |
| 4 | u32 | Zeit seit Start des Lesers in ms |
| 8 | u8 | Anzahl Einträge *n* |
| 9 | 25 × *n* | Einträge |

Eintrag (25 Byte):

| Byte | Typ | Inhalt |
|---|---|---|
| 0 | u32 | CAN-ID (Bit 0–28), Bit 31 = erweiterte ID (29 Bit), Bit 30 = RTR |
| 4 | u8 | Datenlänge (0–8) |
| 5 | 8 × u8 | letzte Daten (unbenutzte Bytes 0) |
| 13 | 8 × u8 | **geänderte Bits** seit der letzten Übersicht (ODER über alle Botschaften dazwischen, so gehen auch schnelle Wechsel nicht verloren) |
| 21 | u16 | Anzahl Botschaften seit der letzten Übersicht (höchstens 65535) |
| 23 | u16 | mittlerer Abstand in ms (0 = unbekannt) |

Bei MTU 247 passen 9 Einträge in eine Nachricht.

### 2.2 `0x02` Status

| Byte | Typ | Inhalt |
|---|---|---|
| 0 | u8 | Typ `0x02` |
| 1 | u8 | Protokollversion `1` |
| 2 | 3 × u8 | Firmwareversion (Major, Minor, Patch) |
| 5 | u8 | Busmodus: `0` = nur mithören, `1` = aktiv (Stufe 2, noch nicht vorhanden) |
| 6 | u8 | Buszustand: `0` = ok, `1` = still (keine Botschaften), `2` = Fehler (Warnung/passiv), `3` = Bus aus (bus-off), `4` = CAN-Controller fehlt |
| 7 | u8 | Bit 0 = Kopplungsfenster offen, Bit 1 = USB am PC |
| 8 | u32 | Laufzeit in s |
| 12 | u32 | Botschaften gesamt |
| 16 | u32 | verlorene Botschaften (Empfangspuffer übergelaufen) |
| 20 | u16 | Anzahl verschiedener CAN-IDs |
| 22 | u16 | Versorgungsspannung in mV (0 = unbekannt) |

### 2.3 `0x03` Diagnose

Jede Sekunde, zusammen mit dem Status.

| Byte | Typ | Inhalt |
|---|---|---|
| 0 | u8 | Typ `0x03` |
| 1 | u8 | Protokollversion `1` |
| 2 | u16 | Buslast der letzten vollen Sekunde in 0,01 % |
| 4 | u16 | Buslast, Mittel der letzten 10 Sekunden, in 0,01 % |
| 6 | u16 | Buslast, höchste Sekunde seit dem Zurücksetzen, in 0,01 % |
| 8 | u8 | Empfangsfehlerzähler des CAN-Controllers (REC, 0–255) |
| 9 | u8 | Fehler-Flags des Controllers (MCP2515: Register EFLG) |
| 10 | u32 | fehlerhafte Botschaften seit Start bzw. Zurücksetzen |
| 14 | u16 | höchster Füllstand des Zwischenpuffers im Leser |
| 16 | u16 | Größe des Zwischenpuffers |
| 18 | u8 | Grund des letzten Neustarts: `0` unbekannt, `1` eingeschaltet, `2` Spannungseinbruch, `3` Neustart durch Firmware, `4` Absturz, `5` Watchdog, `6` Tiefschlaf, `7` Reset-Taste/USB, `8` sonstiges |
| 19 | u8 | frei (0) |
| 20 | u32 | Starts seit dem ersten Flashen |

**Buslast:** Der Leser berechnet für jede empfangene Botschaft ihre Länge
auf dem Bus in Bit: Kopf, Daten, CRC, Füllbits, Begrenzer, Rahmenende und
Pause (3 Bit). Die Summe je Sekunde geteilt durch die Bitrate ergibt die
Last. Botschaften, die der Controller verloren hat, fehlen darin.

## 3. Befehle an den Leser (Merkmal „Steuerung“)

| Befehl | Aufbau | Wirkung |
|---|---|---|
| `0x10` | `10` | Zähler, ID-Tabelle, Spitze der Buslast und fehlerhafte Botschaften zurücksetzen |
| `0x11` | `11 n (id u32, maske u32) × n` | Filter setzen, höchstens 8. Eine Botschaft passt, wenn `(id & maske) == (filter & maske)`; verglichen wird das ID-Feld wie in 2.1 ohne RTR-Bit. `n = 0` lässt alles durch. |
| `0x12` | `12 ms u16` | Abstand der Übersichten, 100–5000 ms |

Es gibt in Stufe 1 **keinen** Befehl zum Senden auf den Bus und keinen zum
Umschalten in den aktiven Modus. Ungültige Befehle werden ignoriert.

## 4. Koppeln und Sicherheit

- BLE ist erst nach dem Koppeln verschlüsselt. Der Leser verlangt **LE Secure
  Connections mit Passkey** (Schutz gegen Mithörer und Zwischenschalten) und
  speichert die Kopplung (Bonding).
- **Neue Geräte lassen sich nur koppeln, solange das Kopplungsfenster offen
  ist.** Geöffnet wird es über die serielle Konsole am USB-Anschluss
  (`pair`), also nur mit dem Leser am PC. Die Konsole zeigt dann einen
  zufälligen 6-stelligen Code, den man in den Kopplungsdialog von Android
  eingibt. Das Fenster schließt nach 2 Minuten.
- Ist das Fenster zu, antwortet der Leser auf einen Kopplungsversuch mit
  einem geheimen Zufallscode, den niemand kennt, und trennt die Verbindung.
- Höchstens 3 gespeicherte Geräte. `unpair` auf der Konsole löscht alle.
- Gekoppelte Handys verbinden sich ohne erneute Eingabe. Mehrere Apps auf
  demselben Handy teilen sich die Kopplung, weil Android sie für das ganze
  Gerät speichert. Gleichzeitig verbunden ist immer nur eine App.

## 5. Prüfung beider Seiten

Firmware (C++) und `can_link` (Dart) testen dieselben Beispielnachrichten
(Übersicht, Status, Diagnose) Byte für Byte (`firmware/test/test_protocol.cpp` und
`packages/can_link/test/protocol_test.dart`). Wer das Format ändert, muss
beide Seiten anpassen.
