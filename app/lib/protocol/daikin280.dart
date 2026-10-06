import 'dart:typed_data';

import 'ac_state.dart';
import 'bits.dart';
import 'daikin_protocol.dart';
import 'pulse_builder.dart';

/// Port of IRremoteESP8266 `IRDaikinESP` (DAIKIN, 280 bits / 35 bytes).
class Daikin280State {
  static const length = 35;
  static const minTemp = 10;
  static const maxTemp = 32;
  static const unusedTime = 0x600;
  static const freq = 38000;
  static const timing = BitTiming(3650, 1623, 428, 1280, 428, 428 + 29000);

  final raw = Uint8List(length);

  Daikin280State() {
    reset();
  }

  void reset() {
    raw.fillRange(0, length, 0);
    raw
      ..put(0, 0x11)
      ..put(1, 0xDA)
      ..put(2, 0x27)
      ..put(4, 0xC5)
      ..put(8, 0x11)
      ..put(9, 0xDA)
      ..put(10, 0x27)
      ..put(12, 0x42)
      ..put(16, 0x11)
      ..put(17, 0xDA)
      ..put(18, 0x27)
      ..put(21, 0x49)
      ..put(22, 0x1E)
      ..put(24, 0xB0)
      ..put(27, 0x06)
      ..put(28, 0x60)
      ..put(31, 0xC0);
    checksum();
  }

  void setPower(bool on) => raw.setBits(21, 0, 1, on ? 1 : 0);

  /// One of the 3-bit Daikin mode codes.
  void setMode(int code) => raw.setBits(21, 4, 3, code);

  void setTemp(int c) => raw.put(22, clampInt(c, minTemp, maxTemp) * 2);

  /// 1–5, or 0xA (auto) / 0xB (quiet).
  void setFan(int fan) => raw.setBits(24, 4, 4, daikinFanCode(fan));

  void setSwingVertical(bool on) => raw.setBits(24, 0, 4, on ? 0xF : 0);
  void setSwingHorizontal(bool on) => raw.setBits(25, 0, 4, on ? 0xF : 0);

  void setCurrentTime(int minsSinceMidnight) =>
      raw.setBits(13, 0, 11, minsSinceMidnight > 24 * 60 ? 0 : minsSinceMidnight);

  void setCurrentDay(int day) => raw.setBits(14, 3, 3, day);

  void enableOnTimer(int start) {
    raw.setBits(21, 1, 1, 1);
    raw.setBits(26, 0, 12, start);
  }

  void disableOnTimer() {
    raw.setBits(21, 1, 1, 0);
    raw.setBits(26, 0, 12, unusedTime);
  }

  void enableOffTimer(int end) {
    raw.setBits(21, 2, 1, 1);
    raw.setBits(27, 4, 12, end);
  }

  void disableOffTimer() {
    raw.setBits(21, 2, 1, 0);
    raw.setBits(27, 4, 12, unusedTime);
  }

  void checksum() {
    raw.put(7, sumBytes(raw, 0, 7));
    raw.put(15, sumBytes(raw, 8, 7));
    raw.put(34, sumBytes(raw, 16, length - 16 - 1));
  }

  Uint8List finish() {
    checksum();
    return Uint8List.fromList(raw);
  }

  static IrFrame send(Uint8List data) => IrFrame(
        freq,
        (PulseBuilder()
              ..zeroBits(timing, 5, timing.gap)
              ..section(timing, data, from: 0, length: 8)
              ..section(timing, data, from: 8, length: 8)
              ..section(timing, data, from: 16, length: length - 16))
            .build(),
      );
}

class Daikin280 extends DaikinProtocol {
  const Daikin280();

  @override
  String get id => 'DAIKIN';
  @override
  String get displayName => 'Daikin (280-bit)';
  @override
  String get remotes => 'ARC433**, ARC470A1, ARC466A12/A33, ARC443A5 – most wall splits';
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
    final ac = Daikin280State()
      ..setPower(state.power)
      ..setMode(state.mode.daikinCode);
    switch (state.mode) {
      // Real ARC remotes send 0xC0 in Dry and 25°C in Fan (see ir_Daikin.h).
      case Mode.dry:
        ac.raw.put(22, 0xC0);
      case Mode.fan:
        ac.setTemp(25);
      default:
        ac.setTemp(state.tempC);
    }
    ac
      ..setFan(state.fan.daikinCode)
      ..setSwingVertical(state.swingV)
      ..setSwingHorizontal(state.swingH);
    if (now != null) {
      ac
        ..setCurrentTime(minutesOfDay(now))
        ..setCurrentDay(daikinDay(now));
    }
    final on = state.onTimerAt, off = state.offTimerAt;
    on != null ? ac.enableOnTimer(minutesOfDay(on)) : ac.disableOnTimer();
    off != null ? ac.enableOffTimer(minutesOfDay(off)) : ac.disableOffTimer();
    return Daikin280State.send(ac.finish());
  }
}
