# Daikin Remote for iOS

The iOS version of the Android app. iPhones have no IR blaster, so the app sends each command
over Wi-Fi to a small ESP32/ESP8266 **IR bridge** (`../firmware/daikin-ir-bridge`), and the
bridge flashes the IR LED at the AC. All of the Daikin encoding runs in the app, using the same
protocol port, golden tests and reverse-engineered Daikin152 timer as the Android app.

```
iPhone ──Wi-Fi/HTTP──▶ ESP32 + IR LED ──IR──▶ AC
```

## 1. Build the bridge (about $5)

Parts: an ESP32 dev board or a Wemos D1 mini (ESP8266), a 940 nm IR LED, an NPN transistor
(2N2222/S8050), a 1 kΩ resistor and a 47 Ω resistor. A bare LED on a GPIO pin only reaches
about 1 m, so drive it through the transistor:

```
GPIO4 (D2 on D1 mini) ──1kΩ── B   2N2222
                                   C ──── LED cathode (−)
                                   E ──── GND
5V ──47Ω── LED anode (+)
```

A ready-made "IR transmitter module" that has a transistor on the board also works (S → GPIO4).

Flash it with PlatformIO (`pip install platformio`):

```sh
cd firmware/daikin-ir-bridge
cp include/secrets.example.h include/secrets.h   # set WIFI_SSID / WIFI_PASSWORD
pio run -e esp32 -t upload        # or: -e esp8266
pio device monitor                # prints "Connected: http://daikin-ir.local (192.168.x.y)"
```

Mount it with the LED facing the AC. It can stay plugged into any USB charger.

## 2. Build the app (Mac with Xcode 15+)

```sh
brew install xcodegen
cd ios
xcodegen                  # creates DaikinRemote.xcodeproj from project.yml
open DaikinRemote.xcodeproj
```

In Xcode, select the **DaikinRemote** target, open **Signing & Capabilities**, choose your Team
(a free Apple ID works), connect the iPhone and press Run. With a free Apple ID the app has to
be re-installed from Xcode every 7 days. A paid developer account removes that limit.

On first launch, allow **Local Network** access when iOS asks. The app talks to
`daikin-ir.local` by default. If that name doesn't resolve on your network, tap **Bridge** and
enter the IP address the serial monitor printed.

Then pick the protocol the same way as on Android: **Test ON** on each protocol until the AC
beeps, then **Use this**. Your AC is **Daikin152**.

## Timers

- **AC-run timers** (Daikin152 and the other `nativeTimer` protocols) are sent inside the IR
  frame. The AC counts down itself, so the phone and the bridge can both be off.
- **Bridge-run timers** cover protocols with no IR timer (160/176/216), or any absolute-power
  protocol when "Run timer on the bridge" is on. The bridge stores the finished frame and
  sends it when the timer is due. iOS can't run code in the background on a schedule, so the
  phone isn't involved. If the bridge loses power, the timer is lost, and the app says so the
  next time it opens.

## Tests

The protocol code is a Swift package that builds without Xcode:

```sh
cd ios/DaikinCore && swift test
```

## Layout

| Path | Contents |
|---|---|
| `DaikinCore/` | Swift package: protocol encoders, pulse builder, timer/state logic, golden tests |
| `DaikinRemote/` | SwiftUI app: remote screen, protocol picker, bridge setup, HTTP client |
| `project.yml` | XcodeGen spec for the app target |
| `../firmware/daikin-ir-bridge/` | ESP32/ESP8266 firmware (PlatformIO) |

## Bridge HTTP API

| Request | Effect |
|---|---|
| `GET /info` | `{"device":"daikin-ir-bridge","version":1,"timers":{"on":S,"off":S}}`; S is the seconds left, or −1 if no timer is set |
| `POST /send` | Body `"<freqHz> <mark> <space> …"` (µs); sends it now |
| `POST /timer/on?in=S` | Same body; sends it after S seconds (also `/timer/off`) |
| `DELETE /timer/on` | Cancels that timer (also `/timer/off`) |
