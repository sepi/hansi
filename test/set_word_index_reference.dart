// Reference copy of the set-based word index that the inverted WordIndex
// replaced. Kept only so tests can check the new index holds exactly the
// same words per entry and definition.
import 'package:hansi/dict_entry.dart';
import 'package:hansi/search.dart' show tokenizeDef;

class SetWordIndex {
  SetWordIndex(List<DictEntry> entries) {
    for (final entry in entries) {
      final sets = entry.definitions.map(tokenizeDef).toList();
      perDef.add(sets);
      combined.add({for (final s in sets) ...s});
      normStr.add(
        entry.definitions.map((d) => d.toLowerCase().replaceAll(';', ' ')).join(' '),
      );
    }
  }

  final perDef = <List<Set<String>>>[];
  final combined = <Set<String>>[];
  final normStr = <String>[];
}
