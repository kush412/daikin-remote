// DAIKIN128 and DAIKIN64: toggle-power protocols with a BCD clock.

import 'dart:typed_data';

import 'ac_state.dart';
import 'bits.dart';
import 'daikin_protocol.dart';
import 'pulse_builder.dart';

/// Mode/fan codes shared by DAIKIN128 and DAIKIN64.
abstract final class Daikin128Codes {
  static const dry = 0x1;
  static const cool = 0x2;
  static const fan = 0x4;
  static const heat = 0x8;
  static const auto = 0xA;

  static const fanAuto = 0x1;
  static const fanHigh = 0x2;
  static const fanMed = 0x4;
  static const fanLow = 0x8;
  static const fanPowerful = 0x3;
  static const fanQuiet = 0x9;

  static int fanCode(Fan f) => switch (f) {
        Fan.auto => fanAuto,
        Fan.quiet => fanQuiet,
        Fan.l1 || Fan.l2 => fanLow,
        Fan.l3 => fanMed,
        Fan.l4 || Fan.l5 => fanHigh,
      };

  static int modeCode(Mode m) => switch (m) {
        Mode.auto => auto,
        Mode.cool => cool,
        Mode.dry => dry,
        Mode.heat => heat,
        Mode.fan => fan,
      };

  // Leader 2× (9800/9800), then header 4600/2500.
  static const leader = 9800;
  static const timing = BitTiming(4600, 2500, 350, 954, 382, 20300);
}

void _setTime(Uint8List raw, int byte, int minsSinceMidnight) {
  final mins = minsSinceMidnight >= 24 * 60 ? 0 : minsSinceMidnight;
  raw.setBits(byte, 6, 1, mins % 60 >= 30 ? 1 : 0);
  raw.setBits(byte, 0, 6, toBcd(mins ~/ 60));
}

/// Port of IRremoteESP8266 `IRDaikin128` (DAIKIN128, 128 bits / 16 bytes).
class Daikin128State {
  static const minTemp = 16;
  static const maxTemp = 30;

  final raw = Uint8List(16)
    ..put(0, 0x16)
    ..put(7, 0x04)
    ..put(8, 0xA1);

  int get _mode => raw.getBits(1, 0, 4);

  /// The power bit means "toggle power".
  void setPowerToggle(bool toggle) => raw.setBits(7, 3, 1, toggle ? 1 : 0);

  void setMode(int code) {
    const valid = [Daikin128Codes.auto, Daikin128Codes.cool, Daikin128Codes.heat, Daikin128Codes.fan, Daikin128Codes.dry];
    raw.setBits(1, 0, 4, valid.contains(code) ? code : Daikin128Codes.auto);
    setFan(raw.getBits(1, 4, 4)); // Quiet/Powerful depend on mode.
  }

  void setTemp(int c) => raw.put(6, toBcd(clampInt(c, minTemp, maxTemp)));

  void setFan(int speed) {
    var s = speed;
    switch (speed) {
      case Daikin128Codes.fanQuiet || Daikin128Codes.fanPowerful:
        if (_mode == Daikin128Codes.auto) s = Daikin128Codes.fanAuto;
      case Daikin128Codes.fanAuto || Daikin128Codes.fanHigh || Daikin128Codes.fanMed || Daikin128Codes.fanLow:
        break;
      default:
        s = Daikin128Codes.fanAuto;
    }
    raw.setBits(1, 4, 4, s);
  }

  void setSwingVertical(bool on) => raw.setBits(7, 0, 1, on ? 1 : 0);

  void setClock(int mins) {
    final m = mins >= 24 * 60 ? 0 : mins;
    raw.put(3, toBcd(m ~/ 60));
    raw.put(2, toBcd(m % 60));
  }

  void setOnTimerEnabled(bool on) => raw.setBits(4, 7, 1, on ? 1 : 0);
  void setOnTimer(int mins) => _setTime(raw, 4, mins);
  void setOffTimerEnabled(bool on) => raw.setBits(5, 7, 1, on ? 1 : 0);
  void setOffTimer(int mins) => _setTime(raw, 5, mins);

  Uint8List finish() {
    raw.setBits(7, 4, 4, sumNibbles(raw, 0, 7, raw[7] & 0x0F) & 0x0F);
    raw.put(15, sumNibbles(raw, 8, 7));
    return Uint8List.fromList(raw);
  }

  static IrFrame send(Uint8List data) {
    const t = Daikin128Codes.timing;
    return IrFrame(
      38000,
      (PulseBuilder()
            ..mark(Daikin128Codes.leader)
            ..space(Daikin128Codes.leader)
            ..mark(Daikin128Codes.leader)
            ..space(Daikin128Codes.leader)
            ..section(t, data, from: 0, length: 8)
            ..section(t, data, from: 8, length: 8, hdrMark: 0, hdrSpace: 0, footerMark: t.hdrMark))
          .build(),
    );
  }
}

class Daikin128 extends DaikinProtocol {
  const Daikin128();

  @override
  String get id => 'DAIKIN128';
  @override
  String get displayName => 'Daikin128';
  @override
  String get remotes => 'BRC52B63, 17 Series FTXB**AXVJU';
  @override
  List<Mode> get modes => Mode.values;
  @override
  List<Fan> get fans => const [Fan.auto, Fan.quiet, Fan.l1, Fan.l3, Fan.l5];
  @override
  bool get supportsSwingV => true;
  @override
  bool get supportsSwingH => false;
  @override
  bool get nativeTimer => true;
  @override
  bool get powerIsToggle => true;

  @override
  TempRange tempRange(Mode mode) => const TempRange(Daikin128State.minTemp, Daikin128State.maxTemp);

  @override
  IrFrame encode(AcState state, RemoteKey key, DateTime? now) {
    final ac = Daikin128State()
      ..setPowerToggle(key == RemoteKey.power)
      ..setMode(Daikin128Codes.modeCode(state.mode))
      ..setTemp(state.tempC)
      ..setFan(Daikin128Codes.fanCode(state.fan))
      ..setSwingVertical(state.swingV);
    if (now != null) ac.setClock(minutesOfDay(now));
    final on = state.onTimerAt, off = state.offTimerAt;
    ac.setOnTimerEnabled(on != null);
    if (on != null) ac.setOnTimer(minutesOfDay(on));
    ac.setOffTimerEnabled(off != null);
    if (off != null) ac.setOffTimer(minutesOfDay(off));
    return Daikin128State.send(ac.finish());
  }
}

/// Port of IRremoteESP8266 `IRDaikin64` (DAIKIN64, 64 bits). Held as 8 little-endian bytes,
/// which is exactly the LSB-first order the 64-bit value is transmitted in.
class Daikin64State {
  // kDaikin64KnownGoodState = 0x7C16161607204216
  final raw = bytesOf(const [0x16, 0x42, 0x20, 0x07, 0x16, 0x16, 0x16, 0x7C]);

  void setPowerToggle(bool toggle) => raw.setBits(7, 3, 1, toggle ? 1 : 0);

  void setMode(int code) {
    const valid = [Daikin128Codes.fan, Daikin128Codes.dry, Daikin128Codes.cool, Daikin128Codes.heat];
    raw.setBits(1, 0, 4, valid.contains(code) ? code : Daikin128Codes.cool);
  }

  void setTemp(int c) => raw.put(6, toBcd(clampInt(c, Daikin128State.minTemp, Daikin128State.maxTemp)));

  void setFan(int speed) => raw.setBits(1, 4, 4, speed);

  void setSwingVertical(bool on) => raw.setBits(7, 0, 1, on ? 1 : 0);

  void setClock(int mins) {
    final m = mins >= 24 * 60 ? 0 : mins;
    raw.put(2, toBcd(m % 60));
    raw.put(3, toBcd(m ~/ 60));
  }

  void setOnTimerEnabled(bool on) => raw.setBits(4, 7, 1, on ? 1 : 0);
  void setOnTimer(int mins) => _setTime(raw, 4, mins);
  void setOffTimerEnabled(bool on) => raw.setBits(5, 7, 1, on ? 1 : 0);
  void setOffTimer(int mins) => _setTime(raw, 5, mins);

  Uint8List finish() {
    // Sum of the 15 nibbles below the checksum nibble.
    final sum = sumNibbles(raw, 0, 7, raw[7] & 0x0F) & 0x0F;
    raw.setBits(7, 4, 4, sum);
    return Uint8List.fromList(raw);
  }

  /// The raw state as a 64-bit hex string (avoids JS int limits in tests).
  String get hex64 => raw.reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  static IrFrame send(Uint8List data) {
    const t = Daikin128Codes.timing;
    return IrFrame(
      38000,
      (PulseBuilder()
            ..mark(Daikin128Codes.leader)
            ..space(Daikin128Codes.leader)
            ..mark(Daikin128Codes.leader)
            ..space(Daikin128Codes.leader)
            ..section(t, data)
            ..mark(t.hdrMark)
            ..space(100000))
          .build(),
    );
  }
}

class Daikin64 extends DaikinProtocol {
  const Daikin64();

  @override
  String get id => 'DAIKIN64';
  @override
  String get displayName => 'Daikin64';
  @override
  String get remotes => 'DGS01, BRC4C158, FFN-C/FCN-F, FTWX35AXV1';
  @override
  List<Mode> get modes => const [Mode.cool, Mode.dry, Mode.heat, Mode.fan];
  @override
  List<Fan> get fans => const [Fan.auto, Fan.quiet, Fan.l1, Fan.l3, Fan.l5];
  @override
  bool get supportsSwingV => true;
  @override
  bool get supportsSwingH => false;
  @override
  bool get nativeTimer => true;
  @override
  bool get powerIsToggle => true;

  @override
  TempRange tempRange(Mode mode) => const TempRange(Daikin128State.minTemp, Daikin128State.maxTemp);

  @override
  IrFrame encode(AcState state, RemoteKey key, DateTime? now) {
    final ac = Daikin64State()
      ..setPowerToggle(key == RemoteKey.power)
      ..setMode(Daikin128Codes.modeCode(state.mode))
      ..setTemp(state.tempC)
      ..setFan(Daikin128Codes.fanCode(state.fan))
      ..setSwingVertical(state.swingV);
    if (now != null) ac.setClock(minutesOfDay(now));
    final on = state.onTimerAt, off = state.offTimerAt;
    ac.setOnTimerEnabled(on != null);
    if (on != null) ac.setOnTimer(minutesOfDay(on));
    ac.setOffTimerEnabled(off != null);
    if (off != null) ac.setOffTimer(minutesOfDay(off));
    return Daikin64State.send(ac.finish());
  }
}
