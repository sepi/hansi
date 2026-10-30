// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import 'theme.dart';

// ignore_for_file: always_use_package_imports

class MenuSheet extends StatefulWidget {
  const MenuSheet({
    super.key,
    required this.font,
    required this.textSize,
    required this.toneColors, // null = disabled
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
  final List<Color>? toneColors;
  final bool showTraditional;
  final double strokeSpeed;
  final ValueChanged<HanziFont> onFontChanged;
  final ValueChanged<AppTextSize> onSizeChanged;
  final ValueChanged<List<Color>?> onToneColorsChanged;
  final ValueChanged<bool> onTraditionalChanged;
  final ValueChanged<double> onStrokeSpeedChanged;
  final bool ankiInstalled;

  @override
  State<MenuSheet> createState() => _MenuSheetState();
}

class _MenuSheetState extends State<MenuSheet> {
  late HanziFont _font;
  late AppTextSize _textSize;
  late List<Color>? _toneColors;
  late List<Color> _toneColorScheme; // the 5 colors, even when disabled
  late bool _showTraditional;
  late double _strokeSpeed;

  @override
  void initState() {
    super.initState();
    _font = widget.font;
    _textSize = widget.textSize;
    _toneColors = widget.toneColors;
    _toneColorScheme = widget.toneColors ?? List.of(kDefaultToneColors);
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

  void _toggleToneColors(bool enabled) {
    setState(() => _toneColors = enabled ? List.of(_toneColorScheme) : null);
    widget.onToneColorsChanged(_toneColors);
  }

  void _setToneColor(int tone, Color color) {
    setState(() {
      _toneColorScheme[tone] = color;
      if (_toneColors != null) _toneColors = List.of(_toneColorScheme);
    });
    widget.onToneColorsChanged(_toneColors);
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
            RadioGroup<HanziFont>(
              groupValue: _font,
              onChanged: (v) { if (v != null) _selectFont(v); },
              child: Column(
                children: HanziFont.values
                    .map((f) => RadioListTile<HanziFont>(
                          value: f,
                          title: Text(f.label,
                              style: TextStyle(
                                  fontFamily: f.family, fontSize: 15)),
                          activeColor: kRed,
                        ))
                    .toList(),
              ),
            ),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                      child: Text('Color each tone individually',
                          style: TextStyle(fontSize: 13))),
                  Switch(
                    value: _toneColors != null,
                    activeThumbColor: kRed,
                    onChanged: _toggleToneColors,
                  ),
                ],
              ),
            ),
            if (_toneColors != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: List.generate(5, (tone) {
                    final label = tone < 4 ? 'Tone ${tone + 1}' : 'Neutral';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: Text(label,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              children: kToneColorPalette.map((c) {
                                final selected =
                                    _toneColorScheme[tone].toARGB32() ==
                                        c.toARGB32();
                                return GestureDetector(
                                  onTap: () => _setToneColor(tone, c),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: selected
                                          ? Border.all(
                                              color: Colors.white, width: 2)
                                          : null,
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: c.withAlpha(180),
                                                blurRadius: 4,
                                                spreadRadius: 1,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: selected
                                        ? const Icon(Icons.check,
                                            size: 14, color: Colors.white)
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              )
            else
              const SizedBox(height: 12),
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
    final subtleStyle = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: Theme.of(context).colorScheme.outline,
    );

    Widget section(String title, String body, {bool subtle = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: headingStyle),
              const SizedBox(height: 4),
              Text(body, style: subtle ? subtleStyle : bodyStyle),
            ],
          ),
        );

    Widget divider(String label) => Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Theme.of(context).colorScheme.outline,
            ),
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
                      'Hansi is a free, open-source Chinese–English dictionary.',
                      style: bodyStyle,
                    ),
                    const SizedBox(height: 16),

                    // ── App ──────────────────────────────────────────────────
                    divider('App'),
                    section(
                      'Author',
                      'Raffael Mancini <raffael@mancini.lu>\n'
                      'Built with Claude Code (Anthropic).',
                    ),
                    section(
                      'License',
                      'GNU Affero General Public License v3.0 or later '
                      '(AGPL-3.0-or-later).\n'
                      'Source code available at the author\'s request.',
                    ),

                    // ── Dictionary & data ────────────────────────────────────
                    divider('Dictionary & data'),
                    section(
                      'CC-CEDICT',
                      'Dictionary data © MDBG and contributors.\n'
                      'Licensed under Creative Commons Attribution-ShareAlike 4.0 '
                      'International (CC BY-SA 4.0).\n'
                      'https://cc-cedict.org',
                    ),
                    section(
                      'Word Frequency — SUBTLEX-CH',
                      'Word frequency rankings derived from film and TV subtitles.\n'
                      'Cai, Q. & Brysbaert, M. (2010). SUBTLEX-CH: Chinese Word '
                      'and Character Frequencies Based on Film Subtitles. '
                      'PLOS ONE 5(6): e10729.\n'
                      'Licensed under Creative Commons Attribution 4.0 '
                      'International (CC BY 4.0).',
                    ),
                    section(
                      'HSK Vocabulary (旧版 2010)',
                      'Level tags (旧HSK 1–4) follow the 2010 Hanban/CIE standard, '
                      'covering ~535 multi-character words. Single characters and '
                      'HSK 5–6 are not tagged. The 2021 revision (新HSK 3.0) is '
                      'not included.\n'
                      'Source: Hanban/CIE official HSK 2010 curriculum (public).',
                    ),
                    section(
                      'Example Sentences',
                      'Generated with Claude (Anthropic) and segmented using jieba. '
                      'AI-generated content; errors may occur.\n'
                      'Licensed under Creative Commons Attribution-NonCommercial-'
                      'ShareAlike 4.0 International (CC BY-NC-SA 4.0).',
                    ),

                    // ── Stroke graphics ──────────────────────────────────────
                    divider('Stroke order'),
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

                    // ── Fonts ────────────────────────────────────────────────
                    divider('Fonts'),
                    section(
                      'Gentium Plus',
                      'Pinyin display font. Designed by SIL International.\n'
                      'Licensed under the SIL Open Font License 1.1 (OFL).\n'
                      'https://software.sil.org/gentiumplus',
                    ),
                    section(
                      'Hanzi Display Fonts',
                      'Noto Sans SC, Noto Serif SC — Google & Monotype.\n'
                      'Ma Shan Zheng — Arphic Technology.\n'
                      'ZCOOL XiaoWei — ZCOOL.\n'
                      'Zhi Mang Xing — Arphic Technology.\n'
                      'All licensed under the SIL Open Font License 1.1 (OFL).',
                    ),

                    // ── Open-source libraries ────────────────────────────────
                    divider('Open-source libraries'),
                    section(
                      'Flutter SDK',
                      '© Google LLC. Licensed under BSD 3-Clause.\n'
                      'https://flutter.dev',
                      subtle: true,
                    ),
                    section(
                      'archive',
                      '© 2013–2021 Brendan Duncan. MIT License.',
                      subtle: true,
                    ),
                    section(
                      'shared_preferences',
                      '© The Flutter Authors. BSD 3-Clause License.',
                      subtle: true,
                    ),
                    section(
                      'stroke_order_animator',
                      '© 2020 Felipe Peter. BSD 3-Clause License.',
                      subtle: true,
                    ),
                    section(
                      'flutter_tts',
                      '© 2018 Daniel Lutton. MIT License.',
                      subtle: true,
                    ),
                    section(
                      'cupertino_icons',
                      '© 2016 Vladimir Kharlampidi. MIT License.',
                      subtle: true,
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
