// DAIKIN216, DAIKIN160, DAIKIN152 and DAIKIN176: single-state protocols without a clock.

import 'dart:typed_data';

import 'ac_state.dart';
import 'bits.dart';
import 'daikin2.dart';
import 'daikin280.dart';
import 'daikin_protocol.dart';
import 'pulse_builder.dart';

/// Port of IRremoteESP8266 `IRDaikin216` (DAIKIN216, 216 bits / 27 bytes).
class Daikin216State {
  static const length = 27;
  static const timing = BitTiming(3440, 1750, 420, 1300, 450, 29650);

  final raw = Uint8List(length);

  Daikin216State() {
    raw
      ..put(0, 0x11)
      ..put(1, 0xDA)
      ..put(2, 0x27)
      ..put(3, 0xF0)
      ..put(8, 0x11)
      ..put(9, 0xDA)
      ..put(10, 0x27)
      ..put(23, 0xC0);
  }

  void setPower(bool on) => raw.setBits(13, 0, 1, on ? 1 : 0);
  void setMode(int code) => raw.setBits(13, 4, 3, code);
  void setTemp(int c) => raw.setBits(14, 1, 6, clampInt(c, Daikin280State.minTemp, Daikin280State.maxTemp));
  void setFan(int fan) => raw.setBits(16, 4, 4, daikinFanCode(fan));
  void setSwingVertical(bool on) => raw.setBits(16, 0, 4, on ? 0xF : 0);
  void setSwingHorizontal(bool on) => raw.setBits(17, 0, 4, on ? 0xF : 0);

  Uint8List finish() {
    raw.put(7, sumBytes(raw, 0, 7));
    raw.put(26, sumBytes(raw, 8, length - 8 - 1));
    return Uint8List.fromList(raw);
  }

  static IrFrame send(Uint8List data) => IrFrame(
        38000,
        (PulseBuilder()
              ..section(timing, data, from: 0, length: 8)
              ..section(timing, data, from: 8, length: length - 8))
            .build(),
      );
}

class Daikin216 extends DaikinProtocol {
  const Daikin216();

  @override
  String get id => 'DAIKIN216';
  @override
  String get displayName => 'Daikin216';
  @override
  String get remotes => 'ARC433B69, ARC484A4, FTQ60TV16U2';
  @override
  List<Mode> get modes => Mode.values;
  @override
  List<Fan> get fans => Fan.values;
  @override
  bool get supportsSwingV => true;
  @override
  bool get supportsSwingH => true;
  @override
  bool get nativeTimer => false;

  @override
  TempRange tempRange(Mode mode) => standardTempRange(mode);

  @override
  IrFrame encode(AcState state, RemoteKey key, DateTime? now) {
    final ac = Daikin216State()
      ..setPower(state.power)
      ..setMode(state.mode.daikinCode)
      ..setTemp(state.tempC)
      ..setFan(state.fan.daikinCode)
      ..setSwingVertical(state.swingV)
      ..setSwingHorizontal(state.swingH);
    return Daikin216State.send(ac.finish());
  }
}

/// Port of IRremoteESP8266 `IRDaikin160` (DAIKIN160, 160 bits / 20 bytes).
class Daikin160State {
  static const swingLowest = 0x1;
  static const swingAuto = 0xF;
  static const timing = BitTiming(5000, 2145, 342, 1786, 700, 29650);

  final raw = bytesOf(const [
    0x11, 0xDA, 0x27, 0xF0, 0x0D, 0x00, 0x00, //
    0x11, 0xDA, 0x27, 0x00, 0xD3, 0x30, 0x11, 0x00, 0x00, 0x1E, 0x0A, 0x08, 0x00,
  ]);

  void setPower(bool on) => raw.setBits(12, 0, 1, on ? 1 : 0);
  void setMode(int code) => raw.setBits(12, 4, 3, code);
  void setTemp(int c) =>
      raw.setBits(16, 1, 6, clampInt(c, Daikin280State.minTemp, Daikin280State.maxTemp) - 10);
  void setFan(int fan) => raw.setBits(17, 0, 4, daikinFanCode(fan));

  /// 1 (lowest) … 5 (highest), or 0xF for auto swing.
  void setSwingVertical(int position) =>
      raw.setBits(13, 4, 4, position >= 1 && position <= 5 ? position : swingAuto);

  Uint8List finish() {
    raw.put(6, sumBytes(raw, 0, 6));
    raw.put(19, sumBytes(raw, 7, 12));
    return Uint8List.fromList(raw);
  }

  static IrFrame send(Uint8List data) => IrFrame(
        38000,
        (PulseBuilder()
              ..section(timing, data, from: 0, length: 7)
              ..section(timing, data, from: 7, length: data.length - 7))
            .build(),
      );
}

class Daikin160 extends DaikinProtocol {
  const Daikin160();

  @override
  String get id => 'DAIKIN160';
  @override
  String get displayName => 'Daikin160';
  @override
  String get remotes => 'ARC423A5, FTE12HV2S';
  @override
  List<Mode> get modes => Mode.values;
  @override
  List<Fan> get fans => Fan.values;
  @override
  bool get supportsSwingV => true;
  @override
  bool get supportsSwingH => false;
  @override
  bool get nativeTimer => false;

  @override
  TempRange tempRange(Mode mode) => standardTempRange(mode);

  @override
  IrFrame encode(AcState state, RemoteKey key, DateTime? now) {
    final ac = Daikin160State()
      ..setPower(state.power)
      ..setMode(state.mode.daikinCode)
      ..setTemp(state.tempC)
      ..setFan(state.fan.daikinCode)
      // No "off" position exists; swing off parks the vane at its reset (lowest) position.
      ..setSwingVertical(state.swingV ? Daikin160State.swingAuto : Daikin160State.swingLowest);
    return Daikin160State.send(ac.finish());
  }
}

/// Port of IRremoteESP8266 `IRDaikin152` (DAIKIN152, 152 bits / 19 bytes).
class Daikin152State {
  static const length = 19;
  static const fanTemp = 0x60;
  static const maxTimerMinutes = 12 * 60;
  static const timing = BitTiming(3492, 1718, 433, 1529, 433, 25182);

  final raw = Uint8List(length);

  Daikin152State() {
    raw
      ..put(0, 0x11)
      ..put(1, 0xDA)
      ..put(2, 0x27)
      ..put(15, 0xC5);
  }

  int get _mode => raw.getBits(5, 4, 3);

  void setPower(bool on) => raw.setBits(5, 0, 1, on ? 1 : 0);

  void setMode(int code) {
    switch (code) {
      case 0x6:
        setTemp(fanTemp); // Fan mode uses a special temperature.
      case 0x2:
        setTemp(Daikin2State.minCoolTemp); // Dry is fixed at 18°C.
      case 0x0 || 0x3 || 0x4:
        break;
      default:
        raw.setBits(5, 4, 3, 0);
        return;
    }
    raw.setBits(5, 4, 3, code);
  }

  void setTemp(int c) {
    final min = _mode == 0x4 ? Daikin280State.minTemp : Daikin2State.minCoolTemp;
    final degrees = c == fanTemp ? c : clampInt(c, min, Daikin280State.maxTemp);
    raw.setBits(6, 1, 7, degrees);
  }

  void setFan(int fan) => raw.setBits(8, 4, 4, daikinFanCode(fan));

  void setSwingV(bool on) => raw.setBits(8, 0, 4, on ? 0xF : 0);

  // Timers: not in IRremoteESP8266. The frame matches section 3 of DAIKIN280 (and section 2 of
  // DAIKIN2), whose timer fields sit at the same offsets; a real ARC480A5 "night sleep" capture
  // (issue #873) carries 0x3C (60) there. With no clock in this protocol, the value is the
  // number of minutes from now. Unused timers are sent as 0, as the real remote does.
  // Confirmed working on a real unit.
  void enableOnTimer(int minutesFromNow) {
    raw.setBits(5, 1, 1, 1);
    raw.setBits(10, 0, 12, clampInt(minutesFromNow, 1, maxTimerMinutes));
  }

  void enableOffTimer(int minutesFromNow) {
    raw.setBits(5, 2, 1, 1);
    raw.setBits(11, 4, 12, clampInt(minutesFromNow, 1, maxTimerMinutes));
  }

  Uint8List finish() {
    raw.put(length - 1, sumBytes(raw, 0, length - 1));
    return Uint8List.fromList(raw);
  }

  static IrFrame send(Uint8List data) => IrFrame(
        38000,
        (PulseBuilder()
              ..zeroBits(timing, 5, timing.gap)
              ..section(timing, data))
            .build(),
      );
}

class Daikin152 extends DaikinProtocol {
  const Daikin152();

  @override
  String get id => 'DAIKIN152';
  @override
  String get displayName => 'Daikin152';
  @override
  String get remotes => 'ARC480A5, ARC480A93 (timer support is reverse-engineered)';
  @override
  List<Mode> get modes => Mode.values;
  @override
  List<Fan> get fans => Fan.values;
  @override
  bool get supportsSwingV => true;
  @override
  bool get supportsSwingH => false;
  @override
  bool get nativeTimer => true;

  @override
  TempRange tempRange(Mode mode) => standardTempRange(mode);

  @override
  IrFrame encode(AcState state, RemoteKey key, DateTime? now) {
    final ac = Daikin152State()
      ..setPower(state.power)
      // Temp before mode, so Dry/Fan can override it with their fixed values.
      ..setTemp(state.tempC)
      ..setMode(state.mode.daikinCode);
    if (state.mode == Mode.auto || state.mode == Mode.cool || state.mode == Mode.heat) {
      ac.setTemp(state.tempC);
    }
    ac
      ..setFan(state.fan.daikinCode)
      ..setSwingV(state.swingV);
    // Relative timers: re-sent with the remaining minutes on every press, like the remote.
    final reference = now ?? DateTime.now();
    final on = state.onTimerAt, off = state.offTimerAt;
    if (on != null) ac.enableOnTimer(minutesUntil(on, reference));
    if (off != null) ac.enableOffTimer(minutesUntil(off, reference));
    return Daikin152State.send(ac.finish());
  }
}

/// Port of IRremoteESP8266 `IRDaikin176` (DAIKIN176, 176 bits / 22 bytes).
class Daikin176State {
  static const fan = 0x0;
  static const heat = 0x1;
  static const cool = 0x2;
  static const auto = 0x3;
  static const dry = 0x7;
  static const modeButton = 0x04;
  static const dryFanTemp = 17;
  static const fanMax = 3;
  static const swingHAuto = 0x5;
  static const swingHOff = 0x6;
  static const timing = BitTiming(5070, 2140, 370, 1780, 710, 29410);

  final raw = bytesOf(const [
    0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x00, //
    0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x00, 0x20, 0x00, 0x00, 0x00, 0x16, 0x00, 0x20, 0x00,
  ]);
  late int _savedTemp = raw.getBits(17, 1, 6) + 9;

  int get _mode => raw.getBits(14, 4, 3);

  void setPower(bool on) {
    raw.put(13, 0); // ModeButton
    raw.setBits(14, 0, 1, on ? 1 : 0);
  }

  void setMode(int code) {
    var m = code;
    final int alt;
    switch (code) {
      case dry:
        alt = 2;
      case fan:
        alt = 6;
      case auto || cool || heat:
        alt = 7;
      default:
        m = cool;
        alt = 7;
    }
    raw.setBits(14, 4, 3, m);
    raw.setBits(12, 4, 3, alt);
    setTemp(_savedTemp);
    raw.put(13, modeButton); // Must follow setTemp(), which clears it.
  }

  void setTemp(int c) {
    var degrees = clampInt(c, Daikin280State.minTemp, Daikin280State.maxTemp);
    _savedTemp = degrees;
    if (_mode == dry || _mode == fan) degrees = dryFanTemp;
    raw.setBits(17, 1, 6, degrees - 9);
    raw.put(13, 0);
  }

  /// 1 (min) or 3 (max).
  void setFan(int speed) {
    raw.setBits(18, 4, 4, speed == 1 || speed == fanMax ? speed : fanMax);
    raw.put(13, 0);
  }

  void setSwingHorizontal(int position) =>
      raw.setBits(18, 0, 4, position == swingHOff || position == swingHAuto ? position : swingHAuto);

  Uint8List finish() {
    raw.put(6, sumBytes(raw, 0, 6));
    raw.put(21, sumBytes(raw, 7, 14));
    return Uint8List.fromList(raw);
  }

  static IrFrame send(Uint8List data) => IrFrame(
        38000,
        (PulseBuilder()
              ..section(timing, data, from: 0, length: 7)
              ..section(timing, data, from: 7, length: data.length - 7))
            .build(),
      );
}

class Daikin176 extends DaikinProtocol {
  const Daikin176();

  @override
  String get id => 'DAIKIN176';
  @override
  String get displayName => 'Daikin176';
  @override
  String get remotes => 'BRC4C151, BRC4C153, FFQ35B8V1B (ceiling cassettes)';
  @override
  List<Mode> get modes => Mode.values;
  @override
  List<Fan> get fans => const [Fan.l1, Fan.l5];
  @override
  bool get supportsSwingV => false;
  @override
  bool get supportsSwingH => true;
  @override
  bool get nativeTimer => false;

  @override
  TempRange tempRange(Mode mode) => standardTempRange(mode);

  @override
  IrFrame encode(AcState state, RemoteKey key, DateTime? now) {
    final ac = Daikin176State()
      ..setMode(switch (state.mode) {
        Mode.auto => Daikin176State.auto,
        Mode.cool => Daikin176State.cool,
        Mode.dry => Daikin176State.dry,
        Mode.heat => Daikin176State.heat,
        Mode.fan => Daikin176State.fan,
      })
      ..setPower(state.power)
      ..setTemp(state.tempC)
      ..setFan(state.fan == Fan.l1 || state.fan == Fan.l2 ? 1 : Daikin176State.fanMax)
      ..setSwingHorizontal(state.swingH ? Daikin176State.swingHAuto : Daikin176State.swingHOff);
    // The remote flags frames sent by the Mode button.
    if (key == RemoteKey.mode) ac.raw.put(13, Daikin176State.modeButton);
    return Daikin176State.send(ac.finish());
  }
}
