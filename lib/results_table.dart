// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard + PlatformException

import 'anki_service.dart';
import 'constants.dart';
import 'decomposition_tree.dart';
import 'example_sentence.dart';
import 'dict_entry.dart';
import 'hsk.dart';
import 'mma_entry.dart';
import 'pinyin_utils.dart';
import 'search.dart';
import 'stroke_overlay.dart';
import 'theme.dart';
import 'tts_service.dart';

class ResultsTable extends StatefulWidget {
  const ResultsTable({
    super.key,
    required this.results,
    required this.font,
    required this.toneColors, // null = disabled
    required this.showTraditional,
    required this.strokeData,
    required this.mmaData,
    required this.strokeSpeed,
    required this.onSearch,
    required this.ankiInstalled,
    required this.sentenceData,
  });

  final List<SearchResult> results;
  final HanziFont font;
  final List<Color>? toneColors;
  final bool showTraditional;
  final Map<String, String> strokeData;
  final Map<String, MmaEntry> mmaData;
  final double strokeSpeed;
  final void Function(String query) onSearch;
  final bool ankiInstalled;
  final SentenceData sentenceData;

  @override
  State<ResultsTable> createState() => _ResultsTableState();
}

class _ResultsTableState extends State<ResultsTable> {
  int? _expandedIndex;
  int _visibleCount = _pageSize;
  final _scrollController = ScrollController();
  static const _pageSize = 30;
  static const _padding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ResultsTable old) {
    super.didUpdateWidget(old);
    if (old.results != widget.results) {
      _expandedIndex = null;
      _visibleCount = _pageSize;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
    // When enhancement data arrives after the home page is already shown,
    // force a rebuild so expanded rows pick up stroke and etymology data.
    if ((old.strokeData.isEmpty && widget.strokeData.isNotEmpty) ||
        (old.mmaData.isEmpty && widget.mmaData.isNotEmpty)) {
      setState(() {});
    }
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - kScrollLoadThreshold &&
        _visibleCount < widget.results.length) {
      setState(() {
        _visibleCount =
            (_visibleCount + _pageSize).clamp(0, widget.results.length);
      });
    }
  }

  void _showDecompositionDialog(
      BuildContext context, String char, String pinyin) {
    if (!widget.mmaData.containsKey(char)) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(char,
                        style: const TextStyle(fontSize: 38, height: 1.1)),
                    const SizedBox(width: 12),
                    Text(pinyin,
                        style: TextStyle(fontFamily: 'GentiumPlus', fontSize: 18)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DecompositionTree(
                  char: char,
                  mmaData: widget.mmaData,
                  onSearch: (q) {
                    Navigator.of(context).pop();
                    widget.onSearch(q);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                itemCount: _visibleCount.clamp(0, widget.results.length),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: _buildItem,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int i) {
    final entry = widget.results[i].entry;
    final expanded = _expandedIndex == i;
    final hanzi = widget.showTraditional ? entry.traditional : entry.simplified;
    final hskLvl = _hskLevel(entry);
    final pinyin = toUnicodePinyin(entry.pinyin);
    final english = entry.definitions.join('; ');

    return InkWell(
      onTap: () => setState(() => _expandedIndex = expanded ? null : i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: _padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: hanziPinyinGrid(
                      context,
                      hanzi,
                      entry.pinyin,
                      TextStyle(fontFamily: widget.font.family, fontSize: 26),
                      TextStyle(fontFamily: 'GentiumPlus', fontSize: 12),
                      toneColors: widget.toneColors,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _numberedDefs(entry.definitions),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                SizedBox(
                  width: 74,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.ankiInstalled)
                            _AnkiButton(
                              hanzi: hanzi,
                              pinyin: pinyin,
                              english: english,
                            ),
                          _TtsButton(
                              text: hanzi,
                              traditional: widget.showTraditional),
                        ],
                      ),
                      Opacity(
                        opacity: hskLvl != null ? 1.0 : 0.0,
                        child: _HskChip(level: hskLvl ?? 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child:
                expanded ? _buildDetail(context, entry) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied'),
        duration: Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        width: 120,
      ),
    );
  }

  Widget _buildDetail(BuildContext context, DictEntry entry) {
    final hanzi = widget.showTraditional ? entry.traditional : entry.simplified;
    final pinyin = toUnicodePinyin(entry.pinyin);
    final defs = entry.definitions.join('; ');
    final all = '$hanzi\t$pinyin\t$defs';
    final syllables = entry.pinyin.split(' ');

    Widget copyBtn(String label, String text) => OutlinedButton.icon(
          onPressed: () => _copy(context, text),
          icon: const Icon(Icons.copy_outlined, size: 12),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            textStyle: const TextStyle(fontSize: 11),
            visualDensity: VisualDensity.compact,
          ),
        );

    return Column(
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SequentialStrokeRow(
                  key: ValueKey(widget.strokeData.isEmpty),
                  chars: List.generate(hanzi.length, (i) => hanzi[i]),
                  syllables: syllables,
                  strokeData: widget.strokeData,
                  mmaData: widget.mmaData,
                  strokeSpeed: widget.strokeSpeed,
                  onDecomposeTap: (i) {
                    final c = hanzi[i];
                    final syl = i < syllables.length ? syllables[i] : '';
                    _showDecompositionDialog(context, c, toUnicodePinyin(syl));
                  },
                  onSearchTap: (i) => widget.onSearch(hanzi[i]),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  copyBtn('汉', hanzi),
                  const SizedBox(height: 4),
                  copyBtn('pī', pinyin),
                  const SizedBox(height: 4),
                  copyBtn('En', defs),
                  const SizedBox(height: 4),
                  copyBtn('All', all),
                ],
              ),
            ],
          ),
        ),
        _SentencesSection(
          word: hanzi,
          sentenceData: widget.sentenceData,
          onSearch: widget.onSearch,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TTS button
// ---------------------------------------------------------------------------

class _TtsButton extends StatelessWidget {
  const _TtsButton({required this.text, required this.traditional});
  final String text;
  final bool traditional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton(
        icon: const Icon(Icons.volume_up_outlined),
        iconSize: 26,
        color: Colors.grey.shade500,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        tooltip: 'Listen',
        onPressed: () => TtsService.instance.speak(text, traditional: traditional),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anki button
// ---------------------------------------------------------------------------

class _AnkiButton extends StatelessWidget {
  const _AnkiButton({
    required this.hanzi,
    required this.pinyin,
    required this.english,
  });
  final String hanzi;
  final String pinyin;
  final String english;

  void _snack(BuildContext context, String msg, {int seconds = 2}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: seconds),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.send),
      iconSize: 20,
      color: Colors.grey.shade500,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 30),
      tooltip: 'Add to AnkiDroid',
      onPressed: () async {
        final granted = await ensureAnkiPermission(context);
        if (!context.mounted) return;
        if (!granted) {
          _snack(context,
              'Permission denied — grant it in Settings → Apps → Hansi → Permissions',
              seconds: 5);
          return;
        }
        try {
          await AnkiService.instance.addNote(hanzi, pinyin, english);
          if (context.mounted) _snack(context, 'Added to AnkiDroid');
        } on PlatformException catch (e) {
          if (context.mounted) {
            _snack(context, e.message ?? 'Failed to add note', seconds: 5);
          }
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HSK level chip
// ---------------------------------------------------------------------------

const _kHskBg = Color(0xFFBBDEFB); // blue[100]
const _kHskFg = Color(0xFF1565C0); // blue[800]

int? _hskLevel(DictEntry e) =>
    kHskLevel[e.simplified] ?? kHskLevel[e.traditional];

class _HskChip extends StatelessWidget {
  const _HskChip({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Old HSK standard (2010, levels 1–4)',
      child: Container(
        margin: const EdgeInsets.only(left: 6, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: _kHskBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '旧HSK $level',
          softWrap: false,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            fontSize: 11,
            color: _kHskFg,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Example sentences section
// ---------------------------------------------------------------------------

class _SentencesSection extends StatefulWidget {
  const _SentencesSection({
    required this.word,
    required this.sentenceData,
    required this.onSearch,
  });
  final String word;
  final SentenceData sentenceData;
  final void Function(String) onSearch;

  @override
  State<_SentencesSection> createState() => _SentencesSectionState();
}

class _SentencesSectionState extends State<_SentencesSection> {
  final Set<int> _pinyinRevealed = {};
  final Set<int> _englishRevealed = {};

  @override
  void didUpdateWidget(_SentencesSection old) {
    super.didUpdateWidget(old);
    if (old.word != widget.word) {
      _pinyinRevealed.clear();
      _englishRevealed.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.sentenceData.targetFor(widget.word);
    final incidental = widget.sentenceData.incidentalFor(widget.word);
    if (target.isEmpty && incidental.isEmpty) return const SizedBox.shrink();

    final outline = Theme.of(context).colorScheme.outline;
    final primaryContainer = Theme.of(context).colorScheme.primaryContainer;
    final onPrimaryContainer = Theme.of(context).colorScheme.onPrimaryContainer;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: outline,
            ),
          ),
        );

    void toggle(Set<int> set, int uid) =>
        setState(() => set.contains(uid) ? set.remove(uid) : set.add(uid));

    Widget toggleBtn(String label, bool active, VoidCallback onTap) =>
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            textStyle: const TextStyle(fontSize: 11),
            visualDensity: VisualDensity.compact,
            backgroundColor: active ? primaryContainer : null,
            foregroundColor: active ? onPrimaryContainer : null,
          ),
          child: Text(label),
        );

    Widget sentenceRow(ExampleSentence s, int uid) {
      final pinyin = _pinyinRevealed.contains(uid);
      final english = _englishRevealed.contains(uid);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 4, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                _circled(s.level),
                style: TextStyle(fontSize: 12, color: outline),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SegmentedSentence(
                    segments: s.segments,
                    onSearch: widget.onSearch,
                  ),
                  if (pinyin) ...[
                    const SizedBox(height: 2),
                    Text(
                      s.pinyin,
                      style: TextStyle(
                        fontFamily: 'GentiumPlus',
                        fontSize: 12,
                        color: outline,
                      ),
                    ),
                  ],
                  if (english) ...[
                    const SizedBox(height: 1),
                    Text(
                      s.en,
                      style: TextStyle(fontSize: 12, color: outline),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                toggleBtn('pī', pinyin, () => toggle(_pinyinRevealed, uid)),
                const SizedBox(height: 4),
                toggleBtn('En', english, () => toggle(_englishRevealed, uid)),
              ],
            ),
            _TtsButton(text: s.zh, traditional: false),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        if (target.isNotEmpty) ...[
          heading('EXAMPLES'),
          for (var i = 0; i < target.length; i++) sentenceRow(target[i], i),
        ],
        if (incidental.isNotEmpty) ...[
          heading('ALSO APPEARS IN'),
          for (var i = 0; i < incidental.length; i++)
            sentenceRow(incidental[i], target.length + i),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tappable segmented sentence
// ---------------------------------------------------------------------------

class _SegmentedSentence extends StatelessWidget {
  const _SegmentedSentence({required this.segments, required this.onSearch});
  final List<String> segments;
  final void Function(String) onSearch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 0,
      runSpacing: 0,
      children: segments.map((seg) {
        final isPunct = RegExp(r'^[\p{P}\p{S}\s]+$', unicode: true).hasMatch(seg);
        if (isPunct) {
          return Text(seg, style: const TextStyle(fontSize: 15));
        }
        return GestureDetector(
          onTap: () => onSearch(seg),
          child: Text(
            seg,
            style: const TextStyle(
              fontSize: 16,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: kSegmentUnderline,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Definition numbering
// ---------------------------------------------------------------------------

// ①–⑳ live at U+2460–U+2473; ㉑–㉟ at U+3251–U+325F.
String _circled(int n) {
  if (n >= 1 && n <= 20) return String.fromCharCode(0x245F + n);
  if (n >= 21 && n <= 35) return String.fromCharCode(0x3250 + n);
  return '$n.';
}

String _numberedDefs(List<String> defs) => List.generate(
      defs.length,
      (i) => '${_circled(i + 1)} ${defs[i]}',
    ).join('\n');

