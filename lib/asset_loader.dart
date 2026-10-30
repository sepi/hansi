// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import 'cedict_parser.dart';
import 'dict_entry.dart';
import 'example_sentence.dart';
import 'mma_entry.dart';
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
  final byteData = await rootBundle.load('assets/word_freq.tsv.gz');
  final compressed = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  onProgress(0.2);

  final raw = await Future(() => GZipDecoder().decodeBytes(compressed));
  onProgress(0.6);

  final map = await Future(() => parseNumberedWords(utf8.decode(raw)));
  onProgress(1.0);

  return map;
}

/// Old HSK level per simplified word; same `number<TAB>word` format as the
/// frequency list.
Future<Map<String, int>> loadHskLevels() async =>
    parseNumberedWords(await rootBundle.loadString('assets/hsk_levels.tsv'));

/// Loads the prebuilt English index (see tool/build_index.dart).
Future<WordIndex> loadWordIndex(
  List<DictEntry> entries,
  ProgressCallback onProgress,
) async {
  final data = await rootBundle.load('assets/word_index.bin');
  onProgress(0.5);
  final index = await Future(() => decodeWordIndex(data, entries));
  onProgress(1.0);
  return index;
}

Future<Map<String, String>> loadGraphics(ProgressCallback onProgress) async {
  final byteData = await rootBundle.load('assets/graphics.txt.gz');
  final compressed = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  onProgress(0.15);

  final raw = await Future(() => GZipDecoder().decodeBytes(compressed));
  onProgress(0.4);

  final text = await Future(() => utf8.decode(raw));
  onProgress(0.5);

  // Parse line by line in chunks to keep the UI responsive.
  // Each line: {"character":"X","strokes":[...],"medians":[...]}
  final lines = text.split('\n');
  final map = <String, String>{};
  const chunkSize = 500;
  for (var start = 0; start < lines.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, lines.length);
    await Future(() {
      for (var i = start; i < end; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        // Fast key extraction without full JSON decode.
        final ci = line.indexOf('"character"');
        if (ci == -1) continue;
        final q1 = line.indexOf('"', ci + 11) + 1;
        final q2 = line.indexOf('"', q1);
        if (q1 <= 0 || q2 <= q1) continue;
        map[line.substring(q1, q2)] = line;
      }
    });
    onProgress(0.5 + 0.5 * end / lines.length);
  }

  return map;
}

Future<Map<String, MmaEntry>> loadMmaDict(ProgressCallback onProgress) async {
  final byteData = await rootBundle.load('assets/mma_dict.txt.gz');
  final compressed = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  onProgress(0.1);

  final raw = await Future(() => GZipDecoder().decodeBytes(compressed));
  onProgress(0.3);

  final text = await Future(() => utf8.decode(raw));
  onProgress(0.4);

  final lines = text.split('\n');
  final map = <String, MmaEntry>{};
  const chunkSize = 500;
  for (var start = 0; start < lines.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, lines.length);
    await Future(() {
      for (var i = start; i < end; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          final entry = MmaEntry.fromJson(j);
          map[entry.character] = entry;
        } catch (_) {}
      }
    });
    onProgress(0.4 + 0.6 * end / lines.length);
  }

  return map;
}

Future<List<ExampleSentence>> loadExampleSentences(
    ProgressCallback onProgress) async {
  final text = await rootBundle.loadString('assets/example_sentences.json');
  onProgress(0.5);
  final raw = jsonDecode(text) as List<dynamic>;
  final sentences = raw
      .map((j) => ExampleSentence.fromJson(j as Map<String, dynamic>))
      .toList();
  onProgress(1.0);
  return sentences;
}

/// Parses `number<TAB>word` lines into word → number; other lines, such as
/// `#` comments, are skipped.
Map<String, int> parseNumberedWords(String text) {
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
