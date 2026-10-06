# Daikin Remote

A replacement for a lost Daikin air-conditioner remote, for Android and iOS. The app sends the
same infrared frames a real Daikin remote sends: power, mode, temperature, fan speed, swing
and on/off timers. It supports nine Daikin IR protocols, and a picker helps you find which one
your AC uses.

| Platform | How the IR gets to the AC |
|---|---|
| **Android** | The phone's built-in IR blaster (many Xiaomi/Redmi/POCO, some Huawei/Honor/Vivo phones) |
| **iOS** | iPhones have no IR blaster, so the app sends each command over Wi-Fi to a ~$5 ESP32/ESP8266 **IR bridge**, which flashes it at the AC |

```
Android phone ─────────────IR─────────────▶ AC

iPhone ──Wi-Fi/HTTP──▶ ESP32 + IR LED ──IR──▶ AC
```

## Repository layout

```
android/                    Android app (Kotlin, Jetpack Compose, Gradle)
  app/src/main/…/protocol/  Daikin protocol encoders (Kotlin port of IRremoteESP8266)
  app/src/main/…/ir/        Pulse builder + ConsumerIrManager transmitter
  app/src/main/…/timer/     Phone-side timers (alarms + foreground service)
  app/src/main/…/ui/        Remote screen, protocol picker
  app/src/test/             Golden-vector tests
ios/                        iOS app (Swift, SwiftUI)
  DaikinCore/               Swift package: protocol encoders, pulse builder, state/timer logic, tests
  DaikinRemote/             SwiftUI app: remote, protocol picker, bridge setup, HTTP client
  project.yml               XcodeGen spec that generates the Xcode project
firmware/daikin-ir-bridge/  ESP32/ESP8266 IR bridge for the iOS app (PlatformIO, C++)
```

Both apps use the same protocol code. The Swift encoders are a line-by-line port of the Kotlin
ones, and both are tested against the same vectors from IRremoteESP8266's test suite, so they
produce bit-identical frames.

## Features

- Power, mode (Auto/Cool/Dry/Heat/Fan), temperature, fan (Auto/Quiet/1–5), vertical and
  horizontal swing. Each protocol only shows the controls it supports.
- **Full state in every frame**, like a real Daikin remote. Each press re-sends the whole
  state, so the AC never drifts out of sync, except on toggle-power protocols (see below).
- **Protocol picker**: tap *Test ON* on each protocol until the AC beeps, then *Use this*.
- **On/off timers** from 15 minutes to 12 hours, with a live countdown. Who runs a timer
  depends on the protocol (see [Timers](#timers)).
- State and settings persist across app restarts.

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

If you know your remote's model number (printed on its back), look for it in the table.
Otherwise use the picker.

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

| Mode | Used for | Who counts down | Phone needed afterwards? |
|---|---|---|---|
| **AC-run** | Protocols with a native IR timer (default) | The AC itself | No |
| **Phone-run** (Android) | Protocols without one, or "Run timer on the phone" switched on | Android alarm + foreground service, which sends IR when due | Yes: it must stay pointed at the AC |
| **Bridge-run** (iOS) | Protocols without one, or "Run timer on the bridge" switched on | The ESP bridge, which holds the finished frame | No, but the bridge must stay powered |

Notes:

- **Android:** OEM ROMs such as Xiaomi HyperOS kill background apps. For phone-run timers, allow
  *Autostart* and set battery saver to *No restrictions*. If a timer couldn't fire, the app
  says so the next time it opens.
- **iOS:** the phone can't run code on a schedule in the background, so the bridge sends the
  command. If the bridge loses power, the timer is lost, and the app reports it the next time
  it opens.
- Toggle-power protocols always use the AC's own timer, because an external timer can't know
  which way a toggle will go.

---

## Android

**Requirements:** Android 8.0+ (API 26) and a phone with a built-in IR blaster. USB-C IR dongles
don't work, because the app uses Android's `ConsumerIrManager`. To build: JDK 17 and the
Android SDK (API 35).

```sh
cd android
./gradlew testDebugUnitTest      # golden-vector tests
./gradlew assembleRelease        # app/build/outputs/apk/release/app-release.apk
```

The release build is signed with the debug key so you can sideload it directly (`adb install`,
or copy the APK to the phone). Alternatively, open the `android/` folder in Android Studio.

**Usage:** on first launch, point the top of the phone at the AC from 1–3 m away and work
through the protocol picker. The *Protocol* button in the top bar reopens the picker later.

Permissions: `TRANSMIT_IR`, plus exact alarms, boot-completed, a foreground service and
notifications. Those are only used for phone-run timers.

---

## iOS

**Requirements:** a Mac with Xcode 15+, an iPhone on iOS 17+, and the IR bridge below.

### 1. Build the IR bridge

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

### 2. Build the app

```sh
brew install xcodegen
cd ios
xcodegen                          # generates DaikinRemote.xcodeproj from project.yml
open DaikinRemote.xcodeproj
```

In Xcode, select the **DaikinRemote** target, open **Signing & Capabilities**, choose your Team
and press **Run** with the iPhone connected. A free Apple ID works, but the app then has to be
re-installed from Xcode every 7 days. A paid developer account removes that limit.

### 3. First launch

1. Allow **Local Network** access when iOS asks. Without it the app can't reach the bridge.
2. The app talks to `daikin-ir.local` by default. If that name doesn't resolve on your
   network, tap **Bridge** and enter the IP address the serial monitor printed. The dot next
   to *Bridge* is green when it's reachable.
3. Use the protocol picker as on Android, with the bridge (not the phone) pointed at the AC.

### Bridge HTTP API

The bridge doesn't know anything about Daikin. It transmits whatever mark/space pattern the
app sends, so new protocols only need an app update.

| Request | Body | Effect |
|---|---|---|
| `GET /info` | — | `{"device":"daikin-ir-bridge","version":1,"timers":{"on":S,"off":S}}`: S is the seconds left, or −1 if no timer is set |
| `POST /send` | `<freqHz> <mark> <space> <mark> …` (µs, space/comma separated) | Sends it now |
| `POST /timer/on?in=S` | same as `/send` | Sends it after S seconds (also `/timer/off`) |
| `DELETE /timer/on` | — | Cancels that timer (also `/timer/off`) |

Example, testing from a computer on the same Wi-Fi:

```sh
curl http://daikin-ir.local/info
```

The bridge holds up to 1024 pulses per pattern, and timers live in RAM.

---

## Tests

| What | Command | Covers |
|---|---|---|
| Android protocols | `cd android && ./gradlew testDebugUnitTest` | Golden vectors from IRremoteESP8266, the full DAIKIN280 pulse train, Daikin152 timer layout, a pattern sanity check for every protocol and button |
| iOS protocols + logic | `cd ios/DaikinCore && swift test` (macOS or Linux) | The same golden vectors, plus timer settling, bridge-timer frame stripping, state clamping, decoding of old saves |
| Firmware | `cd firmware/daikin-ir-bridge && pio run` | Compiles for ESP32 and ESP8266 |

When you change a protocol, change it in **both** `android/…/protocol/` and
`ios/DaikinCore/Sources/DaikinCore/`, and keep the tests in step.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Android: "No IR blaster found" | This phone has no IR emitter. The Android app can't use the bridge, so use an iPhone with the bridge instead |
| AC doesn't react to any protocol | Get closer (1–3 m) and aim at the indoor unit's receiver window. On iOS, check the bridge LED with a phone camera (IR shows as purple) |
| iOS: "Can't reach the bridge" | Make sure the phone and bridge are on the same Wi-Fi, Local Network permission is allowed (Settings → Daikin Remote), and use the IP instead of `.local` |
| Timer light doesn't come on (AC-run timer) | Try another protocol, or turn on "Run timer on the phone/bridge" |
| Toggle protocol out of sync | Press Power once more |
| Bridge flashing fails on ESP8266 | Hold FLASH/BOOT while it connects, or lower `upload_speed` |

## License and credits

The protocol encoders are Kotlin and Swift ports of the byte layouts, timings and checksums in
[IRremoteESP8266](https://github.com/crankyoldgit/IRremoteESP8266) (`src/ir_Daikin.cpp`), and
the test vectors come from its `test/ir_Daikin_test.cpp`. That code is © its contributors and
licensed under the **GNU LGPL v2.1**, and the bridge firmware links the library itself. See
[NOTICE](NOTICE).
