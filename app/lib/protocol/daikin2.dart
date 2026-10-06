import 'dart:typed_data';

import 'ac_state.dart';
import 'bits.dart';
import 'daikin280.dart';
import 'daikin_protocol.dart';
import 'pulse_builder.dart';

/// Port of IRremoteESP8266 `IRDaikin2` (DAIKIN2, 312 bits / 39 bytes).
class Daikin2State {
  static const length = 39;
  static const minCoolTemp = 18;
  static const swingVAuto = 0xF;
  static const swingVOff = 0xE;
  static const swingHAuto = 0xBE;
  static const swingHOff = 0xBF;
  static const freq = 36700;
  static const _leaderMark = 10024;
  static const _leaderSpace = 25180;
  static const timing = BitTiming(3500, 1728, 460, 1270, 420, _leaderMark + _leaderSpace);

  final raw = Uint8List(length);

  Daikin2State() {
    reset();
  }

  void reset() {
    raw.setAll(0, const [
      0x11, 0xDA, 0x27, 0x00, 0x01, 0x00, 0xC0, 0x70, 0x08, 0x0C, //
      0x80, 0x04, 0xB0, 0x16, 0x24, 0x00, 0x00, 0xBE, 0xD0, 0x00,
      0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x00, 0x00, 0xA0, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0xC1, 0x80, 0x60, 0x00,
    ]);
    disableOnTimer();
    disableOffTimer();
    checksum();
  }

  int get _mode => raw.getBits(25, 4, 3);
  int get _temp => raw.getBits(26, 1, 6);

  void setPower(bool on) {
    raw.setBits(25, 0, 1, on ? 1 : 0);
    raw.setBits(6, 7, 1, on ? 0 : 1); // Power2
  }

  void setMode(int code) {
    final m = const [0x3, 0x4, 0x6, 0x2].contains(code) ? code : 0;
    raw.setBits(25, 4, 3, m);
    if (m == 0x3) setTemp(_temp); // Cool has a different minimum temperature.
  }

  void setTemp(int c) {
    final min = _mode == 0x3 ? minCoolTemp : Daikin280State.minTemp;
    raw.setBits(26, 1, 6, clampInt(c, min, Daikin280State.maxTemp));
  }

  void setFan(int fan) => raw.setBits(28, 4, 4, daikinFanCode(fan));

  void setSwingVertical(int position) => raw.setBits(18, 0, 4, position);
  void setSwingHorizontal(int position) => raw.put(17, position);

  void setCurrentTime(int mins) => raw.setBits(5, 0, 12, mins > 24 * 60 ? 0 : mins);

  void enableOnTimer(int start) {
    raw.setBits(36, 5, 1, 0); // SleepTimer
    raw.setBits(25, 1, 1, 1);
    raw.setBits(30, 0, 12, start);
  }

  void disableOnTimer() {
    raw.setBits(30, 0, 12, Daikin280State.unusedTime);
    raw.setBits(25, 1, 1, 0);
    raw.setBits(36, 5, 1, 0);
  }

  void enableOffTimer(int end) {
    raw.setBits(25, 2, 1, 1);
    raw.setBits(31, 4, 12, end);
  }

  void disableOffTimer() {
    raw.setBits(31, 4, 12, Daikin280State.unusedTime);
    raw.setBits(25, 2, 1, 0);
  }

  void setBeep(int beep) => raw.setBits(7, 6, 2, beep);
  void setLight(int light) => raw.setBits(7, 4, 2, light);
  void setMold(bool on) => raw.setBits(8, 3, 1, on ? 1 : 0);
  void setClean(bool on) => raw.setBits(8, 5, 1, on ? 1 : 0);

  void checksum() {
    raw.put(19, sumBytes(raw, 0, 19));
    raw.put(38, sumBytes(raw, 20, 18));
  }

  Uint8List finish() {
    checksum();
    return Uint8List.fromList(raw);
  }

  static IrFrame send(Uint8List data) => IrFrame(
        freq,
        (PulseBuilder()
              ..mark(_leaderMark)
              ..space(_leaderSpace)
              ..section(timing, data, from: 0, length: 20)
              ..section(timing, data, from: 20, length: length - 20))
            .build(),
      );
}

class Daikin2 extends DaikinProtocol {
  const Daikin2();

  @override
  String get id => 'DAIKIN2';
  @override
  String get displayName => 'Daikin2 (312-bit)';
  @override
  String get remotes => 'ARC477A1, FTXZ**NV1B';
  @override
  List<Mode> get modes => Mode.values;
  @override
  List<Fan> get fans => Fan.values;
  @override
  bool get supportsSwingV => true;
  @override
  bool get supportsSwingH => true;
  @override
  bool get nativeTimer => true;

  @override
  TempRange tempRange(Mode mode) => standardTempRange(mode);

  @override
  IrFrame encode(AcState state, RemoteKey key, DateTime? now) {
    final ac = Daikin2State()
      ..setPower(state.power)
      ..setMode(state.mode.daikinCode)
      ..setTemp(state.tempC)
      ..setFan(state.fan.daikinCode)
      ..setSwingVertical(state.swingV ? Daikin2State.swingVAuto : Daikin2State.swingVOff)
      ..setSwingHorizontal(state.swingH ? Daikin2State.swingHAuto : Daikin2State.swingHOff);
    if (now != null) ac.setCurrentTime(minutesOfDay(now));
    final on = state.onTimerAt, off = state.offTimerAt;
    on != null ? ac.enableOnTimer(minutesOfDay(on)) : ac.disableOnTimer();
    off != null ? ac.enableOffTimer(minutesOfDay(off)) : ac.disableOffTimer();
    return Daikin2State.send(ac.finish());
  }
}
