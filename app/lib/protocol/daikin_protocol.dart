import 'ac_state.dart';
import 'pulse_builder.dart';

class TempRange {
  const TempRange(this.min, this.max);
  final int min;
  final int max;
  int clamp(int v) => v < min ? min : (v > max ? max : v);
}

abstract class DaikinProtocol {
  const DaikinProtocol();

  String get id;
  String get displayName;

  /// Remote / AC models known to use this protocol.
  String get remotes;
  List<Mode> get modes;
  List<Fan> get fans;
  bool get supportsSwingV;
  bool get supportsSwingH;

  /// True if the AC itself runs the on/off timer; otherwise the phone or bridge sends it later.
  bool get nativeTimer;

  /// True if the power bit means "toggle" rather than an absolute on/off.
  bool get powerIsToggle => false;

  TempRange tempRange(Mode mode);

  /// Encode the full [state]. [now] is the local time, used for the clock and timer fields;
  /// null leaves them at their reset values (the golden tests rely on that).
  IrFrame encode(AcState state, RemoteKey key, DateTime? now);
}

const standardRange = TempRange(18, 32);
const heatRange = TempRange(10, 30);
TempRange standardTempRange(Mode mode) => mode == Mode.heat ? heatRange : standardRange;

/// Minutes since local midnight.
int minutesOfDay(DateTime t) {
  final l = t.toLocal();
  return l.hour * 60 + l.minute;
}

/// Whole minutes from [now] until [at], rounded up.
int minutesUntil(DateTime at, DateTime now) => (at.difference(now).inMilliseconds + 59999) ~/ 60000;

/// Daikin day-of-week: SUN=1 … SAT=7.
int daikinDay(DateTime t) => t.toLocal().weekday % 7 + 1;

extension FanCode on Fan {
  /// The value the ported `setFan()` setters take: 1–5, or 0xA (auto) / 0xB (quiet).
  int get daikinCode => switch (this) {
        Fan.auto => 0xA,
        Fan.quiet => 0xB,
        _ => level,
      };
}

extension ModeCode on Mode {
  /// Daikin 3-bit mode codes shared by most protocols.
  int get daikinCode => switch (this) {
        Mode.auto => 0x0,
        Mode.dry => 0x2,
        Mode.cool => 0x3,
        Mode.heat => 0x4,
        Mode.fan => 0x6,
      };
}

/// Shared setFan() of the 280/2/152/160/216/312 families: 1–5 -> 3–7, auto/quiet pass through.
int daikinFanCode(int fan) {
  if (fan == 0xA || fan == 0xB) return fan;
  if (fan < 1 || fan > 5) return 0xA;
  return 2 + fan;
}
