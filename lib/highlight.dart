// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/painting.dart';

/// Words too common to be worth bolding, unless the query has nothing else.
const _stopwords = {'to', 'a', 'an', 'the', 'of', 'be', 'sth', 'sb'};

final _nonWord = RegExp(r'\W+');

/// Splits [text] into spans with whole-word, case-insensitive matches of the
/// words in [query] in bold. Non-Latin queries (hanzi) highlight nothing.
List<TextSpan> highlightWords(String text, String query) {
  final words = query
      .toLowerCase()
      .split(_nonWord)
      .where((w) => w.isNotEmpty)
      .toSet();
  final content = words.difference(_stopwords);
  final targets = content.isEmpty ? words : content;
  if (targets.isEmpty) return [TextSpan(text: text)];

  final pattern = RegExp(
    '\\b(${targets.map(RegExp.escape).join('|')})\\b',
    caseSensitive: false,
  );
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(TextSpan(
      text: m[0],
      style: const TextStyle(fontWeight: FontWeight.bold),
    ));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}
