enum Mode {
  auto('Auto'),
  cool('Cool'),
  dry('Dry'),
  heat('Heat'),
  fan('Fan');

  const Mode(this.label);
  final String label;
}

/// Fan levels as on Daikin remotes: Auto, Quiet (silent indoor unit) and 1–5 bars.
enum Fan {
  auto('Auto'),
  quiet('Quiet'),
  l1('1'),
  l2('2'),
  l3('3'),
  l4('4'),
  l5('5');

  const Fan(this.label);
  final String label;

  /// l1 -> 1 … l5 -> 5; meaningless for auto/quiet.
  int get level => index - 1;

  bool get isLevel => this != Fan.auto && this != Fan.quiet;
}

/// The button pressed for this frame. Some protocols encode it (power toggle, mode button).
enum RemoteKey { power, mode, temp, fan, swing, timer, test }

const _unset = Object();

/// Complete remote state; every frame encodes all of it, like a real Daikin remote.
class AcState {
  const AcState({
    this.power = false,
    this.mode = Mode.cool,
    this.tempC = 25,
    this.fan = Fan.auto,
    this.swingV = false,
    this.swingH = false,
    this.onTimerAt,
    this.offTimerAt,
  });

  final bool power;
  final Mode mode;
  final int tempC;
  final Fan fan;
  final bool swingV;
  final bool swingH;

  /// When the AC should switch on, or null.
  final DateTime? onTimerAt;

  /// When the AC should switch off, or null.
  final DateTime? offTimerAt;

  AcState copyWith({
    bool? power,
    Mode? mode,
    int? tempC,
    Fan? fan,
    bool? swingV,
    bool? swingH,
    Object? onTimerAt = _unset,
    Object? offTimerAt = _unset,
  }) =>
      AcState(
        power: power ?? this.power,
        mode: mode ?? this.mode,
        tempC: tempC ?? this.tempC,
        fan: fan ?? this.fan,
        swingV: swingV ?? this.swingV,
        swingH: swingH ?? this.swingH,
        onTimerAt: identical(onTimerAt, _unset) ? this.onTimerAt : onTimerAt as DateTime?,
        offTimerAt: identical(offTimerAt, _unset) ? this.offTimerAt : offTimerAt as DateTime?,
      );

  AcState withoutTimers() => copyWith(onTimerAt: null, offTimerAt: null);

  Map<String, Object?> toJson() => {
        'power': power,
        'mode': mode.name,
        'tempC': tempC,
        'fan': fan.name,
        'swingV': swingV,
        'swingH': swingH,
        'onTimerAt': onTimerAt?.millisecondsSinceEpoch,
        'offTimerAt': offTimerAt?.millisecondsSinceEpoch,
      };

  factory AcState.fromJson(Map<String, Object?> j) {
    DateTime? time(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return AcState(
      power: j['power'] as bool? ?? false,
      mode: Mode.values.asNameMap()[j['mode']] ?? Mode.cool,
      tempC: j['tempC'] as int? ?? 25,
      fan: Fan.values.asNameMap()[j['fan']] ?? Fan.auto,
      swingV: j['swingV'] as bool? ?? false,
      swingH: j['swingH'] as bool? ?? false,
      onTimerAt: time(j['onTimerAt']),
      offTimerAt: time(j['offTimerAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AcState &&
      other.power == power &&
      other.mode == mode &&
      other.tempC == tempC &&
      other.fan == fan &&
      other.swingV == swingV &&
      other.swingH == swingH &&
      other.onTimerAt == onTimerAt &&
      other.offTimerAt == offTimerAt;

  @override
  int get hashCode => Object.hash(power, mode, tempC, fan, swingV, swingH, onTimerAt, offTimerAt);
}
