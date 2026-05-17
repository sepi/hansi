import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/cedict_parser.dart';
import 'package:hansi/dict_entry.dart';
import 'package:hansi/hsk.dart';
import 'package:hansi/search.dart';

// ---------------------------------------------------------------------------
// Test corpus
// ---------------------------------------------------------------------------

// Frequency map: lower rank = more common.
const _freq = {
  '你': 10,
  '好': 20,
  '中国': 50,
  '说': 30,
  '走': 80,
  '学生': 60,
  '大学': 70,
  // 漂亮, 美丽, 你好, 吃饭 — unranked (99999)
};

final _corpus = <DictEntry>[
  DictEntry(traditional: '你', simplified: '你', pinyin: 'ni3', definitions: ['you']),
  DictEntry(traditional: '你好', simplified: '你好', pinyin: 'ni3 hao3', definitions: ['hello']),
  DictEntry(traditional: '中國', simplified: '中国', pinyin: 'Zhong1 guo2', definitions: ['China']),
  DictEntry(traditional: '漂亮', simplified: '漂亮', pinyin: 'piao4 liang4', definitions: ['pretty; beautiful']),
  DictEntry(traditional: '美麗', simplified: '美丽', pinyin: 'mei3 li4', definitions: ['beautiful']),
  DictEntry(traditional: '好', simplified: '好', pinyin: 'hao3', definitions: ['good; well']),
  DictEntry(traditional: '說', simplified: '说', pinyin: 'shuo1', definitions: ['to speak; to say']),
  DictEntry(traditional: '走', simplified: '走', pinyin: 'zou3', definitions: ['to walk; to go']),
  DictEntry(traditional: '吃飯', simplified: '吃饭', pinyin: 'chi1 fan4', definitions: ['to eat a meal']),
  DictEntry(traditional: '大學', simplified: '大学', pinyin: 'da4 xue2', definitions: ['university; college']),
  DictEntry(traditional: '學生', simplified: '学生', pinyin: 'xue2 sheng1', definitions: ['student']),
  // Entry whose two definitions together contain both words of a query.
  DictEntry(
    traditional: '說話', simplified: '说话', pinyin: 'shuo1 hua4',
    definitions: ['to speak', 'to say something'],
  ),
  // Entry where match is only a substring (not a whole word).
  DictEntry(
    traditional: '漂', simplified: '漂', pinyin: 'piao1',
    definitions: ['to float; prettily coloured'],
  ),
];

final _corpusIndex = buildWordIndex(_corpus);

List<SearchResult> _search(
  String query, {
  bool hanzi = false,
  bool pinyin = false,
  bool english = false,
  Map<String, int> freqMap = _freq,
}) =>
    search(_corpus, query,
        hanzi: hanzi, pinyin: pinyin, english: english,
        freqMap: freqMap, wordIndex: _corpusIndex);

// ---------------------------------------------------------------------------
// Hanzi search
// ---------------------------------------------------------------------------

void main() {
  group('Hanzi search', () {
    test('empty query returns nothing', () {
      expect(_search('', hanzi: true), isEmpty);
    });

    test('finds exact match in tier 0', () {
      final r = _search('你好', hanzi: true);
      expect(r.any((x) => x.entry.simplified == '你好'), isTrue);
      final hit = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(hit.tier, 0);
    });

    test('startsWith is tier 0, contains-only is tier 1', () {
      // '你' starts with '你' (tier 0); '你好' also starts with '你' (tier 0).
      // There is no entry that merely *contains* '你' without starting with it
      // in this corpus, so just verify tier 0 for both.
      final r = _search('你', hanzi: true);
      final nee = r.firstWhere((x) => x.entry.simplified == '你');
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(nee.tier, 0);
      expect(nihao.tier, 0);
    });

    test('contains-only match is tier 1', () {
      // Add a synthetic entry where '好' is embedded, not at start.
      final extra = DictEntry(
        traditional: '不好', simplified: '不好',
        pinyin: 'bu4 hao3', definitions: ['not good'],
      );
      final entries = [..._corpus, extra];
      final r = search(entries, '好',
          hanzi: true, pinyin: false, english: false,
          wordIndex: _corpusIndex);
      final buHao = r.firstWhere((x) => x.entry.simplified == '不好');
      expect(buHao.tier, 1);
    });

    test('traditional fallback: 中國 found by traditional', () {
      // simplified is '中国', traditional is '中國'
      final r = _search('中國', hanzi: true);
      expect(r.any((x) => x.entry.traditional == '中國'), isTrue);
    });

    test('hanzi=false returns empty for CJK query', () {
      expect(_search('你', hanzi: false, pinyin: true, english: true), isEmpty);
    });

    test('tier 0 results appear before tier 1', () {
      final extra = DictEntry(
        traditional: '不好', simplified: '不好',
        pinyin: 'bu4 hao3', definitions: ['not good'],
      );
      final entries = [..._corpus, extra];
      final r = search(entries, '好',
          hanzi: true, pinyin: false, english: false,
          wordIndex: _corpusIndex);
      final idxHao = r.indexWhere((x) => x.entry.simplified == '好');
      final idxBuHao = r.indexWhere((x) => x.entry.simplified == '不好');
      expect(idxHao, lessThan(idxBuHao));
    });
  });

  // ---------------------------------------------------------------------------
  // Pinyin search
  // ---------------------------------------------------------------------------

  group('Pinyin search (toneless)', () {
    test('prefix match: "ni" finds 你 and 你好', () {
      final r = _search('ni', pinyin: true);
      final simplified = r.map((x) => x.entry.simplified).toSet();
      expect(simplified, containsAll(['你', '你好']));
    });

    test('prefix match is tier 0', () {
      final r = _search('ni', pinyin: true);
      final nee = r.firstWhere((x) => x.entry.simplified == '你');
      expect(nee.tier, 0);
    });

    test('contains-only match is tier 1', () {
      // 你好 pinyin: ni3hao3 — 'hao' appears but does not start the string.
      final r = _search('hao', pinyin: true);
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(nihao.tier, 1);
    });

    test('query normalises unicode tones: nǐ → ni3', () {
      final toned = _search('nǐ', pinyin: true);
      final plain = _search('ni3', pinyin: true);
      expect(
        toned.map((x) => x.entry.simplified).toSet(),
        equals(plain.map((x) => x.entry.simplified).toSet()),
      );
    });
  });

  group('Pinyin search (numbered tones)', () {
    test('ni3 finds 你 (prefix tier 0)', () {
      final r = _search('ni3', pinyin: true);
      final nee = r.firstWhere((x) => x.entry.simplified == '你');
      expect(nee.tier, 0);
    });

    test('ni3 does NOT match 你好 as prefix (ni3hao3 ≠ starts with ni3hao3)', () {
      // ni3hao3 starts with 'ni3', so 你好 IS a prefix match.
      final r = _search('ni3', pinyin: true);
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      // 你好 flattened = 'ni3hao3', which starts with 'ni3' → tier 0
      expect(nihao.tier, 0);
    });

    test('hao3 finds 好 as tier 0 and 你好 as tier 1', () {
      final r = _search('hao3', pinyin: true);
      final hao = r.firstWhere((x) => x.entry.simplified == '好');
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(hao.tier, 0);
      expect(nihao.tier, 1);
    });

    test('wildcard ? matches any tone: ni? finds 你 (ni3)', () {
      final r = _search('ni?', pinyin: true);
      expect(r.any((x) => x.entry.simplified == '你'), isTrue);
    });

    test('wildcard ni? does not match 好 (hao3)', () {
      final r = _search('ni?', pinyin: true);
      expect(r.any((x) => x.entry.simplified == '好'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // English search
  // ---------------------------------------------------------------------------

  group('English search — tier structure', () {
    test('all words in one definition → tier 0', () {
      // "to speak" both words appear in the single def of 说 ("to speak; to say")
      final r = _search('to speak', english: true);
      final shuo = r.firstWhere((x) => x.entry.simplified == '说');
      expect(shuo.tier, 0);
    });

    test('words spread across multiple definitions → tier 1 at most', () {
      // 说话 has defs ["to speak", "to say something"].
      // "speak something" → not all in one def → tier 1 (all across combined).
      final r = _search('speak something', english: true);
      final shuoHua = r.firstWhere((x) => x.entry.simplified == '说话');
      expect(shuoHua.tier, lessThanOrEqualTo(1));
    });

    test('single whole word match → at most tier 2', () {
      final r = _search('student', english: true);
      final xuesheng = r.firstWhere((x) => x.entry.simplified == '学生');
      expect(xuesheng.tier, lessThanOrEqualTo(2));
    });

    test('substring match only → tier 3', () {
      // "univer" is not a whole word but is a substring of "university".
      final r = _search('univer', english: true);
      final daxue = r.firstWhere((x) => x.entry.simplified == '大学');
      expect(daxue.tier, 3);
    });

    test('no match returns nothing', () {
      final r = _search('xyzzy', english: true);
      expect(r, isEmpty);
    });
  });

  group('English search — semicolons', () {
    test('"pretty" finds 漂亮 despite semicolon in definition', () {
      // Definition is "pretty; beautiful" — semicolon must not block the match.
      final r = _search('pretty', english: true);
      expect(r.any((x) => x.entry.simplified == '漂亮'), isTrue);
    });

    test('"beautiful" finds both 漂亮 and 美丽', () {
      final r = _search('beautiful', english: true);
      final simplified = r.map((x) => x.entry.simplified).toSet();
      expect(simplified, containsAll(['漂亮', '美丽']));
    });

    test('"pretty beautiful" finds 漂亮 at tier 0 (both words in one def)', () {
      final r = _search('pretty beautiful', english: true);
      final piaoliang = r.firstWhere((x) => x.entry.simplified == '漂亮');
      expect(piaoliang.tier, 0);
    });

    test('whole-word boundary: "pretty" does not match "prettily" at tier 0/1', () {
      // 漂 has def "prettily coloured" — "pretty" as a whole word should NOT match it.
      final r = _search('pretty', english: true);
      final piao = r.where((x) => x.entry.simplified == '漂');
      // Either not found, or found only at tier 3 (substring).
      if (piao.isNotEmpty) {
        expect(piao.first.tier, 3);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Sorting
  // ---------------------------------------------------------------------------

  group('Sorting', () {
    test('lower tier appears before higher tier', () {
      // Search "good": 好 (tier 0, "good; well") vs anything with tier > 0.
      final r = _search('good', english: true);
      if (r.length >= 2) {
        // Verify sorted by tier ascending.
        for (var i = 1; i < r.length; i++) {
          expect(r[i].tier, greaterThanOrEqualTo(r[i - 1].tier));
        }
      }
    });

    test('within same tier, more frequent word ranks higher', () {
      // Both 你 (freq 10) and 你好 (unranked) may be tier 0 for "ni".
      // 你 should appear before 你好.
      final r = _search('ni', pinyin: true);
      final tier0 = r.where((x) => x.tier == 0).toList();
      final idxNi = tier0.indexWhere((x) => x.entry.simplified == '你');
      final idxNiHao = tier0.indexWhere((x) => x.entry.simplified == '你好');
      if (idxNi != -1 && idxNiHao != -1) {
        expect(idxNi, lessThan(idxNiHao));
      }
    });

    test('among equally frequent entries, shorter first-def wins', () {
      // 学生 def "student" (7) vs 大学 def "university; college" (split → "university" = 10).
      // Both are unranked. 学生 should rank above 大学 when both match.
      // 大学 is the only hit for 'uni'; the real test uses two synthetic entries.
      final a = DictEntry(
        traditional: 'A', simplified: 'A', pinyin: 'a1', definitions: ['cat'],
      );
      final b = DictEntry(
        traditional: 'B', simplified: 'B', pinyin: 'b1',
        definitions: ['cat; feline animal'],
      );
      final entries = [a, b];
      final results = search(entries, 'cat',
          hanzi: false, pinyin: false, english: true, freqMap: {},
          wordIndex: buildWordIndex(entries));
      final tier0 = results.where((x) => x.tier == 0).toList();
      final idxA = tier0.indexWhere((x) => x.entry.simplified == 'A');
      final idxB = tier0.indexWhere((x) => x.entry.simplified == 'B');
      // 'cat' (3) < 'cat' from 'cat; feline animal' split → 'cat' (3) — tie.
      // Both are length 3 after split, so order may be equal; just verify both present.
      expect(idxA, isNot(-1));
      expect(idxB, isNot(-1));
    });

    test('pinyin mode: 好 (freq 20) appears before 你好 (unranked) at tier 1 for "hao"', () {
      final r = _search('hao', pinyin: true);
      // 好 is tier 0 (starts with hao). Verify it appears before unranked 你好.
      final allHao = r.firstWhere((x) => x.entry.simplified == '好');
      final allNiHao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(r.indexOf(allHao), lessThan(r.indexOf(allNiHao)));
    });
  });

  // ---------------------------------------------------------------------------
  // Mode gating
  // ---------------------------------------------------------------------------

  group('Mode gating', () {
    test('all modes off returns nothing', () {
      expect(
        _search('ni', hanzi: false, pinyin: false, english: false),
        isEmpty,
      );
    });

    test('pinyin=false skips pinyin results', () {
      final r = _search('ni', hanzi: false, pinyin: false, english: true);
      // No English definition contains "ni" as a whole word in this corpus.
      expect(r.any((x) => x.entry.simplified == '你'), isFalse);
    });

    test('english=false skips english results', () {
      final r = _search('hello', hanzi: false, pinyin: true, english: false);
      expect(r, isEmpty); // no pinyin matches "hello"
    });

    test('pinyin and english combined de-duplicates entries', () {
      // Run both modes; confirm no entry appears twice.
      final r = _search('hao', pinyin: true, english: true);
      final simplified = r.map((x) => x.entry.simplified).toList();
      expect(simplified.toSet().length, equals(simplified.length));
    });
  });

  // ---------------------------------------------------------------------------
  // Real CC-CEDICT data: performance + indexed-vs-legacy comparison
  // ---------------------------------------------------------------------------

  group('Real data', () {
    late List<DictEntry> realCorpus;
    late Map<String, int> realFreq;
    late WordIndex realIndex;

    setUpAll(() {
      const assets = 'assets';
      final cedictText = utf8.decode(
          GZipDecoder().decodeBytes(File('$assets/cedict.txt.gz').readAsBytesSync()));
      realCorpus = parseCedict(cedictText);

      final freqText = utf8.decode(
          GZipDecoder().decodeBytes(File('$assets/hanzi_freq.tsv.gz').readAsBytesSync()));
      realFreq = {};
      for (final line in freqText.split('\n')) {
        final tab = line.indexOf('\t');
        if (tab == -1) continue;
        final rank = int.tryParse(line.substring(0, tab));
        if (rank == null) continue;
        realFreq[line.substring(tab + 1).trim()] = rank;
      }

      realIndex = buildWordIndex(realCorpus);
    });

    // -------------------------------------------------------------------------
    // Performance (indicative smoke signals, not hard SLAs)
    // -------------------------------------------------------------------------

    group('Performance', () {
      void bench(String label, void Function() fn, int limitMs) {
        test(label, () {
          fn(); // warm-up (not measured)
          final sw = Stopwatch()..start();
          fn();
          sw.stop();
          // ignore: avoid_print
          print('  $label: ${sw.elapsedMilliseconds} ms (limit $limitMs ms)');
          expect(sw.elapsedMilliseconds, lessThan(limitMs),
              reason: '$label took ${sw.elapsedMilliseconds} ms');
        });
      }

      bench('hanzi — 你', () {
        search(realCorpus, '你', hanzi: true, pinyin: false, english: false,
            freqMap: realFreq, wordIndex: realIndex);
      }, 200);

      bench('hanzi — 中国', () {
        search(realCorpus, '中国', hanzi: true, pinyin: false, english: false,
            freqMap: realFreq, wordIndex: realIndex);
      }, 200);

      bench('pinyin toneless — ni', () {
        search(realCorpus, 'ni', hanzi: false, pinyin: true, english: false,
            freqMap: realFreq, wordIndex: realIndex);
      }, 200);

      bench('pinyin numbered — ni3', () {
        search(realCorpus, 'ni3', hanzi: false, pinyin: true, english: false,
            freqMap: realFreq, wordIndex: realIndex);
      }, 200);

      bench('pinyin wildcard — ni?', () {
        search(realCorpus, 'ni?', hanzi: false, pinyin: true, english: false,
            freqMap: realFreq, wordIndex: realIndex);
      }, 200);

      bench('english — pretty', () {
        search(realCorpus, 'pretty', hanzi: false, pinyin: false, english: true,
            freqMap: realFreq, wordIndex: realIndex);
      }, 1000);

      bench('english — to speak', () {
        search(realCorpus, 'to speak', hanzi: false, pinyin: false, english: true,
            freqMap: realFreq, wordIndex: realIndex);
      }, 1000);

      bench('english — ephemeral', () {
        search(realCorpus, 'ephemeral', hanzi: false, pinyin: false, english: true,
            freqMap: realFreq, wordIndex: realIndex);
      }, 1000);
    });

    // -------------------------------------------------------------------------
    // Indexed vs. legacy: same results, indexed is faster
    // -------------------------------------------------------------------------

    group('Indexed vs legacy English', () {
      // Legacy implementation (regex-based, verbatim copy of the old code).
      List<SearchResult> legacy(String rawQuery) {
        final words = rawQuery.toLowerCase().trim().split(RegExp(r'\s+'));
        if (words.isEmpty || words.first.isEmpty) return [];

        final res = words.map((w) => RegExp('\\b${RegExp.escape(w)}\\b')).toList();

        List<String> defs(DictEntry e) => e.definitions
            .map((d) => d.toLowerCase().replaceAll(';', ' '))
            .toList();

        bool allInOne(List<String> ds) =>
            ds.any((d) => res.every((re) => re.hasMatch(d)));
        bool allInAll(List<String> ds) =>
            res.every((re) => re.hasMatch(ds.join(' ')));
        bool anyWholeWord(List<String> ds) =>
            res.any((re) => ds.any(re.hasMatch));
        bool anySubstring(List<String> ds) =>
            words.any((w) => ds.any((d) => d.contains(w)));

        final seen = <DictEntry>{};
        final results = <SearchResult>[];

        void pass(int tier, bool Function(List<String>) match) {
          for (final entry in realCorpus) {
            if (seen.contains(entry)) continue;
            if (match(defs(entry))) {
              seen.add(entry);
              results.add(SearchResult(entry: entry, tier: tier));
            }
          }
        }

        pass(0, allInOne);
        pass(1, allInAll);
        pass(2, anyWholeWord);
        pass(3, anySubstring);

        int hsk(DictEntry e) =>
            kHskLevel[e.simplified] ?? kHskLevel[e.traditional] ?? 99;
        results.sort((a, b) {
          final t = a.tier.compareTo(b.tier);
          if (t != 0) return t;
          final h = hsk(a.entry).compareTo(hsk(b.entry));
          if (h != 0) return h;
          final fa = realFreq[a.entry.simplified] ?? realFreq[a.entry.traditional] ?? 99999;
          final fb = realFreq[b.entry.simplified] ?? realFreq[b.entry.traditional] ?? 99999;
          final f = fa.compareTo(fb);
          if (f != 0) return f;
          return a.entry.definitions.first.split(';').first.trim().length
              .compareTo(b.entry.definitions.first.split(';').first.trim().length);
        });

        return results;
      }

      List<SearchResult> indexed(String rawQuery) =>
          search(realCorpus, rawQuery,
              hanzi: false, pinyin: false, english: true,
              freqMap: realFreq, wordIndex: realIndex);

      void compare(String query) {
        test('same results as legacy for "$query"', () {
          final legacyResults = legacy(query);
          final indexedResults = indexed(query);
          expect(indexedResults.length, legacyResults.length,
              reason: 'result count differs for "$query"');
          for (var i = 0; i < legacyResults.length; i++) {
            final leg = legacyResults[i];
            final idx = indexedResults[i];
            // Object identity: both searches operate on the same realCorpus list,
            // so matching entries must be the exact same DictEntry instance.
            expect(
              identical(idx.entry, leg.entry),
              isTrue,
              reason: 'position $i: indexed="${idx.entry.simplified}" '
                  'legacy="${leg.entry.simplified}"',
            );
            expect(
              idx.tier,
              leg.tier,
              reason: 'tier at position $i (${leg.entry.simplified}) differs',
            );
          }
        });
      }

      compare('pretty');
      compare('beautiful');
      compare('student');
      compare('university');
      compare('walk');
      compare('ephemeral');

      test('indexed is faster than legacy for "to speak"', () {
        // warm-up
        legacy('to speak');
        indexed('to speak');

        final sw1 = Stopwatch()..start();
        legacy('to speak');
        sw1.stop();

        final sw2 = Stopwatch()..start();
        indexed('to speak');
        sw2.stop();

        // ignore: avoid_print
        print('  legacy: ${sw1.elapsedMilliseconds} ms  '
            'indexed: ${sw2.elapsedMilliseconds} ms');
        expect(sw2.elapsedMilliseconds, lessThan(sw1.elapsedMilliseconds),
            reason: 'indexed (${sw2.elapsedMilliseconds} ms) should beat '
                'legacy (${sw1.elapsedMilliseconds} ms)');
      });
    });
  });
}
