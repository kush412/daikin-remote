import 'package:flutter/material.dart' hide Banner;

import '../protocol/protocols.dart';
import '../remote.dart';
import '../remote_controller.dart';
import 'common.dart';
import 'connection_sheet.dart';

class PickerScreen extends StatelessWidget {
  const PickerScreen({super.key, required this.c});
  final RemoteController c;

  @override
  Widget build(BuildContext context) {
    final canGoBack = c.stored.protocolId != null;
    final viaPhone = c.transportKind == TransportKind.phone;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canGoBack) c.closePicker();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Find your AC\'s protocol'),
          leading: canGoBack ? BackButton(onPressed: c.closePicker) : null,
          actions: [ConnectionButton(c: c)],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${viaPhone ? 'Point the top of the phone at the AC from 1–3 m away.' : 'Put the bridge where its IR LED can see the AC.'} '
              'Tap “Test ON” on each protocol, starting at the top, until the AC beeps and starts (Cool 24°C). '
              'Then tap “Use this”.\n\nIf you know your remote\'s model number (printed on its back), look for it below.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Banner(
                text: c.error!,
                error: true,
                onDismiss: c.dismissError,
                action: TextButton(onPressed: () => showConnectionSheet(context, c), child: const Text('Connection')),
              ),
            ],
            for (final p in Protocols.all) ...[
              const SizedBox(height: 12),
              _ProtocolCard(c: c, p: p, current: p.id == c.stored.protocolId, cs: cs),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.c, required this.p, required this.current, required this.cs});
  final RemoteController c;
  final DaikinProtocol p;
  final bool current;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      color: current ? cs.primaryContainer : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(p.displayName + (current ? '  (in use)' : ''), style: text.titleMedium),
            Text(p.remotes, style: text.bodySmall),
            if (p.powerIsToggle) Text('Power is a toggle: Test ON and Test OFF both flip it.', style: text.bodySmall),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: tap(() => c.test(p, power: true)),
                    child: const Text('Test ON', maxLines: 1),
                  ),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: tap(() => c.test(p, power: false)),
                    child: const Text('Test OFF', maxLines: 1),
                  ),
                ),
                Expanded(
                  child: FilledButton(onPressed: () => c.choose(p), child: const Text('Use this', maxLines: 1)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
