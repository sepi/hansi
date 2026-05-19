// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dict_entry.dart';
import 'search.dart' as search_lib;

/// Web implementation: no background thread available, so search runs on the
/// main isolate. A single Future yield before each search lets the framework
/// render the loading spinner before the synchronous work begins.
class SearchWorker {
  SearchWorker._({
    required List<DictEntry> entries,
    required Map<String, int> freqMap,
    required search_lib.WordIndex wordIndex,
  })  : _entries = entries,
        _freqMap = freqMap,
        _wordIndex = wordIndex;

  final List<DictEntry> _entries;
  final Map<String, int> _freqMap;
  final search_lib.WordIndex _wordIndex;

  static Future<SearchWorker> create({
    required List<DictEntry> entries,
    required Map<String, int> freqMap,
    required search_lib.WordIndex wordIndex,
  }) async =>
      SearchWorker._(entries: entries, freqMap: freqMap, wordIndex: wordIndex);

  Future<List<search_lib.SearchResult>> search(
    String query, {
    required bool hanzi,
    required bool pinyin,
    required bool english,
  }) =>
      Future(() => search_lib.search(
            _entries,
            query,
            hanzi: hanzi,
            pinyin: pinyin,
            english: english,
            freqMap: _freqMap,
            wordIndex: _wordIndex,
          ));

  void dispose() {}
}
