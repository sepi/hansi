// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import 'asset_loader.dart';
import 'dict_entry.dart';
import 'example_sentence.dart';
import 'home_page.dart';
import 'mma_entry.dart';
import 'search_worker.dart';
import 'theme.dart';

void main() {
  runApp(const HansiApp());
}

class HansiApp extends StatelessWidget {
  const HansiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hansi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kRed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DictLoader(),
    );
  }
}

// ---------------------------------------------------------------------------
// Boot loader — loads dictionary data and shows progress, then hands off.
// ---------------------------------------------------------------------------

class DictLoader extends StatefulWidget {
  const DictLoader({super.key});

  @override
  State<DictLoader> createState() => _DictLoaderState();
}

class _DictLoaderState extends State<DictLoader> {
  // Static cache survives Android activity recreation when the Dart VM stays
  // alive, avoiding a full reload on brief focus loss.
  static SearchWorker? _cachedWorker;
  static Map<String, int> _cachedHskLevels = const {};
  static Map<String, String> _cachedStrokeData = const {};
  static Map<String, MmaEntry> _cachedMmaData = const {};
  static SentenceData _cachedSentenceData = SentenceData.empty;

  SearchWorker? _worker;
  Map<String, int> _hskLevels = const {};
  Map<String, String> _strokeData = const {};
  Map<String, MmaEntry> _mmaData = const {};
  SentenceData _sentenceData = SentenceData.empty;
  String? _error;

  final Map<String, double> _progress = {
    'Loading dictionary': 0,
    'Loading frequency data': 0,
    'Building index': 0,
  };

  bool _precached = false;

  @override
  void initState() {
    super.initState();
    if (_cachedWorker != null) {
      // Dart VM still alive — reuse previously loaded data instantly.
      _worker = _cachedWorker;
      _hskLevels = _cachedHskLevels;
      _strokeData = _cachedStrokeData;
      _mmaData = _cachedMmaData;
      _sentenceData = _cachedSentenceData;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kick off PNG decode before the first build so the logo is ready
    // by the time the loading screen is painted to the screen.
    if (!_precached) {
      _precached = true;
      precacheImage(const AssetImage('assets/hansi.png'), context);
    }
  }

  @override
  void dispose() {
    // Worker is held by the static cache — do not dispose it so it
    // survives activity recreation.
    super.dispose();
  }

  void _report(String name, double p) {
    if (mounted) setState(() => _progress[name] = p);
  }

  Future<void> _load() async {
    try {
      // Phase 1 — minimum data required to start searching.
      final phase1 = await Future.wait([
        loadCedict((p) => _report('Loading dictionary', p)),
        loadFrequency((p) => _report('Loading frequency data', p)),
        loadHskLevels(),
      ]);
      final entries = phase1[0] as List<DictEntry>;
      final freqMap = phase1[1] as Map<String, int>;
      final hskLevels = phase1[2] as Map<String, int>;

      final wordIndex =
          await loadWordIndex(entries, (p) => _report('Building index', p));

      // Spawn the persistent search isolate. Data is copied once here;
      // every query after this sends only a short string across the boundary.
      final worker = await SearchWorker.create(
        entries: entries,
        freqMap: freqMap,
        hskLevels: hskLevels,
        wordIndex: wordIndex,
      );
      _cachedWorker = worker;
      _cachedHskLevels = hskLevels;
      if (mounted) {
        setState(() {
          _worker = worker;
          _hskLevels = hskLevels;
        });
      }

      // Phase 2 — stroke and etymology data loaded in the background.
      // The home page is already visible; widgets degrade gracefully until
      // this completes and the maps are swapped in.
      _loadEnhancementData();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadEnhancementData() async {
    try {
      final results = await Future.wait([
        loadGraphics((_) {}),
        loadMmaDict((_) {}),
        loadExampleSentences((_) {}),
      ]);
      _cachedStrokeData = results[0] as Map<String, String>;
      _cachedMmaData = results[1] as Map<String, MmaEntry>;
      _cachedSentenceData = SentenceData(results[2] as List<ExampleSentence>);
      if (mounted) {
        setState(() {
          _strokeData = _cachedStrokeData;
          _mmaData = _cachedMmaData;
          _sentenceData = _cachedSentenceData;
        });
      }
    } catch (_) {
      // Enhancement data is non-critical; the app remains fully usable
      // for searching even if this fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Failed to load dictionary:\n$_error')),
      );
    }
    if (_worker == null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Image.asset('assets/hansi.png', height: 72)),
                  const SizedBox(height: 24),
                  ..._progress.entries.map(
                    (e) => _AssetProgressRow(name: e.key, progress: e.value),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return HomePage(
      worker: _worker!,
      hskLevels: _hskLevels,
      strokeData: _strokeData,
      mmaData: _mmaData,
      sentenceData: _sentenceData,
    );
  }
}

class _AssetProgressRow extends StatelessWidget {
  const _AssetProgressRow({required this.name, required this.progress});

  final String name;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final done = progress >= 1.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(name, style: const TextStyle(fontSize: 13))),
              Text(
                done ? 'done' : '${(progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: done ? kRed : Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            color: kRed,
            minHeight: 3,
          ),
        ],
      ),
    );
  }
}
