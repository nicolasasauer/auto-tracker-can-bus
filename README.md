# Auto Tracker CAN-Bus

**English** · [Deutsch](README.de.md)

A small **CAN reader for the OBD-II port** and the Android app
**CAN-Werkbank** ("CAN workbench"): listen to your car's CAN bus, watch
messages live, map signals (RPM, speed, steering angle …) to bits and turn
them into a **vehicle profile** (JSON). A first profile for the Peugeot 208 I
(2016) is included.

> **Listen-only. Use at your own risk, without any warranty.**
> The CAN controller runs in listen-only mode and never transmits on the
> bus, not even acknowledgements (ACK); the firmware contains no code to
> send. Still: any work on a vehicle, even read-only, is at your own risk
> and may affect your warranty. Do not handle the reader or your phone
> while driving. Nobody accepts liability for damage to the vehicle, the
> battery or any other consequences (see [LICENSE](LICENSE)).

The app, the firmware console, code comments and the detailed docs are in
German.

## Contents

| Folder | Contents |
|---|---|
| [`firmware/`](firmware/) | Firmware for the reader (PlatformIO, C++). Core in `lib/can_core`, tested on the PC. |
| [`app/`](app/) | CAN-Werkbank, Android app (Flutter) |
| [`packages/can_link/`](packages/can_link/) | Dart package: BLE protocol, profiles, simulation. Vehicle profiles in [`profiles/`](packages/can_link/profiles/). |
| [`docs/`](docs/) | [Concept](docs/CAN-KONZEPT.md), [BLE protocol](docs/CAN-BLE-PROTOKOLL.md), [Peugeot 208 research](docs/FAHRZEUG-PEUGEOT-208.md) (German) |

## Hardware

| Part | Note |
|---|---|
| **Seeed Studio XIAO ESP32-C6** | microcontroller with Bluetooth LE |
| **Seeed "XIAO CAN Bus Expansion Board"** | MCP2515 CAN controller (SPI, 16 MHz crystal) and SN65HVD230 transceiver, screw terminal GND / CAN-H / CAN-L |
| **OBD-II cable with open wires** | plug for the car's port |
| USB-C cable, laptop | for flashing and for power during the first test |

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
3. **Power over USB.** Power the XIAO over USB from a laptop running on
   battery. The CAN board has **no 12 V input**. Only connect pin 16 once a
   dedicated regulator with protection sits in between (fuse, reverse
   polarity protection, TVS diode, regulator rated for inputs up to 40 V;
   the car's supply dips during cranking and has spikes, see
   [concept, chapter 7](docs/CAN-KONZEPT.md#7-hardware)).
4. Ignition on, open the console (see below) and type `status`. "still"
   (silent) means nothing arrives at the port without a request. That is
   normal for many newer cars, where a gateway sits in front of the port.

More on assembly, the console and known limits: [`firmware/README.md`](firmware/README.md)
(German).

## Building and flashing the firmware

With [PlatformIO](https://platformio.org/) (command line or the VS Code
extension). PlatformIO downloads the "pioarduino" platform (Arduino-ESP32
3.x) and the libraries on the first build.

```bash
pip install platformio
cd firmware
pio run -t upload          # build and flash over USB
pio device monitor         # serial console, 115200 baud
```

A prebuilt firmware (`can-logger-xiao-esp32c6.bin`) is also attached to the
[releases](../../releases).

Core tests without hardware (only a C++ compiler needed):

```bash
bash tool/check.sh firmware
```

## Pairing over Bluetooth (PIN)

The reader only talks to **paired** phones. The link is encrypted (LE
Secure Connections with passkey). New phones can only be paired while the
reader is connected to a PC over USB:

1. Connect the reader to the PC over USB, open the console
   (`pio device monitor`).
2. Type `pair`. The console shows a random **6-digit code**. The pairing
   window stays open for 2 minutes.
3. In the CAN-Werkbank tap "CAN-Leser suchen" (search reader), connect and
   enter the code in Android's pairing dialog.

After that the phone reconnects without asking. At most 3 phones; `unpair`
on the console removes all of them. Details:
[BLE protocol, chapter 4](docs/CAN-BLE-PROTOKOLL.md#4-koppeln-und-sicherheit).

## CAN-Werkbank

**Install:** the APK (arm64, for current Android phones) is attached to the
[releases](../../releases). Download and install it (allow installing from
unknown sources). The app asks for Bluetooth permissions.

**Build it yourself** (Flutter 3.47.6, stable):

```bash
cd app
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Without your own key, Gradle signs with the debug key. That is fine for
personal use. The APKs from the releases carry a different signature, so
you cannot install one over the other.

**Working with the app:**

1. **Listen:** connect the reader (or pick "Simulation" without hardware).
   The sniff view shows every CAN ID with its bytes, rate and count; changed
   bytes light up. Standard OBD requests and responses are shown with name
   and unit right away.
2. **Map signals:** tap a CAN ID, mark the bits of a signal in the bit grid,
   set factor and offset. "Faktor aus Sollwert" computes the factor from the
   value your speedometer or trip computer shows. Pin signals and watch
   them as a graph.
3. **Record:** red dot in the sniff view, set markers while recording
   ("left indicator"). Replay later or share as a bundle for an AI-assisted
   analysis.
4. **Export the profile:** share it or save it as a file from the profile
   page; import works from a file or the clipboard.

Example profiles in the menu of the profile page: Peugeot 208 (2016) and
simulation.

## Contributing profiles

Profiles are JSON files in the workbench format
([concept, chapter 9.1](docs/CAN-KONZEPT.md#91-arbeitsprofil); code:
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

- `start`: offset from the most significant bit of byte 0 (0 = byte 0
  bit 7); signals are big endian. With `"byte_order": "little"` the DBC/Intel
  numbering applies.
- `value = raw × factor + offset`; `length` 1 to 63.
- `confidence`: `verified` (checked against the car or a second signal),
  `probable`, `guess`. Please be honest.
- Unknown fields (`note`, `cycle_ms`, `store`, `ignored` …) are preserved;
  `note` is a good place to say where a signal comes from.

How to contribute:

1. Create the profile in the workbench and export it.
2. Save it as `packages/can_link/profiles/<make>_<model>_<year>_<bus>.json`
   and open a pull request. Name the vehicle (model, year, engine) and how
   the signals were checked.
3. **Do not include anything personal:** no VIN (some cars broadcast it in
   plain text on the bus; OBD mode 09 PID 02), no real recordings, no
   odometer readings, places or times in the notes.

## License

This project is licensed under the [MIT License](LICENSE).

Dependencies and their licenses (checked for the versions in
`platformio.ini` and `app/pubspec.lock`):

| Dependency | License |
|---|---|
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) (BLE in the firmware) | Apache-2.0 |
| [autowp-mcp2515](https://github.com/autowp/arduino-mcp2515) (MCP2515 driver) | MIT |
| [Arduino-ESP32](https://github.com/espressif/arduino-esp32) (core, via the [pioarduino](https://github.com/pioarduino/platform-espressif32) platform) | LGPL-2.1, ESP-IDF underneath Apache-2.0 |
| Flutter, Dart SDK | BSD-3-Clause |
| [universal_ble](https://pub.dev/packages/universal_ble) (Bluetooth LE in the app) | BSD-3-Clause |
| [file_picker](https://pub.dev/packages/file_picker) | MIT |
| [path_provider](https://pub.dev/packages/path_provider), [share_plus](https://pub.dev/packages/share_plus) | BSD-3-Clause |
| [clock](https://pub.dev/packages/clock) | Apache-2.0 |
| other transitive Dart packages | mostly BSD-3-Clause or MIT; `material_color_utilities` Apache-2.0; `bluez` and `dbus` (Linux only, via `universal_ble`) MPL-2.0 |

The license texts ship with each package.
