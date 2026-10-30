// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anki_service.dart';
import 'app_settings.dart';
import 'constants.dart';
import 'dict_entry.dart';
import 'example_sentence.dart';
import 'idiom_card.dart';
import 'mma_entry.dart';
import 'results_table.dart';
import 'search.dart';
import 'search_history.dart';
import 'search_page.dart';
import 'search_section.dart';
import 'search_worker.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.worker,
    required this.hskLevels,
    required this.idioms,
    required this.strokeData,
    required this.mmaData,
    required this.sentenceData,
  });

  final SearchWorker worker;
  final Map<String, int> hskLevels;

  /// Pool for the idiom-of-the-day card; empty hides it.
  final List<DictEntry> idioms;
  final Map<String, String> strokeData;
  final Map<String, MmaEntry> mmaData;
  final SentenceData sentenceData;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _searchHanzi = true;
  bool _searchPinyin = true;
  bool _searchEnglish = true;

  final _settings = AppSettings();

  bool _ankiInstalled = false;

  final _controller = TextEditingController();
  Timer? _debounce;
  Timer? _historyTimer;
  bool _searching = false;
  int _searchId = 0;
  List<SearchResult> _results = [];
  // The query [_results] were computed for, which can lag the text field.
  String _resultsQuery = '';
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _settings
      ..addListener(_onSettingsChanged)
      ..load();
    _loadHistory();
    AnkiService.instance.isInstalled.then((v) {
      if (mounted) setState(() => _ankiInstalled = v);
    });
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _history.addAll(prefs.getStringList('history') ?? []));
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('history', _history);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _historyTimer?.cancel();
    _controller.dispose();
    _settings.dispose();
    super.dispose();
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
    _addToHistory(query);
    _runSearch(query);
  }

  void _addToHistory(String query) {
    setState(() {
      _history.remove(query);
      _history.insert(0, query);
      if (_history.length > kMaxHistory) _history.removeLast();
    });
    _saveHistory();
  }

  Future<void> _runSearch(String value) async {
    final query = value.trim();
    final id = ++_searchId;

    if (query.isEmpty) {
      _historyTimer?.cancel();
      setState(() {
        _searching = false;
        _results = [];
      });
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
      _historyTimer = Timer(kHistoryAddDelay, () => _addToHistory(query));
    }
    setState(() {
      _searching = false;
      _results = results;
      _resultsQuery = query;
    });
  }

  Widget _idiomCard() {
    final idiom = idiomOfTheDay(widget.idioms, DateTime.now());
    return IdiomCard(
      entry: idiom,
      font: _settings.font,
      toneColors: _settings.toneColors,
      showTraditional: _settings.showTraditional,
      onTap: () {
        _controller.text = idiom.simplified;
        _runSearch(idiom.simplified);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        title: Image.asset('assets/hansi.png', height: 34),
        centerTitle: true,
        actions: [
          SettingsButton(settings: _settings, ankiInstalled: _ankiInstalled),
        ],
      ),
      body: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(_settings.textSize.scale)),
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
                  font: _settings.font,
                  toneColors: _settings.toneColors,
                  showTraditional: _settings.showTraditional,
                  hskLevels: widget.hskLevels,
                  strokeData: widget.strokeData,
                  mmaData: widget.mmaData,
                  strokeSpeed: _settings.strokeSpeed,
                  onSearch: (q) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SearchPage(
                        initialQuery: q,
                        worker: widget.worker,
                        hskLevels: widget.hskLevels,
                        strokeData: widget.strokeData,
                        mmaData: widget.mmaData,
                        sentenceData: widget.sentenceData,
                        ankiInstalled: _ankiInstalled,
                        settings: _settings,
                        history: _history,
                        onAddToHistory: _addToHistory,
                        onClearHistory: () {
                          setState(() => _history.clear());
                          _saveHistory();
                        },
                      ),
                    ),
                  ),
                  ankiInstalled: _ankiInstalled,
                  sentenceData: widget.sentenceData,
                  highlightQuery: _searchEnglish ? _resultsQuery : '',
                ),
              )
            else if (_controller.text.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Text('No results', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              if (widget.idioms.isNotEmpty) _idiomCard(),
              if (_history.isNotEmpty)
                Expanded(
                  child: SearchHistory(
                    history: _history,
                    onSelect: (q) {
                      _controller.text = q;
                      _runSearch(q);
                    },
                    onClear: () {
                      setState(() => _history.clear());
                      _saveHistory();
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

