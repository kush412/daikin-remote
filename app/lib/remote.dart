import 'protocol/protocols.dart';

enum TimerSlot {
  on,
  off;

  bool get power => this == TimerSlot.on;
}

/// How commands reach the AC.
enum TransportKind {
  /// The phone's built-in IR blaster (Android only).
  phone,

  /// The ESP32/ESP8266 Wi-Fi IR bridge (any platform).
  bridge,
}

const defaultBridgeHost = 'daikin-ir.local';

/// Everything the app persists: the remote state plus settings.
class Stored {
  const Stored({
    this.state = const AcState(),
    this.protocolId,
    this.transport,
    this.externalTimer = false,
    this.bridgeHost = defaultBridgeHost,
  });

  final AcState state;
  final String? protocolId;

  /// null until the user picks one; see [RemoteController.transportKind].
  final TransportKind? transport;

  /// Run timers on the phone/bridge instead of in the AC (forced for protocols without IR timers).
  final bool externalTimer;
  final String bridgeHost;

  DaikinProtocol get protocol => Protocols.byId(protocolId);

  /// Timers run by the phone or bridge rather than encoded into the IR frame. Toggle-power
  /// protocols always use the AC's own timer: an external timer can't know which way a toggle
  /// would go.
  bool get usesExternalTimer {
    final p = protocol;
    return !p.nativeTimer || (externalTimer && !p.powerIsToggle);
  }

  Stored copyWith({
    AcState? state,
    String? protocolId,
    TransportKind? transport,
    bool? externalTimer,
    String? bridgeHost,
  }) =>
      Stored(
        state: state ?? this.state,
        protocolId: protocolId ?? this.protocolId,
        transport: transport ?? this.transport,
        externalTimer: externalTimer ?? this.externalTimer,
        bridgeHost: bridgeHost ?? this.bridgeHost,
      );

  /// The frame to send for the current state. External timers must not also be programmed into
  /// the AC.
  IrFrame frame(RemoteKey key, DateTime now) =>
      protocol.encode(usesExternalTimer ? state.withoutTimers() : state, key, now);

  /// The frame an external timer sends when it fires: the current settings with power set.
  IrFrame timerFrame(TimerSlot slot, DateTime now) =>
      protocol.encode(state.withoutTimers().copyWith(power: slot.power), RemoteKey.power, now);

  Map<String, Object?> toJson() => {
        'state': state.toJson(),
        'protocolId': protocolId,
        'transport': transport?.name,
        'externalTimer': externalTimer,
        'bridgeHost': bridgeHost,
      };

  factory Stored.fromJson(Map<String, Object?> j) => Stored(
        state: j['state'] is Map ? AcState.fromJson((j['state'] as Map).cast<String, Object?>()) : const AcState(),
        protocolId: j['protocolId'] as String?,
        transport: TransportKind.values.asNameMap()[j['transport']],
        externalTimer: j['externalTimer'] as bool? ?? false,
        bridgeHost: j['bridgeHost'] as String? ?? defaultBridgeHost,
      );
}

extension AcStateLogic on AcState {
  /// Brings timers up to date at [now]: once a timer is due, the AC (or phone/bridge) has
  /// switched power, so the remote state follows and the timer is cleared, like a real
  /// remote's display.
  AcState settled(DateTime now) {
    var s = this;
    final due = <(DateTime, bool)>[
      if (onTimerAt != null) (onTimerAt!, true),
      if (offTimerAt != null) (offTimerAt!, false),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (at, power) in due) {
      if (at.isAfter(now)) continue;
      s = power ? s.copyWith(power: true, onTimerAt: null) : s.copyWith(power: false, offTimerAt: null);
    }
    return s;
  }

  /// Clamp to what [p] supports.
  AcState fittedTo(DaikinProtocol p) {
    final m = p.modes.contains(mode) ? mode : p.modes.first;
    var f = fan;
    if (!p.fans.contains(fan)) {
      // Closest supported level; auto/quiet fall back to the first option.
      f = fan.isLevel
          ? p.fans.reduce((a, b) => (a.index - fan.index).abs() <= (b.index - fan.index).abs() ? a : b)
          : p.fans.first;
    }
    return copyWith(
      mode: m,
      tempC: p.tempRange(m).clamp(tempC),
      fan: f,
      swingV: swingV && p.supportsSwingV,
      swingH: swingH && p.supportsSwingH,
    );
  }

  DateTime? timerAt(TimerSlot slot) => slot == TimerSlot.on ? onTimerAt : offTimerAt;
}
