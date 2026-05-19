// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'menu_sheet.dart';
import 'mma_entry.dart';
import 'results_table.dart';
import 'search.dart';
import 'search_history.dart';
import 'search_section.dart';
import 'search_worker.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.worker,
    required this.strokeData,
    required this.mmaData,
  });

  final SearchWorker worker;
  final Map<String, String> strokeData;
  final Map<String, MmaEntry> mmaData;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _searchHanzi = true;
  bool _searchPinyin = true;
  bool _searchEnglish = true;

  HanziFont _font = HanziFont.sans;
  AppTextSize _textSize = AppTextSize.md;
  bool _toneColors = false;
  bool _showTraditional = false;
  double _strokeSpeed = 1.2;

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
    final sizeIdx = prefs.getInt('text_size') ?? 2;
    if (mounted) {
      setState(() {
        _font = HanziFont.values[fontIdx.clamp(0, HanziFont.values.length - 1)];
        _textSize =
            AppTextSize.values[sizeIdx.clamp(0, AppTextSize.values.length - 1)];
        _toneColors = prefs.getBool('tone_colors') ?? false;
        _showTraditional = prefs.getBool('show_traditional') ?? false;
        _strokeSpeed = prefs.getDouble('stroke_speed') ?? 1.2;
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
    await prefs.setDouble('stroke_speed', _strokeSpeed);
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
      _historyTimer = Timer(const Duration(seconds: 3), () {
        setState(() {
          _history.remove(query);
          _history.insert(0, query);
          if (_history.length > 100) _history.removeLast();
        });
        _saveHistory();
      });
    }
    setState(() {
      _searching = false;
      _results = results;
    });
  }

  void _openMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
        strokeSpeed: _strokeSpeed,
        onStrokeSpeedChanged: (v) {
          setState(() => _strokeSpeed = v);
          _saveSettings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        title: Image.asset('assets/hansi.png', height: 34),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _openMenu(context),
            tooltip: 'Menu',
          ),
        ],
      ),
      body: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(_textSize.scale)),
        child: Column(
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
                  strokeData: widget.strokeData,
                  mmaData: widget.mmaData,
                  strokeSpeed: _strokeSpeed,
                  onSearch: (q) {
                    _controller.text = q;
                    _runSearch(q);
                  },
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

