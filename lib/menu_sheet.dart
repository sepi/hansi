import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme.dart';

class MenuSheet extends StatefulWidget {
  const MenuSheet({
    super.key,
    required this.font,
    required this.textSize,
    required this.toneColors,
    required this.showTraditional,
    required this.onFontChanged,
    required this.onSizeChanged,
    required this.onToneColorsChanged,
    required this.onTraditionalChanged,
  });

  final HanziFont font;
  final AppTextSize textSize;
  final bool toneColors;
  final bool showTraditional;
  final ValueChanged<HanziFont> onFontChanged;
  final ValueChanged<AppTextSize> onSizeChanged;
  final ValueChanged<bool> onToneColorsChanged;
  final ValueChanged<bool> onTraditionalChanged;

  @override
  State<MenuSheet> createState() => _MenuSheetState();
}

class _MenuSheetState extends State<MenuSheet> {
  late HanziFont _font;
  late AppTextSize _textSize;
  late bool _toneColors;
  late bool _showTraditional;

  @override
  void initState() {
    super.initState();
    _font = widget.font;
    _textSize = widget.textSize;
    _toneColors = widget.toneColors;
    _showTraditional = widget.showTraditional;
  }

  void _selectFont(HanziFont f) {
    setState(() => _font = f);
    widget.onFontChanged(f);
  }

  void _selectSize(AppTextSize s) {
    setState(() => _textSize = s);
    widget.onSizeChanged(s);
  }

  void _selectToneColors(bool v) {
    setState(() => _toneColors = v);
    widget.onToneColorsChanged(v);
  }

  void _selectTraditional(bool v) {
    setState(() => _showTraditional = v);
    widget.onTraditionalChanged(v);
  }

  Widget _heading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
            letterSpacing: 0.8,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(context, 'FONT STYLE'),
            ...HanziFont.values.map((f) => RadioListTile<HanziFont>(
                  value: f,
                  groupValue: _font,
                  title: Text(f.label,
                      style: GoogleFonts.getFont(f.family, fontSize: 15)),
                  activeColor: kRed,
                  onChanged: (v) => _selectFont(v!),
                )),
            const Divider(height: 1),
            _heading(context, 'TEXT SIZE'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SegmentedButton<AppTextSize>(
                segments: AppTextSize.values
                    .map((s) => ButtonSegment(value: s, label: Text(s.label)))
                    .toList(),
                selected: {_textSize},
                onSelectionChanged: (sel) => _selectSize(sel.first),
              ),
            ),
            const Divider(height: 1),
            _heading(context, 'TONE COLOURS'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '1=red  2=orange  3=green  4=blue',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  Switch(
                    value: _toneColors,
                    activeColor: kRed,
                    onChanged: _selectToneColors,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _heading(context, 'CHARACTERS'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Show traditional script',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  Switch(
                    value: _showTraditional,
                    activeColor: kRed,
                    onChanged: _selectTraditional,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                    context: context,
                    builder: (_) => const AboutDialog());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AboutDialog extends StatelessWidget {
  const AboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final headingStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: Theme.of(context).colorScheme.primary,
    );
    const bodyStyle = TextStyle(fontSize: 13, height: 1.5);

    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: headingStyle),
              const SizedBox(height: 4),
              Text(body, style: bodyStyle),
            ],
          ),
        );

    return AlertDialog(
      title: const Text('About Hansi'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hansi is a Chinese–English dictionary based on CC-CEDICT.',
              style: bodyStyle,
            ),
            const SizedBox(height: 20),
            section(
              'CC-CEDICT',
              'Dictionary data © MDBG and contributors.\n'
              'Licensed under Creative Commons Attribution-ShareAlike 4.0 '
              'International (CC BY-SA 4.0).\n'
              'https://cc-cedict.org',
            ),
            section(
              'Hanzi Frequency Data',
              'Character frequency rankings from Jun Da\'s Modern Chinese '
              'Character Frequency List, made available by ruddfawcett/hanziDB.csv.\n'
              'Licensed under the MIT License.',
            ),
            section(
              'Fonts',
              'Hanzi display fonts (Noto Sans SC, Noto Serif SC, Ma Shan Zheng) '
              'and pinyin font (Gentium Plus) are served via Google Fonts.\n'
              'All fonts are licensed under the SIL Open Font License 1.1 (OFL).',
            ),
            section(
              'Stroke Order Images',
              'Stroke order diagrams fetched from Wikimedia Commons '
              '(upload.wikimedia.org). Individual files are licensed under '
              'Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0) '
              'or compatible licenses as stated on each file\'s page.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
