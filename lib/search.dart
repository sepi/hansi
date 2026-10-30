// SPDX-License-Identifier: AGPL-3.0-or-later
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
  const SearchResult({required this.entry, required this.tier});
  final DictEntry entry;
  final int tier; // lower = better match quality; meaning varies by search mode
}

/// Main entry point. Routes to hanzi or pinyin search based on query content,
/// gated by the [hanzi] and [pinyin] flags from the UI checkboxes.
List<SearchResult> search(
  List<DictEntry> entries,
  String rawQuery, {
  required bool hanzi,
  required bool pinyin,
  required bool english,
  Map<String, int> freqMap = const {},
  required WordIndex wordIndex,
}) {
  if (rawQuery.isEmpty) return [];
  final results = <SearchResult>[];
  final seen = <DictEntry>{};
  if (hanzi) {
    for (final r in _searchHanzi(entries, rawQuery)) {
      if (seen.add(r.entry)) results.add(r);
    }
  }
  if (pinyin) {
    for (final r in _searchPinyin(entries, rawQuery)) {
      if (seen.add(r.entry)) results.add(r);
    }
  }
  if (english) {
    for (final r in searchEnglish(entries, rawQuery, wordIndex)) {
      if (seen.add(r.entry)) results.add(r);
    }
  }
  return _sort(results, freqMap);
}

// ---------------------------------------------------------------------------
// Hanzi search
// ---------------------------------------------------------------------------

List<SearchResult> _searchHanzi(List<DictEntry> entries, String query) {
  final seen = <DictEntry>{};
  final results = <SearchResult>[];

  // Tier 0: exact match — the character/word itself.
  for (final entry in entries) {
    if (entry.simplified == query || entry.traditional == query) {
      seen.add(entry);
      results.add(SearchResult(entry: entry, tier: 0));
    }
  }

  // Tier 1: starts with (non-exact).
  for (final entry in entries) {
    if (seen.contains(entry)) continue;
    if (entry.simplified.startsWith(query) ||
        entry.traditional.startsWith(query)) {
      seen.add(entry);
      results.add(SearchResult(entry: entry, tier: 1));
    }
  }

  // Tier 2: contains anywhere (non-prefix).
  for (final entry in entries) {
    if (seen.contains(entry)) continue;
    if (entry.simplified.contains(query) ||
        entry.traditional.contains(query)) {
      seen.add(entry);
      results.add(SearchResult(entry: entry, tier: 2));
    }
  }

  return results;
}

// ---------------------------------------------------------------------------
// Pinyin search
// ---------------------------------------------------------------------------

List<SearchResult> _searchPinyin(List<DictEntry> entries, String rawQuery) {
  final query = _normalizeQuery(rawQuery);
  if (query.isEmpty) return [];

  final hasTones = RegExp(r'[1-5?]').hasMatch(query);

  final bool Function(String) prefixMatch;
  final bool Function(String) containsMatch;

  if (hasTones) {
    final pattern = _toRegexPattern(query);
    final prefixRe = RegExp('^$pattern');
    final containsRe = RegExp(pattern);
    prefixMatch = prefixRe.hasMatch;
    containsMatch = containsRe.hasMatch;
  } else {
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

  final seen = <DictEntry>{};
  final results = <SearchResult>[];

  for (final entry in entries) {
    if (prefixMatch(flatten(entry))) {
      seen.add(entry);
      results.add(SearchResult(entry: entry, tier: 0));
    }
  }

  for (final entry in entries) {
    if (seen.contains(entry)) continue;
    if (containsMatch(flatten(entry))) {
      seen.add(entry);
      results.add(SearchResult(entry: entry, tier: 1));
    }
  }

  return results;
}

// ---------------------------------------------------------------------------
// English search  (uses precomputed WordIndex — no regex at query time)
// ---------------------------------------------------------------------------

/// Unsorted English matches, grouped by tier and in dictionary order within
/// each tier. Public so tests can compare it before [search] sorts it.
List<SearchResult> searchEnglish(
  List<DictEntry> entries,
  String rawQuery,
  WordIndex index,
) {
  final words = rawQuery.toLowerCase().trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return [];

  final postings = [for (final w in words.toSet()) index.postingsFor(w)];
  final entryLists = [for (final p in postings) _entryIds(p)];

  final seen = Uint8List(entries.length);
  final results = <SearchResult>[];

  void emit(int tier, Iterable<int> ids) {
    for (final i in ids) {
      if (seen[i] != 0) continue;
      seen[i] = 1;
      results.add(SearchResult(entry: entries[i], tier: tier));
    }
  }

  // Tier 0: all query words present in a single definition.
  emit(0, _entryIds(_intersect(postings)));

  // Tier 1: all query words present across all definitions combined.
  emit(1, _intersect(entryLists));

  // Tier 2: any query word present as a whole word in any definition.
  emit(2, _union(entryLists));

  // Tier 3: any query word as a substring in the normalized combined string.
  for (var i = 0; i < entries.length; i++) {
    if (seen[i] == 0 && words.any(index.normStr[i].contains)) emit(3, [i]);
  }

  return results;
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

/// Values present in every one of the ascending [lists], ascending.
List<int> _intersect(List<List<int>> lists) {
  final sorted = [...lists]..sort((a, b) => a.length.compareTo(b.length));
  var acc = sorted.first;
  for (final other in sorted.skip(1)) {
    final next = <int>[];
    var j = 0;
    for (final v in acc) {
      while (j < other.length && other[j] < v) {
        j++;
      }
      if (j == other.length) break;
      if (other[j] == v) next.add(v);
    }
    acc = next;
  }
  return acc;
}

/// Values present in any of the ascending [lists], ascending and distinct.
List<int> _union(List<List<int>> lists) {
  if (lists.length == 1) return lists.first;
  final all = [for (final l in lists) ...l]..sort();
  final out = <int>[];
  for (final v in all) {
    if (out.isEmpty || out.last != v) out.add(v);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _freqUnranked = 99999;

int _freq(DictEntry e, Map<String, int> freqMap) =>
    freqMap[e.simplified] ?? freqMap[e.traditional] ?? _freqUnranked;

int _hsk(DictEntry e) =>
    kHskLevel[e.simplified] ?? kHskLevel[e.traditional] ?? 99;

// Sort priority: tier → HSK level → entry length → character-freq rank →
// first sub-def length.
// Entry length ensures shorter matches beat longer compounds within the same
// tier (e.g. startsWith tier: 好 beats 好吃 beats 好不容易).
// HSK level ensures common vocabulary beats rarer synonyms of equal length.
List<SearchResult> _sort(List<SearchResult> results, Map<String, int> freqMap) {
  results.sort((a, b) {
    final t = a.tier.compareTo(b.tier);
    if (t != 0) return t;
    final len = a.entry.simplified.length.compareTo(b.entry.simplified.length);
    if (len != 0) return len;
    final h = _hsk(a.entry).compareTo(_hsk(b.entry));
    if (h != 0) return h;
    final f = _freq(a.entry, freqMap).compareTo(_freq(b.entry, freqMap));
    if (f != 0) return f;
    // Use text before the first ';' so "pretty; beautiful" competes as "pretty".
    return a.entry.definitions.first.split(';').first.trim().length
        .compareTo(b.entry.definitions.first.split(';').first.trim().length);
  });
  return results;
}

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
