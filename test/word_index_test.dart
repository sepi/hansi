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

  test('every word maps to exactly the (entry, definition) pairs that contain it', () {
    final expected = <String, List<int>>{};
    for (var i = 0; i < reference.perDef.length; i++) {
      final defs = reference.perDef[i];
      for (var d = 0; d < defs.length; d++) {
        for (final w in defs[d]) {
          (expected[w] ??= []).add((i << 5) | d);
        }
      }
    }
    for (final w in index.words) {
      expect(index.postingsFor(w), expected[w], reason: 'postings for "$w"');
    }
    expect(index.postingsFor('xyzzy'), isEmpty);
  });
}
