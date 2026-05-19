// SPDX-License-Identifier: AGPL-3.0-or-later
// Converts between number-coded and Unicode pinyin.
// toUnicodePinyin:  "ni3 hao3"  → "nǐ hǎo"
// toNumberedPinyin: "nǐ hǎo"   → "ni3 hao3"

const _tones = {
  'a': ['ā', 'á', 'ǎ', 'à', 'a'],
  'e': ['ē', 'é', 'ě', 'è', 'e'],
  'i': ['ī', 'í', 'ǐ', 'ì', 'i'],
  'o': ['ō', 'ó', 'ǒ', 'ò', 'o'],
  'u': ['ū', 'ú', 'ǔ', 'ù', 'u'],
  'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ', 'ü'],
  'A': ['Ā', 'Á', 'Ǎ', 'À', 'A'],
  'E': ['Ē', 'É', 'Ě', 'È', 'E'],
  'I': ['Ī', 'Í', 'Ǐ', 'Ì', 'I'],
  'O': ['Ō', 'Ó', 'Ǒ', 'Ò', 'O'],
  'U': ['Ū', 'Ú', 'Ǔ', 'Ù', 'U'],
  'Ü': ['Ǖ', 'Ǘ', 'Ǚ', 'Ǜ', 'Ü'],
};

const _vowels = {'a', 'e', 'i', 'o', 'u', 'ü', 'A', 'E', 'I', 'O', 'U', 'Ü'};

String toUnicodePinyin(String numbered) =>
    numbered.split(' ').map(_convertSyllable).join(' ');

String _applyTone(String base, int idx, int tone) =>
    base.substring(0, idx) + (_tones[base[idx]]![tone]) + base.substring(idx + 1);

String _convertSyllable(String syl) {
  if (syl.isEmpty) return syl;
  final last = syl[syl.length - 1];
  if (last.compareTo('1') < 0 || last.compareTo('5') > 0) return syl;

  final tone = int.parse(last) - 1; // 0-based index
  final base = syl
      .substring(0, syl.length - 1)
      .replaceAll('u:', 'ü')
      .replaceAll('U:', 'Ü');

  if (tone == 4) return base; // neutral tone: strip number, no mark

  // Rule 1: 'a' or 'e' always takes the mark
  for (final v in ['a', 'e', 'A', 'E']) {
    final idx = base.indexOf(v);
    if (idx != -1) return _applyTone(base, idx, tone);
  }

  // Rule 2: 'ou' combination → 'o' takes the mark
  for (final pair in [('ou', 'o'), ('Ou', 'O'), ('OU', 'O')]) {
    if (base.contains(pair.$1)) return _applyTone(base, base.indexOf(pair.$2), tone);
  }

  // Rule 3: last vowel takes the mark
  int lastIdx = -1;
  for (var i = 0; i < base.length; i++) {
    if (_vowels.contains(base[i])) lastIdx = i;
  }
  if (lastIdx == -1) return base;
  return base.substring(0, lastIdx) + (_tones[base[lastIdx]]?[tone] ?? base[lastIdx]) + base.substring(lastIdx + 1);
}

// ---------------------------------------------------------------------------
// Unicode → numbered
// ---------------------------------------------------------------------------

// Maps every toned Unicode vowel to its (base, toneNumber) pair.
final _unicodeToTone = <String, (String, int)>{
  'ā': ('a', 1), 'á': ('a', 2), 'ǎ': ('a', 3), 'à': ('a', 4),
  'ē': ('e', 1), 'é': ('e', 2), 'ě': ('e', 3), 'è': ('e', 4),
  'ī': ('i', 1), 'í': ('i', 2), 'ǐ': ('i', 3), 'ì': ('i', 4),
  'ō': ('o', 1), 'ó': ('o', 2), 'ǒ': ('o', 3), 'ò': ('o', 4),
  'ū': ('u', 1), 'ú': ('u', 2), 'ǔ': ('u', 3), 'ù': ('u', 4),
  'ǖ': ('ü', 1), 'ǘ': ('ü', 2), 'ǚ': ('ü', 3), 'ǜ': ('ü', 4),
  'Ā': ('A', 1), 'Á': ('A', 2), 'Ǎ': ('A', 3), 'À': ('A', 4),
  'Ē': ('E', 1), 'É': ('E', 2), 'Ě': ('E', 3), 'È': ('E', 4),
  'Ī': ('I', 1), 'Í': ('I', 2), 'Ǐ': ('I', 3), 'Ì': ('I', 4),
  'Ō': ('O', 1), 'Ó': ('O', 2), 'Ǒ': ('O', 3), 'Ò': ('O', 4),
  'Ū': ('U', 1), 'Ú': ('U', 2), 'Ǔ': ('U', 3), 'Ù': ('U', 4),
  'Ǖ': ('Ü', 1), 'Ǘ': ('Ü', 2), 'Ǚ': ('Ü', 3), 'Ǜ': ('Ü', 4),
};

String toNumberedPinyin(String unicode) =>
    unicode.split(' ').map(_syllableToNumbered).join(' ');

String _syllableToNumbered(String syl) {
  int? tone;
  final buf = StringBuffer();
  for (final rune in syl.runes) {
    final char = String.fromCharCode(rune);
    final entry = _unicodeToTone[char];
    if (entry != null) {
      buf.write(entry.$1);
      tone = entry.$2;
    } else {
      buf.write(char);
    }
  }
  if (tone != null) buf.write(tone);
  return buf.toString();
}
