// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import 'theme.dart';

class MenuSheet extends StatefulWidget {
  const MenuSheet({
    super.key,
    required this.font,
    required this.textSize,
    required this.toneColors,
    required this.showTraditional,
    required this.strokeSpeed,
    required this.onFontChanged,
    required this.onSizeChanged,
    required this.onToneColorsChanged,
    required this.onTraditionalChanged,
    required this.onStrokeSpeedChanged,
    required this.ankiInstalled,
  });

  final HanziFont font;
  final AppTextSize textSize;
  final bool toneColors;
  final bool showTraditional;
  final double strokeSpeed;
  final ValueChanged<HanziFont> onFontChanged;
  final ValueChanged<AppTextSize> onSizeChanged;
  final ValueChanged<bool> onToneColorsChanged;
  final ValueChanged<bool> onTraditionalChanged;
  final ValueChanged<double> onStrokeSpeedChanged;
  final bool ankiInstalled;

  @override
  State<MenuSheet> createState() => _MenuSheetState();
}

class _MenuSheetState extends State<MenuSheet> {
  late HanziFont _font;
  late AppTextSize _textSize;
  late bool _toneColors;
  late bool _showTraditional;
  late double _strokeSpeed;

  @override
  void initState() {
    super.initState();
    _font = widget.font;
    _textSize = widget.textSize;
    _toneColors = widget.toneColors;
    _showTraditional = widget.showTraditional;
    _strokeSpeed = widget.strokeSpeed;
  }

  // Speed stored as actual strokeAnimationSpeed value; 100% == 1.2 (default).
  double get _speedPct => (_strokeSpeed / 1.2 * 100).roundToDouble();

  static double _pctToSpeed(double pct) => (pct / 100.0 * 1.2).clamp(0.1, 5.0);

  void _selectStrokeSpeed(double pct) =>
      setState(() => _strokeSpeed = _pctToSpeed(pct));

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
                      style: TextStyle(fontFamily: f.family, fontSize: 15)),
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
            _heading(context, 'STROKE ANIMATION SPEED'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _speedPct.clamp(25.0, 300.0),
                      min: 25,
                      max: 300,
                      divisions: 11,
                      activeColor: kRed,
                      onChanged: _selectStrokeSpeed,
                      onChangeEnd: (pct) =>
                          widget.onStrokeSpeedChanged(_pctToSpeed(pct)),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_speedPct.round()}%',
                      style: const TextStyle(fontSize: 13),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
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
                    activeThumbColor: kRed,
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
                    activeThumbColor: kRed,
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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'About Hansi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
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
                      'HSK Vocabulary (旧版 2010)',
                      'Level tags (旧HSK 1–4) follow the 2010 Hanban/CIE standard, '
                      'covering ~535 multi-character words. Single characters and '
                      'HSK 5–6 are not tagged. '
                      'The 2021 revision (新HSK 3.0) is not included.\n'
                      'Source: Hanban/CIE official HSK 2010 curriculum (public).',
                    ),
                    section(
                      'Fonts — Gentium Plus',
                      'Pinyin display font bundled with the app.\n'
                      'Designed by SIL International, licensed under the '
                      'SIL Open Font License 1.1 (OFL).\n'
                      'https://software.sil.org/gentiumplus',
                    ),
                    section(
                      'Fonts — Hanzi display',
                      'Noto Sans SC, Noto Serif SC, Ma Shan Zheng, '
                      'ZCOOL XiaoWei, Zhi Mang Xing — loaded via Google Fonts.\n'
                      'All licensed under the SIL Open Font License 1.1 (OFL).',
                    ),
                    section(
                      'Make Me A Hanzi — Stroke Graphics',
                      'Stroke order graphics (graphics.txt) by Stroke Order Project '
                      'contributors, packaged by Make Me A Hanzi.\n'
                      'Licensed under the Arphic Public License.\n'
                      'https://github.com/skishore/makemeahanzi',
                    ),
                    section(
                      'Make Me A Hanzi — Dictionary',
                      'Character decomposition and etymology data (dictionary.txt) '
                      'by Make Me A Hanzi contributors.\n'
                      'Licensed under Creative Commons Attribution-ShareAlike 4.0 '
                      'International (CC BY-SA 4.0).\n'
                      'https://github.com/skishore/makemeahanzi',
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
