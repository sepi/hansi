// SPDX-License-Identifier: AGPL-3.0-or-later
// The one definition of an English "word", shared by the search index, the
// query and the bold highlighting, so the three always agree.
//
// A word is a run of Latin letters, digits or '_'. Letters are lowercased
// and accents folded (é → e, ü → u, ǎ → a), so "cafe" finds "café". CJK
// characters are not letters here: definitions mention them ("variant of
// 嗬[he1]"), and a hanzi query must not match those as English words.
// Folding maps one UTF-16 unit to one, so positions in the folded text are
// positions in the original.

const _accented = 'àáâãäåāăąǎ çćĉċč ďđ èéêëēĕėęěẽ ĝğġģ ĥħ ìíîïĩīĭįıǐ ĵ ķ '
    'ĺļľŀł ñńņň òóôõöøōŏőǒ ŕŗř śŝşš ţťŧ ùúûüũūŭůűųǔǖǘǚǜ ŵ ýÿŷ źżž';
const _plain = 'a c d e g h i j k l n o r s t u w y z';

final Map<int, int> _fold = () {
  final map = <int, int>{};
  final groups = _accented.split(' ');
  final bases = _plain.split(' ');
  for (var g = 0; g < groups.length; g++) {
    for (final c in groups[g].codeUnits) {
      map[c] = bases[g].codeUnitAt(0);
    }
  }
  return map;
}();

/// The folded form of code unit [c], or -1 if it is not part of a word.
int _foldUnit(int c) {
  if ((c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F) {
    return c;
  }
  if (c >= 0x41 && c <= 0x5A) return c + 32;
  // Latin-1 Supplement and Latin Extended-A/B letters (not × and ÷).
  if (c < 0xC0 || c > 0x24F || c == 0xD7 || c == 0xF7) return -1;
  final lower = String.fromCharCode(c).toLowerCase();
  final l = lower.length == 1 ? lower.codeUnitAt(0) : c;
  return _fold[l] ?? l;
}

/// The words of [text] with their position in it.
List<({int start, int end, String word})> wordSpans(String text) {
  final spans = <({int start, int end, String word})>[];
  final buf = StringBuffer();
  var start = -1;
  for (var i = 0; i <= text.length; i++) {
    final f = i < text.length ? _foldUnit(text.codeUnitAt(i)) : -1;
    if (f >= 0) {
      if (start < 0) start = i;
      buf.writeCharCode(f);
    } else if (start >= 0) {
      spans.add((start: start, end: i, word: buf.toString()));
      buf.clear();
      start = -1;
    }
  }
  return spans;
}

/// The folded words of [text], in order.
List<String> words(String text) => [for (final s in wordSpans(text)) s.word];

/// [text] with word characters lowercased and folded, other characters
/// unchanged; same length as [text]. For substring matching.
String foldText(String text) => String.fromCharCodes([
      for (final c in text.codeUnits)
        if (_foldUnit(c) case final f when f >= 0) f else c,
    ]);
