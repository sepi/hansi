import 'package:flutter/material.dart';

import 'theme.dart';

class SearchSection extends StatelessWidget {
  const SearchSection({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.searchHanzi,
    required this.searchPinyin,
    required this.searchEnglish,
    required this.onHanziChanged,
    required this.onPinyinChanged,
    required this.onEnglishChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool searchHanzi;
  final bool searchPinyin;
  final bool searchEnglish;
  final ValueChanged<bool> onHanziChanged;
  final ValueChanged<bool> onPinyinChanged;
  final ValueChanged<bool> onEnglishChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SearchToggle(
                      label: '汉',
                      tooltip: 'Hanzi',
                      active: searchHanzi,
                      onTap: () => onHanziChanged(!searchHanzi),
                    ),
                    SearchToggle(
                      label: 'pī',
                      tooltip: 'Pinyin',
                      active: searchPinyin,
                      onTap: () => onPinyinChanged(!searchPinyin),
                    ),
                    SearchToggle(
                      label: 'En',
                      tooltip: 'English',
                      active: searchEnglish,
                      onTap: () => onEnglishChanged(!searchEnglish),
                    ),
                    if (value.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
                  ],
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SearchToggle extends StatelessWidget {
  const SearchToggle({
    super.key,
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: active ? kRed : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
