import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../protocol/protocols.dart';
import '../remote_controller.dart';
import 'connection_sheet.dart';

/// Every button gives a short tick, like pressing a physical remote.
VoidCallback tap(VoidCallback action) => () {
      HapticFeedback.selectionClick();
      action();
    };

String fanText(Fan f) => switch (f) {
      Fan.auto => 'Auto',
      Fan.quiet => 'Quiet',
      _ => 'Speed ${f.level} of 5',
    };

String clockText(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(t));

/// "in 1h 05m" / "in 4m" until [at].
String countdown(DateTime at, DateTime now) {
  var mins = (at.difference(now).inSeconds / 60).ceil();
  if (mins < 0) mins = 0;
  return mins >= 60 ? 'in ${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m' : 'in ${mins}m';
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// Error / notice card with an OK button and an optional extra action.
class Banner extends StatelessWidget {
  const Banner({super.key, required this.text, required this.error, required this.onDismiss, this.action});
  final String text;
  final bool error;
  final VoidCallback onDismiss;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = error ? cs.errorContainer : cs.tertiaryContainer;
    final fg = error ? cs.onErrorContainer : cs.onTertiaryContainer;
    return Card(
      color: bg,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(color: fg)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [?action, TextButton(onPressed: onDismiss, child: const Text('OK'))],
            ),
          ],
        ),
      ),
    );
  }
}

/// Toolbar button showing where commands go and whether that's reachable.
class ConnectionButton extends StatelessWidget {
  const ConnectionButton({super.key, required this.c});
  final RemoteController c;

  @override
  Widget build(BuildContext context) {
    final phone = c.transportKind.name == 'phone';
    final color = phone || c.online == true
        ? Colors.green
        : c.online == false
            ? Colors.red
            : Colors.grey;
    return TextButton.icon(
      onPressed: () => showConnectionSheet(context, c),
      icon: Icon(Icons.circle, size: 10, color: color),
      label: Text(phone ? 'Phone IR' : 'Bridge'),
    );
  }
}

/// One-line button label that shrinks to fit instead of wrapping (large system font sizes).
class FitLabel extends StatelessWidget {
  const FitLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));
}
