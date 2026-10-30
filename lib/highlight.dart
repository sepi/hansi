// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/painting.dart';

import 'words.dart';

/// Words too common to be worth bolding, unless the query has nothing else.
const _stopwords = {'to', 'a', 'an', 'the', 'of', 'be', 'sth', 'sb'};

/// Splits [text] into spans with the words of [query] in bold. Words match
/// as search does: whole words, ignoring case and accents. Non-Latin
/// queries (hanzi) highlight nothing.
List<TextSpan> highlightWords(String text, String query) {
  final queryWords = words(query).toSet();
  final content = queryWords.difference(_stopwords);
  final targets = content.isEmpty ? queryWords : content;
  if (targets.isEmpty) return [TextSpan(text: text)];

  final spans = <TextSpan>[];
  var last = 0;
  for (final w in wordSpans(text)) {
    if (!targets.contains(w.word)) continue;
    if (w.start > last) spans.add(TextSpan(text: text.substring(last, w.start)));
    spans.add(TextSpan(
      text: text.substring(w.start, w.end),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ));
    last = w.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}
