import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../protocol/protocols.dart';
import '../remote.dart';

class TransportException implements Exception {
  TransportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TimerStatus {
  const TimerStatus(this.remaining, [this.missed = const []]);

  /// Seconds until each slot fires, or null if not armed.
  final Map<TimerSlot, int?> remaining;

  /// Slots whose timer never fired (Android blocked the alarm).
  final List<TimerSlot> missed;
}

/// Something that can put IR frames in the air now or later.
abstract class IrTransport {
  Future<void> send(IrFrame frame);
  Future<void> setTimer(TimerSlot slot, int seconds, IrFrame frame);
  Future<void> cancelTimer(TimerSlot slot);
  Future<TimerStatus> status();
}

/// The phone's built-in IR blaster, through the Android side of the app (MainActivity.kt).
class PhoneIrTransport implements IrTransport {
  static const _channel = MethodChannel('vn.cake.daikinremote/ir');

  static Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('hasEmitter') ?? false;
    } on MissingPluginException {
      return false; // iOS: no IR hardware.
    } on PlatformException {
      return false;
    }
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw TransportException(e.message ?? e.code);
    } on MissingPluginException {
      throw TransportException('This phone has no IR blaster. Use the Wi-Fi bridge instead.');
    }
  }

  @override
  Future<void> send(IrFrame frame) =>
      _call<void>('transmit', {'freq': frame.frequencyHz, 'pattern': frame.pattern});

  @override
  Future<void> setTimer(TimerSlot slot, int seconds, IrFrame frame) => _call<void>(
      'setTimer', {'slot': slot.name, 'seconds': seconds, 'freq': frame.frequencyHz, 'pattern': frame.pattern});

  @override
  Future<void> cancelTimer(TimerSlot slot) => _call<void>('cancelTimer', {'slot': slot.name});

  @override
  Future<TimerStatus> status() async {
    final m = await _call<Map<Object?, Object?>>('timers') ?? const {};
    int? secs(Object? v) => v is int && v >= 0 ? v : null;
    final missed = (m['missed'] as List?)?.cast<String>() ?? const [];
    return TimerStatus(
      {TimerSlot.on: secs(m['on']), TimerSlot.off: secs(m['off'])},
      [for (final s in missed) TimerSlot.values.byName(s)],
    );
  }
}

/// The ESP32/ESP8266 IR bridge (firmware/daikin-ir-bridge) over HTTP.
class BridgeTransport implements IrTransport {
  BridgeTransport(this.host, {http.Client? client}) : _client = client ?? http.Client();

  final String host;
  final http.Client _client;
  static const _timeout = Duration(seconds: 6);

  Uri _uri(String path, [Map<String, String>? query]) {
    final h = host.trim();
    final uri = h.isEmpty ? null : Uri.tryParse('http://$h');
    if (uri == null || uri.host.isEmpty) {
      throw TransportException('“$host” isn\'t a valid host name or IP address.');
    }
    return uri.replace(path: path, queryParameters: query);
  }

  static String _body(IrFrame f) => [f.frequencyHz, ...f.pattern].join(' ');

  Future<String> _request(String method, String path, {Map<String, String>? query, String? body}) async {
    final uri = _uri(path, query);
    final http.Response res;
    try {
      final req = http.Request(method, uri);
      if (body != null) {
        req.headers['Content-Type'] = 'text/plain';
        req.body = body;
      }
      res = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
    } catch (_) {
      throw TransportException('Can\'t reach the bridge at $host. Is it powered and on the same Wi-Fi?');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TransportException('Bridge error ${res.statusCode}: ${res.body}');
    }
    return res.body;
  }

  /// "daikin-ir-bridge v1", or throws.
  Future<String> info() async {
    final j = await _infoJson();
    return '${j['device']} v${j['version']}';
  }

  Future<Map<String, Object?>> _infoJson() async {
    final body = await _request('GET', '/info');
    try {
      final j = jsonDecode(body) as Map<String, Object?>;
      if (j['device'] != 'daikin-ir-bridge') throw const FormatException();
      return j;
    } catch (_) {
      throw TransportException('$host answered, but it isn\'t a Daikin IR bridge.');
    }
  }

  @override
  Future<void> send(IrFrame frame) => _request('POST', '/send', body: _body(frame));

  @override
  Future<void> setTimer(TimerSlot slot, int seconds, IrFrame frame) =>
      _request('POST', '/timer/${slot.name}', query: {'in': '$seconds'}, body: _body(frame));

  @override
  Future<void> cancelTimer(TimerSlot slot) => _request('DELETE', '/timer/${slot.name}');

  @override
  Future<TimerStatus> status() async {
    final timers = (await _infoJson())['timers'] as Map? ?? const {};
    int? secs(Object? v) => v is int && v >= 0 ? v : null;
    return TimerStatus({TimerSlot.on: secs(timers['on']), TimerSlot.off: secs(timers['off'])});
  }
}
