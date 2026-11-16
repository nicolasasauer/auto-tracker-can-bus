# Peugeot 208 I (A9) – Recherche: OBD-Buchse und CAN-Daten

Rechercheergebnis für das erste Zielfahrzeug: **Peugeot 208, 1. Generation, Baujahr 2016, 1,0-Liter-Benziner (68 PS)**. Grundlage für das Fahrzeugprofil (`CAN-KONZEPT.md`, Kapitel 3) und für die ersten Messungen am Auto.

> **Status: Recherche.** Dieses Kapitel gibt den Stand vor der ersten Messung wieder; was sich am Auto bestätigt hat, steht im Profil `packages/can_link/profiles/peugeot_208_2016_hs_can.json`. Die CAN-Daten stammen überwiegend aus einem Open-Source-Projekt, das viele PSA-Modelle gemeinsam beschreibt. Einzelne IDs können beim 208 I abweichen oder fehlen. Jedes Signal muss am Auto gemessen und gegen Tacho bzw. Bordcomputer geprüft werden, bevor es im Profil auf `verified: true` gesetzt wird.

---

## 1. Fahrzeug einordnen

| | |
|---|---|
| Projektcode | **A9** (A90 = 3-Türer, A91 = 5-Türer) |
| Plattform | PF1 |
| Elektronik-Architektur | **AEE2010, Variante „eco“** (Low-Cost-Variante mit zusammengelegten Bussen) |
| Zentrales Steuergerät / Gateway | **BSI** (Boîtier de Servitude Intelligent), Modell „BSI2010“ |
| Busse im Auto | HS.IS (500 kbit/s, Antrieb/Fahrwerk), LS.CONF, LS.HABITACLE, LS.INFO-DIV (je 125 kbit/s), LIN |
| Motorsteuergerät (CMM) | beim 1,0 VTi vermutlich Bosch **MEVD17.4.4** oder Continental **V46** (prüfen, Typenschild bzw. Diagnose-Abfrage `22 F1 8C`/`22 F0 80`) |
| FIN beginnt mit | `VF3` (prüfen im Fahrzeugschein) |

Quelle: PSA-RE (`cars/` und `architectures.yml`), siehe Kapitel 7.

---

## 2. OBD-Buchse

### 2.1 Lage und Zugang

Übereinstimmend in mehreren Quellen: **Fahrerseite, unter dem Lenkrad, hinter einer Kunststoffabdeckung im unteren Armaturenbrett.** Die Abdeckung lässt sich laut Besitzerforum **ohne Werkzeug abziehen** (keine Schrauben). Im gleichen Bereich sitzt der Innenraum-Sicherungskasten. Bei Rechtslenkern liegt dieser im Handschuhfach, das betrifft uns nicht.

→ Am Auto prüfen: Wie viel Platz ist hinter der Abdeckung? Passt dort die Box (ca. 55 × 40 × 20 mm) samt flachem Stecker, und lässt sich die Abdeckung danach wieder schließen? Fotos machen, Maße nehmen, Gehäuse danach konstruieren.

### 2.2 Pinbelegung

| Pin | Belegung | Sicherheit der Angabe |
|---|---|---|
| 16 | +12 V Dauerplus | genormt |
| 4 | Fahrzeugmasse | genormt |
| 5 | Signalmasse | genormt |
| 6 / 14 | CAN-H / CAN-L, genormter OBD-Bus (500 kbit/s), Weg zum Motorsteuergerät für OBD-II-Abfragen | genormt |
| 3 / 8 | **CAN-H / CAN-L „Diagnose-CAN Peugeot“** (500 kbit/s), herstellerspezifische Diagnose (BSI und andere Steuergeräte) | für den e-208 (2. Gen.) von einem Besitzer gemessen; in einem deutschen Peugeot-Forum für einige Modelle so genannt, für andere nicht belegt. **Beim 208 I unbestätigt.** |
| 1 | +12 V **nach Zündung** (geschaltet) | nur für den e-208 berichtet. **Beim 208 I unbestätigt.** Wäre ein ideales Zündungssignal (siehe 2.3). |
| übrige | nicht belegt oder unbekannt | |

Einordnung: Bei PSA hängen beide CAN-Paare an der Buchse in der Regel **am BSI**, das als Gateway weiterleitet. Ob an 6/14 auch mitlesbarer Verkehr des internen HS.IS-Busses zu sehen ist (ein deutsches Forum spricht bei einigen Modellen von „CAN I/S“ an Pin 6/14), ist offen und die wichtigste Frage für die erste Messung.

### 2.3 Erste Messung am Auto (Checkliste)

Mit Multimeter, OBD-Breakout und dem Prototyp (`firmware/README.md`):

1. **Spannungen** an allen 16 Pins gegen Pin 4 messen: Zündung aus, Zündung an, Motor läuft. Liegt an Pin 1 (oder einem anderen Pin) 12 V nur bei Zündung an?
2. **Ruhepegel CAN:** An einem aktiven CAN-Paar liegen CAN-H und CAN-L in Ruhe beide bei ca. 2,5 V. Damit lassen sich 3/8 und 6/14 (und eventuelle weitere Paare) finden, ohne etwas zu senden.
3. **Mithören (listen only)** an 6/14 und 3/8, jeweils bei Zündung an und bei laufendem Motor: Kommt Verkehr ohne Anfrage? Welche IDs? Mitschnitt mit SavvyCAN speichern.
4. **Abfragen** (erst wenn 1–3 klar sind): unterstützte OBD-PIDs (`01 00`, `01 20`, `01 40`, …) an 6/14; Steuergeräte-Identifikation BSI und CMM (Kapitel 4) an dem Paar, auf dem sie antworten.
5. **Zündung aus, Auto abschließen:** Wie lange bleibt Verkehr auf dem Bus? (Entscheidet über die Weckstrategie.)

---

## 3. Weg A: Mithören (Broadcast)

Falls an der Buchse interner Verkehr ankommt, ist das der beste Weg: kein Senden nötig, hohe Datenrate, Verbrauch als exakter Zähler.

### 3.1 HS.IS (500 kbit/s)

Aus PSA-RE, Architektur AEE2010 (Basisvariante „full“, für „eco“ nicht einzeln dokumentiert, IDs können abweichen):

| ID | Botschaft | Signal | Bits (Byte.Bit) | Umrechnung | Takt |
|---|---|---|---|---|---|
| `0x38D` | VEHICLE_DYNAMICS_WHEELS (ABS) | Geschwindigkeit | 1.7–2.0 | × 0,01 km/h | 40 ms |
| | | Wegstrecke (Zähler) | 3.7–4.0 | × 0,1 m? (Einheit prüfen) | |
| `0x488` | ENGINE_PERFORMANCE_DATA_2 (CMM) | **Kraftstoff-Verbrauchszähler** („Econometer“) | 2.7–2.0 | × 80 mm³, läuft über | 100 ms |
| `0x4AE` | BSI_CABIN_DATA_10 | Drehzahl | 1.7–2.0 | × 0,125 1/min | 1 s |
| | | Geschwindigkeit | 3.7–4.0 | × 0,01 km/h | |
| `0x54E` | BSI_CABIN_DATA_13 | **Kilometerstand** | 4.7–6.0 | × 0,1 km | 1 s |
| | | Tageskilometer | 1.7–3.0 | × 0,001 km | |
| | | **Tankfüllstand** (gefiltert) | 7.7–7.0 | % | |
| `0x552` | BSI_ODOMETER_DATA | Kilometerstand | 5.7–7.0 | km | 1 s |
| `0x612` | BSI_DATA_3 | Tankfüllstand | 4.7–4.0 | × 0,5 (Einheit prüfen) | 100 ms |
| `0x412` | BSI_CABIN_DATA_4 | Reserve erreicht | 4.0 | bool | 50 ms |
| `0x348` | ENGINE_ECU_STATUS_HEV (CMM) | Zündung an (OBD-Sicht) | 7.6 | bool | 20 ms |

### 3.2 Komfort- bzw. Infotainment-Bus (125 kbit/s)

Diese Botschaften sind bei PSA seit vielen Jahren nahezu unverändert und gut dokumentiert. Sie liegen auf LS.CONF bzw. LS.INFO-DIV (Kombiinstrument, Radio). An der OBD-Buchse sind sie wahrscheinlich **nicht** zu sehen, aber hinter dem Radio oder am Kombiinstrument. Für einen späteren direkten Anschluss interessant:

| ID | Botschaft | Inhalt |
|---|---|---|
| `0x0B6` | FAST_BSI_DATA | Drehzahl (× 0,125), Geschwindigkeit (× 0,01 km/h), **Verbrauchszähler** (× 80 mm³) |
| `0x0F6` | BSI_SLOW_DATA_2 | **Kilometerstand** (× 0,1 km), **Außentemperatur** (× 0,5 − 40 °C), Zündungs-/Schlüsselstellung |
| `0x161` | BSI_GAUGES | **Tankfüllstand** (%), Tankvolumen (L) |
| `0x221` | TRIP_GENERAL_INFOS | **Momentanverbrauch** (× 0,1 L/100 km), Restreichweite (km) |
| `0x2A1` / `0x261` | TRIP_FIRST/SECOND_INFOS | Bordcomputer Fahrt 1/2: Ø-Geschwindigkeit, Strecke, Ø-Verbrauch |

Eine Blog-Analyse eines 208-Kombiinstruments nennt dieselben IDs `0x0B6` (Tacho/Drehzahl), `0x0F6` (Temperatur, Kilometerzähler) und `0x161` (Tankanzeige). Das passt zu PSA-RE.

---

## 4. Weg B: Diagnose-Abfragen (UDS)

Funktioniert, wenn an der Buchse nur auf Anfrage geantwortet wird. Nur lesender Dienst `0x22` (ReadDataByIdentifier), im Einklang mit der Sicherheits-Whitelist (`CAN-KONZEPT.md`, Kapitel 5). Adressierung 11 Bit, ISO-TP.

### 4.1 BSI (Gateway, Bordnetz-Steuergerät)

Anfrage-ID **`0x752`**, Antwort-ID **`0x652`**. Laut PSA-RE „über die Diagnosebuchse erreichbar (bei den meisten Autos über das Gateway)“.

| DID | Bedeutung | Länge | Umrechnung |
|---|---|---|---|
| `D8C7` | **Momentanverbrauch** | 2 Byte | × 0,1 L/100 km (ändert sich erst ab ca. 30 km/h) |
| `D8CA` | „schneller“ Verbrauch (ungefiltert?) | | prüfen |
| `DB61` | **Geschwindigkeit** | 2 Byte | × 0,01 km/h |
| `D8F9` | im Kombiinstrument angezeigte Geschwindigkeit | | prüfen |
| `DB8D` | **Gesamtkilometer** | 4 Byte | × 0,1 km |
| `DBA2` | im BSI gespeicherter Gesamtkilometerstand | 4 Byte | km |
| `D8C5` | **Tankfüllstand angezeigt** | 1 Byte | % |
| `D8C4` | Tankfüllstand berechnet | 2 Byte | × 0,01 L |
| `D8C3` | Tankfüllstand gemessen | | prüfen |
| `D8C8` / `D8C9` | Ø-Verbrauch Fahrt 1 / 2 | | prüfen |
| `DB9A` / `DB9B` | Strecke Fahrt 1 / 2 | | prüfen |
| `DBED` | Kilometer bis zur nächsten Wartung | | prüfen |

### 4.2 Motorsteuergerät (CMM)

Anfrage-ID **`0x6A8`**, Antwort-ID **`0x688`** (für MEVD17.4.4 dokumentiert, andere Varianten prüfen).

| DID | Bedeutung | Bemerkung |
|---|---|---|
| `D400` | Drehzahl | |
| `D402` | Geschwindigkeit | × 0,0078125 km/h |
| `D49C` | Kilometerstand | km |
| `D489` | Luftmasse (geschätzt aus Drehzahl, Saugrohrdruck, Temperatur) | Grundlage für eigene Verbrauchsberechnung |
| `D4CB`–`D4CD` | Einspritzzeit Zylinder 1–3 | Dreizylinder, `D4CE` (Zyl. 4) entfällt |
| `D4DC` | angezeigter Tankfüllstand | nur bei manchen Varianten dokumentiert |

### 4.3 Genormte OBD-II-Abfragen (Pins 6/14)

Funktionieren bei jedem Benziner seit 2001 (EOBD), Umfang je Auto verschieden. Die App fragt zuerst die unterstützten PIDs ab.

| PID | Inhalt | Nutzen |
|---|---|---|
| `0x0D` | Geschwindigkeit (km/h, ganzzahlig) | Grundsignal |
| `0x0C` | Drehzahl | Fahrstil, Gangschätzung |
| `0x05` | Kühlmitteltemperatur | Kaltstart-Anteil |
| `0x0B` / `0x0F` | Saugrohrdruck / Ansauglufttemperatur | Luftmasse rechnen, falls kein `0x10` |
| `0x10` | Luftmasse (g/s) | Momentanverbrauch rechnen |
| `0x5E` | Kraftstoffdurchfluss (L/h) | direkt, aber selten unterstützt |
| `0x2F` | Tankfüllstand (%) | oft unterstützt |
| `0x46` | Außentemperatur | |
| `0x42` | Steuergeräte-Spannung | 12-V-Bordnetz |
| `0x1F` | Zeit seit Motorstart | |
| `0xA6` | Kilometerstand | erst ab ca. 2019 genormt, beim 208 I unwahrscheinlich |

---

## 5. Die Wunschwerte im Überblick

| Wert | Bester Weg | Rückfallebene | Einschätzung |
|---|---|---|---|
| **Geschwindigkeit** | OBD-PID `0x0D` | BSI `DB61`, HS.IS `0x38D` | sicher machbar |
| **Momentanverbrauch** | Verbrauchszähler HS.IS `0x488` (falls an der Buchse sichtbar), aufsummiert = exakter Verbrauch | BSI `D8C7` (L/100 km wie im Bordcomputer); selbst rechnen aus Luftmasse (`0x10` bzw. `D489`) oder aus Einspritzzeiten | sehr wahrscheinlich machbar, Weg offen |
| **Kilometerstand** | BSI `DB8D` | CMM `D49C`, HS.IS `0x54E` | wahrscheinlich machbar, wenn das BSI über die Buchse antwortet |
| **Tankfüllstand** | OBD-PID `0x2F` | BSI `D8C5`/`D8C4`, HS.IS `0x54E` | wahrscheinlich machbar |

**Verbrauch selbst rechnen** (Benziner, Lambda = 1):

```
Kraftstoff [L/h]  = Luftmasse [g/s] × 3600 / (14,7 × 745 g/L)
Verbrauch [L/100 km] = Kraftstoff [L/h] / Geschwindigkeit [km/h] × 100
```

Im Stand oder beim Rollen mit Schubabschaltung ist L/100 km nicht sinnvoll. Deshalb intern immer **L/h bzw. den aufsummierten Kraftstoff in mL** speichern und L/100 km erst bei der Auswertung bilden. Die Rechnung wird am Ende einer Tankfüllung gegen die tatsächlich getankte Menge kalibriert (Korrekturfaktor im Profil).

---

## 6. Ideen für die Auswertung

Die CAN-Daten werden mit Zeitstempel aufgezeichnet. Zeichnet eine App auf dem Handy zugleich die GPS-Spur auf, lassen sich beide über die Zeit zusammenführen. Daraus ergibt sich:

**Karte**
- **Verbrauchs-Heatmap** auf der Fahrtstrecke: Abschnitte nach L/100 km eingefärbt. Zeigt Steigungen, Ampelstrecken, Autobahnabschnitte.
- Geschwindigkeit als zweite Ebene, umschaltbar.
- „Teuerste Kilometer“: Abschnitte mit dem höchsten Verbrauch je Strecke.

**Diagramme**
- **Verbrauch über Geschwindigkeit** (Punktwolke aller Fahrten): die persönliche Verbrauchskurve des Autos, mit dem Sweetspot.
- Verbrauch je Fahrt über der Zeit, mit **Außentemperatur** eingefärbt (Winterverbrauch).
- **Kaltstart-Anteil:** Wie viel Kraftstoff geht in den ersten Kilometern drauf, bis der Motor warm ist (Kühlmitteltemperatur)? Lohnt sich die kurze Fahrt?
- **Leerlauf-Verbrauch:** Liter im Stand pro Woche.

**Fahrstil**
- Durchschnittsverbrauch und -geschwindigkeit pro Fahrt (statt nur pro Tankfüllung)
- Anteil Zeit in Leerlauf, Schubabschaltung, Volllast
- **Schaltpunkte:** Drehzahl beim Hochschalten (Gang geschätzt aus Drehzahl/Geschwindigkeit)
- Starke Beschleunigungen und Bremsungen pro 100 km (aus der Geschwindigkeitsänderung)
- Ein einfacher **Eco-Score** pro Fahrt aus diesen Kennzahlen

**Kosten und Alltag**
- Kosten pro Fahrt (Verbrauch × letzter Tankpreis)
- Tank-Erkennung über den Sprung im Tankfüllstand, automatischer Vorschlag für einen Tankeintrag in einem Fahrtenbuch
- Restreichweite, Kilometerstand automatisch übernehmen
- Zustand der 12-V-Batterie (Ruhespannung, Spannungseinbruch beim Start) als Frühwarnung

---

## 7. Quellen

- **PSA-RE**, Reverse Engineering der PSA-Elektronik (Botschaften, Diagnose-DIDs, Fahrzeugzuordnung): https://github.com/prototux/PSA-RE. Relevante Pfade: `cars/` (Eintrag A9), `buses/AEE2010.full/HS.IS/`, `buses/AEE2010.full/LS.INFO-DIV/`, `diag/AEE2010.full/BSI/BSI2010/dids/`, `diag/AEE2010.full/CMM/MEVD17_4_4/dids/`
- Vorgängerprojekt mit älteren PSA-Botschaften: https://github.com/prototux/PSA-CAN-RE-old und https://autowp.github.io/
- Analyse eines 208-Kombiinstruments (IDs `0x0B6`, `0x0F6`, `0x161`): https://blog.snowdenlabs.co.uk/2020/02/14/reverse-engineering-a-peugeot-208-instrument-cluster/
- Pinbelegung e-208 (Pins 1, 3/8, 6/14), Besitzerbericht: https://www.openvehicles.com/node/2505
- Lage der OBD-Buchse 208 (2012–2019): https://www.klavkarr.com/location-plug-connector-obd/Peugeot-208 und https://www.208ownersclub.co.uk/threads/ecu.528/
- OBD-Buchsen und Pinbelegungen verschiedener Peugeot-Modelle (Forum): https://www.mittns.de/thread/884-obd-diagnose-anschl%C3%BCsse-fundorte-und-pin-belegungen/
- Genormte OBD-II-PIDs: https://en.wikipedia.org/wiki/OBD-II_PIDs
