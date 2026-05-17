import 'package:flutter/material.dart';

import 'cedict_loader.dart';
import 'dict_entry.dart';
import 'home_page.dart';
import 'search.dart';
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
  List<DictEntry>? _entries;
  Map<String, int> _freqMap = const {};
  WordIndex? _wordIndex;
  String? _error;

  final Map<String, double> _progress = {
    'Dictionary': 0,
    'Frequency': 0,
    'Index': 0,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _report(String name, double p) {
    if (mounted) setState(() => _progress[name] = p);
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        loadCedict((p) => _report('Dictionary', p)),
        loadFrequency((p) => _report('Frequency', p)),
      ]);
      final entries = results[0] as List<DictEntry>;
      final freqMap = results[1] as Map<String, int>;
      if (mounted) setState(() { _entries = entries; _freqMap = freqMap; });

      final wordIndex =
          await loadWordIndex(entries, (p) => _report('Index', p));
      if (mounted) setState(() => _wordIndex = wordIndex);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Failed to load dictionary:\n$_error')),
      );
    }
    if (_entries == null || _wordIndex == null) {
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
                  const Text(
                    'hansi',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: kRed,
                    ),
                  ),
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
        entries: _entries!, freqMap: _freqMap, wordIndex: _wordIndex!);
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
              Text(name, style: const TextStyle(fontSize: 13)),
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
