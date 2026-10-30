import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/cedict_parser.dart';
import 'package:hansi/dict_entry.dart';
import 'package:hansi/search.dart';

import 'set_word_index_reference.dart';

void main() {
  late List<DictEntry> corpus;
  late WordIndex index;
  late SetWordIndex reference;

  setUpAll(() {
    corpus = parseCedict(utf8.decode(GZipDecoder()
        .decodeBytes(File('assets/cedict.txt.gz').readAsBytesSync())));
    index = buildWordIndex(corpus);
    reference = SetWordIndex(corpus);
  });

  test('vocabulary and postings match the set-based index', () {
    final vocab = <String>{for (final s in reference.combined) ...s};
    expect(index.words.toSet(), vocab);
    final sorted = [...index.words]..sort();
    expect(index.words, sorted);
    final occurrences = reference.perDef
        .fold<int>(0, (n, defs) => n + defs.fold<int>(0, (m, s) => m + s.length));
    expect(index.postings.length, occurrences);
  });

  test('English search matches the set-based search exactly', () {
    final queries = <String>[
      'pretty', 'beautiful', 'student', 'university', 'walk', 'ephemeral',
      'to speak', 'turn on', 'TURN   On', '  to speak  ', 'to to', 'a', 'the',
      'of', 'to', 'bank', 'cl', 'ge4', 'speak say', 'go to school',
      'very good', 'a b c d', "it's", 'u.s.', '(a', 'to-do', 'xyzzy',
      'mother', 'ni hao', '1', '2008', 'e', 'ing', 'tion', 'pre', 'zzz qqq',
    ];
    final words = index.words;
    for (var k = 0; k < words.length; k += 500) {
      final w = words[k];
      queries.add(w);
      if (k + 250 < words.length) queries.add('$w ${words[k + 250]}');
      if (w.length > 4) queries.add(w.substring(1, w.length - 1));
    }

    for (final q in queries) {
      final expected = referenceSearchEnglish(corpus, q, reference);
      final actual = searchEnglish(corpus, q, index);
      expect(actual.length, expected.length, reason: 'result count for "$q"');
      for (var i = 0; i < expected.length; i++) {
        expect(identical(actual[i].entry, expected[i].entry), isTrue,
            reason: '"$q" position $i: got ${actual[i].entry.simplified}, '
                'expected ${expected[i].entry.simplified}');
        expect(actual[i].tier, expected[i].tier,
            reason: '"$q" position $i tier');
      }
    }
  });
}
