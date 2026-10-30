// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'constants.dart';
import 'example_sentence.dart';
import 'mma_entry.dart';
import 'results_table.dart';
import 'search.dart';
import 'search_history.dart';
import 'search_section.dart';
import 'search_worker.dart';
import 'theme.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.initialQuery,
    required this.worker,
    required this.hskLevels,
    required this.strokeData,
    required this.mmaData,
    required this.sentenceData,
    required this.ankiInstalled,
    required this.settings,
    this.history = const [],
    this.onAddToHistory,
    this.onClearHistory,
  });

  final String initialQuery;
  final SearchWorker worker;
  final Map<String, int> hskLevels;
  final Map<String, String> strokeData;
  final Map<String, MmaEntry> mmaData;
  final SentenceData sentenceData;
  final bool ankiInstalled;
  final AppSettings settings;
  final List<String> history;
  final ValueChanged<String>? onAddToHistory;
  final VoidCallback? onClearHistory;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  bool _searchHanzi = true;
  bool _searchPinyin = true;
  bool _searchEnglish = true;

  final _controller = TextEditingController();
  Timer? _debounce;
  Timer? _historyTimer;
  bool _searching = false;
  int _searchId = 0;
  List<SearchResult> _results = [];
  // The query [_results] were computed for, which can lag the text field.
  String _resultsQuery = '';

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    if (widget.initialQuery.isNotEmpty) {
      _controller.text = widget.initialQuery;
      _searching = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) { if (mounted) _runSearch(widget.initialQuery); },
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _historyTimer?.cancel();
    _controller.dispose();
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _searching = value.trim().isNotEmpty);
    _debounce = Timer(kDebounceDelay, () => _runSearch(value));
  }

  void _onSubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _historyTimer?.cancel();
    widget.onAddToHistory?.call(query);
    setState(() {});
    _runSearch(query);
  }

  Future<void> _runSearch(String value) async {
    final query = value.trim();
    final id = ++_searchId;
    if (query.isEmpty) {
      _historyTimer?.cancel();
      setState(() { _searching = false; _results = []; });
      return;
    }
    final results = await widget.worker.search(
      query,
      hanzi: _searchHanzi,
      pinyin: _searchPinyin,
      english: _searchEnglish,
    );
    if (id != _searchId) return;
    _historyTimer?.cancel();
    if (results.isNotEmpty) {
      _historyTimer = Timer(kHistoryAddDelay, () {
        widget.onAddToHistory?.call(query);
        if (mounted) setState(() {});
      });
    }
    setState(() {
      _searching = false;
      _results = results;
      _resultsQuery = query;
    });
  }

  void _onSearch(String q) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchPage(
        initialQuery: q,
        worker: widget.worker,
        hskLevels: widget.hskLevels,
        strokeData: widget.strokeData,
        mmaData: widget.mmaData,
        sentenceData: widget.sentenceData,
        ankiInstalled: widget.ankiInstalled,
        settings: widget.settings,
        history: widget.history,
        onAddToHistory: widget.onAddToHistory,
        onClearHistory: widget.onClearHistory,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final showHistory =
        !_searching && _results.isEmpty && _controller.text.trim().isEmpty && widget.history.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        title: Image.asset('assets/hansi.png', height: 34),
        centerTitle: true,
        actions: [
          SettingsButton(
              settings: widget.settings, ankiInstalled: widget.ankiInstalled),
        ],
      ),
      body: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(widget.settings.textSize.scale)),
        child: Column(
          children: [
            SearchSection(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
              searchHanzi: _searchHanzi,
              searchPinyin: _searchPinyin,
              searchEnglish: _searchEnglish,
              onHanziChanged: (v) {
                setState(() => _searchHanzi = v);
                _runSearch(_controller.text);
              },
              onPinyinChanged: (v) {
                setState(() => _searchPinyin = v);
                _runSearch(_controller.text);
              },
              onEnglishChanged: (v) {
                setState(() => _searchEnglish = v);
                _runSearch(_controller.text);
              },
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: CircularProgressIndicator(color: kRed),
              )
            else if (_results.isNotEmpty)
              Expanded(
                child: ResultsTable(
                  results: _results,
                  font: widget.settings.font,
                  toneColors: widget.settings.toneColors,
                  showTraditional: widget.settings.showTraditional,
                  hskLevels: widget.hskLevels,
                  strokeData: widget.strokeData,
                  mmaData: widget.mmaData,
                  strokeSpeed: widget.settings.strokeSpeed,
                  onSearch: _onSearch,
                  ankiInstalled: widget.ankiInstalled,
                  sentenceData: widget.sentenceData,
                  highlightQuery: _searchEnglish ? _resultsQuery : '',
                ),
              )
            else if (_controller.text.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Text('No results', style: TextStyle(color: Colors.grey)),
              )
            else if (showHistory)
              Expanded(
                child: SearchHistory(
                  history: widget.history,
                  onSelect: (q) {
                    _controller.text = q;
                    _runSearch(q);
                  },
                  onClear: () {
                    widget.onClearHistory?.call();
                    setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
