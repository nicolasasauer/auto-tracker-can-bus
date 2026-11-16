/// Anleitung, die beim Teilen „für die KI-Analyse“ neben Mitschnitt und
/// Profil liegt. Sie beschreibt beide Formate so genau, dass die Antwort
/// ohne Nacharbeit wieder importiert werden kann.
String aiInstructions({required String recording, required String profile}) =>
    '''
# CAN-Mitschnitt auswerten

Du bekommst zwei Dateien aus der App „CAN-Werkbank“:

- `$recording`: Mitschnitt vom CAN-Bus eines Autos (nur mitgehört).
- `$profile`: das bisherige Fahrzeugprofil mit den schon zugeordneten Signalen.

**Aufgabe:** Finde heraus, welche Bits welcher CAN-ID welches Signal sind
(Drehzahl, Geschwindigkeit, Pedale, Temperaturen, Tankinhalt, Kilometerstand,
Blinker, Türen …), und gib am Ende **ein vollständiges Profil als JSON** im
Format unten zurück. Es wird unverändert in die App importiert.

## Mitschnitt

Textdatei, Trennzeichen `;`, Kommentarzeilen beginnen mit `#`.

```
t_ms;id;dlc;data;changed;frames;period_ms
0;208;8;1F 40 00 12 00 00 00 00;00 00 00 00 00 00 00 00;20;10
```

- `t_ms`: Zeit seit Aufnahmebeginn in Millisekunden.
- `id`: CAN-ID hexadezimal (3 Stellen = 11 Bit, 8 Stellen = 29 Bit).
- `data`: Nutzdaten hexadezimal, Byte 0 zuerst.
- `changed`: Bits, die seit der vorigen Zeile dieser ID gewechselt haben,
  auch wenn sie inzwischen zurückgefallen sind.
- `frames`, `period_ms`: Zahl der Botschaften seit der vorigen Übersicht und
  ihr mittlerer Abstand.

Wichtig:

- Das Gerät schickt keine Einzelbotschaften, sondern etwa alle 200 ms den
  **letzten Stand je CAN-ID**. Schnellere Verläufe sind also unterabgetastet.
- Eine Zeile gibt es **nur bei einer Änderung**. Der Wert gilt bis zur
  nächsten Zeile derselben ID. Für Zeitreihen den letzten Wert fortschreiben.
- Zeilen mit `MARK` in der Spalte `id` sind Marken des Fahrers, der Text
  steht in der Spalte `data` (z. B. „Blinker links“, „Tacho 50“). Sie sind
  der beste Hinweis darauf, was sich in diesem Moment geändert hat.
- Zeilen mit `LOST` nennen verlorene Übersichten (Funkstrecke).

## Profil

```json
{
  "profile_id": "peugeot_208_2016_hs_can",
  "schema_version": 1,
  "vehicle": {"make": "Peugeot", "model": "208", "year": 2016},
  "messages": [
    {
      "id": "0x208",
      "name": "ENGINE_1",
      "dlc": 8,
      "signals": [
        {
          "name": "engine_rpm",
          "start": 0,
          "length": 16,
          "signed": false,
          "factor": 0.125,
          "offset": 0,
          "unit": "rpm",
          "confidence": "verified",
          "note": "gegen Gang und Geschwindigkeit geprüft"
        }
      ]
    }
  ]
}
```

Dekodierung eines Signals:

```
x    = Datenbytes als eine Big-Endian-Ganzzahl
n    = Anzahl Datenbytes * 8
raw  = (x >> (n - start - length)) & ((1 << length) - 1)
wenn signed und raw >= 1 << (length - 1):  raw -= 1 << length
wert = raw * factor + offset
```

- `start` zählt ab dem höchstwertigen Bit von Byte 0 (0 = Byte 0 Bit 7,
  8 = Byte 1 Bit 7). Das gilt für Big-Endian-Signale, den Normalfall.
- Für Little-Endian-Signale `"byte_order": "little"` setzen; `start` ist
  dann die Position des niederwertigsten Bits wie bei DBC/Intel
  (Byte * 8 + Bit).
- `length` 1 bis 63. Bitfeld muss in `dlc` Bytes passen.
- `confidence`: `verified` (an einem zweiten, unabhängigen Signal oder einer
  Marke gegengerechnet), `probable` (Lage klar, Skalierung offen) oder
  `guess`.
- `name`: eindeutig, klein, mit Unterstrich, englisch (`engine_rpm`,
  `vehicle_speed`, `gear`, `brake_pedal`, `steering_angle`, `fuel_level`,
  `coolant_temp`, `odometer`). Rohwerte ohne bekannte Skalierung enden auf
  `_raw`.
- Nur lineare Umrechnung. Keine Formeln, keine weiteren Pflichtfelder.
  Zusätzliche Felder (z. B. `store`, `cycle_ms`, `ignored`) bleiben erhalten;
  vorhandene bitte nicht entfernen.

## So bitte vorgehen

1. Mitschnitt mit Code auswerten, nicht von Hand.
2. Bestehende Signale aus dem Profil prüfen und behalten. `verified` nur
   ändern, wenn die Daten klar widersprechen, und das in `note` begründen.
3. Je CAN-ID: Welche Bytes ändern sich, wie (Zähler, Prüfsumme, stetiger
   Verlauf, Schalter)? Zähler und Prüfsummen nicht als Signal eintragen,
   sondern unter `ignored` mit einer Notiz.
4. Kandidaten gegeneinander prüfen (z. B. Wegzähler gegen Integral der
   Geschwindigkeit, Gang gegen Drehzahl/Geschwindigkeit).
5. Antwort: kurze Tabelle der neuen oder geänderten Signale mit Begründung,
   dann Vorschläge, was bei der nächsten Fahrt gezielt zu tun und zu
   markieren ist, und **zum Schluss das vollständige Profil in einem
   einzigen JSON-Block**.
''';
