// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import 'dict_entry.dart';
import 'theme.dart';

/// Four-character idioms common enough to be worth a daily card: marked
/// "(idiom)" in CC-CEDICT and within the 40,000 most frequent words.
List<DictEntry> commonIdioms(
  List<DictEntry> entries,
  Map<String, int> freqMap,
) {
  final idioms = [
    for (final e in entries)
      if (e.simplified.length == 4 &&
          (freqMap[e.simplified] ?? 1 << 30) <= 40000 &&
          e.definitions.any((d) => d.contains('(idiom)')))
        e,
  ];
  // A fixed order, so the same day always picks the same idiom.
  return idioms..sort((a, b) => a.simplified.compareTo(b.simplified));
}

/// The idiom for [day]'s local date; stepping by a prime spreads
/// consecutive days across the list.
DictEntry idiomOfTheDay(List<DictEntry> idioms, DateTime day) {
  final days = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(2000)).inDays;
  return idioms[(days * 7919) % idioms.length];
}

/// Splits CC-CEDICT's "lit. … ; fig. …" into the literal picture and the
/// meaning; definitions without "lit." are all meaning.
({String? literal, String meaning}) idiomMeaning(DictEntry e) {
  final parts = [
    for (final d in e.definitions)
      for (final p in d.split(';')) p.replaceAll('(idiom)', '').trim(),
  ].where((p) => p.isNotEmpty).toList();
  String? literal;
  final meaning = <String>[];
  for (final p in parts) {
    if (literal == null && p.startsWith('lit.')) {
      literal = p.substring(4).trim();
    } else {
      meaning.add(p.startsWith('fig.') ? p.substring(4).trim() : p);
    }
  }
  return (literal: literal, meaning: meaning.join('; '));
}

class IdiomCard extends StatelessWidget {
  const IdiomCard({
    super.key,
    required this.entry,
    required this.font,
    required this.toneColors,
    required this.showTraditional,
    required this.onTap,
  });

  final DictEntry entry;
  final HanziFont font;
  final List<Color>? toneColors;
  final bool showTraditional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final (:literal, :meaning) = idiomMeaning(entry);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SizedBox(
          width: double.infinity,
          child: Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'IDIOM OF THE DAY',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: outline,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    hanziPinyinGrid(
                      context,
                      showTraditional ? entry.traditional : entry.simplified,
                      entry.pinyin,
                      TextStyle(fontFamily: font.family, fontSize: 30),
                      const TextStyle(fontFamily: 'GentiumPlus', fontSize: 13),
                      toneColors: toneColors,
                    ),
                    const SizedBox(height: 8),
                    if (literal != null)
                      Text(
                        'lit. $literal',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: outline,
                        ),
                      ),
                    Text(
                      meaning,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
