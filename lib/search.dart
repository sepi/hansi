// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dict_entry.dart';
import 'pinyin_utils.dart';
import 'words.dart';

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

Set<String> tokenizeDef(String def) => words(def).toSet();

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
    _normStr.add(_normalizedDefs(entry));
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

/// An entry's definitions, lowercased and joined, for substring matching.
String _normalizedDefs(DictEntry e) => foldText(e.definitions.join(' '));

// ---------------------------------------------------------------------------
// Prebuilt index file (assets/word_index.bin, written by tool/build_index.dart)
// ---------------------------------------------------------------------------
//
// Little-endian int32 word count, posting count and word-list byte length,
// then the words as UTF-8 joined by '\n', then wordStart and postings as
// int32. normStr is not stored: it is cheap to derive from the entries.
// The file must be rebuilt whenever cedict.txt.gz or the tokenizer changes.

Uint8List encodeWordIndex(WordIndex index) {
  final words = utf8.encode(index.words.join('\n'));
  final ints = index.wordStart.length + index.postings.length;
  final out = ByteData(12 + words.length + 4 * ints)
    ..setInt32(0, index.words.length, Endian.little)
    ..setInt32(4, index.postings.length, Endian.little)
    ..setInt32(8, words.length, Endian.little);
  final bytes = out.buffer.asUint8List()..setAll(12, words);
  var at = 12 + words.length;
  for (final list in [index.wordStart, index.postings]) {
    for (final v in list) {
      out.setInt32(at, v, Endian.little);
      at += 4;
    }
  }
  return bytes;
}

/// Reads an index written by [encodeWordIndex] for the same [entries].
WordIndex decodeWordIndex(ByteData data, List<DictEntry> entries) {
  final wordCount = data.getInt32(0, Endian.little);
  final postingCount = data.getInt32(4, Endian.little);
  final wordBytes = data.getInt32(8, Endian.little);
  final words = utf8
      .decode(data.buffer.asUint8List(data.offsetInBytes + 12, wordBytes))
      .split('\n');
  var at = 12 + wordBytes;
  Int32List readInts(int n) {
    // Copied rather than viewed, so the asset needs no alignment.
    final list = Int32List(n);
    for (var i = 0; i < n; i++, at += 4) {
      list[i] = data.getInt32(at, Endian.little);
    }
    return list;
  }

  final wordStart = readInts(wordCount + 1);
  final postings = readInts(postingCount);
  return WordIndex(
    words: words,
    wordStart: wordStart,
    postings: postings,
    normStr: [for (final e in entries) _normalizedDefs(e)],
  );
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

/// Every constant of the ranking, in one place.
///
/// ```
/// score      = quality × matchQuality
///            + commonness × commonness(entry) × share(entry)
///            + shortness ÷ characters
/// ```
///
/// Match quality (0–1) is computed per search mode; an entry found by
/// several modes keeps its best. It dominates the score, so a common word
/// with a weak match cannot outrank an exact match; commonness reorders
/// matches of similar quality; shortness is a tiebreak.
class RankingWeights {
  const RankingWeights({
    this.quality = 1.0,
    this.commonness = 0.3,
    this.shortness = 0.05,
    this.frequencyRanks = 100000,
    this.hskTop = 0.8,
    this.hskStep = 0.1,
    this.properNounShare = 0.5,
    this.exact = 1.0,
    this.prefix = 0.7,
    this.contains = 0.4,
    this.toneless = 0.85,
    this.phrase = 0.7,
    this.phraseCoverage = 0.15,
    this.allWords = 0.55,
    this.allWordsCoverage = 0.15,
    this.spreadWords = 0.45,
    this.someWords = 0.25,
    this.someWordsCoverage = 0.1,
    this.substring = 0.15,
    this.rareRegister = 0.7,
    this.boundForm = 0.9,
    this.indirect = 0.5,
    this.positionStep = 0.05,
    this.positionMax = 0.2,
    this.specificity = 0.05,
    this.partOfSpeech = 0.9,
    this.qualified = 0.93,
  });

  // ── Score ────────────────────────────────────────────────────────────────
  final double quality;
  final double commonness;
  final double shortness;

  // ── Commonness (0–1) and share ───────────────────────────────────────────
  /// Frequency rank that scores 0; rank 1 scores 1, on a log scale.
  final double frequencyRanks;

  /// Commonness from an HSK level alone: [hskTop] at level 1, minus
  /// [hskStep] per level. Kept below 1 so being on a learner list does not
  /// outweigh being a much better match.
  final double hskTop;
  final double hskStep;

  /// Frequency belongs to the written word, not to one reading of it: the
  /// reading with the most definitions gets it in full, others in
  /// proportion, and proper nouns (surname Hong) this much on top.
  final double properNounShare;

  // ── Hanzi and pinyin match quality ───────────────────────────────────────
  /// The entry's characters or pinyin equal / start with / contain the query.
  final double exact;
  final double prefix;
  final double contains;

  /// Multiplier for pinyin typed without tones: a toneless syllable matches
  /// many characters, and may be an English word ("run" vs 润 rùn).
  final double toneless;

  // ── English match quality: how the best meaning matches ─────────────────
  // A meaning is one ';'-separated part of a definition. Coverage is the
  // share of the meaning's words that the query accounts for.

  /// Query is a contiguous run of words in the meaning ("river bank"):
  /// [phrase] + [phraseCoverage] × coverage.
  final double phrase;
  final double phraseCoverage;

  /// All query words in the meaning, in any order:
  /// [allWords] + [allWordsCoverage] × coverage.
  final double allWords;
  final double allWordsCoverage;

  /// Fallbacks when no single meaning holds every query word: all words
  /// spread over the entry's meanings; some words
  /// ([someWords] + [someWordsCoverage] × share of words found); a query word
  /// only as part of a longer word.
  final double spreadWords;
  final double someWords;
  final double someWordsCoverage;
  final double substring;

  // ── English match quality: multipliers on the best meaning ──────────────
  /// Definition labelled (archaic), (literary), (old), (classical) or
  /// (dialect), or an entry whose first definition is.
  final double rareRegister;

  /// Definition labelled (bound form).
  final double boundForm;

  /// Meaning that mentions a word without meaning it ("classifier for
  /// rivers", "variant of", "surname").
  final double indirect;

  /// Later definitions are lesser senses: 1 − min([positionMax],
  /// [positionStep] × definition number).
  final double positionStep;
  final double positionMax;

  /// Entries with fewer senses match more exactly (老师 "teacher" vs 先生
  /// "teacher; sir; husband…"): 1 − [specificity] + [specificity] ÷ senses.
  final double specificity;

  /// Only one of query and meaning starts with the verb marker "to"
  /// ("water" vs "to water (plants)").
  final double partOfSpeech;

  /// Bracket text narrows the meaning ("to drink (alcohol)").
  final double qualified;
}

/// Records one named factor of a score.
typedef _Note = void Function(String factor, double value);

/// Main entry point. Each enabled mode reports a match quality per entry;
/// an entry matched by several modes keeps its best quality.
List<SearchResult> search(
  List<DictEntry> entries,
  String rawQuery, {
  required bool hanzi,
  required bool pinyin,
  required bool english,
  Map<String, int> freqMap = const {},
  Map<String, int> hskLevels = const {},
  required WordIndex wordIndex,
  RankingWeights weights = const RankingWeights(),
}) {
  if (rawQuery.trim().isEmpty) return [];
  final quality = <int, double>{};
  void merge(int i, double q) {
    if (q > (quality[i] ?? 0)) quality[i] = q;
  }

  if (hanzi) {
    for (var i = 0; i < entries.length; i++) {
      final q = _hanziQuality(entries[i], rawQuery, weights);
      if (q > 0) merge(i, q);
    }
  }
  final pinyinQuery = pinyin ? _PinyinQuery.parse(rawQuery) : null;
  if (pinyinQuery != null) {
    for (var i = 0; i < entries.length; i++) {
      final q = pinyinQuery.quality(entries[i], weights);
      if (q > 0) merge(i, q);
    }
  }
  final englishQuery = english ? _EnglishQuery.parse(rawQuery) : null;
  if (englishQuery != null) {
    for (final i in englishQuery.candidates(entries, wordIndex)) {
      merge(i, englishQuery.quality(entries[i], weights));
    }
  }

  final homographDefs = _homographDefs(entries);
  final ranked = [
    for (final MapEntry(key: i, value: q) in quality.entries)
      (i: i, result: SearchResult(
        entry: entries[i],
        quality: q,
        score: _scoreParts(
                entries[i], q, freqMap, hskLevels, homographDefs, weights)
            .score,
      )),
  ]..sort((a, b) {
      final s = b.result.score.compareTo(a.result.score);
      return s != 0 ? s : a.i.compareTo(b.i);
    });
  return [for (final r in ranked) r.result];
}

// ---------------------------------------------------------------------------
// Explaining a score
// ---------------------------------------------------------------------------

/// Why an entry scored what it did, factor by factor.
class ScoreExplanation {
  const ScoreExplanation({
    required this.mode,
    required this.qualityFactors,
    required this.quality,
    required this.commonness,
    required this.share,
    required this.characters,
    required this.score,
    required this.weights,
  });

  /// The mode that gave the best match: 'hanzi', 'pinyin' or 'english'.
  final String mode;

  /// The named factors whose product (or, for a fallback, value) is
  /// [quality].
  final List<(String, double)> qualityFactors;
  final double quality;
  final double commonness;
  final double share;
  final int characters;
  final double score;
  final RankingWeights weights;

  @override
  String toString() {
    String n(double v) => v.toStringAsFixed(3);
    // The first factor is the kind of match; neutral multipliers are hidden.
    final factors = [
      for (final (i, f) in qualityFactors.indexed)
        if (i == 0 || f.$2 != 1.0) '${f.$1} ${n(f.$2)}',
    ].join(' × ');
    final w = weights;
    return 'score ${n(score)} = ${w.quality} × quality ${n(quality)} '
        '[$mode $factors]'
        ' + ${w.commonness} × commonness ${n(commonness)} × share ${n(share)}'
        ' + ${w.shortness} ÷ $characters chars';
  }
}

/// Recomputes [entry]'s score for [rawQuery] with each factor recorded,
/// or returns null if no enabled mode matches it. Arguments are as for
/// [search]; [entry] must be an element of [entries].
ScoreExplanation? explainScore(
  List<DictEntry> entries,
  DictEntry entry,
  String rawQuery, {
  bool hanzi = true,
  bool pinyin = true,
  bool english = true,
  Map<String, int> freqMap = const {},
  Map<String, int> hskLevels = const {},
  required WordIndex wordIndex,
  RankingWeights weights = const RankingWeights(),
}) {
  final i = entries.indexOf(entry);
  if (i < 0 || rawQuery.trim().isEmpty) return null;

  var best = 0.0;
  var mode = '';
  var factors = <(String, double)>[];
  void tryMode(String name, double Function(_Note note) quality) {
    final notes = <(String, double)>[];
    final q = quality((f, v) => notes.add((f, v)));
    if (q > best) {
      best = q;
      mode = name;
      factors = notes;
    }
  }

  if (hanzi) {
    tryMode('hanzi', (note) => _hanziQuality(entry, rawQuery, weights, note));
  }
  final pinyinQuery = pinyin ? _PinyinQuery.parse(rawQuery) : null;
  if (pinyinQuery != null) {
    tryMode('pinyin', (note) => pinyinQuery.quality(entry, weights, note));
  }
  final englishQuery = english ? _EnglishQuery.parse(rawQuery) : null;
  if (englishQuery != null && englishQuery.isCandidate(i, entry, wordIndex)) {
    tryMode('english', (note) => englishQuery.quality(entry, weights, note));
  }
  if (best == 0) return null;

  final parts = _scoreParts(
      entry, best, freqMap, hskLevels, _homographDefs(entries), weights);
  return ScoreExplanation(
    mode: mode,
    qualityFactors: factors,
    quality: best,
    commonness: parts.commonness,
    share: parts.share,
    characters: entry.simplified.length,
    score: parts.score,
    weights: weights,
  );
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

({double commonness, double share, double score}) _scoreParts(
  DictEntry e,
  double quality,
  Map<String, int> freqMap,
  Map<String, int> hskLevels,
  Map<String, int> homographDefs,
  RankingWeights w,
) {
  final most = homographDefs[e.simplified] ?? e.definitions.length;
  var share = math.min(1.0, e.definitions.length / most);
  if (_isProperNoun(e)) share *= w.properNounShare;
  final commonness = _commonness(e, freqMap, hskLevels, w);
  return (
    commonness: commonness,
    share: share,
    score: w.quality * quality +
        w.commonness * commonness * share +
        w.shortness / e.simplified.length,
  );
}

/// 0–1: 1 for the most frequent words, 0 for unranked.
double _commonness(DictEntry e, Map<String, int> freqMap,
    Map<String, int> hskLevels, RankingWeights w) {
  final rank = freqMap[e.simplified] ?? freqMap[e.traditional];
  final byFreq = rank == null
      ? 0.0
      : (1 - math.log(rank) / math.log(w.frequencyRanks)).clamp(0.0, 1.0);
  final level = hskLevels[e.simplified] ?? hskLevels[e.traditional];
  final byHsk = level == null ? 0.0 : w.hskTop - w.hskStep * (level - 1);
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

double _hanziQuality(DictEntry e, String query, RankingWeights w,
    [_Note? note]) {
  final String kind;
  final double q;
  if (e.simplified == query || e.traditional == query) {
    (kind, q) = ('exact', w.exact);
  } else if (e.simplified.startsWith(query) ||
      e.traditional.startsWith(query)) {
    (kind, q) = ('prefix', w.prefix);
  } else if (e.simplified.contains(query) || e.traditional.contains(query)) {
    (kind, q) = ('contains', w.contains);
  } else {
    return 0;
  }
  note?.call(kind, q);
  return q;
}

// ---------------------------------------------------------------------------
// Pinyin search
// ---------------------------------------------------------------------------

final _toneDigit = RegExp(r'[1-5]');

/// A pinyin query, parsed once and matched against each entry.
class _PinyinQuery {
  _PinyinQuery._(this.query)
      : hasTones = RegExp(r'[1-5?]').hasMatch(query),
        // Typing ü (or v) asks for ü specifically; a plain u matches both,
        // since many people type "nu" for 女 nǚ.
        strictU = query.contains('ü') {
    if (hasTones) {
      final pattern = _toRegexPattern(query);
      _exact = RegExp('^$pattern\$').hasMatch;
      _prefix = RegExp('^$pattern').hasMatch;
      _contains = RegExp(pattern).hasMatch;
    } else {
      _exact = (p) => p == query;
      _prefix = (p) => p.startsWith(query);
      _contains = (p) => p.contains(query);
    }
  }

  static _PinyinQuery? parse(String rawQuery) {
    final query = _normalizeQuery(rawQuery);
    return query.isEmpty ? null : _PinyinQuery._(query);
  }

  final String query;
  final bool hasTones;
  final bool strictU;
  late final bool Function(String) _exact;
  late final bool Function(String) _prefix;
  late final bool Function(String) _contains;

  // CEDICT encodes ü as "u:".
  String _flatten(DictEntry e) {
    var s = e.pinyin
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('u:', strictU ? 'ü' : 'u');
    if (!hasTones) s = s.replaceAll(_toneDigit, '');
    return s;
  }

  double quality(DictEntry e, RankingWeights w, [_Note? note]) {
    final p = _flatten(e);
    final String kind;
    final double q;
    if (_exact(p)) {
      (kind, q) = ('exact', w.exact);
    } else if (_prefix(p)) {
      (kind, q) = ('prefix', w.prefix);
    } else if (_contains(p)) {
      (kind, q) = ('contains', w.contains);
    } else {
      return 0;
    }
    final certainty = hasTones ? 1.0 : w.toneless;
    note?.call(kind, q);
    note?.call('toneless', certainty);
    return q * certainty;
  }
}

// ---------------------------------------------------------------------------
// English search
// ---------------------------------------------------------------------------

final _bracketed = RegExp(r'\([^)]*\)|\[[^\]]*\]');
final _neutralBrackets = RegExp(r'\((sth|sb|sth\.|sb\.|cl:[^)]*)\)');

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

/// Drops a leading "to", the verb marker, so "to eat" equals "eat".
List<String> _stripTo(List<String> words) =>
    words.length > 1 && words.first == 'to' ? words.sublist(1) : words;

/// An English query, parsed once and matched against candidate entries.
class _EnglishQuery {
  _EnglishQuery._(this.query, this.content, this.isVerb);

  static _EnglishQuery? parse(String rawQuery) {
    final all = words(rawQuery);
    final query = _stripTo(all);
    if (query.isEmpty) return null;
    final content = query.where((w) => !_stopwords.contains(w)).toSet();
    if (content.isEmpty) content.addAll(query);
    return _EnglishQuery._(query, content, query.length < all.length);
  }

  /// Query words, without a leading "to".
  final List<String> query;

  /// Query words that identify a meaning (no stopwords, unless that is all
  /// there is).
  final Set<String> content;

  /// Whether the query started with "to".
  final bool isVerb;

  /// Entries containing a content word, or one of 3+ letters as a substring.
  Set<int> candidates(List<DictEntry> entries, WordIndex index) {
    final ids = <int>{
      for (final w in content) ..._entryIds(index.postingsFor(w)),
    };
    for (final w in content.where((w) => w.length >= 3)) {
      for (var i = 0; i < entries.length; i++) {
        if (index.normStr[i].contains(w)) ids.add(i);
      }
    }
    return ids;
  }

  /// Whether entry [i] is one of [candidates], without scanning them all.
  bool isCandidate(int i, DictEntry e, WordIndex index) {
    final words = {for (final d in e.definitions) ...tokenizeDef(d)};
    return content.any((w) =>
        words.contains(w) || (w.length >= 3 && index.normStr[i].contains(w)));
  }

  /// 0–1 quality of [e]'s best meaning.
  double quality(DictEntry e, RankingWeights w, [_Note? note]) {
    final senses = e.definitions
        .expand((d) => d.split(';'))
        .where((m) => !m.trim().toLowerCase().startsWith('cl:'))
        .length;
    final double specificity =
        1 - w.specificity + w.specificity / math.max(1, senses);

    // An entry led by an archaic or literary sense (那 nuó "(archaic) many")
    // is a rare reading as a whole.
    final rareEntry = e.definitions.isNotEmpty &&
        _rareLabels.any(e.definitions.first.toLowerCase().contains);

    var best = 0.0;
    List<(String, double)>? bestFactors;
    for (var d = 0; d < e.definitions.length; d++) {
      final def = e.definitions[d].toLowerCase();
      final register = rareEntry || _rareLabels.any(def.contains)
          ? w.rareRegister
          : def.contains('(bound form)') ? w.boundForm : 1.0;
      final double position =
          1 - math.min(w.positionMax, w.positionStep * d);

      for (final raw in def.split(';')) {
        final meaning = raw.trim();
        if (meaning.startsWith('cl:')) continue;
        final indirect =
            _indirectPrefixes.any(meaning.startsWith) ? w.indirect : 1.0;
        final unlabeled = _rareLabels.fold(
            meaning
                .replaceAll(_neutralBrackets, '')
                .replaceAll('(bound form)', ''),
            (s, l) => s.replaceAll(l, ''));
        final qualified = unlabeled.contains('(') ? w.qualified : 1.0;
        final all = words(meaning.replaceAll(_bracketed, ' '));
        final m = _stripTo(all);
        if (m.isEmpty) continue;
        final partOfSpeech =
            (m.length < all.length) == isVerb ? 1.0 : w.partOfSpeech;

        final String kind;
        final double base;
        if (_listEquals(m, query)) {
          (kind, base) = ('exact', w.exact);
        } else if (_containsRun(m, query)) {
          (kind, base) =
              ('phrase', w.phrase + w.phraseCoverage * query.length / m.length);
        } else if (content.every(m.contains)) {
          (kind, base) = (
            'all words',
            w.allWords + w.allWordsCoverage * content.length / m.length,
          );
        } else {
          continue;
        }
        final q = base *
            register *
            indirect *
            position *
            specificity *
            partOfSpeech *
            qualified;
        if (q > best) {
          best = q;
          if (note != null) {
            bestFactors = [
              (kind, base), ('register', register), ('indirect', indirect),
              ('position', position), ('specificity', specificity),
              ('part of speech', partOfSpeech), ('qualified', qualified),
            ];
          }
        }
      }
    }
    if (best > 0) {
      bestFactors?.forEach((f) => note!(f.$1, f.$2));
      return best;
    }

    // No single meaning holds every content word.
    final all = {for (final d in e.definitions) ...tokenizeDef(d)};
    final matched = content.where(all.contains).length;
    final String kind;
    final double q;
    if (matched == content.length) {
      (kind, q) = ('spread words', w.spreadWords);
    } else if (matched > 0) {
      (kind, q) = (
        'some words',
        w.someWords + w.someWordsCoverage * matched / content.length,
      );
    } else {
      (kind, q) = ('substring', w.substring);
    }
    note?.call(kind, q);
    return q;
  }
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
// and read v as ü (a common substitute on keyboards without ü).
String _normalizeQuery(String raw) =>
    toNumberedPinyin(raw)
        .toLowerCase()
        .replaceAll(RegExp(r"[' ]"), '')
        .replaceAll('v', 'ü');

String _toRegexPattern(String query) => query
    .replaceAllMapped(RegExp(r'[.+*^${}()|[\]\\]'), (m) => '\\${m[0]}')
    .replaceAll('?', '[1-5]');
