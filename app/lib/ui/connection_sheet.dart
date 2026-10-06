import 'package:flutter/material.dart';

import '../remote.dart';
import '../remote_controller.dart';
import '../transport/transport.dart';

Future<void> showConnectionSheet(BuildContext context, RemoteController c) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ConnectionSheet(c: c),
    );

/// Choose between the phone's IR blaster and the Wi-Fi bridge, and set the bridge address.
class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({super.key, required this.c});
  final RemoteController c;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late TransportKind _kind = widget.c.transportKind;
  late final _host = TextEditingController(text: widget.c.stored.bridgeHost);
  String? _status;
  bool _checking = false;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    widget.c.setTransport(_kind, _host.text);
    if (_kind == TransportKind.phone) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _checking = true;
      _status = null;
    });
    String status;
    try {
      status = '✅ Connected to ${await BridgeTransport(_host.text).info()}.';
    } on TransportException catch (e) {
      status = '❌ ${e.message}';
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phoneOk = widget.c.phoneIrAvailable;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send commands with', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<TransportKind>(
            groupValue: _kind,
            onChanged: (v) => setState(() => _kind = v ?? _kind),
            child: Column(
              children: [
                RadioListTile<TransportKind>(
                  value: TransportKind.phone,
                  enabled: phoneOk,
                  title: const Text('This phone\'s IR blaster'),
                  subtitle: Text(phoneOk
                      ? 'Point the top of the phone at the AC.'
                      : 'Not available: this phone has no IR emitter (iPhones never do).'),
                ),
                const RadioListTile<TransportKind>(
                  value: TransportKind.bridge,
                  title: Text('Wi-Fi IR bridge'),
                  subtitle: Text('An ESP32/ESP8266 with an IR LED that sends the commands for the phone.'),
                ),
              ],
            ),
          ),
          if (_kind == TransportKind.bridge) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _host,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Bridge address',
                hintText: 'daikin-ir.local or 192.168.1.50',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _checking ? null : _save,
            child: Text(_checking
                ? 'Testing…'
                : _kind == TransportKind.bridge
                    ? 'Save and test connection'
                    : 'Save'),
          ),
        ],
      ),
    );
  }
}
