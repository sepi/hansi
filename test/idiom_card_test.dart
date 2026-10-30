import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hansi/asset_loader.dart';
import 'package:hansi/cedict_parser.dart';
import 'package:hansi/dict_entry.dart';
import 'package:hansi/idiom_card.dart';
import 'package:hansi/theme.dart';

String _gz(String path) =>
    utf8.decode(GZipDecoder().decodeBytes(File(path).readAsBytesSync()));

void main() {
  final entries = parseCedict(_gz('assets/cedict.txt.gz'));
  final freq = parseNumberedWords(_gz('assets/word_freq.tsv.gz'));
  final idioms = commonIdioms(entries, freq);

  test('pool holds common four-character idioms', () {
    expect(idioms.length, greaterThan(1000));
    expect(idioms.every((e) => e.simplified.length == 4), isTrue);
    expect(idioms.map((e) => e.simplified), contains('一模一样'));
  });

  test('one idiom per day, changing at midnight', () {
    final morning = idiomOfTheDay(idioms, DateTime(2026, 10, 30, 7));
    final evening = idiomOfTheDay(idioms, DateTime(2026, 10, 30, 23, 59));
    final tomorrow = idiomOfTheDay(idioms, DateTime(2026, 10, 31, 0, 1));
    expect(identical(morning, evening), isTrue);
    expect(identical(morning, tomorrow), isFalse);
    final week = {
      for (var d = 0; d < 7; d++)
        idiomOfTheDay(idioms, DateTime(2026, 11, 1 + d)).simplified,
    };
    expect(week.length, 7);
  });

  test('splits literal and figurative meaning', () {
    final m = idiomMeaning(DictEntry(
      traditional: '畫蛇添足', simplified: '画蛇添足', pinyin: 'hua4 she2 tian1 zu2',
      definitions: [
        'lit. draw legs on a snake (idiom); fig. to ruin the effect by adding sth superfluous',
        'to overdo it',
      ],
    ));
    expect(m.literal, 'draw legs on a snake');
    expect(m.meaning, 'to ruin the effect by adding sth superfluous; to overdo it');

    final plain = idiomMeaning(DictEntry(
      traditional: '一模一樣', simplified: '一模一样', pinyin: 'yi1 mu2 yi1 yang4',
      definitions: ['(idiom) exactly alike; identical'],
    ));
    expect(plain.literal, isNull);
    expect(plain.meaning, 'exactly alike; identical');
  });

  testWidgets('card fits a phone and taps through', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var tapped = false;
    final longest = idioms.reduce((a, b) =>
        idiomMeaning(a).meaning.length >= idiomMeaning(b).meaning.length ? a : b);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IdiomCard(
          entry: longest,
          font: HanziFont.sans,
          toneColors: null,
          showTraditional: false,
          onTap: () => tapped = true,
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    // Full width; the Card's size includes its 16 px side margins.
    expect(tester.getSize(find.byType(Card)).width, 360);
    // Content is centred.
    for (final f in [find.text('IDIOM OF THE DAY'), find.byType(Wrap)]) {
      expect(tester.getCenter(f).dx, closeTo(180, 1));
    }
    await tester.tap(find.text('IDIOM OF THE DAY'));
    expect(tapped, isTrue);
  });
}
