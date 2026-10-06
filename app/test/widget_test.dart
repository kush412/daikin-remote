import 'package:daikin_remote/main.dart';
import 'package:daikin_remote/remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final sent = <Map<Object?, Object?>>[];

  setUp(() {
    sent.clear();
    // Fake Android IR blaster.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vn.cake.daikinremote/ir'), (call) async {
      switch (call.method) {
        case 'hasEmitter':
          return true;
        case 'transmit':
          sent.add(call.arguments as Map<Object?, Object?>);
          return null;
        case 'timers':
          return {'on': -1, 'off': -1, 'missed': <String>[]};
        default:
          return null;
      }
    });
  });

  testWidgets('pick a protocol, then drive the remote', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final c = await RemoteController.load();
    await tester.pumpWidget(DaikinRemoteApp(controller: c));
    await tester.pumpAndSettle();

    // First run opens the picker.
    expect(find.text('Find your AC\'s protocol'), findsOneWidget);
    await tester.tap(find.text('Test ON').first);
    await tester.pump();
    expect(sent, hasLength(1));
    expect(sent.single['freq'], 38000);

    await tester.scrollUntilVisible(find.text('Daikin152'), 300);
    final card = find.ancestor(of: find.text('Daikin152'), matching: find.byType(Column)).first;
    final useThis = find.descendant(of: card, matching: find.text('Use this'));
    await tester.ensureVisible(useThis);
    await tester.pumpAndSettle();
    await tester.tap(useThis);
    await tester.pumpAndSettle();

    // Remote screen.
    expect(find.text('Daikin Remote'), findsOneWidget);
    expect(c.protocol.id, 'DAIKIN152');
    await tester.tap(find.bySemanticsLabel('Power'));
    await tester.pump();
    expect(c.state.power, isTrue);
    expect(sent, hasLength(2));

    await tester.tap(find.text('+'));
    await tester.pump();
    expect(c.state.tempC, 26);

    await tester.scrollUntilVisible(find.text('OFF timer'), 300);
    await tester.tap(find.text('OFF timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2h'));
    await tester.pumpAndSettle();
    expect(c.state.offTimerAt, isNotNull);
    expect(find.textContaining('in 2h 00m'), findsWidgets);

    c.dispose();
  });
}
