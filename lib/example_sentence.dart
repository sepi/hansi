// SPDX-License-Identifier: AGPL-3.0-or-later

class ExampleSentence {
  const ExampleSentence({
    required this.targetWord,
    required this.level,
    required this.zh,
    required this.pinyin,
    required this.en,
    required this.segments,
  });

  final String targetWord;
  final int level;
  final String zh;
  final String pinyin;
  final String en;
  final List<String> segments;

  factory ExampleSentence.fromJson(Map<String, dynamic> j) {
    final rawSegments = j['segments'];
    final List<String> segments;
    if (rawSegments is List) {
      segments = rawSegments.cast<String>();
    } else {
      final zh = j['zh'] as String;
      segments = List.generate(zh.length, (i) => zh[i]);
    }
    return ExampleSentence(
      targetWord: j['targetWord'] as String,
      level: j['level'] as int,
      zh: j['zh'] as String,
      pinyin: j['pinyin'] as String,
      en: j['en'] as String,
      segments: segments,
    );
  }
}

/// Holds all example sentences.  Provides O(1) lookup by target word
/// and O(n) containment search for sentences that mention a word incidentally.
class SentenceData {
  SentenceData(List<ExampleSentence> sentences)
      : all = List.unmodifiable(sentences),
        byTarget = _buildIndex(sentences);

  static final SentenceData empty = SentenceData(const []);

  final List<ExampleSentence> all;
  final Map<String, List<ExampleSentence>> byTarget;

  static Map<String, List<ExampleSentence>> _buildIndex(
      List<ExampleSentence> sentences) {
    final map = <String, List<ExampleSentence>>{};
    for (final s in sentences) {
      (map[s.targetWord] ??= []).add(s);
    }
    return Map.unmodifiable(map);
  }

  /// Sentences generated specifically to illustrate [word].
  List<ExampleSentence> targetFor(String word) =>
      byTarget[word] ?? const [];

  /// Sentences for other target words whose text contains [word].
  List<ExampleSentence> incidentalFor(String word, {int limit = 3}) {
    if (word.isEmpty) return const [];
    final results = <ExampleSentence>[];
    for (final s in all) {
      if (s.targetWord != word && s.zh.contains(word)) {
        results.add(s);
        if (results.length >= limit) break;
      }
    }
    return results;
  }
}
