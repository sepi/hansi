class DictEntry {
  const DictEntry({
    required this.traditional,
    required this.simplified,
    required this.pinyin,
    required this.definitions,
  });

  final String traditional;
  final String simplified;
  final String pinyin;
  final List<String> definitions;
}
