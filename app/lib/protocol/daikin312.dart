import 'dart:typed_data';

import 'ac_state.dart';
import 'bits.dart';
import 'daikin2.dart';
import 'daikin280.dart';
import 'daikin_protocol.dart';
import 'pulse_builder.dart';

/// Port of IRremoteESP8266 `IRDaikin312` (DAIKIN312, 312 bits / 39 bytes).
class Daikin312State {
  static const length = 39;
  static const swingAuto = 0xF;
  static const swingOff = 0x0;
  static const freq = 36700;
  static const _hdrGap = 25100;
  static const timing = BitTiming(3518, 1688, 453, 1275, 414, 35512);

  final raw = Uint8List(length);

  Daikin312State() {
    reset();
  }

  void reset() {
    raw.setAll(0, const [
      0x11, 0xDA, 0x27, 0x00, 0x02, 0x58, 0x64, 0x00, 0x64, 0x00, //
      0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x2C, 0x00, 0x00, 0x00,
      0x00, 0x06, 0x60, 0x00, 0x00, 0xC5, 0x00, 0x08, 0x00,
    ]);
    disableOnTimer();
    disableOffTimer();
    checksum();
  }

  int get _mode => raw.getBits(25, 4, 3);
  int get _tempC => raw.getBits(26, 0, 7) ~/ 2;

  void setPower(bool on) {
    raw.setBits(25, 0, 1, on ? 1 : 0);
    raw.setBits(6, 7, 1, on ? 0 : 1); // Power2
  }

  void setMode(int code) {
    final m = const [0x3, 0x4, 0x6, 0x2].contains(code) ? code : 0;
    raw.setBits(25, 4, 3, m);
    if (m == 0x3) setTemp(_tempC);
  }

  void setTemp(int c) {
    final min = _mode == 0x3 ? Daikin2State.minCoolTemp : Daikin280State.minTemp;
    raw.setBits(26, 0, 7, clampInt(c, min, Daikin280State.maxTemp) * 2);
  }

  void setFan(int fan) => raw.setBits(28, 4, 4, daikinFanCode(fan));

  void setSwingVertical(int position) => raw.setBits(28, 0, 4, position);
  void setSwingHorizontal(int position) => raw.setBits(29, 0, 4, position);

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
              ..zeroBits(timing, 5, _hdrGap)
              ..section(timing, data, from: 0, length: 20)
              ..section(timing, data, from: 20, length: length - 20))
            .build(),
      );
}

class Daikin312 extends DaikinProtocol {
  const Daikin312();

  @override
  String get id => 'DAIKIN312';
  @override
  String get displayName => 'Daikin312';
  @override
  String get remotes => 'ARC466A58, ARC466A67, ARC472A43, FTXM20R5V1B';
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
    final ac = Daikin312State()
      ..setPower(state.power)
      ..setMode(state.mode.daikinCode)
      ..setTemp(state.tempC)
      ..setFan(state.fan.daikinCode)
      ..setSwingVertical(state.swingV ? Daikin312State.swingAuto : Daikin312State.swingOff)
      ..setSwingHorizontal(state.swingH ? Daikin312State.swingAuto : Daikin312State.swingOff);
    if (now != null) ac.setCurrentTime(minutesOfDay(now));
    final on = state.onTimerAt, off = state.offTimerAt;
    on != null ? ac.enableOnTimer(minutesOfDay(on)) : ac.disableOnTimer();
    off != null ? ac.enableOffTimer(minutesOfDay(off)) : ac.disableOffTimer();
    return Daikin312State.send(ac.finish());
  }
}
