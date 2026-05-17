import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import 'cedict_parser.dart';
import 'dict_entry.dart';
import 'search.dart';

typedef ProgressCallback = void Function(double progress);

// Future(() => ...) schedules synchronous CPU work as a microtask, yielding
// control back to Flutter between stages so the UI can repaint progress.
// compute() is not used because it spawns an isolate, which is unavailable
// on Flutter web.

Future<List<DictEntry>> loadCedict(ProgressCallback onProgress) async {
  final byteData = await rootBundle.load('assets/cedict.txt.gz');
  final compressed = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  onProgress(0.15);

  final raw = await Future(() => GZipDecoder().decodeBytes(compressed));
  onProgress(0.5);

  final text = await Future(() => utf8.decode(raw));
  onProgress(0.65);

  final entries = await Future(() => parseCedict(text));
  onProgress(1.0);

  return entries;
}

Future<Map<String, int>> loadFrequency(ProgressCallback onProgress) async {
  final byteData = await rootBundle.load('assets/hanzi_freq.tsv.gz');
  final compressed = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  onProgress(0.2);

  final raw = await Future(() => GZipDecoder().decodeBytes(compressed));
  onProgress(0.6);

  final map = await Future(() => _parseFreq(utf8.decode(raw)));
  onProgress(1.0);

  return map;
}

Future<WordIndex> loadWordIndex(
  List<DictEntry> entries,
  ProgressCallback onProgress,
) async {
  const chunkSize = 10000;
  final perDef = <List<Set<String>>>[];
  final combined = <Set<String>>[];
  final normStr = <String>[];
  final total = entries.length;

  for (var start = 0; start < total; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, total);
    await Future(() {
      for (var i = start; i < end; i++) {
        final sets = entries[i].definitions.map(_tokenizeDef).toList();
        perDef.add(sets);
        combined.add({for (final s in sets) ...s});
        normStr.add(
          entries[i]
              .definitions
              .map((d) => d.toLowerCase().replaceAll(';', ' '))
              .join(' '),
        );
      }
    });
    onProgress(end / total);
  }

  return WordIndex(perDef: perDef, combined: combined, normStr: normStr);
}

Set<String> _tokenizeDef(String def) => def
    .toLowerCase()
    .replaceAll(';', ' ')
    .split(RegExp(r'\W+'))
    .where((w) => w.isNotEmpty)
    .toSet();

Map<String, int> _parseFreq(String text) {
  final map = <String, int>{};
  for (final line in text.split('\n')) {
    final tab = line.indexOf('\t');
    if (tab == -1) continue;
    final rank = int.tryParse(line.substring(0, tab));
    if (rank == null) continue;
    map[line.substring(tab + 1).trim()] = rank;
  }
  return map;
}
