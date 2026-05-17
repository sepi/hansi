// Run from project root: dart run tool/test_parser.dart
import 'dart:convert';
import 'dart:io';

import 'package:hansi/cedict_parser.dart';
import 'package:hansi/search.dart';
import 'package:hansi/pinyin_utils.dart';

void main() {
  final bytes = File('assets/cedict.txt.gz').readAsBytesSync();
  final raw = GZipCodec().decode(bytes);
  final text = utf8.decode(raw);

  print('Decompressed: ${(raw.length / 1024 / 1024).toStringAsFixed(1)} MB');
  print('Lines: ${text.split('\n').length}');

  final entries = parseCedict(text);
  print('Entries parsed: ${entries.length}\n');

  // Pinyin conversion round-trip
  const samples = ['ni3 hao3', 'Zhong1 guo2', 'lu:4'];
  for (final s in samples) {
    final unicode = toUnicodePinyin(s);
    final back = toNumberedPinyin(unicode);
    print('$s → $unicode → $back');
  }
  print('');

  // Search tests
  final index = buildWordIndex(entries);

  void show(String query, {bool hanzi = true, bool pinyin = true, bool english = false}) {
    final results = search(entries, query,
        hanzi: hanzi, pinyin: pinyin, english: english, wordIndex: index);
    final top = results.take(5).map((r) =>
      '${r.entry.simplified}[${r.entry.pinyin}](tier${r.tier})').join('  ');
    print('  "$query" → $top');
  }

  print('Pinyin search tests:');
  show('ni3 hao');       // toned, space
  show('nihao');         // toneless, no space
  show('nǐ hǎo');        // unicode tones
  show('ni? hao3');      // wildcard tone
  show('hao3');          // contains: should find 你好 in tier 1
  show('你好');           // hanzi startsWith
  show('好');            // hanzi contains

  print('\nEnglish search tests:');
  show('hello', english: true, pinyin: false);           // single word
  show('old man', english: true, pinyin: false);         // multi-word
  show('running water', english: true, pinyin: false);   // tier 1 candidate
  show('love', english: true, pinyin: false);            // common word, many hits
}
