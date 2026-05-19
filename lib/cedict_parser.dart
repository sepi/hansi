// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dict_entry.dart';

final _lineRe = RegExp(r'^(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+/(.+)/$');

List<DictEntry> parseCedict(String text) {
  final entries = <DictEntry>[];
  for (var line in text.split('\n')) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.isEmpty || line.startsWith('#')) continue;
    final m = _lineRe.firstMatch(line);
    if (m == null) continue;
    entries.add(DictEntry(
      traditional: m.group(1)!,
      simplified: m.group(2)!,
      pinyin: m.group(3)!,
      definitions: m.group(4)!.split('/'),
    ));
  }
  return entries;
}
