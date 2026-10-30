// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import 'dict_entry.dart';
import 'hsk.dart';
import 'pinyin_utils.dart';

// ---------------------------------------------------------------------------
// Word index — inverted index from English word to (entry, definition)
// ---------------------------------------------------------------------------

/// Bits of a posting reserved for the definition number within an entry.
const _defBits = 5;
const _defMask = (1 << _defBits) - 1;

/// Inverted index over definition words, stored as flat typed arrays
/// (CSR layout) instead of per-entry hash sets.
///
/// Each posting packs `(entryId << 5) | defIndex`. The postings of word k are
/// `postings[wordStart[k] .. wordStart[k + 1]]`, sorted ascending, so they are
/// ordered by entry and then by definition.
class WordIndex {
  const WordIndex({
    required this.words,
    required this.wordStart,
    required this.postings,
    required this.normStr,
  });

  /// Distinct definition words, sorted for binary search.
  final List<String> words;

  /// Start of each word's slice in [postings]; length is `words.length + 1`.
  final Int32List wordStart;

  final Int32List postings;

  /// Per-entry normalized combined string for substring tier-3 fallback.
  final List<String> normStr;

  /// Packed postings for [word], or an empty list if it never occurs.
  Int32List postingsFor(String word) {
    var lo = 0, hi = words.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final c = words[mid].compareTo(word);
      if (c == 0) {
        return Int32List.sublistView(
            postings, wordStart[mid], wordStart[mid + 1]);
      }
      if (c < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return Int32List(0);
  }
}

Set<String> tokenizeDef(String def) => def
    .toLowerCase()
    .replaceAll(';', ' ')
    .split(RegExp(r'\W+'))
    .where((w) => w.isNotEmpty)
    .toSet();

/// Builds a [WordIndex] one entry at a time, so boot-time loading can yield
/// between chunks. Entries must be added in dictionary order.
class WordIndexBuilder {
  final _wordIds = <String, int>{};
  final _words = <String>[];
  final _normStr = <String>[];
  // (wordId, posting) pairs in insertion order; grown by doubling.
  var _pairWord = Int32List(1 << 16);
  var _pairPosting = Int32List(1 << 16);
  var _pairCount = 0;
  var _entryCount = 0;

  void add(DictEntry entry) {
    final defs = entry.definitions;
    if (defs.length > _defMask + 1) {
      throw StateError('Entry ${entry.simplified} has ${defs.length} '
          'definitions; the index supports at most ${_defMask + 1}.');
    }
    for (var d = 0; d < defs.length; d++) {
      for (final w in tokenizeDef(defs[d])) {
        final id = _wordIds.putIfAbsent(w, () {
          _words.add(w);
          return _words.length - 1;
        });
        if (_pairCount == _pairWord.length) {
          _pairWord = _grow(_pairWord);
          _pairPosting = _grow(_pairPosting);
        }
        _pairWord[_pairCount] = id;
        _pairPosting[_pairCount] = (_entryCount << _defBits) | d;
        _pairCount++;
      }
    }
    _normStr.add(
      defs.map((d) => d.toLowerCase().replaceAll(';', ' ')).join(' '),
    );
    _entryCount++;
  }

  static Int32List _grow(Int32List a) => Int32List(a.length * 2)..setAll(0, a);

  WordIndex finish() {
    // Assign final ids in sorted word order.
    final order = List<int>.generate(_words.length, (i) => i)
      ..sort((a, b) => _words[a].compareTo(_words[b]));
    final rank = Int32List(_words.length);
    for (var r = 0; r < order.length; r++) {
      rank[order[r]] = r;
    }

    // Counting sort of pairs by word rank. Pairs were added in ascending
    // posting order, so each word's slice comes out already sorted.
    final wordStart = Int32List(_words.length + 1);
    for (var i = 0; i < _pairCount; i++) {
      wordStart[rank[_pairWord[i]] + 1]++;
    }
    for (var k = 0; k < _words.length; k++) {
      wordStart[k + 1] += wordStart[k];
    }
    final fill = Int32List.fromList(wordStart);
    final postings = Int32List(_pairCount);
    for (var i = 0; i < _pairCount; i++) {
      postings[fill[rank[_pairWord[i]]]++] = _pairPosting[i];
    }

    return WordIndex(
      words: [for (final i in order) _words[i]],
      wordStart: wordStart,
      postings: postings,
      normStr: _normStr,
    );
  }
}

/// Builds a [WordIndex] synchronously. Use [loadWordIndex] from
/// asset_loader.dart for the boot-time chunked version with progress.
WordIndex buildWordIndex(List<DictEntry> entries) {
  final builder = WordIndexBuilder();
  entries.forEach(builder.add);
  return builder.finish();
}

// ---------------------------------------------------------------------------

typedef SearchArgs = ({
  List<DictEntry> entries,
  String rawQuery,
  bool hanzi,
  bool pinyin,
  bool english,
  Map<String, int> freqMap,
  WordIndex wordIndex,
});

List<SearchResult> searchIsolate(SearchArgs args) => search(
      args.entries,
      args.rawQuery,
      hanzi: args.hanzi,
      pinyin: args.pinyin,
      english: args.english,
      freqMap: args.freqMap,
      wordIndex: args.wordIndex,
    );

class SearchResult {
  const SearchResult({
    required this.entry,
    required this.quality,
    required this.score,
  });
  final DictEntry entry;

  /// How well the entry matched the query, 0–1, independent of how common
  /// the entry is. 1.0 is an exact match.
  final double quality;

  /// Final ranking score; higher ranks first.
  final double score;
}

/// Weights of the ranking score:
/// `quality * matchQuality + commonness * commonness + shortness / length`.
///
/// Match quality dominates so a common word with a weak match cannot outrank
/// an exact match; commonness reorders matches of similar quality; shortness
/// is a tiebreak.
class RankingWeights {
  const RankingWeights({
    this.quality = 1.0,
    this.commonness = 0.3,
    this.shortness = 0.05,
  });
  final double quality;
  final double commonness;
  final double shortness;
}

/// Main entry point. Each enabled mode reports a match quality per entry;
/// an entry matched by several modes keeps its best quality.
List<SearchResult> search(
  List<DictEntry> entries,
  String rawQuery, {
  required bool hanzi,
  required bool pinyin,
  required bool english,
  Map<String, int> freqMap = const {},
  required WordIndex wordIndex,
  RankingWeights weights = const RankingWeights(),
}) {
  if (rawQuery.trim().isEmpty) return [];
  final quality = <int, double>{};
  void merge(Map<int, double> mode) {
    mode.forEach((i, q) {
      if (q > (quality[i] ?? 0)) quality[i] = q;
    });
  }

  if (hanzi) merge(_searchHanzi(entries, rawQuery));
  if (pinyin) merge(_searchPinyin(entries, rawQuery));
  if (english) merge(_searchEnglish(entries, rawQuery, wordIndex));

  final homographDefs = _homographDefs(entries);
  final ranked = [
    for (final MapEntry(key: i, value: q) in quality.entries)
      (i: i, result: SearchResult(
        entry: entries[i],
        quality: q,
        score: _score(entries[i], q, freqMap, homographDefs, weights),
      )),
  ]..sort((a, b) {
      final s = b.result.score.compareTo(a.result.score);
      return s != 0 ? s : a.i.compareTo(b.i);
    });
  return [for (final r in ranked) r.result];
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

double _score(
  DictEntry e,
  double quality,
  Map<String, int> freqMap,
  Map<String, int> homographDefs,
  RankingWeights w,
) {
  // Frequency belongs to the written word, not to one reading of it. The
  // reading with the most definitions gets it in full, others in proportion;
  // proper nouns (surname Hong) are names, not what an English search means.
  final most = homographDefs[e.simplified] ?? e.definitions.length;
  var share = math.min(1.0, e.definitions.length / most);
  if (_isProperNoun(e)) share *= 0.5;
  return w.quality * quality +
      w.commonness * _commonness(e, freqMap) * share +
      w.shortness / e.simplified.length;
}

/// 0–1: 1 for the most frequent words and HSK level 1, 0 for unranked.
double _commonness(DictEntry e, Map<String, int> freqMap) {
  final rank = freqMap[e.simplified] ?? freqMap[e.traditional];
  final byFreq = rank == null
      ? 0.0
      : (1 - math.log(rank) / math.log(100000)).clamp(0.0, 1.0);
  final level = kHskLevel[e.simplified] ?? kHskLevel[e.traditional];
  final byHsk = level == null ? 0.0 : 1 - (level - 1) / 6;
  return math.max(byFreq, byHsk);
}

List<DictEntry>? _homographEntries;
Map<String, int> _homographTotals = const {};

bool _isProperNoun(DictEntry e) =>
    e.pinyin.isNotEmpty && e.pinyin[0] != e.pinyin[0].toLowerCase();

/// Largest definition count among the common-noun entries sharing each
/// simplified form, cached for the last dictionary seen.
Map<String, int> _homographDefs(List<DictEntry> entries) {
  if (!identical(entries, _homographEntries)) {
    final totals = <String, int>{};
    for (final e in entries) {
      if (_isProperNoun(e)) continue;
      totals[e.simplified] =
          math.max(totals[e.simplified] ?? 0, e.definitions.length);
    }
    _homographEntries = entries;
    _homographTotals = totals;
  }
  return _homographTotals;
}

// ---------------------------------------------------------------------------
// Hanzi search
// ---------------------------------------------------------------------------

Map<int, double> _searchHanzi(List<DictEntry> entries, String query) {
  final results = <int, double>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e.simplified == query || e.traditional == query) {
      results[i] = 1.0;
    } else if (e.simplified.startsWith(query) ||
        e.traditional.startsWith(query)) {
      results[i] = 0.7;
    } else if (e.simplified.contains(query) || e.traditional.contains(query)) {
      results[i] = 0.4;
    }
  }
  return results;
}

// ---------------------------------------------------------------------------
// Pinyin search
// ---------------------------------------------------------------------------

Map<int, double> _searchPinyin(List<DictEntry> entries, String rawQuery) {
  final query = _normalizeQuery(rawQuery);
  if (query.isEmpty) return {};

  final hasTones = RegExp(r'[1-5?]').hasMatch(query);

  final bool Function(String) exactMatch;
  final bool Function(String) prefixMatch;
  final bool Function(String) containsMatch;

  if (hasTones) {
    final pattern = _toRegexPattern(query);
    exactMatch = RegExp('^$pattern\$').hasMatch;
    prefixMatch = RegExp('^$pattern').hasMatch;
    containsMatch = RegExp(pattern).hasMatch;
  } else {
    exactMatch = (e) => e == query;
    prefixMatch = (e) => e.startsWith(query);
    containsMatch = (e) => e.contains(query);
  }

  // CEDICT encodes ü as "u:". Normalise to bare "u" so that users typing
  // "nuer", "nüer", or "lver" all find 女儿, 旅, etc.
  String flatten(DictEntry e) {
    var s = e.pinyin.toLowerCase().replaceAll(' ', '').replaceAll('u:', 'u');
    if (!hasTones) s = s.replaceAll(RegExp(r'[1-5]'), '');
    return s;
  }

  // Without tones a syllable matches many characters, and the query may be
  // an English word ("run" vs 润 rùn), so the match is less certain.
  final certainty = hasTones ? 1.0 : 0.85;

  final results = <int, double>{};
  for (var i = 0; i < entries.length; i++) {
    final p = flatten(entries[i]);
    if (exactMatch(p)) {
      results[i] = certainty;
    } else if (prefixMatch(p)) {
      results[i] = 0.7 * certainty;
    } else if (containsMatch(p)) {
      results[i] = 0.4 * certainty;
    }
  }
  return results;
}

// ---------------------------------------------------------------------------
// English search
// ---------------------------------------------------------------------------

final _nonWord = RegExp(r'\W+');
final _bracketed = RegExp(r'\([^)]*\)|\[[^\]]*\]');

/// Words that do not identify a meaning on their own. They still count for
/// exact and phrase matches ("go to school"), but not for finding candidates.
const _stopwords = {'to', 'a', 'an', 'the', 'of', 'be', 'sth', 'sb'};

/// Register labels that mark a definition as rare in modern use.
const _rareLabels = [
  '(archaic)', '(literary)', '(old)', '(classical)', '(dialect)',
];

/// Meanings that mention a word without meaning it ("classifier for rivers").
const _indirectPrefixes = [
  'classifier for', 'measure word', 'variant of', 'old variant of',
  'surname', 'used in', 'see ', 'abbr.', 'japanese variant',
];

List<String> _words(String s) =>
    s.toLowerCase().split(_nonWord).where((w) => w.isNotEmpty).toList();

/// Drops a leading "to", the verb marker, so "to eat" equals "eat".
List<String> _stripTo(List<String> words) =>
    words.length > 1 && words.first == 'to' ? words.sublist(1) : words;

Map<int, double> _searchEnglish(
  List<DictEntry> entries,
  String rawQuery,
  WordIndex index,
) {
  final words = _words(rawQuery);
  final query = _stripTo(words);
  final queryIsVerb = query.length < words.length;
  if (query.isEmpty) return {};
  final content = query.where((w) => !_stopwords.contains(w)).toSet();
  if (content.isEmpty) content.addAll(query);

  // Candidates: entries containing any content word, or one as a substring.
  final candidates = <int>{
    for (final w in content) ..._entryIds(index.postingsFor(w)),
  };
  for (final w in content.where((w) => w.length >= 3)) {
    for (var i = 0; i < entries.length; i++) {
      if (index.normStr[i].contains(w)) candidates.add(i);
    }
  }

  return {
    for (final i in candidates)
      i: _englishQuality(entries[i], query, content, queryIsVerb),
  };
}

/// 0–1 quality of [e]'s best meaning for [query]. A meaning is one
/// ';'-separated part of a definition.
double _englishQuality(
  DictEntry e,
  List<String> query,
  Set<String> content,
  bool queryIsVerb,
) {
  // An entry whose only sense is the query (老师 "teacher") matches more
  // exactly than one listing it among many (先生 "teacher; sir; husband…").
  final senses = e.definitions
      .expand((d) => d.split(';'))
      .where((m) => !m.trim().toLowerCase().startsWith('cl:'))
      .length;
  final specificity = 0.95 + 0.05 / math.max(1, senses);

  // An entry led by an archaic or literary sense (那 nuó "(archaic) many")
  // is a rare reading as a whole.
  final rareEntry = e.definitions.isNotEmpty &&
      _rareLabels.any(e.definitions.first.toLowerCase().contains);

  var best = 0.0;
  for (var d = 0; d < e.definitions.length; d++) {
    final def = e.definitions[d].toLowerCase();
    final register = rareEntry || _rareLabels.any(def.contains)
        ? 0.7
        : def.contains('(bound form)') ? 0.9 : 1.0;
    // Earlier definitions are the main senses.
    final position = 1 - math.min(0.15, 0.04 * d);

    for (final raw in def.split(';')) {
      final meaning = raw.trim();
      if (meaning.startsWith('cl:')) continue;
      final indirect = _indirectPrefixes.any(meaning.startsWith) ? 0.5 : 1.0;
      // Bracket text left after labels narrows the meaning:
      // "to drink (alcohol)", "(of a computer etc) to read (data)".
      final unlabeled = meaning
          .replaceAll(RegExp(r'\((sth|sb|sth\.|sb\.|cl:[^)]*)\)'), '')
          .replaceAll('(bound form)', '');
      final unlabeledOther =
          _rareLabels.fold(unlabeled, (s, l) => s.replaceAll(l, ''));
      final qualified = unlabeledOther.contains('(') ? 0.93 : 1.0;
      final words = _words(meaning.replaceAll(_bracketed, ' '));
      final m = _stripTo(words);
      if (m.isEmpty) continue;
      // "water" should prefer the noun over "to water (plants)", and
      // "to run" the verb over "run (of stockings)".
      final partOfSpeech = (m.length < words.length) == queryIsVerb ? 1.0 : 0.9;

      final double base;
      if (_listEquals(m, query)) {
        base = 1.0;
      } else if (_containsRun(m, query)) {
        base = 0.7 + 0.15 * query.length / m.length;
      } else if (content.every(m.contains)) {
        base = 0.55 + 0.15 * content.length / m.length;
      } else {
        continue;
      }
      best = math.max(
          best,
          base * register * indirect * position * specificity * partOfSpeech *
              qualified);
    }
  }
  if (best > 0) return best;

  // No single meaning holds every content word.
  final all = {for (final d in e.definitions) ...tokenizeDef(d)};
  final matched = content.where(all.contains).length;
  if (matched == content.length) return 0.45;
  if (matched > 0) return 0.25 + 0.1 * matched / content.length;
  return 0.15; // substring only
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether [needle] occurs as a contiguous run of words in [hay].
bool _containsRun(List<String> hay, List<String> needle) {
  for (var s = 0; s + needle.length <= hay.length; s++) {
    var k = 0;
    while (k < needle.length && hay[s + k] == needle[k]) {
      k++;
    }
    if (k == needle.length) return true;
  }
  return false;
}

/// Distinct entry ids of ascending [postings], ascending.
List<int> _entryIds(List<int> postings) {
  final ids = <int>[];
  for (final p in postings) {
    final id = p >> _defBits;
    if (ids.isEmpty || ids.last != id) ids.add(id);
  }
  return ids;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Normalise a raw query to the same form used by flatten():
// convert Unicode tone marks → numbered, strip spaces and apostrophes,
// and collapse ü/v → u to match CEDICT's u: normalisation in flatten().
String _normalizeQuery(String raw) =>
    toNumberedPinyin(raw)
        .toLowerCase()
        .replaceAll(RegExp(r"[' ]"), '')
        .replaceAll('ü', 'u')
        .replaceAll('v', 'u'); // v is a common ü substitute on many keyboards

String _toRegexPattern(String query) => query
    .replaceAllMapped(RegExp(r'[.+*^${}()|[\]\\]'), (m) => '\\${m[0]}')
    .replaceAll('?', '[1-5]');
