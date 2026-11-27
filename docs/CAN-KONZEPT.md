# CAN-Leser – Konzept

Beschreibt den eigenen CAN-Leser auf ESP32-Basis, wie Apps ihn nutzen (allen voran der **Auto Tracker**) und vor allem das **Fahrzeugprofil**. Die BLE-Schnittstelle steht in [`CAN-BLE-PROTOKOLL.md`](CAN-BLE-PROTOKOLL.md). Mit diesem Profil bleiben Firmware und Apps generisch und werden per JSON auf ein konkretes Auto angepasst.

Fahrzeug, für das das System zuerst konfiguriert werden soll: **Peugeot 208 (1. Generation, Baujahr 2016) mit 1,0-Liter-Benziner**.

---

## 1. Gesamtbild

```
┌──────────── Auto ────────────┐
│  Steuergeräte ── CAN-Bus ─┐  │
│                    OBD-Buchse│
└───────────────────────────┼──┘
                            │
                ┌───────────┴───────────┐
                │  ESP32 + CAN-Transceiver │  firmware/
                │  • Profil (kompakt)    │
                │  • Filtern, Abfragen,  │
                │    Dekodieren          │
                │  • Ringpuffer im Flash │
                │  • Schlafmodus         │
                └───────────┬───────────┘
                            │ Bluetooth LE, eine Schnittstelle für alle Apps
                            │ (packages/can_link, CAN-BLE-PROTOKOLL.md)
                            │ WLAN (später: Rohmitschnitt, Updates)
              ┌─────────────┴──────────────┐
              │                            │
┌─────────────┴───────────┐  ┌─────────────┴───────────┐
│  Auto Tracker (App)      │  │  weitere Apps (optional) │
│  • koppeln, Live-Werte   │  │  z. B. ein Fahrtenbuch   │
│  • Fahrten mit CAN-Daten │  │  • holt die Alltagsdaten │
│  • Mitschnitt für die KI │  │    selbst ab (Fahrten,   │
│  • Profil importieren    │  │    Tanken, Kilometer-    │
│                          │  │    stand)                │
└─────────────────────────┘  └─────────────────────────┘
```

**Aufgabenteilung:**

| Komponente | Weiß über das Auto Bescheid? | Aufgabe |
|---|---|---|
| ESP32-Firmware | Nur über das geladene Profil | CAN lesen, Diagnose-Abfragen senden, Rohwerte in physikalische Werte umrechnen, puffern, schlafen |
| Auto Tracker (App) | Nur über das Profil | Koppeln, Live-Werte, Fahrten mit CAN-Daten, Mitschnitte für die KI-Auswertung, Profil importieren |
| Weitere Apps | **Gar nicht** | Holen die Alltagsdaten über dieselbe BLE-Schnittstelle (`packages/can_link`) und kennen nur die genormten Signalnamen |
| **Fahrzeugprofil (JSON)** | **Ja, ausschließlich hier** | Alles Fahrzeugspezifische an einer Stelle |

Neues Auto = neues Profil. Keine Codeänderung.

Die frühere Begleit-App **CAN-Werkbank** (Sniff-Ansicht, Bits von Hand zuordnen) liegt nicht mehr in diesem Repository; ihre Alltagsfunktionen stecken im Auto Tracker. Die alten APKs stehen weiter unter „Releases“ (bis v1.0.2). Wo dieses Konzept unten die Werkbank nennt, beschreibt es ihren damaligen Stand.

---

## 2. Die Kernidee: genormte Signalnamen

Fahrzeugprofile übersetzen fahrzeugspezifische CAN-Daten in einen **festen Katalog von Signalnamen**. Alles oberhalb des Profils (Firmware-Logik, Apps) arbeitet nur mit diesen Namen.

| Signal | Einheit | Wofür gebraucht | Pflicht? |
|---|---|---|---|
| `ignition_on` | bool | Fahrt-Erkennung, Schlafmodus | **ja** |
| `odometer_km` | km | Kilometerstand, Fahrtlänge | **ja** |
| `speed_kmh` | km/h | Fahrt-Erkennung (Fallback), Durchschnitt | empfohlen |
| `fuel_level_pct` / `fuel_level_l` | % / L | Tank-Erkennung, Verbrauch | Verbrenner |
| `soc_pct` | % | Lade-Erkennung, Verbrauch | E-Auto |
| `charging_active` | bool | Lade-Erkennung | E-Auto, empfohlen |
| `charge_energy_kwh` | kWh (Zähler) | Energie in die Batterie → Ladeverluste | optional |
| `hv_battery_power_kw` | kW | Verbrauch während der Fahrt | optional |
| `hv_battery_soh_pct` | % | Batteriegesundheit | optional |
| `hv_battery_temp_c` | °C | Auswertung Winterverbrauch | optional |
| `battery_12v_v` | V | Schutz vor Tiefentladung, Zustand 12-V-Batterie | optional (ESP kann auch selbst messen) |
| `outside_temp_c` | °C | Verbrauch nach Temperatur | optional |
| `fuel_rate_lph` | L/h | Momentanverbrauch | optional |
| `vin` | Text | Fahrzeugzuordnung | empfohlen |
| `dtc_list` | Liste | Fehlercodes | optional |

Geplant: Der Katalog liegt als Code in einem Dart-Paket und als Header in der Firmware. Beide werden aus **einer** JSON-Datei erzeugt (`profiles/schema/signals.json`), damit sie nie auseinanderlaufen. Neue Signale lassen sich jederzeit ergänzen.

---

## 3. Was pro Auto konfiguriert werden muss

Das ist die Antwort auf die Frage „was gehört alles ins Profil?“. Nach Gruppen:

### 3.1 Stammdaten des Profils
- ID, Name, Profilversion, Status (`draft` / `tested` / `verified`), Autor, Quellen
- **Passt zu:** Marke, Modell, Baujahre, Antriebsarten, FIN-Präfixe (beim Peugeot `VF3`, bei neueren Modellen auch `VR3`). Damit kann die App anhand der ausgelesenen FIN das passende Profil vorschlagen.
- **Erbt von:** z. B. `generic-obd2`. Ein Fahrzeugprofil ergänzt oder überschreibt dann nur, was abweicht.

### 3.2 Bus-Konfiguration
- Bitrate (bei OBD fast immer 500 kbit/s)
- Anschluss: OBD-Buchse (Pins 6/14) oder direkt an einer CAN-Leitung im Auto
- **Modus:** `listen_only` (nur mithören, sendet nichts, nicht einmal ACKs) oder `active` (darf Diagnose-Abfragen senden)

### 3.3 Signale
Für jedes Signal: **woher** kommt es, **wie** wird es dekodiert, **wie oft** und **wann** wird es gelesen, und auf welchen **genormten Namen** wird es abgebildet.

Es gibt drei Arten von Quellen:

| Quelle | Funktionsweise | Was konfiguriert wird |
|---|---|---|
| **`obd2_pid`** | Genormte OBD-II-Abfrage (Service 01 / 09). Funktioniert bei jedem Auto, aber mit begrenztem Umfang. | Nur die PID-Nummer. Die Dekodierung ist von der Norm vorgegeben und in der Firmware fest eingebaut. |
| **`uds_did`** | Herstellerspezifische Diagnose-Abfrage (UDS Service `0x22` ReadDataByIdentifier) an ein bestimmtes Steuergerät. Hier stecken meist SoC, SoH, Kilometerstand usw. | Sende-ID und Antwort-ID des Steuergeräts, DID (2 Byte), ggf. Diagnosesitzung, Dekodierung |
| **`broadcast`** | Botschaften, die Steuergeräte ohnehin zyklisch senden. Man hört nur mit, sendet nichts. | CAN-ID (11 oder 29 Bit), Dekodierung |

**Dekodierung** (für `uds_did` und `broadcast`), angelehnt an das bewährte DBC-Format:
- Startbyte bzw. Startbit, Länge in Bit, Byte-Reihenfolge (Big/Little Endian), vorzeichenbehaftet ja/nein
- Umrechnung **linear**: `Wert = Rohwert × Faktor + Offset`
- Gültigkeitsbereich (Min/Max). Werte außerhalb werden verworfen, z. B. `0xFFFF` für „nicht verfügbar“.
- Optional: **Werte-Tabelle** (Enum) für Zustände, z. B. `0 = aus, 1 = lädt AC, 2 = lädt DC`
- Optional: **Multiplexer** für Botschaften, die je nach Kennbyte unterschiedliche Inhalte haben

Bewusst **keine frei formulierten Formeln** wie `(A*256+B)/100`. Lineare Umrechnung plus Enum deckt praktisch alles ab und ist auf dem ESP32 einfach und sicher auszuwerten.

**Lese-Regeln pro Signal:**
- Abfrage-Intervall (bei `obd2_pid` / `uds_did`) bzw. maximale Speicherrate (bei `broadcast`, z. B. nur alle 10 s speichern, obwohl die Botschaft alle 100 ms kommt)
- **Wann:** immer, nur bei Zündung an, nur beim Laden
- Speichern nur bei Änderung um mindestens X (Totband). Spart Speicher und Funk.
- `verified`: wurde der Wert mit dem Tacho / Display im Auto abgeglichen?

### 3.4 Erkennungs-Parameter
Die Logik für Fahrten, Tank- und Ladevorgänge ist generisch, nur die Schwellen sind pro Auto einstellbar:
- **Fahrt:** Start bei `ignition_on` (oder `speed_kmh > 0`), Ende nach X Sekunden Zündung aus
- **Tanken:** Füllstand steigt um mindestens X % im Stand
- **Laden:** `charging_active` oder SoC steigt um mindestens X % im Stand
- Mindestfahrstrecke, ab der eine Fahrt gespeichert wird

### 3.5 Strom und Schlafmodus
- Ab welcher 12-V-Spannung der ESP32 sich vollständig abschaltet (Schutz der Starterbatterie)
- Nach wie vielen Sekunden ohne CAN-Verkehr er schlafen geht
- Aufwachen durch CAN-Aktivität und/oder Spannungsanstieg (Motor läuft → Lichtmaschine lädt)
- Ob beim Laden (E-Auto, Zündung aus) trotzdem gelesen werden soll

---

## 4. Beispielprofil (Entwurf)

Das Beispiel zeigt bewusst ein E-Auto, weil daran alle drei Quellenarten gut sichtbar werden. Die CAN-IDs und DIDs unten sind **Platzhalter**, keine echten Werte für einen Peugeot. Sie werden erst ermittelt, wenn das Auto da ist (siehe Kapitel 6).

```jsonc
{
  "$schema": "../schema/vehicle-profile.schema.json",
  "schema_version": 1,

  "profile": {
    "id": "peugeot-e-208-p21",
    "name": "Peugeot e-208 (2. Gen.)",
    "version": "0.1.0",
    "status": "draft",
    "extends": ["generic-obd2"],
    "match": {
      "make": "Peugeot",
      "models": ["208", "e-208"],
      "years": [2019, 2026],
      "powertrains": ["electric"],
      "vin_prefixes": ["VR3"]
    },
    "sources": ["eigene Messung"]
  },

  "buses": [
    { "id": "obd", "bitrate": 500000, "connector": "obd2", "mode": "active" }
  ],

  "signals": [
    {
      "id": "vehicle_speed",
      "maps_to": "speed_kmh",
      "source": { "kind": "obd2_pid", "bus": "obd", "service": 1, "pid": "0x0D" },
      "poll_ms": 1000,
      "when": "ignition_on"
    },
    {
      "id": "bms_soc",
      "maps_to": "soc_pct",
      "source": {
        "kind": "uds_did", "bus": "obd",
        "tx_id": "0x000", "rx_id": "0x000",      // TODO: Steuergerät Batteriemanagement
        "did": "0x0000"                          // TODO
      },
      "decode": {
        "start_byte": 0, "length_bits": 16, "byte_order": "big_endian", "signed": false,
        "factor": 0.01, "offset": 0, "min": 0, "max": 100
      },
      "unit": "%",
      "poll_ms": 30000,
      "when": "always",
      "deadband": 0.5,
      "verified": false
    },
    {
      "id": "charge_state",
      "maps_to": "charging_active",
      "source": { "kind": "broadcast", "bus": "obd", "can_id": "0x000", "extended": false },  // TODO
      "decode": {
        "start_bit": 0, "length_bits": 2, "byte_order": "little_endian",
        "enum": { "0": false, "1": true, "2": true, "3": null }
      },
      "store_interval_ms": 10000,
      "verified": false
    }
  ],

  "detectors": {
    "trip":   { "end_after_ignition_off_s": 120, "min_distance_km": 0.2 },
    "charge": { "min_soc_increase_pct": 2 }
  },

  "power": {
    "cutoff_voltage_v": 11.8,
    "sleep_after_bus_silence_s": 60,
    "wake_on": ["can_activity", "voltage_rise"],
    "read_while_charging": true
  }
}
```

Dazu gehören (geplant, noch nicht im Repository):
- `profiles/schema/vehicle-profile.schema.json`: **JSON-Schema**, mit dem jedes Profil automatisch geprüft wird (im Editor mit Autovervollständigung, in der CI bei jedem Push).
- `profiles/generic-obd2.json`: Basisprofil nur mit genormten OBD-II-PIDs. Funktioniert bei jedem Auto ab Tag 1, wenn auch mit wenigen Werten.
- Ein Profil pro Fahrzeug, das von `generic-obd2` erbt.

**Profil auf den ESP32:** Die App löst Vererbung und Kommentare auf, prüft das Profil gegen das Schema und schickt eine **kompakte Fassung** per Bluetooth an den ESP32. Der speichert sie im Flash. So muss die Firmware weder Vererbung noch JSON-Kommentare verstehen. Zum Profilwechsel muss nichts neu geflasht werden.

---

## 5. Sicherheit am Fahrzeug

### 5.1 Zwei Stufen: erst mithören, dann abfragen

**OBD-PIDs gibt es nur auf Anfrage.** Ein Tester fragt z. B. „Service 01, PID `0x0D`?“, das Motorsteuergerät antwortet mit dem Tempo. Wer nur mithört, sieht keine einzige PID, sondern nur Botschaften, die Steuergeräte ohnehin zyklisch senden (CAN-ID plus 8 Datenbytes, ohne Namen und Einheit). Beim 208 I kann es an der Buchse sogar ganz still sein (BSI als Gateway, siehe [`FAHRZEUG-PEUGEOT-208.md`](FAHRZEUG-PEUGEOT-208.md)).

| Stufe | Was der Leser tut | Was man sieht |
|---|---|---|
| **1: nur mithören** (umgesetzt) | CAN-Controller im Listen-Only-Modus: sendet nichts, nicht einmal ACKs | Broadcast-Botschaften; OBD-Anfragen und -Antworten nur, wenn ein anderes Gerät fragt |
| **2: abfragen** (geplant) | nur genormte Leseanfragen (Service 01/09) und UDS `0x22`, höchstens wenige pro Sekunde | OBD-PIDs wie bei jedem OBD-Dongle, herstellerspezifische Werte |

Stufe 1 klärt am Auto, ob an der Buchse überhaupt Verkehr ist. Stufe 2 kommt danach und nur mit den Regeln aus 5.2.

### 5.2 Regeln der Firmware

Diese Regeln setzt die **Firmware** durch, unabhängig davon, was im Profil steht:

1. **Standard ist `listen_only`.** Senden ist nur möglich, wenn das Profil `active` ausdrücklich verlangt.
2. **Nur lesende Diagnose-Dienste** sind erlaubt: OBD-Service `01`, `09` und UDS `0x22`, dazu `0x10` (Sitzung wechseln) und `0x3E` (Tester Present), falls nötig. Alles, was schreibt, löscht, codiert, Routinen startet oder Steuergeräte zurücksetzt, wird von der Firmware **fest blockiert** (Whitelist, kein Blacklist).
3. **Begrenzte Abfragerate** (z. B. höchstens 10 Anfragen pro Sekunde), damit der Bus nie nennenswert belastet wird.
4. Keine Abfragen an Steuergeräte, die das Profil nicht ausdrücklich nennt.
5. Bei CAN-Fehlern (Bus-Off, viele Fehlerframes) sofort Senden einstellen und nur noch mithören.
6. Schutz der 12-V-Batterie über Abschaltspannung und Schlafmodus (siehe 3.5).
7. **Nur gekoppelte Handys** dürfen Daten lesen oder Befehle schicken. Neue Handys lassen sich nur koppeln, wenn der Leser per USB am PC hängt (Code auf der seriellen Konsole). Der Wechsel in Stufe 2 bekommt dieselbe Hürde. Details: [`CAN-BLE-PROTOKOLL.md`](CAN-BLE-PROTOKOLL.md), Kapitel 4.

### 5.3 Ist Bluetooth LE verschlüsselt?

Von sich aus nicht. Erst nach dem **Koppeln** (Bonding) ist die Verbindung verschlüsselt (AES-CCM). Gegen jemanden, der sich dazwischenschaltet, schützt nur „LE Secure Connections“ **mit Passkey**; die einfache Variante „Just Works“ ohne Code tut das nicht. Der Leser verlangt deshalb Passkey und speichert die Kopplung. Der Code kommt über USB, also über einen zweiten, sicheren Weg. Wer im Fußraum an die Buchse kommt, kommt ohnehin ans Auto; physischer Zugang ist hier ein vertretbarer Vertrauensanker.

Hinweis: Eingriffe am Fahrzeug, auch rein lesende, geschehen auf eigenes Risiko und können Garantiefragen aufwerfen. Ein Leser an der OBD-Buchse lässt sich jederzeit spurlos abziehen.

---

## 6. Wie ein Profil für ein neues Auto entsteht

Weil noch nicht am Auto geprüft ist, welche Werte der 208 wo liefert (Rechercheergebnis: [`FAHRZEUG-PEUGEOT-208.md`](FAHRZEUG-PEUGEOT-208.md)), ist der Ablauf zum Erstellen eines Profils Teil des Konzepts:

1. **Mit `generic-obd2` starten.** Damit gibt es sofort Geschwindigkeit, Zündung, oft Tankfüllstand und manchmal Kilometerstand (PID `0xA6`, nur bei neueren Autos). Die App zeigt an, welche PIDs das Auto überhaupt unterstützt (PID `0x00`, `0x20`, … liefern das als Bitmaske).
2. **Vorhandenes Wissen suchen.** Für viele Fahrzeuge gibt es offene Sammlungen von PIDs/DIDs und DBC-Dateien (z. B. aus Foren, OBD-App-Communities oder dem opendbc-Projekt). Die Werte werden als `draft` ins Profil übernommen.
3. **Selbst ermitteln.** Heute am einfachsten im Auto Tracker: während der Fahrt einen Mitschnitt aufnehmen, Marken setzen und ihn mit Profil und Anleitung von einer KI auswerten lassen (Kapitel 9.3). Früher ging das von Hand in der Sniff-Ansicht: Die CAN-Werkbank zeigte live jede CAN-ID mit ihren Bytes; geänderte Bytes leuchteten auf, ein Bitraster zeigte, welche Bits sich je geändert haben. Der Leser fasst dafür alle Botschaften je ID zusammen und schickt nur die Übersicht per BLE (Kapitel 9). Für vollständige Rohmitschnitte kommt später ein WLAN-Modus mit dem **GVRET-Protokoll** dazu, sodass sich das Open-Source-Werkzeug **SavvyCAN** direkt verbinden kann. Damit beobachtet man gezielt Änderungen: Tanken, 1 km fahren, Tankanzeige vergleichen.
4. **Prüfen.** Die App zeigt Live-Werte neben dem Rohwert an. Stimmt der Wert mit Tacho bzw. Bordcomputer überein, wird das Signal auf `verified: true` gesetzt.
5. **Ins Repository.** Das Profil wird committet, die CI prüft es gegen das Schema.

**Wichtiger Hinweis für neuere Autos wie den 208:** An der OBD-Buchse liegt bei vielen neueren Fahrzeugen nur noch ein Diagnose-Gateway. Dort ist dann kaum Broadcast-Verkehr zu sehen, und fast alles muss per Abfrage (`obd2_pid`, `uds_did`) gelesen werden. Manche Hersteller schränken auch die Diagnose am Gateway ein. Beim 208 übernimmt das Bordnetz-Steuergerät (BSI) diese Rolle. Wie viel davon an der OBD-Buchse ankommt, zeigt sich erst am Auto. Das Profilformat unterstützt beide Fälle, deshalb muss das Konzept dafür nicht geändert werden. Falls nötig, kann der Leser später auch direkt an einer internen CAN-Leitung hängen (eigener Bus im Profil).

---

## 7. Hardware

**Prototyp (vorhanden):** Seeed Studio **XIAO ESP32-C6** auf dem Seeed **„XIAO CAN Bus Expansion Board“** (MCP2515 über SPI plus Transceiver, 16-MHz-Quarz), dazu ein OBD-Kabel mit offenen Adern. Damit wird Stufe 1 am Auto erprobt. Anleitung zum Aufbau: [`firmware/README.md`](../firmware/README.md). Abweichend von der Planung unten nutzt der Prototyp einen externen CAN-Controller; das ist für den Anfang in Ordnung, weil der Diagnose-CAN wenig Verkehr hat. Der C6 hat selbst zwei CAN-Controller (TWAI), die eigene Platine kann also bei der Planung bleiben.

**Eigene Platine (geplant, nicht Teil dieses Repositorys):**

- **ESP32 mit eingebautem CAN-Controller** (Espressif nennt ihn „TWAI“). Dann wird nur ein **CAN-Transceiver** gebraucht (z. B. SN65HVD230, 3,3 V). Einige Seeed-Studio-Erweiterungsplatinen nutzen stattdessen einen externen Controller (MCP2515 über SPI). Die Firmware kapselt den CAN-Zugriff hinter einer kleinen Treiber-Schnittstelle, damit beides funktioniert und die genaue Platine später gewählt werden kann.
- **Empfehlung Modul:** ESP32-S3 oder ESP32-C3, z. B. aus der Seeed-XIAO-Reihe. Klein, mit Bluetooth LE und WLAN. Der S3 hat mehr RAM, was beim Sniff-Modus hilft.
- **Stromversorgung** aus der OBD-Buchse (Pin 16, Dauerplus): Schaltregler 12 V → 5 V/3,3 V mit **niedrigem Ruhestrom**, Verpolungs- und Überspannungsschutz (im Bordnetz gibt es Spitzen). Spannungsteiler an einem ADC-Pin, damit der ESP32 die Batteriespannung selbst messen kann.
- **Speicher:** Ringpuffer im Flash für die Tage, an denen das Handy nicht in der Nähe ist. Optional eine microSD-Karte für lange Rohdaten-Aufzeichnungen im Sniff-Modus.
- Gehäuse und Stecker: fertiger OBD-Stecker mit Gehäuse, damit nichts im Fußraum lose hängt.

Recherche zu OBD-Buchse und CAN-Daten des 208 I: [`FAHRZEUG-PEUGEOT-208.md`](FAHRZEUG-PEUGEOT-208.md).

---

## 8. Firmware

| Thema | Wahl |
|---|---|
| Build | **PlatformIO** (reproduzierbare Builds, CI-tauglich) |
| Framework | ESP-IDF (bzw. Arduino-ESP32 auf ESP-IDF-Basis), C++ |
| CAN | TWAI-Treiber von ESP-IDF, alternativ MCP2515-Treiber, hinter gemeinsamer Schnittstelle |
| Diagnose | Kleine ISO-TP-Implementierung (mehrteilige Antworten), OBD-II- und UDS-Abfragen |
| Profil | Kompaktes Format im Flash (NVS oder eigene Partition), per BLE austauschbar |
| Verbindung | **Bluetooth LE** (GATT-Dienst, [`CAN-BLE-PROTOKOLL.md`](CAN-BLE-PROTOKOLL.md)) zu den Apps · **WLAN** später für Rohmitschnitte (GVRET/SavvyCAN) und Firmware-Updates |
| Updates | im Browser über USB (Web-Flasher, `web/`), später OTA per WLAN oder über die App |
| Tests | Dekodier- und Profil-Logik als plattformunabhängiger C++-Code mit Unit-Tests auf dem PC. Die CI braucht keine Hardware. |

Ablauf im Betrieb: aufwachen → Profil laden → Signale abfragen/mithören → dekodieren → bei Änderung mit Zeitstempel in den Ringpuffer → sobald eine App per BLE verbunden ist, Puffer übertragen und quittieren lassen → nach Ruhe wieder schlafen.

Auch hier gilt der Grundsatz „nichts geht verloren“: Daten werden erst aus dem Ringpuffer gelöscht, wenn die App den Empfang bestätigt hat.

**Stand (Stufe 1):** `firmware/` liest im Listen-Only-Modus, fasst je CAN-ID zusammen (letzte Daten, geänderte Bits, Anzahl, Takt) und schickt das per BLE. Koppeln über die serielle Konsole. Noch ohne Profil, Ringpuffer, Schlafmodus und Abfragen.

---

## 9. App-Seite: Arbeitsprofil und Mitschnitt

Ursprünglich für die CAN-Werkbank beschrieben (siehe Kapitel 1); der Auto Tracker nutzt dieselben Formate. Die BLE-Schnittstelle liegt im Paket **`packages/can_link`**, das auch andere Apps einbinden können.

**Eine Schnittstelle für mehrere Apps:** Alle Apps sprechen dasselbe Protokoll mit dem Leser. Die Kopplung speichert Android für das ganze Handy, alle Apps nutzen sie also ohne erneute Eingabe. Gleichzeitig verbunden ist immer nur eine App. Ist der Leser einmal gekoppelt (Code über den Web-Flasher oder die serielle Konsole), gilt das für alle Apps auf dem Handy.

BLE-Bibliothek: `universal_ble` (BSD-Lizenz). `flutter_blue_plus` ist verbreiteter, verlangt aber seit Version 2 für kommerzielle Nutzung eine kostenpflichtige Lizenz und sendet beim Bauen Telemetrie.

**Vorhanden (Grundgerüst):**
- Leser suchen und koppeln, **Simulation** ohne Hardware
- **Sniff-Ansicht:** alle CAN-IDs mit Bytes, Takt und Anzahl; geänderte Bytes leuchten auf; Suche nach ID; anhalten; zurücksetzen
- **OBD-Erkennung:** genormte Anfragen und Antworten (SAE J1979) werden gleich mit Name, Wert und Einheit angezeigt, auch die Liste der unterstützten PIDs
- **Detailansicht** je ID: Bitraster, welche Bits sich je geändert haben
- Statuszeile: Buszustand, Buslast, Zähler, verlorene Botschaften
- **Diagnose-Seite:** Buslast (aktuell, Mittel, Spitze), Empfangsfehler, Reserve des Zwischenpuffers im Leser, Neustarts mit Grund (z. B. Spannungseinbruch beim Motorstart), dazu Hinweise, was zu prüfen ist

- **Arbeitsprofil** (9.1): Signale anlegen (Bits im Raster antippen), importieren, exportieren; ihre Werte stehen in der Sniff-Ansicht unter den Bytes. Noch nicht geprüfte Signale tragen ein Fragezeichen.
- **Signal-Seite:** Rohwert, umgerechneter Wert und Verlauf als Graph. Startbit, Länge, Faktor und Offset wirken sofort, auch rückwirkend auf den Verlauf (die App merkt sich je ID die Bytes der letzten 10 Minuten, nicht die Werte). „Faktor aus Sollwert“ rechnet den Faktor aus dem Wert, den Tacho oder Bordcomputer gerade zeigen.
- **Anpinnen:** Angepinnte Signale stehen oben in der Sniff-Ansicht mit Wert und Verlauf der letzten Minute.
- **Mitschnitt** (9.2): Aufnahme mit Marken („Blinker links“, „Tacho 50“), teilen, am Schreibtisch wieder abspielen.
- **Ablauf mit KI** (9.3): Mitschnitt, Profil und Anleitung teilen, das Profil aus der Antwort importieren, weiter beobachten.

**Als Nächstes (Werkzeuge zum Zuordnen):**
- **Abgleich mit Bekanntem:** GPS-Tempo vom Handy mitschneiden und suchen, welche Bytefolge mit welchem Faktor dazu passt. Das klappt ganz ohne Senden.
- **Vorschläge** aus bekannten Daten (`FAHRZEUG-PEUGEOT-208.md`, opendbc/PSA-Projekt) als `draft`
- Umwandlung des Arbeitsprofils in das Fahrzeugprofil aus Kapitel 4 (genormte Namen, Lese-Regeln), DBC-Import
- Filter auf dem Leser einstellen, Profil auf den Leser laden
- Gerätestatus: Firmwareversion, 12-V-Spannung, Pufferfüllstand

### 9.1 Arbeitsprofil

Zum Zuordnen braucht die Werkbank nur „welche Bits sind welches Signal“. Dafür nutzt sie ein schlankes JSON-Format (Code: `packages/can_link/lib/src/profile.dart`, Beispiel: `packages/can_link/profiles/peugeot_208_2016_hs_can.json`). Es ist bewusst kleiner als das Fahrzeugprofil aus Kapitel 4 und lässt sich später daraus erzeugen.

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

- `start`: Abstand vom höchstwertigen Bit von Byte 0 (0 = Byte 0 Bit 7, 8 = Byte 1 Bit 7), Signale sind Big Endian. Mit `"byte_order": "little"` ist `start` die Position des niederwertigsten Bits wie bei DBC/Intel.
- `wert = roh × factor + offset`, `length` 1 bis 63, das Bitfeld muss in `dlc` Bytes passen.
- `confidence`: `verified` (an einem zweiten Signal oder am Auto gegengeprüft), `probable`, `guess`.
- Signalnamen sind im Profil eindeutig. Beim Import werden alle Fehler auf einmal gemeldet.
- Unbekannte Felder (`store`, `cycle_ms`, `ignored`, `bus` …) bleiben beim Laden und Speichern erhalten. `store.mode` (`sample`, `on_change`, `deadband`, `counter`) wird geprüft; ausgewertet wird es von `SignalSampler` in `can_link` (9.4).

Profil, Pins und Mitschnitte liegen im Ordner der App und überstehen einen Neustart.

### 9.2 Mitschnitt

Der Leser schickt keine Einzelbotschaften, sondern alle 200 ms je CAN-ID den letzten Stand und die Bits, die dazwischen gewechselt haben (`CAN-BLE-PROTOKOLL.md`). Der Mitschnitt hält genau das fest: jede Änderung in diesem Raster. Schnellere Verläufe sind unterabgetastet; für lückenlose Rohdaten bleibt der geplante WLAN-Modus.

Textdatei mit `;`, eine Zeile nur bei Änderung (Code: `packages/can_link/lib/src/can_log.dart`):

```
# CAN-Werkbank Mitschnitt v1
# start=2026-11-13T10:00:00.000Z
# quelle=CAN-Leser
t_ms;id;dlc;data;changed;frames;period_ms
0;208;8;19 75 32 00 4E 32 32 32;00 00 00 00 00 00 00 00;20;10
1400;MARK;;Blinker links;;;
1600;LOST;;2;;;
```

- `t_ms`: Zeit seit Aufnahmebeginn nach der Uhr des Lesers. Startet der Leser neu, zählt die Aufnahme weiter.
- `data` gilt bis zur nächsten Zeile derselben ID. `changed` nennt auch Bits, die kurz gewechselt haben und wieder zurück sind.
- `MARK`: Marke des Nutzers. `LOST`: verlorene Übersichten auf der Funkstrecke.
- Die Aufnahme läuft weiter, wenn die Ansicht angehalten ist, und wird alle 2 s gesichert.

Größenordnung: Bei 42 IDs und 5 Übersichten je Sekunde höchstens rund 25 MB je Stunde, meist deutlich weniger.

### 9.3 Ablauf mit KI

1. **Aufnehmen:** Fahrt mitschneiden, dabei Marken setzen.
2. **Teilen:** „Für KI-Analyse teilen“ verschickt drei Dateien: den Mitschnitt, das aktuelle Profil und `KI-ANLEITUNG.md`. Die Anleitung beschreibt beide Formate und verlangt als Antwort ein vollständiges Profil.
3. **Importieren:** Profil als Datei oder direkt aus der Zwischenablage; Text um das JSON herum stört nicht.
4. **Beobachten:** Signale anpinnen, am Auto oder in der Wiedergabe des Mitschnitts prüfen, Faktor und Bitlage nachstellen, Stand auf „geprüft“ setzen. Dann von vorn, bis alles passt.

### 9.4 Speicherregeln (`store`)

Für Apps, die Werte dauerhaft speichern (etwa ein Fahrtenbuch), verdichtet
`SignalSampler` aus `can_link` die Live-Werte nach `store` im Profil. Live
kommt jeder Wert so oft, wie der Leser ihn schickt. Gespeichert wird:
`sample` (Mittel/Max/Min je Fenster), `on_change`, `deadband`, `counter`
(Schritte seit Beginn des Abschnitts, Überlauf berücksichtigt, z. B. Meter
laut Wegzähler oder Schritte des Kraftstoffzählers). Ohne Regel: Schalter bei
Änderung, sonst Mittel über 5 s.

**Abschnitte:** Jede Verbindung ohne Lücke über 3 s ist ein Abschnitt.
Zähler beginnen je Abschnitt bei 0, weil ihre Differenz über eine Lücke nicht
eindeutig ist; offene Mittelungsfenster werden an der Lücke geschlossen.

## 10. Repository-Struktur

```
auto-tracker-can-bus/
├── web/                         # Web-Flasher: Firmware im Browser flashen, koppeln
├── packages/
│   └── can_link/                # Dart: BLE-Protokoll, Profile, Simulation, Sampler
│       └── profiles/            # Fahrzeugprofile (JSON)
├── firmware/                    # PlatformIO-Projekt für den ESP32-C6
│   └── lib/can_core/            # plattformunabhängiger Kern, auf dem PC getestet
├── tool/check.sh                # Analyse und Tests mit knapper Ausgabe
└── docs/
    ├── CAN-KONZEPT.md
    ├── CAN-BLE-PROTOKOLL.md
    └── FAHRZEUG-PEUGEOT-208.md
```

- Apps binden `can_link` per Pfad oder Git ein.
- **CI (GitHub Actions)** auf `ubuntu-latest` baut und testet nur, was sich geändert hat: `link.yml` (Paket), `firmware.yml` (Kern-Tests, Firmware), `flasher.yml` (Web-Flasher; veröffentlicht ihn nach jedem Release auf GitHub Pages). Später kommt die Profil-Prüfung gegen das Schema dazu.

---

## 11. Reihenfolge

Da noch kein Auto da ist, ergibt sich eine natürliche Reihenfolge:

| Schritt | Ohne Auto möglich? |
|---|---|
| Signal-Katalog, Profil-Schema, `generic-obd2.json` | ja |
| Firmware-Grundgerüst, Dekodier-Logik mit Unit-Tests | ja |
| Prototyp (XIAO ESP32-C6 + CAN-Board) aufbauen, **Stufe 1 am Auto**: Ist an der Buchse Verkehr? | **nein**, braucht das Auto (Firmware vorhanden) |
| Am **Schreibtisch testen** mit einem zweiten CAN-Knoten: zweiter XIAO ESP32-C6 mit eingebautem CAN-Controller und einem Transceiver-Modul (z. B. SN65HVD230) als Fahrzeug-Simulator | ja |
| App: Koppeln, Sniff-Ansicht, Zuordnen (erst CAN-Werkbank, jetzt Auto Tracker mit Mitschnitt und KI) | ja (mit Simulation) |
| Profil für den 208 ermitteln und prüfen | **nein**, braucht das Auto |
| Fahrt-/Lade-/Tankerkennung abstimmen | **nein** |
| Anbindung weiterer Apps über `can_link` | ja (mit Simulation) |

---

## 12. Offene Punkte
1. Eigene Platine statt Prototyp: geplant mit eingebautem CAN-Controller (TWAI) und eigenem Transceiver; nicht Teil dieses Repositorys.
2. ~~Wird es der e-208 oder ein Verbrenner?~~ Entschieden: 208 I, 1,0-Liter-Benziner. Wichtig sind zuerst Füllstand/Tanken, Kilometerstand und Verbrauch (über Luftmasse bzw. Einspritzmenge).
3. Soll der Leser dauerhaft stecken bleiben (dann ist Schlafmodus Pflicht) oder nur bei Bedarf eingesteckt werden?
4. Eigene Platine mit XIAO ESP32-S3 oder mit dem ESP32-C6? Der C6 hat kein PSRAM, aber zwei CAN-Controller. Entscheidung nach den ersten Messungen am Auto.
5. INT-Pin des MCP2515 auf dem CAN-Board klären (Chip-Select D7 ist laut Seeed-Wiki bestätigt, der INT-Pin dort nicht genannt; siehe Schaltplan des Boards, Link in `firmware/README.md`).
