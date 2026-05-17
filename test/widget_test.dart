// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:hansi/main.dart';

void main() {
  testWidgets('App smoke test — renders without crashing',
      (WidgetTester tester) async {
    // runAsync lets real async (Future.delayed, rootBundle) proceed without
    // FakeAsync complaining about pending timers from DictLoader.
    await tester.runAsync(() async {
      await tester.pumpWidget(const HansiApp());
      // DictLoader shows a loading screen; just verify the tree builds.
      expect(find.byType(HansiApp), findsOneWidget);
    });
  });
}
