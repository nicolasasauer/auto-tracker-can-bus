# Auto Tracker CAN-Bus

**English** · [Deutsch](README.de.md)

A small **CAN reader for the OBD-II port** for the Android app
[**Auto Tracker**](https://play.google.com/store/apps/details?id=de.nicolasasauer.auto_tracker).
The reader listens to your car's CAN bus and sends the values to the app
via Bluetooth: speed, RPM, gear, consumption, odometer and more, depending
on the **vehicle profile** (JSON). A first profile for the Peugeot 208 I
(2016) is included.

This repository holds the build guide, the firmware and the vehicle
profiles. The firmware can be **flashed right in the browser**, no extra
software needed.

> **Listen-only. Use at your own risk, without any warranty.**
> The CAN controller runs in listen-only mode and never transmits on the
> bus, not even acknowledgements (ACK); the firmware contains no code to
> send. Still: any work on a vehicle, even read-only, is at your own risk
> and may affect your warranty. Do not handle the reader or your phone
> while driving. Nobody accepts liability for damage to the vehicle, the
> battery or any other consequences (see [LICENSE](LICENSE)).

The firmware console, code comments and the detailed docs are in German.

## Quickstart

1. **Get the parts and plug them together:** see [Hardware](#hardware).
2. **Flash the firmware:** connect the reader to your computer via USB-C,
   open the [**web flasher**](https://nicolasasauer.github.io/auto-tracker-can-bus/)
   in Chrome or Edge and click "Install".
3. **Pair:** on the same page click "Get pairing code". In Auto Tracker turn
   on *Settings → CAN reader (beta)*, open *CAN reader (OBD)*, tap "Search
   for CAN reader", pick the reader and enter the code.
4. **Into the car:** OBD cable to the terminal (pin 6 → CAN-H, pin 14 →
   CAN-L, pin 4/5 → GND, **not** pin 16), see
   [connecting](#connecting-to-the-obd-port). Ignition on: the app shows the
   values live.
5. **Assign to a vehicle:** in *CAN reader (OBD)* assign the reader to a
   vehicle. During a trip the app then connects by itself and stores the
   values with the trip.

## Contents

| Folder | Contents |
|---|---|
| [`firmware/`](firmware/) | Firmware for the reader (PlatformIO, C++). Core in `lib/can_core`, tested on the PC. |
| [`web/`](web/) | Web flasher: install the firmware in the browser and pair ([page](https://nicolasasauer.github.io/auto-tracker-can-bus/)) |
| [`packages/can_link/`](packages/can_link/) | Dart package: BLE protocol, profiles, simulation. Vehicle profiles in [`profiles/`](packages/can_link/profiles/). |
| [`docs/`](docs/) | [Concept](docs/CAN-KONZEPT.md), [BLE protocol](docs/CAN-BLE-PROTOKOLL.md), [Peugeot 208 research](docs/FAHRZEUG-PEUGEOT-208.md) (German) |

## Hardware

| Part | Note |
|---|---|
| **Seeed Studio XIAO ESP32-C6** | microcontroller with Bluetooth LE |
| **Seeed "XIAO CAN Bus Expansion Board"** | MCP2515 CAN controller (SPI, 16 MHz crystal) and SN65HVD230 transceiver, screw terminal GND / CAN-H / CAN-L |
| **OBD-II cable with open wires** | plug for the car's port |
| USB-C cable, computer | for flashing and pairing; a laptop on battery also powers the first test |

Plug the XIAO onto the CAN board. Pins (see `firmware/include/config.h`):
SPI SCK/MISO/MOSI = D8/D9/D10, MCP2515 chip select = **D7** (per the Seeed
wiki), interrupt = **D6** (assumed; not documented in the wiki. If it is
wrong, the firmware polls every millisecond and says so under `status`).

### Connecting to the OBD port

| OBD pin | Function | to the CAN board |
|---|---|---|
| **6** | CAN-H (standard OBD bus, 500 kbit/s) | terminal CAN-H |
| **14** | CAN-L | terminal CAN-L |
| **4 / 5** | chassis / signal ground | terminal GND |
| **16** | +12 V permanent | **do not connect**, insulate the wire (see below) |

1. **Check the cable.** Wire colours are not reliable. Use a continuity
   tester against the plug. Insulate unused wires.
2. **Termination:** **not active** on this board by default (solder pad P1
   on the back is open). Leave it that way in the car; the bus there is
   already terminated. Only close P1 for a two-node test bus on your desk.
   Check without a car: no continuity between CAN-H and CAN-L at the
   terminal, instead of 120 Ω.
3. **Power over USB.** Power the XIAO over USB (laptop on battery or a USB
   charger in the car). The CAN board has **no 12 V input**. Only connect
   pin 16 once a dedicated regulator with protection sits in between (fuse,
   reverse polarity protection, TVS diode, regulator rated for inputs up to
   40 V; the car's supply dips during cranking and has spikes, see
   [concept, chapter 7](docs/CAN-KONZEPT.md#7-hardware)).
4. Ignition on. If the app shows no values: in the web flasher click "Get
   pairing code", then "Show status" (or type `status` in a console).
   "still" (silent) means nothing arrives at the port without a request.
   That is normal for many newer cars, where a gateway sits in front of the
   port.

More on assembly, the console and known limits: [`firmware/README.md`](firmware/README.md)
(German).

## Flashing the firmware

**In the browser (recommended):** open the
[web flasher](https://nicolasasauer.github.io/auto-tracker-can-bus/) in
Chrome or Edge on a computer (Windows, macOS, Linux), connect the reader via
USB-C, click "Install". The page always uses the firmware of the latest
release. The first time, confirm erasing; for an update don't erase, so the
pairing is kept. Phones, Firefox and Safari cannot access USB devices.

**With esptool:** download `can-logger-xiao-esp32c6-factory.bin` from the
[releases](../../releases) and run
`esptool.py --chip esp32c6 write_flash 0x0 can-logger-xiao-esp32c6-factory.bin`.

**Build it yourself** with [PlatformIO](https://platformio.org/) (command
line or the VS Code extension). PlatformIO fetches the "pioarduino"
platform and the libraries on the first build.

```bash
pip install platformio
cd firmware
pio run -t upload          # build and flash via USB
pio device monitor         # serial console, 115200 baud
```

Core tests without hardware (only a C++ compiler needed):

```bash
bash tool/check.sh firmware
```

## Pairing via Bluetooth (PIN)

The reader only talks to **paired** phones. The link is encrypted (LE
Secure Connections with passkey). New phones can only be paired while the
reader is connected to a computer via USB:

1. Reader on the computer via USB, in the
   [web flasher](https://nicolasasauer.github.io/auto-tracker-can-bus/)
   click "Get pairing code". Alternatively open a serial console
   (`pio device monitor`, 115200 baud) and type `pair`. A random **6-digit
   code** appears; the pairing window stays open for 2 minutes.
2. In Auto Tracker under *CAN reader (OBD)* tap "Search for CAN reader",
   pick the reader and enter the code in Android's pairing dialog.

After that the phone connects without entering the code again. At most 3
phones; `unpair` on the console removes all of them. Details:
[BLE protocol, chapter 4](docs/CAN-BLE-PROTOKOLL.md#4-koppeln-und-sicherheit).

## In Auto Tracker

The CAN reader is available to everyone in Auto Tracker as a **beta**:
*Settings → CAN reader (beta)* or in the ⋮ menu of a vehicle. There you get:

- **Live values** per the vehicle profile, a dashboard during a trip
- **Trips with CAN data:** consumption, gear, gradient, odometer
- **Recordings** of all messages, e.g. to find a new signal; "share for AI
  analysis" sends the recording, the profile and instructions to the AI of
  your choice. Its answer is a profile you can import in the app and check
  in the car. Note: a recording may contain your VIN; the app offers to
  remove it.
- **Profile:** view, edit, copy and import

## Contributing profiles

Profiles are JSON files in the working-profile format
([concept, chapter 9.1](docs/CAN-KONZEPT.md#91-arbeitsprofil), German;
code: `packages/can_link/lib/src/profile.dart`):

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

- `start`: offset from the most significant bit of byte 0 (0 = byte 0
  bit 7), signals are big-endian. With `"byte_order": "little"` the DBC/Intel
  numbering applies.
- `value = raw × factor + offset`; `length` 1 to 63.
- `confidence`: `verified` (checked in the car or against a second signal),
  `probable`, `guess`. Please be honest.
- Unknown fields (`note`, `cycle_ms`, `store`, `ignored` …) are kept;
  `note` is a good place for where a signal came from.

How to:

1. Create the profile in Auto Tracker (recording and AI, see above), check
   it in the car and copy it on the profile page.
2. Save it as `packages/can_link/profiles/<make>_<model>_<year>_<bus>.json`
   and open a pull request. Name the vehicle (model, year, engine) and how
   the signals were checked.
3. **Nothing personal:** no VIN (some cars broadcast it in plain text,
   OBD mode 09 PID 02), no real recordings, no odometer readings, places or
   times in the notes.

## Former CAN-Werkbank

Up to v1.0.2 this repository also contained the companion app
**CAN-Werkbank** ("CAN workbench": sniff view, mapping bits by hand,
simulation). Its everyday features now live in Auto Tracker, so it is no
longer developed here. The old APKs remain under [releases](../../releases),
the source in the git history (tag `v1.0.2`).

## License

This project is licensed under the [MIT License](LICENSE).

Dependencies and their licenses:

| Dependency | License |
|---|---|
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) (BLE in the firmware) | Apache-2.0 |
| [autowp-mcp2515](https://github.com/autowp/arduino-mcp2515) (MCP2515 driver) | MIT |
| [Arduino-ESP32](https://github.com/espressif/arduino-esp32) (core, via the [pioarduino](https://github.com/pioarduino/platform-espressif32) platform) | LGPL-2.1, ESP-IDF underneath Apache-2.0 |
| [ESP Web Tools](https://github.com/esphome/esp-web-tools) (web flasher) | Apache-2.0 |
| Flutter, Dart SDK (`can_link`) | BSD-3-Clause |
| [universal_ble](https://pub.dev/packages/universal_ble) (Bluetooth LE in `can_link`) | BSD-3-Clause |
| [clock](https://pub.dev/packages/clock) | Apache-2.0 |

The license texts ship with the respective packages.
