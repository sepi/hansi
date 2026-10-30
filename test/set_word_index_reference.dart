// Reference copy of the set-based English search that the inverted WordIndex
// replaced. Kept only so tests can check the new index returns exactly the
// same results, tiers and order.
import 'package:hansi/dict_entry.dart';
import 'package:hansi/search.dart';

class SetWordIndex {
  SetWordIndex(List<DictEntry> entries) {
    for (final entry in entries) {
      final sets = entry.definitions.map(tokenizeDef).toList();
      perDef.add(sets);
      combined.add({for (final s in sets) ...s});
      normStr.add(
        entry.definitions.map((d) => d.toLowerCase().replaceAll(';', ' ')).join(' '),
      );
    }
  }

  final perDef = <List<Set<String>>>[];
  final combined = <Set<String>>[];
  final normStr = <String>[];
}

/// The old `_searchEnglish`, verbatim apart from the index type.
List<SearchResult> referenceSearchEnglish(
  List<DictEntry> entries,
  String rawQuery,
  SetWordIndex index,
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

  pass(0, (i) => index.perDef[i].any((s) => words.every(s.contains)));
  pass(1, (i) => words.every(index.combined[i].contains));
  pass(2, (i) => words.any(index.combined[i].contains));
  pass(3, (i) => words.any(index.normStr[i].contains));

  return results;
}
