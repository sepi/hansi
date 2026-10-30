import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/dict_entry.dart';
import 'package:hansi/example_sentence.dart';
import 'package:hansi/results_table.dart';
import 'package:hansi/search.dart';
import 'package:hansi/theme.dart';

void main() {
  testWidgets('result rows: compact menu button, no overflow, bold query',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final entries = [
      // 老师 has an HSK level, so its chip is shown.
      DictEntry(traditional: '老師', simplified: '老师', pinyin: 'lao3 shi1',
          definitions: ['teacher', 'CL:個|个[ge4],位[wei4]']),
      DictEntry(traditional: '教師', simplified: '教师', pinyin: 'jiao4 shi1',
          definitions: ['teacher; schoolteacher; instructor of a long subject']),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResultsTable(
          results: [
            for (final e in entries) SearchResult(entry: e, quality: 1, score: 1),
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
          sentenceData: SentenceData.empty,
          highlightQuery: 'teacher',
        ),
      ),
    ));

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
}
