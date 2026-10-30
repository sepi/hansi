// SPDX-License-Identifier: AGPL-3.0-or-later
// Regenerates assets/word_index.bin, the prebuilt English search index.
// Run after updating assets/cedict.txt.gz or changing the tokenizer:
//
//   dart run tool/build_index.dart
import 'dart:convert';
import 'dart:io';

import 'package:hansi/cedict_parser.dart';
import 'package:hansi/search.dart';

void main() {
  final entries = parseCedict(utf8
      .decode(gzip.decode(File('assets/cedict.txt.gz').readAsBytesSync())));
  final bytes = encodeWordIndex(buildWordIndex(entries));
  File('assets/word_index.bin').writeAsBytesSync(bytes);
  stdout.writeln('${entries.length} entries, ${bytes.length} bytes '
      'written to assets/word_index.bin');
}
