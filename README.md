# Daikin Remote

A replacement for a lost Daikin air-conditioner remote. It's a single **Flutter** codebase that
builds for Android and iOS. The app sends the same infrared frames a real Daikin remote sends:
power, mode, temperature, fan speed, swing and on/off timers. It supports nine Daikin IR
protocols, and a picker helps you find which one your AC uses.

## How the IR gets to the AC

Phones send IR in two ways, and the app supports both. You choose in **Connection** (the
button in the top bar).

| | Phone IR blaster | Wi-Fi IR bridge |
|---|---|---|
| Works on | Android phones with an IR emitter (many Xiaomi/Redmi/POCO, some Huawei/Honor/Vivo) | Any Android phone or iPhone |
| Extra hardware | None | ~$5 ESP32/ESP8266 + IR LED ([`firmware/`](firmware/daikin-ir-bridge)) |
| Aim | Point the phone at the AC | The bridge sits facing the AC; the phone can be anywhere on the Wi-Fi |

```
Android phone with IR blaster ──────────IR──────────▶ AC

Any phone ──Wi-Fi/HTTP──▶ ESP32 + IR LED ──IR──▶ AC
```

iPhones have no IR hardware, so on iOS the app always uses the bridge.

## Repository layout

```
app/                          Flutter app (Android + iOS)
  lib/protocol/               Daikin protocol encoders: Dart port of IRremoteESP8266
  lib/remote.dart             Saved state, timer settling, wire/timer frames
  lib/remote_controller.dart  App state, serial send queue, timer sync and reconciliation
  lib/transport/              PhoneIrTransport (MethodChannel) and BridgeTransport (HTTP)
  lib/ui/                     Remote screen, protocol picker, connection sheet
  android/…/kotlin/           Native IR blaster access + alarm-based phone timers
  test/                       Golden-vector protocol tests + a widget test
firmware/daikin-ir-bridge/    ESP32/ESP8266 Wi-Fi IR bridge (PlatformIO, C++)
```

The earlier separate native apps (Kotlin and SwiftUI) are preserved at the git tag
[`native-apps-v1`](../../tree/native-apps-v1).

## Features

- Power, mode (Auto/Cool/Dry/Heat/Fan), temperature, fan (Auto/Quiet/1–5), vertical and
  horizontal swing. Each protocol only shows the controls it supports.
- **Full state in every frame**, like a real Daikin remote. Each press re-sends the whole
  state, so the AC never drifts out of sync, except on toggle-power protocols (see below).
- **Protocol picker**: tap *Test ON* on each protocol until the AC beeps, then *Use this*.
- **On/off timers** from 15 minutes to 12 hours, with a live countdown (see [Timers](#timers)).
- Light and dark themes. State and settings persist across restarts.

## Supported protocols

| Protocol | Known remotes / units | Native IR timer | Notes |
|---|---|---|---|
| Daikin (280-bit) | ARC433\*\*, ARC470A1, ARC466A12/A33, ARC443A5 (most wall splits) | ✅ clock-based | Tried first |
| Daikin2 (312-bit) | ARC477A1, FTXZ\*\*NV1B | ✅ clock-based | 36.7 kHz carrier |
| Daikin312 | ARC466A58, ARC466A67, ARC472A43, FTXM20R5V1B | ✅ clock-based | 36.7 kHz carrier |
| Daikin216 | ARC433B69, ARC484A4, FTQ60TV16U2 | ❌ | Timer run by phone/bridge |
| Daikin160 | ARC423A5, FTE12HV2S | ❌ | Timer run by phone/bridge |
| **Daikin152** | ARC480A5, ARC480A93 | ✅ relative (reverse-engineered) | **Confirmed on a real unit** |
| Daikin176 | BRC4C151, BRC4C153, FFQ35B8V1B (ceiling cassettes) | ❌ | Fan min/max only |
| Daikin128 | BRC52B63, 17 Series FTXB\*\*AXVJU | ✅ clock-based | Power is a toggle |
| Daikin64 | DGS01, BRC4C158, FFN-C/FCN-F, FTWX35AXV1 | ✅ clock-based | Power is a toggle; no Auto mode |

**Toggle-power protocols** (128/64): the frame carries "press power", not on/off. If the AC
and the app disagree, press Power once more.

### The Daikin152 timer

IRremoteESP8266 doesn't implement a timer for DAIKIN152. This project reverse-engineered it from
the matching section-3 layout of DAIKIN280 and a real ARC480A5 capture:

| Field | Location |
|---|---|
| On-timer enabled | byte 5, bit 1 |
| Off-timer enabled | byte 5, bit 2 |
| On time | 12 bits starting at byte 10, bit 0 |
| Off time | 12 bits starting at byte 11, bit 4 |

The value is the number of **minutes from now** (Daikin152 has no clock), from 1 to 720. Every
button press re-sends the remaining minutes, just as the original remote does. This was
confirmed on a real AC: the unit's timer light comes on and the AC switches at the set time.

## Timers

| Mode | Used for | Who counts down |
|---|---|---|
| **AC-run** (default) | Protocols with a native IR timer | The AC itself. The phone can be put away. |
| **External** | Protocols without one, or "Run timer on the phone/bridge" switched on | The **phone** (built-in blaster) or the **bridge**, whichever you send with |

External timers work the same way on both transports. When you set a timer, the app encodes
the finished "power on/off" frame and hands it over with a delay. The phone stores it with an
exact Android alarm, and the bridge keeps it in RAM. When the delay is up, that side transmits
it without running any Dart code, so it still fires after the app is closed.

- **Phone timers (Android):** the phone must stay pointed at the AC. Some ROMs, Xiaomi
  HyperOS especially, block background alarms. Allow *Autostart* and set battery saver to *No
  restrictions*. If a timer couldn't fire, the app says so the next time it opens.
- **Bridge timers:** the bridge must stay powered. If it restarts, the timer is lost, and the
  app reports it the next time it opens.
- Toggle-power protocols always use the AC's own timer, because an external timer can't know
  which way a toggle will go.

---

## Building the app

**Requirements:** [Flutter](https://docs.flutter.dev/get-started/install) 3.47+ (Dart 3.13+).
For Android you need the Android SDK. For iOS you need a Mac with a current Xcode.

```sh
cd app
flutter pub get
flutter test                 # protocol golden vectors + widget test
```

### Android

```sh
flutter build apk --release  # build/app/outputs/flutter-apk/app-release.apk (all CPUs, ~49 MB)
flutter build apk --release --split-per-abi   # smaller per-CPU APKs; phones use app-arm64-v8a-release.apk
flutter install              # or copy the APK to the phone and open it
```

The release build is signed with the debug key so you can sideload it directly. It needs
Android 7.0+ (API 24). Its application ID is `vn.cake.daikinremote`, so it replaces the
earlier native Android app (Android only allows that when both were signed with the same key,
which is the case if both were built on the same computer; otherwise uninstall the old app first).

Permissions: `TRANSMIT_IR` for the blaster, `INTERNET` for the bridge, and exact alarms plus
boot-completed for phone-run timers.

### iOS

```sh
flutter build ios --release  # or: open ios/Runner.xcworkspace and press Run
```

In Xcode, select the **Runner** target, open **Signing & Capabilities** and choose your Team. A
free Apple ID works, but the app has to be re-installed every 7 days. A paid developer account
removes that limit. iOS asks for **Local Network** access on first launch: allow it, or the
app can't reach the bridge.

### First launch

1. Open **Connection**. On an Android phone with a blaster, *This phone's IR blaster* is
   preselected. Otherwise choose *Wi-Fi IR bridge*, enter its address (`daikin-ir.local`, or
   the IP the bridge prints) and tap *Save and test connection*.
2. The protocol picker opens. Tap *Test ON* on each protocol until the AC beeps, then *Use
   this*. Tap **Protocol** in the top bar to change it later.

---

## The Wi-Fi IR bridge

**Parts:** an ESP32 dev board or a Wemos D1 mini (ESP8266), a 940 nm IR LED, an NPN transistor
(2N2222 or S8050), a 1 kΩ resistor and a 47 Ω resistor.

A bare LED on a GPIO pin only reaches about 1 m, so drive it through the transistor:

```
GPIO4 (D2 on D1 mini) ──1kΩ── B   2N2222
                                   C ──── LED cathode (−)
                                   E ──── GND
5V ──47Ω── LED anode (+)
```

A ready-made "IR transmitter module" with a transistor on the board also works (S → GPIO4).
For more range, add a second LED (with its own 47 Ω resistor) in parallel.

**Flash it** with [PlatformIO](https://platformio.org/) (`pip install platformio`):

```sh
cd firmware/daikin-ir-bridge
cp include/secrets.example.h include/secrets.h   # set WIFI_SSID and WIFI_PASSWORD
pio run -e esp32 -t upload                       # or: -e esp8266
pio device monitor                               # prints: Connected: http://daikin-ir.local (192.168.x.y)
```

To use a different GPIO, add `build_flags = -DIR_PIN=<n>` to the environment in
`platformio.ini`. Mount the bridge with the LED facing the AC and power it from any USB
charger.

### Bridge HTTP API

The bridge doesn't know anything about Daikin. It transmits whatever mark/space pattern the
app sends, so new protocols only need an app update.

| Request | Body | Effect |
|---|---|---|
| `GET /info` | — | `{"device":"daikin-ir-bridge","version":1,"timers":{"on":S,"off":S}}`: S is the seconds left, or −1 if no timer is set |
| `POST /send` | `<freqHz> <mark> <space> <mark> …` (µs, space/comma separated) | Sends it now |
| `POST /timer/on?in=S` | same as `/send` | Sends it after S seconds (also `/timer/off`) |
| `DELETE /timer/on` | — | Cancels that timer (also `/timer/off`) |

The bridge holds up to 1024 pulses per pattern. Try it with `curl http://daikin-ir.local/info`.

The phone's built-in blaster is exposed to Dart with the same model, over the
`vn.cake.daikinremote/ir` MethodChannel: `hasEmitter`, `transmit`, `setTimer`, `cancelTimer`
and `timers`.

---

## Tests

| What | Command | Covers |
|---|---|---|
| Protocols + logic | `cd app && flutter test` | Golden vectors from IRremoteESP8266 for every protocol, the full DAIKIN280 pulse train, the Daikin152 timer layout, pattern limits for every protocol and button, timer settling, external-timer frames, state clamping, JSON persistence |
| UI | (same command) | Picker → choose protocol → power, temperature and timer on the remote screen, with a fake IR channel |
| Firmware | `cd firmware/daikin-ir-bridge && pio run` | Compiles for ESP32 and ESP8266 |

## Troubleshooting

| Symptom | Fix |
|---|---|
| "This phone's IR blaster" is greyed out | The phone has no IR emitter, so use the Wi-Fi bridge |
| AC doesn't react to any protocol | Get closer (1–3 m) and aim at the indoor unit's receiver window. Check the IR LED through a phone camera, where IR shows as purple |
| "Can't reach the bridge" | Make sure the phone and bridge are on the same Wi-Fi. On iOS, allow Local Network (Settings → Daikin Remote). Use the IP instead of `.local` |
| Timer light doesn't come on (AC-run timer) | Try another protocol, or turn on "Run timer on the phone/bridge" |
| Phone timer didn't run | Allow Autostart and set Battery saver to *No restrictions* for the app |
| Toggle protocol out of sync | Press Power once more |

## License and credits

The protocol encoders are a Dart port of the byte layouts, timings and checksums in
[IRremoteESP8266](https://github.com/crankyoldgit/IRremoteESP8266) (`src/ir_Daikin.cpp`), and
the test vectors come from its `test/ir_Daikin_test.cpp`. That code is © its contributors and
licensed under the **GNU LGPL v2.1**, and the bridge firmware links the library itself. See
[NOTICE](NOTICE).
