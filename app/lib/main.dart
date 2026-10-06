import 'dart:async';

import 'package:flutter/material.dart';

import 'remote_controller.dart';
import 'ui/picker_screen.dart';
import 'ui/remote_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await RemoteController.load();
  runApp(DaikinRemoteApp(controller: controller));
}

const _seed = Color(0xFF0A7CC1);

class DaikinRemoteApp extends StatefulWidget {
  const DaikinRemoteApp({super.key, required this.controller});
  final RemoteController controller;

  @override
  State<DaikinRemoteApp> createState() => _DaikinRemoteAppState();
}

class _DaikinRemoteAppState extends State<DaikinRemoteApp> with WidgetsBindingObserver {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.refresh();
    // Re-render countdowns and apply timers that came due.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => widget.controller.tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daikin Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark, useMaterial3: true),
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => switch (widget.controller.screen) {
          Screen.picker => PickerScreen(c: widget.controller),
          Screen.remote => RemoteScreen(c: widget.controller),
        },
      ),
    );
  }
}
