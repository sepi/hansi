// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import 'asset_loader.dart';
import 'dict_entry.dart';
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
  SearchWorker? _worker;
  Map<String, String> _strokeData = const {};
  Map<String, MmaEntry> _mmaData = const {};
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
    // Delay loading until after the first frame is painted so the loading
    // screen is guaranteed to be visible before any heavy work begins.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait a few frames so the loading screen is visibly on-screen before
      // any work starts. addPostFrameCallback alone fires before Android's
      // SurfaceFlinger has composited the first frame to the display.
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
    _worker?.dispose();
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
      ]);
      final entries = phase1[0] as List<DictEntry>;
      final freqMap = phase1[1] as Map<String, int>;

      final wordIndex =
          await loadWordIndex(entries, (p) => _report('Building index', p));

      // Spawn the persistent search isolate. Data is copied once here;
      // every query after this sends only a short string across the boundary.
      final worker = await SearchWorker.create(
        entries: entries,
        freqMap: freqMap,
        wordIndex: wordIndex,
      );
      if (mounted) setState(() => _worker = worker);

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
      ]);
      if (mounted) {
        setState(() {
          _strokeData = results[0] as Map<String, String>;
          _mmaData = results[1] as Map<String, MmaEntry>;
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
      strokeData: _strokeData,
      mmaData: _mmaData,
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
