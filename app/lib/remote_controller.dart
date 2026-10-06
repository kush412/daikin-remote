import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'protocol/protocols.dart';
import 'remote.dart';
import 'transport/transport.dart';

enum Screen { remote, picker }

/// Single source of truth for the remote. All IR traffic goes through one serial queue, so
/// quick taps reach the AC in order.
class RemoteController extends ChangeNotifier {
  RemoteController._(this._prefs, this._stored, this.phoneIrAvailable)
      : screen = _stored.protocolId == null ? Screen.picker : Screen.remote;

  static const _key = 'stored';

  static Future<RemoteController> load() async {
    final prefs = await SharedPreferences.getInstance();
    var stored = const Stored();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        stored = Stored.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
    return RemoteController._(prefs, stored, await PhoneIrTransport.available());
  }

  final SharedPreferences _prefs;
  Stored _stored;

  /// True on Android phones with an IR blaster.
  final bool phoneIrAvailable;

  Screen screen;

  /// Increments on every transmission so the UI can flash a "sent" indicator.
  int sendCount = 0;
  String? error;
  String? notice;

  /// null until the first bridge request finishes; always true for the phone blaster.
  bool? online;

  /// Ticks periodically so timer countdowns re-render.
  DateTime now = DateTime.now();

  Future<void> _queue = Future.value();

  Stored get stored => _stored;
  AcState get state => _stored.state;
  DaikinProtocol get protocol => _stored.protocol;

  TransportKind get transportKind =>
      _stored.transport ?? (phoneIrAvailable ? TransportKind.phone : TransportKind.bridge);

  IrTransport get _transport => transportKind == TransportKind.phone && phoneIrAvailable
      ? PhoneIrTransport()
      : BridgeTransport(_stored.bridgeHost);

  String get externalTimerName => transportKind == TransportKind.phone ? 'phone' : 'bridge';

  // MARK: Buttons

  void power() => _press(RemoteKey.power, (s) => s.copyWith(power: !s.power));
  void tempUp() => _press(RemoteKey.temp, (s) => s.copyWith(tempC: s.tempC + 1));
  void tempDown() => _press(RemoteKey.temp, (s) => s.copyWith(tempC: s.tempC - 1));
  void setMode(Mode m) => _press(RemoteKey.mode, (s) => s.copyWith(mode: m));
  void setFan(Fan f) => _press(RemoteKey.fan, (s) => s.copyWith(fan: f));
  void swingV() => _press(RemoteKey.swing, (s) => s.copyWith(swingV: !s.swingV));
  void swingH() => _press(RemoteKey.swing, (s) => s.copyWith(swingH: !s.swingH));

  /// [minutes] from now, or null to cancel.
  void setTimer(TimerSlot slot, int? minutes) {
    final at = minutes == null ? null : DateTime.now().add(Duration(minutes: minutes));
    _press(RemoteKey.timer, (s) => slot == TimerSlot.on ? s.copyWith(onTimerAt: at) : s.copyWith(offTimerAt: at));
  }

  void setExternalTimer(bool enabled) =>
      _press(RemoteKey.timer, (s) => s, settings: (st) => st.copyWith(externalTimer: enabled));

  void setTransport(TransportKind kind, String bridgeHost) {
    // Timers held by the old transport would be orphaned; cancel them there first.
    if (_stored.usesExternalTimer) _cancelExternalTimers(_transport);
    _stored = _stored.copyWith(transport: kind, bridgeHost: bridgeHost.trim());
    online = null;
    _save();
    _syncExternalTimers();
    refresh();
  }

  /// Sends a Cool 24°C power on/off test frame with [p] without changing the saved state.
  void test(DaikinProtocol p, {required bool power}) =>
      _transmit(p.encode(AcState(power: power, mode: Mode.cool, tempC: 24), RemoteKey.power, DateTime.now()));

  void choose(DaikinProtocol p) {
    screen = Screen.remote;
    _stored = _stored.copyWith(protocolId: p.id, state: _stored.state.fittedTo(p));
    _save();
    _syncExternalTimers();
  }

  void showPicker() {
    screen = Screen.picker;
    notifyListeners();
  }

  void closePicker() {
    screen = Screen.remote;
    notifyListeners();
  }

  void dismissError() {
    error = null;
    notifyListeners();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  // MARK: Timers and status

  /// On app resume: check the transport and reconcile external timers *before* applying due
  /// ones, so a timer that never fired isn't shown as done.
  void refresh() {
    final s = _stored;
    final transport = _transport;
    _enqueue(() async {
      try {
        final status = await transport.status();
        online = true;
        if (s.usesExternalTimer) _reconcile(status);
      } on TransportException {
        online = false;
      }
      tick();
    });
  }

  /// Re-renders countdowns and applies timers that are now due.
  void tick() {
    now = DateTime.now();
    final settled = _stored.state.settled(now);
    if (settled != _stored.state) {
      _stored = _stored.copyWith(state: settled);
      _save();
    } else {
      notifyListeners();
    }
  }

  void _reconcile(TimerStatus status) {
    final now = DateTime.now();
    var st = _stored.state;
    final missed = <String>[];
    final lost = <String>[];
    for (final slot in TimerSlot.values) {
      final at = st.timerAt(slot);
      if (at == null) continue;
      final clear = slot == TimerSlot.on ? st.copyWith(onTimerAt: null) : st.copyWith(offTimerAt: null);
      if (status.missed.contains(slot)) {
        st = clear; // Never fired: power stays as it was.
        missed.add(slot.name.toUpperCase());
      } else if (at.isAfter(now.add(const Duration(seconds: 5))) && status.remaining[slot] == null) {
        st = clear;
        lost.add(slot.name.toUpperCase());
      }
    }
    if (st == _stored.state) return;
    _stored = _stored.copyWith(state: st);
    _save();
    if (missed.isNotEmpty) {
      notice = 'The ${missed.join(' and ')} timer didn\'t run: Android blocked the app in the background. '
          'In App info, allow Autostart and set Battery saver to “No restrictions”.';
    } else if (lost.isNotEmpty) {
      notice = 'The $externalTimerName lost the ${lost.join(' and ')} timer (it restarted). Set it again.';
    }
  }

  // MARK: Sending

  /// Applies [change] to the latest state, saves it and transmits it.
  void _press(RemoteKey key, AcState Function(AcState) change, {Stored Function(Stored)? settings}) {
    final now = DateTime.now();
    var s = settings?.call(_stored) ?? _stored;
    s = s.copyWith(state: change(s.state.settled(now)).fittedTo(s.protocol));
    _stored = s;
    _save();
    _transmit(s.frame(key, now));
    // External timers carry a copy of the settings, so refresh them after any change.
    if (key == RemoteKey.timer || (s.usesExternalTimer && (s.state.onTimerAt != null || s.state.offTimerAt != null))) {
      _syncExternalTimers();
    }
  }

  void _transmit(IrFrame frame) {
    sendCount++;
    notifyListeners();
    final transport = _transport;
    _enqueue(() async {
      try {
        await transport.send(frame);
        online = true;
        error = null;
      } on TransportException catch (e) {
        online = false;
        error = e.message;
      }
      notifyListeners();
    });
  }

  void _syncExternalTimers() {
    final s = _stored;
    final transport = _transport;
    final now = DateTime.now();
    _enqueue(() async {
      try {
        for (final slot in TimerSlot.values) {
          final at = s.usesExternalTimer ? s.state.timerAt(slot) : null;
          if (at != null) {
            final seconds = (at.difference(now).inMilliseconds / 1000).ceil();
            await transport.setTimer(slot, seconds < 1 ? 1 : seconds, s.timerFrame(slot, now));
          } else {
            await transport.cancelTimer(slot);
          }
        }
      } on TransportException catch (e) {
        error = 'Couldn\'t update the $externalTimerName timer: ${e.message}';
        notifyListeners();
      }
    });
  }

  void _cancelExternalTimers(IrTransport transport) {
    _enqueue(() async {
      for (final slot in TimerSlot.values) {
        try {
          await transport.cancelTimer(slot);
        } on TransportException {
          // Unreachable old transport: nothing more we can do.
        }
      }
    });
  }

  void _enqueue(Future<void> Function() op) {
    _queue = _queue.then((_) => op()).catchError((Object e) {
      debugPrint('IR queue: $e');
    });
  }

  void _save() {
    _prefs.setString(_key, jsonEncode(_stored.toJson()));
    notifyListeners();
  }
}
