import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/app_settings.dart';
import 'package:hansi/menu_sheet.dart';
import 'package:hansi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a change notifies listeners and is saved', () async {
    final settings = AppSettings();
    var notified = 0;
    settings.addListener(() => notified++);

    settings.font = HanziFont.serif;
    settings.showTraditional = true;
    expect(notified, 2);

    await pumpEventQueue();
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.font, HanziFont.serif);
    expect(reloaded.showTraditional, isTrue);
  });

  testWidgets('the gear button opens the settings sheet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [
          SettingsButton(settings: AppSettings(), ankiInstalled: false),
        ]),
      ),
    ));

    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuSheet), findsOneWidget);
  });
}
