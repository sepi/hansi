import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/words.dart';

void main() {
  test('splits on non-letters and lowercases', () {
    expect(words('To speak; to SAY (sth)'), ['to', 'speak', 'to', 'say', 'sth']);
    expect(words('x-ray, don\'t, T-shirt'), ['x', 'ray', 'don', 't', 't', 'shirt']);
    expect(words('PM2.5 under_score'), ['pm2', '5', 'under_score']);
  });

  test('accented Latin letters stay in the word and are folded', () {
    expect(words('Zürich café Pokémon naïve'), ['zurich', 'cafe', 'pokemon', 'naive']);
    expect(words('Ürümqi Lüliang Garzê Ryūkyū'), ['urumqi', 'luliang', 'garze', 'ryukyu']);
    expect(words('lǜsè nǐhǎo'), ['luse', 'nihao']);
  });

  test('CJK characters and other scripts separate words', () {
    expect(words('variant of 嗬[he1]'), ['variant', 'of', 'he1']);
    expect(words('CL:個|个[ge4]'), ['cl', 'ge4']);
    expect(words('γ射線'), isEmpty);
    expect(words('2×3÷4'), ['2', '3', '4']);
  });

  test('spans point at the original text', () {
    const text = 'a Café, really';
    final spans = wordSpans(text);
    expect([for (final s in spans) text.substring(s.start, s.end)],
        ['a', 'Café', 'really']);
    expect(spans[1].word, 'cafe');
  });

  test('foldText keeps length and non-word characters', () {
    const text = 'Café; Zürich (CL:個)';
    expect(foldText(text), 'cafe; zurich (cl:個)');
    expect(foldText(text).length, text.length);
  });
}
