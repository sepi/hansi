import 'package:flutter/material.dart';

import 'pinyin_utils.dart';

enum HanziFont {
  sans('Noto Sans SC', 'Sans (Hei 黑)'),
  serif('Noto Serif SC', 'Serif (Song 宋)'),
  handwriting('Ma Shan Zheng', 'Handwriting (Kai 楷)');

  const HanziFont(this.family, this.label);
  final String family;
  final String label;
}

enum AppTextSize {
  small(0.8, 'Small'),
  medium(1.0, 'Medium'),
  large(1.5, 'Large');

  const AppTextSize(this.scale, this.label);
  final double scale;
  final String label;
}

const kRed = Color(0xFFC0392B);

const kToneColors = [
  Color(0xFFCC0000), // tone 1
  Color(0xFFCC7700), // tone 2
  Color(0xFF008800), // tone 3
  Color(0xFF0000CC), // tone 4
  Color(0xFF888888), // neutral / tone 5
];

int toneOf(String syllable) {
  if (syllable.isEmpty) return 5;
  final n = int.tryParse(syllable[syllable.length - 1]);
  return (n != null && n >= 1 && n <= 4) ? n : 5;
}

/// One column per character: hanzi on top, unicode pinyin centered below.
/// Both are colored by tone when [toneColors] is true.
Widget hanziPinyinGrid(
  BuildContext context,
  String hanzi,
  String pinyin,
  TextStyle hanziStyle,
  TextStyle pinyinStyle, {
  required bool toneColors,
}) {
  final syllables = pinyin.split(' ');
  return Wrap(
    spacing: 2,
    runSpacing: 4,
    children: List.generate(hanzi.length, (i) {
      final syl = i < syllables.length ? syllables[i] : '';
      final color = toneColors ? kToneColors[toneOf(syl) - 1] : null;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(hanzi[i], style: hanziStyle.copyWith(color: color)),
            Text(toUnicodePinyin(syl), style: pinyinStyle.copyWith(color: color)),
          ],
        ),
      );
    }),
  );
}

/// Returns a [Text] or [RichText] widget for [simplified], optionally coloring
/// each character by its tone using the space-separated numbered [pinyin].
Widget hanziWidget(
  BuildContext context,
  String simplified,
  String pinyin,
  TextStyle style, {
  required bool toneColors,
}) {
  if (!toneColors) return Text(simplified, style: style);
  final syllables = pinyin.split(' ');
  final spans = List.generate(simplified.length, (i) {
    final syllable = i < syllables.length ? syllables[i] : '';
    return TextSpan(
      text: simplified[i],
      style: style.copyWith(color: kToneColors[toneOf(syllable) - 1]),
    );
  });
  return RichText(
    text: TextSpan(children: spans),
    textScaler: MediaQuery.textScalerOf(context),
  );
}
