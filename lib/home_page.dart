import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dict_entry.dart';
import 'menu_sheet.dart';
import 'results_table.dart';
import 'search.dart';
import 'search_history.dart';
import 'search_section.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.entries,
    required this.freqMap,
    required this.wordIndex,
  });

  final List<DictEntry> entries;
  final Map<String, int> freqMap;
  final WordIndex wordIndex;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _searchHanzi = true;
  bool _searchPinyin = true;
  bool _searchEnglish = true;

  HanziFont _font = HanziFont.sans;
  AppTextSize _textSize = AppTextSize.medium;
  bool _toneColors = false;
  bool _showTraditional = false;

  final _controller = TextEditingController();
  Timer? _debounce;
  Timer? _historyTimer;
  bool _searching = false;
  int _searchId = 0;
  List<SearchResult> _results = [];
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final fontIdx = prefs.getInt('font') ?? 0;
    final sizeIdx = prefs.getInt('text_size') ?? 1;
    if (mounted) {
      setState(() {
        _font = HanziFont.values[fontIdx.clamp(0, HanziFont.values.length - 1)];
        _textSize =
            AppTextSize.values[sizeIdx.clamp(0, AppTextSize.values.length - 1)];
        _toneColors = prefs.getBool('tone_colors') ?? false;
        _showTraditional = prefs.getBool('show_traditional') ?? false;
        _history.addAll(prefs.getStringList('history') ?? []);
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('font', _font.index);
    await prefs.setInt('text_size', _textSize.index);
    await prefs.setBool('tone_colors', _toneColors);
    await prefs.setBool('show_traditional', _showTraditional);
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
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _searching = value.trim().isNotEmpty);
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _runSearch(value));
  }

  Future<void> _runSearch(String value) async {
    final query = value.trim();
    final id = ++_searchId;

    if (query.isEmpty) {
      _searching = false;
      _historyTimer?.cancel();
      setState(() => _results = []);
      return;
    }

    final results = await compute(searchIsolate, (
      entries: widget.entries,
      rawQuery: query,
      hanzi: _searchHanzi,
      pinyin: _searchPinyin,
      english: _searchEnglish,
      freqMap: widget.freqMap,
      wordIndex: widget.wordIndex,
    ));

    if (id != _searchId) return;

    _searching = false;
    _historyTimer?.cancel();
    if (results.isNotEmpty) {
      _historyTimer = Timer(const Duration(seconds: 3), () {
        setState(() {
          _history.remove(query);
          _history.insert(0, query);
          if (_history.length > 100) _history.removeLast();
        });
        _saveHistory();
      });
    }
    setState(() => _results = results);
  }

  void _openMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => MenuSheet(
        font: _font,
        textSize: _textSize,
        toneColors: _toneColors,
        showTraditional: _showTraditional,
        onFontChanged: (f) {
          setState(() => _font = f);
          _saveSettings();
        },
        onSizeChanged: (s) {
          setState(() => _textSize = s);
          _saveSettings();
        },
        onToneColorsChanged: (v) {
          setState(() => _toneColors = v);
          _saveSettings();
        },
        onTraditionalChanged: (v) {
          setState(() => _showTraditional = v);
          _saveSettings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(_textSize.scale)),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kRed,
          foregroundColor: Colors.white,
          title: const Text(
            'hansi',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 2,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => _openMenu(context),
              tooltip: 'Menu',
            ),
          ],
        ),
        body: Column(
          children: [
            SearchSection(
              controller: _controller,
              onChanged: _onChanged,
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
                  font: _font,
                  toneColors: _toneColors,
                  showTraditional: _showTraditional,
                ),
              )
            else if (_controller.text.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Text('No results', style: TextStyle(color: Colors.grey)),
              )
            else if (_history.isNotEmpty)
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
        ),
      ),
    );
  }
}
