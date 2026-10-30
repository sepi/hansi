import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/highlight.dart';

/// Renders spans as text with bold parts in [brackets].
String _render(List<TextSpan> spans) => spans
    .map((s) => s.style?.fontWeight == FontWeight.bold ? '[${s.text}]' : s.text)
    .join();

void main() {
  test('bolds whole-word matches case-insensitively', () {
    expect(_render(highlightWords('① Bank; shore\n② river bank', 'bank')),
        '① [Bank]; shore\n② river [bank]');
  });

  test('does not bold partial words', () {
    expect(_render(highlightWords('riverbank; banking', 'bank')),
        'riverbank; banking');
  });

  test('skips stopwords unless the query has nothing else', () {
    expect(_render(highlightWords('to speak; to say', 'to speak')),
        'to [speak]; to say');
    expect(_render(highlightWords('to speak', 'to')), '[to] speak');
  });

  test('matches ignore accents in either text or query', () {
    expect(_render(highlightWords('café; coffee shop', 'cafe')),
        '[café]; coffee shop');
    expect(_render(highlightWords('Zurich, Switzerland', 'zürich')),
        '[Zurich], Switzerland');
    expect(_render(highlightWords('Zürich', 'rich')), 'Zürich');
  });

  test('hanzi query highlights nothing', () {
    expect(_render(highlightWords('good; well', '好')), 'good; well');
  });

  test('regex characters in the query are literal', () {
    expect(_render(highlightWords('a (b) c', '(b)')), 'a ([b]) c');
  });
}
