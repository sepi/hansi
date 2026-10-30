import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/dict_entry.dart';
import 'package:hansi/example_sentence.dart';
import 'package:hansi/results_table.dart';
import 'package:hansi/search.dart';
import 'package:hansi/theme.dart';

final _entries = [
  // 老师 has an HSK level, so its chip is shown.
  DictEntry(traditional: '老師', simplified: '老师', pinyin: 'lao3 shi1',
      definitions: ['teacher', 'CL:個|个[ge4],位[wei4]']),
  DictEntry(traditional: '教師', simplified: '教师', pinyin: 'jiao4 shi1',
      definitions: ['teacher; schoolteacher; instructor of a long subject']),
];

final _sentences = SentenceData(const [
  ExampleSentence(
    targetWord: '老师',
    level: 1,
    zh: '我的老师很好，她每天都很早来学校。',
    pinyin: 'Wǒ de lǎoshī hěn hǎo, tā měitiān dōu hěn zǎo lái xuéxiào.',
    en: 'My teacher is very good; she comes to school early every day.',
    segments: ['我', '的', '老师', '很', '好', '，', '她', '每天', '都', '很',
        '早', '来', '学校', '。'],
  ),
]);

Future<void> _pumpTable(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ResultsTable(
        results: [
          for (final e in _entries) SearchResult(entry: e, quality: 1, score: 1),
        ],
        font: HanziFont.sans,
        toneColors: null,
        showTraditional: false,
        hskLevels: const {'老师': 1},
        strokeData: const {},
        mmaData: const {},
        strokeSpeed: 1,
        onSearch: (_) {},
        ankiInstalled: false,
        sentenceData: _sentences,
        highlightQuery: 'teacher',
      ),
    ),
  ));
}

void main() {
  testWidgets('collapsed rows: compact menu button, no overflow, bold query',
      (tester) async {
    await _pumpTable(tester);

    expect(tester.takeException(), isNull);
    final menus = find.byTooltip('More');
    expect(menus, findsNWidgets(2));
    expect(tester.getSize(menus.first).width, 32);

    bool hasBoldTeacher(InlineSpan root) {
      var found = false;
      root.visitChildren((s) {
        if (s is TextSpan &&
            s.text == 'teacher' &&
            s.style?.fontWeight == FontWeight.bold) {
          found = true;
        }
        return !found;
      });
      return found;
    }

    final bold = find.byWidgetPredicate(
        (w) => w is RichText && hasBoldTeacher(w.text));
    expect(bold, findsNWidgets(2));
  });

  testWidgets('expanded row: no overflow, buttons keep the row margin',
      (tester) async {
    await _pumpTable(tester);
    await tester.tap(find.byTooltip('Old HSK standard (2010, levels 1–6)'));
    // The stroke animation never settles, so pump a fixed time: one frame
    // to start the expand animation, then past its 200 ms duration.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    final menuRight = tester.getRect(find.byTooltip('More').first).right;
    final speaker = tester.getRect(find.byTooltip('Listen'));
    expect(menuRight, 360 - 16);
    expect(speaker.right, menuRight);

    for (final label in ['pī', 'En']) {
      final toggle = find.widgetWithText(OutlinedButton, label);
      expect(tester.getSize(toggle).width, lessThan(40), reason: label);
    }
    expect(find.text('All'), findsNothing); // copy buttons moved to the menu
  });

  testWidgets('menu holds the copy actions', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await _pumpTable(tester);

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    for (final label in ['Copy hanzi', 'Copy pinyin', 'Copy English']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Copy all'));
    await tester.pumpAndSettle();
    expect(copied, '老师\tlǎo shī\tteacher; CL:個|个[ge4],位[wei4]');
  });
}
