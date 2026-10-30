// Relevance regression suite: hand-written queries in golden_queries.json,
// each stating where a given word must rank. Runs with all search modes on,
// as in the app.
//
// Case shapes:
//   {"query": q, "expect": w, "within": n}  — w is among the first n results
//   {"query": q, "expect": w, "above": v}   — w ranks above v
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/cedict_parser.dart';
import 'package:hansi/dict_entry.dart';
import 'package:hansi/search.dart';

String _gz(String path) =>
    utf8.decode(GZipDecoder().decodeBytes(File(path).readAsBytesSync()));

void main() {
  final entries = parseCedict(_gz('assets/cedict.txt.gz'));
  final freq = <String, int>{};
  for (final line in _gz('assets/word_freq.tsv.gz').split('\n')) {
    final tab = line.indexOf('\t');
    if (tab == -1) continue;
    final rank = int.tryParse(line.substring(0, tab));
    if (rank != null) freq[line.substring(tab + 1).trim()] = rank;
  }
  final index = buildWordIndex(entries);
  final cases = (jsonDecode(File('test/golden_queries.json').readAsStringSync())
          as List)
      .cast<Map<String, dynamic>>();

  List<DictEntry> run(String q) => search(entries, q,
          hanzi: true, pinyin: true, english: true,
          freqMap: freq, wordIndex: index)
      .map((r) => r.entry)
      .toList();

  int rankOf(List<DictEntry> results, String word) =>
      results.indexWhere((e) => e.simplified == word);

  for (final c in cases) {
    final q = c['query'] as String;
    final expect_ = c['expect'] as String;
    final within = c['within'] as int?;
    final above = c['above'] as String?;
    final label = within != null
        ? '"$q" → $expect_ within $within'
        : '"$q" → $expect_ above $above';

    test(label, () {
      final results = run(q);
      final top = results.take(5).map((e) => e.simplified).join(' ');
      final rank = rankOf(results, expect_);
      if (within != null) {
        expect(rank, allOf(greaterThanOrEqualTo(0), lessThan(within)),
            reason: '$expect_ at ${rank < 0 ? 'none' : rank + 1}; top: $top');
      } else {
        final other = rankOf(results, above!);
        expect(rank >= 0 && (other < 0 || rank < other), isTrue,
            reason: '$expect_ at ${rank + 1}, $above at ${other + 1}; top: $top');
      }
    });
  }
}
