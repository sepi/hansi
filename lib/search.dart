// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dict_entry.dart';
import 'hsk.dart';
import 'pinyin_utils.dart';

// ---------------------------------------------------------------------------
// Word index — precomputed at boot for fast English lookup
// ---------------------------------------------------------------------------

class WordIndex {
  const WordIndex({
    required this.perDef,
    required this.combined,
    required this.normStr,
  });

  /// Per-entry, per-definition word sets (used for tier-0: all words in one def).
  final List<List<Set<String>>> perDef;

  /// Per-entry union of all definition words (tiers 1 and 2).
  final List<Set<String>> combined;

  /// Per-entry normalized combined string for substring tier-3 fallback.
  final List<String> normStr;
}

Set<String> _tokenizeDef(String def) => def
    .toLowerCase()
    .replaceAll(';', ' ')
    .split(RegExp(r'\W+'))
    .where((w) => w.isNotEmpty)
    .toSet();

/// Builds a [WordIndex] synchronously. Use [loadWordIndex] from
/// asset_loader.dart for the boot-time chunked version with progress.
WordIndex buildWordIndex(List<DictEntry> entries) {
  final perDef = <List<Set<String>>>[];
  final combined = <Set<String>>[];
  final normStr = <String>[];
  for (final entry in entries) {
    final sets = entry.definitions.map(_tokenizeDef).toList();
    perDef.add(sets);
    combined.add({for (final s in sets) ...s});
    normStr.add(
      entry.definitions.map((d) => d.toLowerCase().replaceAll(';', ' ')).join(' '),
    );
  }
  return WordIndex(perDef: perDef, combined: combined, normStr: normStr);
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
    for (final r in _searchEnglish(entries, rawQuery, wordIndex)) {
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

List<SearchResult> _searchEnglish(
  List<DictEntry> entries,
  String rawQuery,
  WordIndex index,
) {
  final words = rawQuery.toLowerCase().trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return [];

  final seen = <DictEntry>{};
  final results = <SearchResult>[];

  void pass(int tier, bool Function(int i) match) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (seen.contains(entry)) continue;
      if (match(i)) {
        seen.add(entry);
        results.add(SearchResult(entry: entry, tier: tier));
      }
    }
  }

  // Tier 0: all query words present in a single definition's word set.
  pass(0, (i) => index.perDef[i].any((s) => words.every(s.contains)));

  // Tier 1: all query words present across all definitions combined.
  pass(1, (i) => words.every(index.combined[i].contains));

  // Tier 2: any query word present as a whole word in any definition.
  pass(2, (i) => words.any(index.combined[i].contains));

  // Tier 3: any query word as a substring in the normalized combined string.
  pass(3, (i) => words.any(index.normStr[i].contains));

  return results;
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
