// SPDX-License-Identifier: AGPL-3.0-or-later
class MmaEtymology {
  const MmaEtymology({
    required this.type,
    this.hint,
    this.semantic,
    this.phonetic,
  });

  final String type; // 'pictographic' | 'ideographic' | 'pictophonetic'
  final String? hint;
  final String? semantic;
  final String? phonetic;

  factory MmaEtymology.fromJson(Map<String, dynamic> j) => MmaEtymology(
        type: (j['type'] as String?) ?? 'unknown',
        hint: j['hint'] as String?,
        semantic: j['semantic'] as String?,
        phonetic: j['phonetic'] as String?,
      );
}

class MmaEntry {
  const MmaEntry({
    required this.character,
    required this.decomposition,
    required this.radical,
    this.etymology,
    this.pinyin = const [],
    this.definition,
  });

  final String character;
  final String decomposition; // IDS string, e.g. '⿰氵青'
  final String radical;
  final MmaEtymology? etymology;
  final List<String> pinyin;
  final String? definition;

  factory MmaEntry.fromJson(Map<String, dynamic> j) => MmaEntry(
        character: j['character'] as String,
        decomposition: (j['decomposition'] as String?) ?? '？',
        radical: (j['radical'] as String?) ?? '',
        etymology: j['etymology'] != null
            ? MmaEtymology.fromJson(j['etymology'] as Map<String, dynamic>)
            : null,
        pinyin: (j['pinyin'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        definition: j['definition'] as String?,
      );
}
