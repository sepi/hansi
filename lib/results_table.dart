import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dict_entry.dart';
import 'pinyin_utils.dart';
import 'search.dart';
import 'theme.dart';

class ResultsTable extends StatefulWidget {
  const ResultsTable({
    super.key,
    required this.results,
    required this.font,
    required this.toneColors,
    required this.showTraditional,
  });

  final List<SearchResult> results;
  final HanziFont font;
  final bool toneColors;
  final bool showTraditional;

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
                      GoogleFonts.getFont(widget.font.family, fontSize: 26),
                      GoogleFonts.gentiumPlus(fontSize: 12),
                      toneColors: widget.toneColors,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.definitions.join('\n'),
                    style: const TextStyle(fontSize: 14),
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

    Widget btn(String label, String text) => OutlinedButton.icon(
          onPressed: () => _copy(context, text),
          icon: const Icon(Icons.copy_outlined, size: 14),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(fontSize: 12),
            visualDensity: VisualDensity.compact,
          ),
        );

    final syllables = entry.pinyin.split(' ');
    return Column(
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              btn('Hanzi', hanzi),
              btn('Pinyin', pinyin),
              btn('English', defs),
              btn('All', all),
            ],
          ),
        ),
        ...List.generate(hanzi.length, (i) {
          final c = hanzi[i];
          final syllable = i < syllables.length ? syllables[i] : '';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                hanziWidget(
                  context,
                  c,
                  syllable,
                  GoogleFonts.getFont(widget.font.family, fontSize: 40),
                  toneColors: widget.toneColors,
                ),
                const SizedBox(width: 24),
                Expanded(child: StrokeOrderImage(char: c)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

String _strokeOrderUrl(String char) {
  final filename = '$char-bw.png';
  final hash = md5.convert(utf8.encode(filename)).toString();
  return 'https://upload.wikimedia.org/wikipedia/commons'
      '/${hash[0]}/${hash.substring(0, 2)}/${Uri.encodeComponent(filename)}';
}

class StrokeOrderImage extends StatelessWidget {
  const StrokeOrderImage({super.key, required this.char});

  final String char;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Image.network(
        _strokeOrderUrl(char),
        width: double.infinity,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, _, _) =>
            const Text('—', style: TextStyle(color: Colors.grey)),
      ),
    );
  }
}
