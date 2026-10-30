// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:isolate';

import 'dict_entry.dart';
import 'search.dart';

/// Native implementation: persistent background isolate.
/// The full dictionary is copied across the isolate boundary once at creation;
/// every subsequent search sends only a tiny query record.
class SearchWorker {
  SearchWorker._({
    required SendPort toIsolate,
    required ReceivePort fromIsolate,
    required Isolate isolate,
  })  : _toIsolate = toIsolate,
        _fromIsolate = fromIsolate,
        _isolate = isolate;

  final SendPort _toIsolate;
  final ReceivePort _fromIsolate;
  final Isolate _isolate;
  final _pending = <int, Completer<List<SearchResult>>>{};
  int _nextId = 0;

  static Future<SearchWorker> create({
    required List<DictEntry> entries,
    required Map<String, int> freqMap,
    required Map<String, int> hskLevels,
    required WordIndex wordIndex,
  }) async {
    final fromIsolate = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, fromIsolate.sendPort);
    final stream = fromIsolate.asBroadcastStream();

    final toIsolate = await stream.first as SendPort;
    toIsolate.send((
      entries: entries,
      freqMap: freqMap,
      hskLevels: hskLevels,
      wordIndex: wordIndex,
    ));

    final worker = SearchWorker._(
      toIsolate: toIsolate,
      fromIsolate: fromIsolate,
      isolate: isolate,
    );
    stream.listen((msg) {
      final (:int id, :List<SearchResult> results) =
          msg as ({int id, List<SearchResult> results});
      worker._pending.remove(id)?.complete(results);
    });
    return worker;
  }

  Future<List<SearchResult>> search(
    String query, {
    required bool hanzi,
    required bool pinyin,
    required bool english,
  }) {
    final id = _nextId++;
    final completer = Completer<List<SearchResult>>();
    _pending[id] = completer;
    _toIsolate.send((
      id: id,
      query: query,
      hanzi: hanzi,
      pinyin: pinyin,
      english: english,
    ));
    return completer.future;
  }

  void dispose() {
    _fromIsolate.close();
    _isolate.kill();
  }
}

void _workerMain(SendPort toMain) {
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);

  List<DictEntry>? entries;
  Map<String, int>? freqMap;
  Map<String, int>? hskLevels;
  WordIndex? wordIndex;

  fromMain.listen((msg) {
    if (entries == null) {
      final init = msg as ({
        List<DictEntry> entries,
        Map<String, int> freqMap,
        Map<String, int> hskLevels,
        WordIndex wordIndex,
      });
      entries = init.entries;
      freqMap = init.freqMap;
      hskLevels = init.hskLevels;
      wordIndex = init.wordIndex;
      return;
    }
    final q = msg as ({
      int id,
      String query,
      bool hanzi,
      bool pinyin,
      bool english,
    });
    final results = search(
      entries!,
      q.query,
      hanzi: q.hanzi,
      pinyin: q.pinyin,
      english: q.english,
      freqMap: freqMap!,
      hskLevels: hskLevels!,
      wordIndex: wordIndex!,
    );
    toMain.send((id: q.id, results: results));
  });
}
