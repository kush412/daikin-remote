// Expected values are copied from IRremoteESP8266 `test/ir_Daikin_test.cpp` (the same vectors as
// the original Android and iOS ports), so these check that the Dart port produces bit-identical
// frames.

import 'dart:io';
import 'dart:typed_data';

import 'package:daikin_remote/protocol/bits.dart';
import 'package:daikin_remote/protocol/daikin128.dart';
import 'package:daikin_remote/protocol/daikin2.dart';
import 'package:daikin_remote/protocol/daikin280.dart';
import 'package:daikin_remote/protocol/daikin312.dart';
import 'package:daikin_remote/protocol/daikin_simple.dart';
import 'package:daikin_remote/protocol/protocols.dart';
import 'package:daikin_remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

void expectBytes(Uint8List actual, Uint8List expected) => expect(actual.hex, expected.hex);

/// Mark/space values from an IRremoteESP8266 `outputStr()` dump ("m428s428…").
List<int> parseOutputStr(String s) =>
    RegExp(r'[ms](\d+)').allMatches(s).map((m) => int.parse(m.group(1)!)).toList();

void main() {
  group('golden vectors', () {
    test('Daikin280 message construction matches the full pulse train', () {
      final golden = File('test/daikin280_message_construction.txt').readAsStringSync().trim();
      const state = AcState(power: true, mode: Mode.cool, tempC: 27, fan: Fan.l1, swingV: false, swingH: true);
      final frame = const Daikin280().encode(state, RemoteKey.power, null);
      expect(frame.frequencyHz, 38000);
      expect(frame.pattern, parseOutputStr(golden));
    });

    test('Daikin2 known construction', () {
      final expected = bytesOf([
        0x11, 0xDA, 0x27, 0x00, 0x01, 0x7A, 0xC3, 0x70, 0x28, 0x0C, //
        0x80, 0x04, 0xB0, 0x16, 0x24, 0x00, 0x00, 0xBE, 0xD5, 0xF5,
        0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x26, 0x00, 0xA0, 0x00,
        0x00, 0x06, 0x60, 0x00, 0x00, 0xC1, 0x80, 0x60, 0xE7,
      ]);
      final ac = Daikin2State()
        ..setPower(false)
        ..setMode(0)
        ..setTemp(19)
        ..setFan(0xA)
        ..setSwingVertical(5)
        ..setSwingHorizontal(Daikin2State.swingHAuto)
        ..setCurrentTime(14 * 60 + 50)
        ..disableOnTimer()
        ..disableOffTimer()
        ..setBeep(1)
        ..setLight(3)
        ..setMold(true)
        ..setClean(true);
      expectBytes(ac.finish(), expected);
    });

    test('Daikin216 reconstruct known state', () {
      final expected = bytesOf([
        0x11, 0xDA, 0x27, 0xF0, 0x00, 0x00, 0x00, 0x02, //
        0x11, 0xDA, 0x27, 0x00, 0x00, 0x00, 0x26, 0x00, 0xA0, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x98,
      ]);
      final ac = Daikin216State()
        ..setPower(false)
        ..setMode(0)
        ..setTemp(19)
        ..setFan(0xA)
        ..setSwingHorizontal(false)
        ..setSwingVertical(false);
      expectBytes(ac.finish(), expected);
    });

    test('Daikin160 default state', () {
      final expected = bytesOf([
        0x11, 0xDA, 0x27, 0xF0, 0x0D, 0x00, 0x0F, //
        0x11, 0xDA, 0x27, 0x00, 0xD3, 0x30, 0x11, 0x00, 0x00, 0x1E, 0x0A, 0x08, 0x56,
      ]);
      expectBytes(Daikin160State().finish(), expected);
      final ac = Daikin160State()
        ..setPower(false)
        ..setMode(Mode.cool.daikinCode)
        ..setTemp(25)
        ..setFan(Fan.auto.daikinCode)
        ..setSwingVertical(Daikin160State.swingLowest);
      expectBytes(ac.finish(), expected);
    });

    test('Daikin176 reconstruct known states', () {
      final onCool25 = bytesOf([
        0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E, //
        0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x00, 0x21, 0x00, 0x00, 0x20, 0x35, 0x00, 0x20, 0x23,
      ]);
      final onFan17 = bytesOf([
        0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E, //
        0x11, 0xDA, 0x17, 0x18, 0x00, 0x63, 0x04, 0x01, 0x00, 0x00, 0x10, 0x35, 0x00, 0x20, 0xE7,
      ]);
      final onDry17 = bytesOf([
        0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E, //
        0x11, 0xDA, 0x17, 0x18, 0x00, 0x23, 0x04, 0x71, 0x00, 0x00, 0x10, 0x35, 0x00, 0x20, 0x17,
      ]);
      final onCool25v2 = bytesOf([
        0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E, //
        0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x04, 0x21, 0x00, 0x00, 0x20, 0x35, 0x00, 0x20, 0x27,
      ]);
      final ac = Daikin176State()
        ..setMode(Daikin176State.cool)
        ..setPower(true)
        ..setTemp(25)
        ..setFan(Daikin176State.fanMax)
        ..setSwingHorizontal(1); // "true" in the C++ test -> invalid -> Auto
      expectBytes(ac.finish(), onCool25);
      ac.setMode(Daikin176State.fan);
      expectBytes(ac.finish(), onFan17);
      ac.setMode(Daikin176State.dry);
      expectBytes(ac.finish(), onDry17);
      ac.setMode(Daikin176State.cool);
      expectBytes(ac.finish(), onCool25v2);

      // Adapter: Cool 25 via the Mode button == the v2 frame.
      const state = AcState(power: true, mode: Mode.cool, tempC: 25, fan: Fan.l5, swingH: true);
      expect(const Daikin176().encode(state, RemoteKey.mode, null).pattern, Daikin176State.send(onCool25v2).pattern);
    });

    test('Daikin128 reconstruct known state', () {
      final expected = bytesOf([
        0x16, 0x12, 0x20, 0x19, 0x47, 0x22, 0x26, 0xAD, //
        0xA1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B,
      ]);
      final ac = Daikin128State()
        ..setPowerToggle(true)
        ..setMode(Daikin128Codes.cool)
        ..setTemp(26)
        ..setFan(Daikin128Codes.fanAuto)
        ..setSwingVertical(true)
        ..setClock(19 * 60 + 20)
        ..setOnTimerEnabled(false)
        ..setOnTimer(7 * 60 + 30)
        ..setOffTimerEnabled(false)
        ..setOffTimer(22 * 60);
      expectBytes(ac.finish(), expected);
    });

    test('Daikin152 build known state', () {
      final expected = bytesOf([
        0x11, 0xDA, 0x27, 0x00, 0x00, 0x31, 0x28, 0x00, 0x3F, 0x00, //
        0x00, 0x00, 0x00, 0x00, 0x00, 0xC5, 0x00, 0x00, 0x6F,
      ]);
      const state = AcState(power: true, mode: Mode.cool, tempC: 20, fan: Fan.l1, swingV: true);
      expect(const Daikin152().encode(state, RemoteKey.power, null).pattern, Daikin152State.send(expected).pattern);
    });

    test('Daikin152 timers are minutes from now', () {
      final now = DateTime(2026, 10, 4, 22, 0);
      final off = AcState(
          power: true, mode: Mode.cool, tempC: 26, swingV: true, offTimerAt: now.add(const Duration(minutes: 60)));
      final ac = Daikin152State()
        ..setPower(true)
        ..setTemp(26)
        ..setMode(Mode.cool.daikinCode)
        ..setTemp(26)
        ..setFan(0xA)
        ..setSwingV(true)
        ..enableOffTimer(60);
      final raw = ac.finish();
      expect(raw.getBits(5, 2, 1), 1); // OffTimer flag
      expect(raw.getBits(5, 1, 1), 0);
      expect(raw.getBits(11, 4, 12), 60);
      expect(raw[18], sumBytes(raw, 0, 18));
      expect(const Daikin152().encode(off, RemoteKey.timer, now).pattern, Daikin152State.send(raw).pattern);

      // Same layout as the real "night sleep" capture: 0x3C in byte 10.
      final on = (Daikin152State()..enableOnTimer(60)).finish();
      expect(on[10], 0x3C);
      expect(on.getBits(5, 1, 1), 1);
    });

    test('Daikin64 known good state', () {
      final now = DateTime(2026, 1, 1, 7, 20);
      final ac = Daikin64State()
        ..setPowerToggle(true)
        ..setMode(Daikin128Codes.cool)
        ..setTemp(16)
        ..setFan(Daikin128Codes.fanMed)
        ..setSwingVertical(false)
        ..setClock(minutesOfDay(now))
        ..setOnTimerEnabled(false)
        ..setOffTimerEnabled(false);
      ac.finish();
      expect(ac.hex64, '7C16161607204216');
      const state = AcState(power: true, mode: Mode.cool, tempC: 16, fan: Fan.l3);
      expect(const Daikin64().encode(state, RemoteKey.power, now).pattern,
          Daikin64State.send(Daikin64State().finish()).pattern);
    });

    test('Daikin312 section 2 matches a real capture', () {
      // Section 2 of TestDecodeDaikin312.SyntheticExample: On, Cool, 21C, fan auto, swings off.
      final expected = bytesOf([
        0x11, 0xDA, 0x27, 0x00, 0x00, 0x39, 0x2A, 0x00, 0xA0, 0x00, //
        0x00, 0x06, 0x60, 0x00, 0x00, 0xC5, 0x00, 0x08, 0x48,
      ]);
      final ac = Daikin312State()
        ..setPower(true)
        ..setMode(Mode.cool.daikinCode)
        ..setTemp(21)
        ..setFan(0xA)
        ..setSwingVertical(Daikin312State.swingOff)
        ..setSwingHorizontal(Daikin312State.swingOff);
      expectBytes(Uint8List.sublistView(ac.finish(), 20, 39), expected);
    });

    test('timers encode minutes since midnight', () {
      final now = DateTime(2026, 10, 3, 21, 45); // Saturday
      final at = now.add(const Duration(hours: 2));
      final ac = Daikin280State()
        ..setCurrentTime(minutesOfDay(now))
        ..setCurrentDay(daikinDay(now))
        ..enableOffTimer(minutesOfDay(at));
      final raw = ac.finish();
      expect(raw.getBits(21, 2, 1), 1);
      expect(raw.getBits(27, 4, 12), 23 * 60 + 45);
      expect(raw.getBits(13, 0, 11), 21 * 60 + 45);
      expect(raw.getBits(14, 3, 3), 7);
    });
  });

  test('every protocol produces a valid pattern for every button', () {
    final now = DateTime(2026, 10, 3, 21, 45);
    final state = AcState(
        power: true, tempC: 24, fan: Fan.l3, swingV: true, swingH: true, offTimerAt: now.add(const Duration(hours: 1)));
    for (final p in Protocols.all) {
      for (final key in RemoteKey.values) {
        final f = p.encode(state, key, now);
        expect(f.pattern, isNotEmpty, reason: p.id);
        expect(f.pattern.every((v) => v > 0), isTrue, reason: '${p.id}: non-positive pulse');
        // Android rejects patterns over 2 s; the bridge buffer holds 1024 pulses.
        expect(f.pattern.length, lessThanOrEqualTo(1024), reason: p.id);
        final body = f.pattern.length.isEven ? f.pattern.sublist(0, f.pattern.length - 1) : f.pattern;
        expect(body.fold<int>(0, (a, b) => a + b), lessThan(2000000), reason: p.id);
      }
    }
  });

  group('remote logic', () {
    test('due timers switch power and clear', () {
      final now = DateTime.now();
      final s = AcState(
        power: true,
        offTimerAt: now.subtract(const Duration(seconds: 10)),
        onTimerAt: now.add(const Duration(minutes: 10)),
      ).settled(now);
      expect(s.power, isFalse);
      expect(s.offTimerAt, isNull);
      expect(s.onTimerAt, isNotNull);
    });

    test('external timers are stripped from the wire frame', () {
      final now = DateTime.now();
      final state = AcState(power: true, offTimerAt: now.add(const Duration(hours: 1)));
      final native = Stored(protocolId: 'DAIKIN152', state: state);
      final external = native.copyWith(externalTimer: true);
      expect(native.frame(RemoteKey.timer, now) == external.frame(RemoteKey.timer, now), isFalse);
      expect(external.frame(RemoteKey.timer, now),
          const Daikin152().encode(state.withoutTimers(), RemoteKey.timer, now));
    });

    test('timer frame sets power and carries no timers', () {
      final now = DateTime.now();
      final st = Stored(protocolId: 'DAIKIN216', state: AcState(power: false, offTimerAt: now.add(const Duration(hours: 1))));
      expect(st.timerFrame(TimerSlot.on, now),
          const Daikin216().encode(const AcState(power: true), RemoteKey.power, now));
    });

    test('toggle protocols never use external timers', () {
      expect(const Stored(protocolId: 'DAIKIN64', externalTimer: true).usesExternalTimer, isFalse);
      expect(const Stored(protocolId: 'DAIKIN216').usesExternalTimer, isTrue);
      expect(const Stored(protocolId: 'DAIKIN152').usesExternalTimer, isFalse);
    });

    test('state is clamped to the protocol', () {
      final s = const AcState(mode: Mode.auto, tempC: 40, fan: Fan.l2, swingH: true).fittedTo(const Daikin64());
      expect(s.mode, Mode.cool);
      expect(s.tempC, 30);
      expect(s.fan, Fan.l1);
      expect(s.swingH, isFalse);
    });

    test('stored state round-trips through JSON and tolerates old saves', () {
      final st = Stored(
        protocolId: 'DAIKIN152',
        transport: TransportKind.bridge,
        bridgeHost: '192.168.1.9',
        state: AcState(power: true, fan: Fan.quiet, onTimerAt: DateTime.fromMillisecondsSinceEpoch(1800000000000)),
      );
      final back = Stored.fromJson(st.toJson());
      expect(back.state, st.state);
      expect(back.transport, TransportKind.bridge);
      expect(back.bridgeHost, '192.168.1.9');
      final old = Stored.fromJson({'protocolId': 'DAIKIN152'});
      expect(old.bridgeHost, defaultBridgeHost);
      expect(old.transport, isNull);
    });
  });
}
