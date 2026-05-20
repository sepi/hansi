// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard + PlatformException

import 'anki_service.dart';
import 'decomposition_tree.dart';
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
    required this.toneColors,
    required this.showTraditional,
    required this.strokeData,
    required this.mmaData,
    required this.strokeSpeed,
    required this.onSearch,
    required this.ankiInstalled,
  });

  final List<SearchResult> results;
  final HanziFont font;
  final bool toneColors;
  final bool showTraditional;
  final Map<String, String> strokeData;
  final Map<String, MmaEntry> mmaData;
  final double strokeSpeed;
  final void Function(String query) onSearch;
  final bool ankiInstalled;

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
    if (pos.pixels >= pos.maxScrollExtent - 200 &&
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
    return IconButton(
      icon: const Icon(Icons.volume_up_outlined),
      iconSize: 22,
      color: Colors.grey.shade500,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 30),
      tooltip: 'Listen',
      onPressed: () => TtsService.instance.speak(text, traditional: traditional),
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
          color: const Color(0xFFBBDEFB),  // blue.shade100
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '旧HSK $level',
          softWrap: false,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF1565C0),  // blue.shade800
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
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

