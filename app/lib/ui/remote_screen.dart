import 'dart:async';

import 'package:flutter/material.dart' hide Banner;

import '../protocol/protocols.dart';
import '../remote.dart';
import '../remote_controller.dart';
import 'common.dart';
import 'connection_sheet.dart';

class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key, required this.c});
  final RemoteController c;

  @override
  Widget build(BuildContext context) {
    final s = c.state;
    final p = c.protocol;
    final cs = Theme.of(context).colorScheme;
    final range = p.tempRange(s.mode);
    final tempEnabled = s.mode != Mode.fan;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daikin Remote'),
            Text(p.displayName, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          ConnectionButton(c: c),
          TextButton(onPressed: c.showPicker, child: const Text('Protocol')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _Display(c: c),
          if (c.notice != null) ...[
            const SizedBox(height: 16),
            Banner(text: c.notice!, error: false, onDismiss: c.dismissNotice),
          ],
          if (c.error != null) ...[
            const SizedBox(height: 16),
            Banner(
              text: c.error!,
              error: true,
              onDismiss: c.dismissError,
              action: TextButton(onPressed: () => showConnectionSheet(context, c), child: const Text('Connection')),
            ),
          ],
          const SizedBox(height: 16),

          // Power + temperature
          Row(
            spacing: 16,
            children: [
              SizedBox.square(
                dimension: 88,
                child: FilledButton(
                  onPressed: tap(c.power),
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: s.power ? cs.primary : cs.surfaceContainerHighest,
                    foregroundColor: s.power ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                  child: const Icon(Icons.power_settings_new, size: 40, semanticLabel: 'Power'),
                ),
              ),
              Expanded(child: _BigButton('−', tempEnabled && s.tempC > range.min ? tap(c.tempDown) : null)),
              Expanded(child: _BigButton('+', tempEnabled && s.tempC < range.max ? tap(c.tempUp) : null)),
            ],
          ),
          if (p.powerIsToggle) ...[
            const SizedBox(height: 8),
            const Hint('This protocol toggles power. If the AC is out of sync with the app, press Power again.'),
          ],

          _Section(
            'Mode',
            _Choices<Mode>(options: p.modes, selected: s.mode, label: (m) => m.label, onSelect: (m) => tap(() => c.setMode(m))()),
          ),
          _Section(
            'Fan speed  ·  ${fanText(s.fan)}',
            _FanSelector(options: p.fans, selected: s.fan, onSelect: (f) => tap(() => c.setFan(f))()),
          ),
          if (p.supportsSwingV || p.supportsSwingH)
            _Section(
              'Swing',
              Row(
                spacing: 8,
                children: [
                  if (p.supportsSwingV) Expanded(child: _Toggle('↕ Up/down', s.swingV, tap(c.swingV))),
                  if (p.supportsSwingH) Expanded(child: _Toggle('↔ Left/right', s.swingH, tap(c.swingH))),
                ],
              ),
            ),
          _Section(
            'Timer',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    for (final slot in TimerSlot.values)
                      Expanded(child: _TimerButton(c: c, slot: slot, onTap: () => _pickTimer(context, slot))),
                  ],
                ),
                if (p.nativeTimer && !p.powerIsToggle)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Run timer on the ${c.externalTimerName} instead of the AC'),
                    value: c.stored.externalTimer,
                    onChanged: c.setExternalTimer,
                  ),
                Hint(_timerHint(c, p)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timerHint(RemoteController c, DaikinProtocol p) {
    if (!c.stored.usesExternalTimer) return 'The timer is stored in the AC; the phone can be put away.';
    final why = p.nativeTimer ? '' : 'This AC has no built-in IR timer, so ';
    return c.transportKind == TransportKind.phone
        ? '${why}the phone sends the command when it\'s due. Leave it pointed at the AC, '
            'and allow the app to run in the background (Autostart / Battery: No restrictions).'
        : '${why}the bridge sends the command when it\'s due. Keep it powered.';
  }

  Future<void> _pickTimer(BuildContext context, TimerSlot slot) async {
    const options = [15, 30, 60, 90, 120, 180, 240, 300, 360, 480, 600, 720];
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(slot == TimerSlot.on ? 'Turn ON after…' : 'Turn OFF after…',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.8,
              children: [
                for (final m in options)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, m),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(m < 60 ? '${m}m' : (m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}.5h')),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context, -1), child: const Text('Cancel timer')),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    tap(() => c.setTimer(slot, minutes < 0 ? null : minutes))();
  }
}

class _Display extends StatefulWidget {
  const _Display({required this.c});
  final RemoteController c;

  @override
  State<_Display> createState() => _DisplayState();
}

class _DisplayState extends State<_Display> {
  bool _flash = false;
  Timer? _flashTimer;
  late int _lastSendCount = widget.c.sendCount;

  @override
  void didUpdateWidget(covariant _Display old) {
    super.didUpdateWidget(old);
    if (widget.c.sendCount == _lastSendCount) return;
    _lastSendCount = widget.c.sendCount;
    _flashTimer?.cancel();
    _flash = true;
    _flashTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = c.state;
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onPrimaryContainer;
    final timers = [
      if (s.onTimerAt != null) 'On at ${clockText(context, s.onTimerAt!)} (${countdown(s.onTimerAt!, c.now)})',
      if (s.offTimerAt != null) 'Off at ${clockText(context, s.offTimerAt!)} (${countdown(s.offTimerAt!, c.now)})',
    ];
    return Card(
      margin: EdgeInsets.zero,
      color: cs.primaryContainer,
      child: Stack(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: s.power ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Text(s.power ? 'ON' : 'OFF', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
                    Text(
                      switch (s.mode) { Mode.fan => 'Fan', Mode.dry => 'Dry', _ => '${s.tempC}°' },
                      style: TextStyle(fontSize: 88, fontWeight: FontWeight.w300, color: fg, height: 1.1),
                    ),
                    Text(
                      [s.mode.label, 'Fan: ${fanText(s.fan)}', if (s.swingV) '↕', if (s.swingH) '↔'].join('  ·  '),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg),
                    ),
                    if (timers.isNotEmpty)
                      Text(timers.join('  ·  '), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg)),
                  ],
                ),
              ),
            ),
          ),
          // Brief "sending" dot each time a frame goes out.
          if (_flash)
            Positioned(
              top: 14,
              right: 14,
              child: Container(width: 10, height: 10, decoration: BoxDecoration(color: cs.tertiary, shape: BoxShape.circle)),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.child);
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton(this.label, this.onPressed);
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 72,
        child: FilledButton.tonal(onPressed: onPressed, child: Text(label, style: const TextStyle(fontSize: 34))),
      );
}

class _Choices<T> extends StatelessWidget {
  const _Choices({required this.options, required this.selected, required this.label, required this.onSelect});
  final List<T> options;
  final T selected;
  final String Function(T) label;
  final void Function(T) onSelect;

  @override
  Widget build(BuildContext context) => Row(
        spacing: 6,
        children: [
          for (final o in options)
            Expanded(
              child: o == selected
                  ? FilledButton(
                      onPressed: () => onSelect(o),
                      style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                      child: FitLabel(label(o)),
                    )
                  : OutlinedButton(
                      onPressed: () => onSelect(o),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      child: FitLabel(label(o)),
                    ),
            ),
        ],
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.on, this.onPressed);
  final String label;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => on
      ? FilledButton(onPressed: onPressed, child: FitLabel(label))
      : OutlinedButton(onPressed: onPressed, child: FitLabel(label));
}

/// Auto / Quiet buttons plus five ascending bars like a signal meter: bars up to the chosen
/// speed are filled, and the number under each bar is the speed it selects.
class _FanSelector extends StatelessWidget {
  const _FanSelector({required this.options, required this.selected, required this.onSelect});
  final List<Fan> options;
  final Fan selected;
  final void Function(Fan) onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final special = options.where((f) => !f.isLevel).toList();
    final levels = options.where((f) => f.isLevel).toList();
    final chosen = levels.contains(selected) ? selected.level : 0;
    return Column(
      spacing: 12,
      children: [
        if (special.isNotEmpty) _Choices<Fan>(options: special, selected: selected, label: (f) => f.label, onSelect: onSelect),
        if (levels.isNotEmpty)
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 10,
              children: [
                for (final f in levels)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onSelect(f),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 12.0 + f.level * 11,
                            decoration: BoxDecoration(
                              color: f.level <= chosen ? cs.primary : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              f.label,
                              style: TextStyle(
                                fontWeight: f == selected ? FontWeight.bold : FontWeight.normal,
                                color: f == selected ? cs.primary : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimerButton extends StatelessWidget {
  const _TimerButton({required this.c, required this.slot, required this.onTap});
  final RemoteController c;
  final TimerSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final at = c.state.timerAt(slot);
    final label = slot.name.toUpperCase();
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          FitLabel(at == null ? '$label timer' : '$label at ${clockText(context, at)}'),
          Text(at == null ? 'not set' : countdown(at, c.now), style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
    return at != null
        ? FilledButton(onPressed: onTap, child: content)
        : OutlinedButton(onPressed: onTap, child: content);
  }
}
