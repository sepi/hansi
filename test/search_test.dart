import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/cedict_parser.dart';
import 'package:hansi/dict_entry.dart';
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

    test('exact match has full quality', () {
      final r = _search('你好', hanzi: true);
      final hit = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(hit.quality, 1.0);
    });

    test('exact match beats startsWith', () {
      final r = _search('你', hanzi: true);
      final nee = r.firstWhere((x) => x.entry.simplified == '你');
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(nee.quality, greaterThan(nihao.quality));
    });

    test('contains-only match is weaker than startsWith', () {
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
      final haoChi = search([..._corpus, extra, DictEntry(
        traditional: '好吃', simplified: '好吃',
        pinyin: 'hao3 chi1', definitions: ['tasty'],
      )], '好', hanzi: true, pinyin: false, english: false,
          wordIndex: _corpusIndex)
          .firstWhere((x) => x.entry.simplified == '好吃');
      expect(buHao.quality, lessThan(haoChi.quality));
    });

    test('traditional fallback: 中國 found by traditional', () {
      // simplified is '中国', traditional is '中國'
      final r = _search('中國', hanzi: true);
      expect(r.any((x) => x.entry.traditional == '中國'), isTrue);
    });

    test('hanzi=false returns empty for CJK query', () {
      expect(_search('你', hanzi: false, pinyin: true, english: true), isEmpty);
    });

    test('exact match ranks before contains-only', () {
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

    test('exact syllable beats prefix', () {
      final r = _search('ni', pinyin: true);
      final nee = r.firstWhere((x) => x.entry.simplified == '你');
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(nee.quality, greaterThan(nihao.quality));
    });

    test('contains-only match is weaker than exact', () {
      // 你好 pinyin: ni3hao3 — 'hao' appears but does not start the string.
      final r = _search('hao', pinyin: true);
      final hao = r.firstWhere((x) => x.entry.simplified == '好');
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(nihao.quality, lessThan(hao.quality));
    });

    test('toneless match is less certain than toned', () {
      final toneless = _search('ni', pinyin: true)
          .firstWhere((x) => x.entry.simplified == '你');
      final toned = _search('ni3', pinyin: true)
          .firstWhere((x) => x.entry.simplified == '你');
      expect(toneless.quality, lessThan(toned.quality));
    });

    test('ü, v and ǚ match only ü; plain u matches u and ü', () {
      final nv = DictEntry(
        traditional: '女', simplified: '女', pinyin: 'nu:3', definitions: ['woman'],
      );
      final nu = DictEntry(
        traditional: '努', simplified: '努', pinyin: 'nu3', definitions: ['to strive'],
      );
      final entries = [nv, nu];
      Set<String> hits(String q) => search(entries, q,
              hanzi: false, pinyin: true, english: false,
              wordIndex: buildWordIndex(entries))
          .map((r) => r.entry.simplified)
          .toSet();
      for (final q in ['nü', 'nv', 'nǚ', 'nü3', 'nv3']) {
        expect(hits(q), {'女'}, reason: q);
      }
      expect(hits('nu'), {'女', '努'});
      expect(hits('nu3'), {'女', '努'});
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
    test('ni3 matches 你 exactly', () {
      final r = _search('ni3', pinyin: true);
      final nee = r.firstWhere((x) => x.entry.simplified == '你');
      expect(nee.quality, 1.0);
    });

    test('ni3 matches 你好 as a prefix', () {
      // 你好 flattened = 'ni3hao3', which starts with 'ni3'.
      final r = _search('ni3', pinyin: true);
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(nihao.quality, allOf(greaterThan(0.4), lessThan(1.0)));
    });

    test('hao3: 好 exact, 你好 contains-only', () {
      final r = _search('hao3', pinyin: true);
      final hao = r.firstWhere((x) => x.entry.simplified == '好');
      final nihao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(hao.quality, 1.0);
      expect(nihao.quality, lessThan(0.7));
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

  group('English search — match quality', () {
    test('a meaning equal to the query is an exact match', () {
      // 说 "to speak; to say" has the meaning "to speak".
      final r = _search('to speak', english: true);
      final shuo = r.firstWhere((x) => x.entry.simplified == '说');
      expect(shuo.quality, greaterThan(0.9));
    });

    test('a leading "to" is optional', () {
      final r = _search('speak', english: true);
      expect(r.first.entry.simplified, anyOf('说', '说话'));
    });

    test('words spread across meanings is weaker than one meaning', () {
      // 说话 has defs ["to speak", "to say something"].
      final r = _search('speak something', english: true);
      final shuoHua = r.firstWhere((x) => x.entry.simplified == '说话');
      expect(shuoHua.quality, lessThan(0.55));
    });

    test('exact meaning beats a meaning that only contains the word', () {
      final extra = DictEntry(
        traditional: '學生會', simplified: '学生会', pinyin: 'xue2 sheng1 hui4',
        definitions: ['student union'],
      );
      final entries = [..._corpus, extra];
      final r = search(entries, 'student',
          hanzi: false, pinyin: false, english: true,
          wordIndex: buildWordIndex(entries));
      final exact = r.firstWhere((x) => x.entry.simplified == '学生');
      final phrase = r.firstWhere((x) => x.entry.simplified == '学生会');
      expect(exact.quality, greaterThan(phrase.quality));
    });

    test('substring-only match has the lowest quality', () {
      // "univer" is not a whole word but is a substring of "university".
      final r = _search('univer', english: true);
      final daxue = r.firstWhere((x) => x.entry.simplified == '大学');
      expect(daxue.quality, lessThan(0.25));
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

    test('"pretty beautiful" finds 漂亮 (words in separate meanings)', () {
      final r = _search('pretty beautiful', english: true);
      expect(r.first.entry.simplified, '漂亮');
    });

    test('whole-word boundary: "pretty" matches "prettily" only as substring', () {
      // 漂 has def "prettily coloured" — "pretty" as a whole word should NOT match it.
      final r = _search('pretty', english: true);
      final piao = r.where((x) => x.entry.simplified == '漂');
      if (piao.isNotEmpty) {
        expect(piao.first.quality, lessThan(0.25));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Sorting
  // ---------------------------------------------------------------------------

  group('Sorting', () {
    test('results are sorted by descending score', () {
      final r = _search('to', english: true);
      for (var i = 1; i < r.length; i++) {
        expect(r[i].score, lessThanOrEqualTo(r[i - 1].score));
      }
    });

    test('equal match quality: more frequent word ranks higher', () {
      // 你 (freq 10) and 你好 (unranked); 你 should appear first for "ni".
      final r = _search('ni', pinyin: true);
      final idxNi = r.indexWhere((x) => x.entry.simplified == '你');
      final idxNiHao = r.indexWhere((x) => x.entry.simplified == '你好');
      expect(idxNi, lessThan(idxNiHao));
    });

    test('equal frequency: entry with fewer senses ranks higher', () {
      final a = DictEntry(
        traditional: 'A', simplified: 'A', pinyin: 'a1', definitions: ['cat'],
      );
      final b = DictEntry(
        traditional: 'B', simplified: 'B', pinyin: 'b1',
        definitions: ['cat; feline animal'],
      );
      // B first in the dictionary, so the order is not a tiebreak artifact.
      final entries = [b, a];
      final results = search(entries, 'cat',
          hanzi: false, pinyin: false, english: true, freqMap: {},
          wordIndex: buildWordIndex(entries));
      expect(results.map((x) => x.entry.simplified), ['A', 'B']);
    });

    test('pinyin mode: 好 (freq 20) appears before 你好 (unranked) for "hao"', () {
      final r = _search('hao', pinyin: true);
      final allHao = r.firstWhere((x) => x.entry.simplified == '好');
      final allNiHao = r.firstWhere((x) => x.entry.simplified == '你好');
      expect(r.indexOf(allHao), lessThan(r.indexOf(allNiHao)));
    });
  });

  // ---------------------------------------------------------------------------
  // Mode gating
  // ---------------------------------------------------------------------------

  group('Score explanation', () {
    test('explains the same score that search ranked by', () {
      for (final q in ['to speak', 'ni', '你', 'univer', 'hao3']) {
        for (final r in _search(q, hanzi: true, pinyin: true, english: true)) {
          final ex = explainScore(_corpus, r.entry, q,
              freqMap: _freq, wordIndex: _corpusIndex)!;
          expect(ex.score, closeTo(r.score, 1e-12), reason: '$q $ex');
          expect(ex.quality, closeTo(r.quality, 1e-12), reason: '$q $ex');
        }
      }
    });

    test('names the factors of an English match', () {
      final ex = explainScore(_corpus, _corpus.firstWhere(
          (e) => e.simplified == '说'), 'to speak',
          freqMap: _freq, wordIndex: _corpusIndex)!;
      expect(ex.mode, 'english');
      expect(ex.qualityFactors.first, ('exact', 1.0));
      expect(ex.toString(), contains('score'));
    });

    test('returns null for an entry the query does not match', () {
      final ex = explainScore(_corpus, _corpus.first, 'xyzzy',
          wordIndex: _corpusIndex);
      expect(ex, isNull);
    });
  });

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
  });
}
