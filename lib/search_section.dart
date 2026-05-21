// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

import 'theme.dart';

class SearchSection extends StatefulWidget {
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
    this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool searchHanzi;
  final bool searchPinyin;
  final bool searchEnglish;
  final ValueChanged<bool> onHanziChanged;
  final ValueChanged<bool> onPinyinChanged;
  final ValueChanged<bool> onEnglishChanged;

  @override
  State<SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends State<SearchSection> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (_, value, _) => TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () =>
                      widget.onSubmitted?.call(widget.controller.text),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SearchToggle(
                      label: '汉',
                      tooltip: 'Hanzi',
                      active: widget.searchHanzi,
                      onTap: () => widget.onHanziChanged(!widget.searchHanzi),
                    ),
                    SearchToggle(
                      label: 'pī',
                      tooltip: 'Pinyin',
                      active: widget.searchPinyin,
                      onTap: () => widget.onPinyinChanged(!widget.searchPinyin),
                    ),
                    SearchToggle(
                      label: 'En',
                      tooltip: 'English',
                      active: widget.searchEnglish,
                      onTap: () => widget.onEnglishChanged(!widget.searchEnglish),
                    ),
                    if (value.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          widget.controller.clear();
                          widget.onChanged('');
                          _focusNode.requestFocus();
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
