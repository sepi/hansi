import 'package:flutter/material.dart';

class SearchHistory extends StatelessWidget {
  const SearchHistory({
    super.key,
    required this.history,
    required this.onSelect,
    required this.onClear,
  });

  final List<String> history;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Theme.of(context).colorScheme.outline,
      letterSpacing: 0.8,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text('RECENT SEARCHES', style: labelStyle)),
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.outline,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: history.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(Icons.history, size: 18),
                  title: Text(history[i]),
                  onTap: () => onSelect(history[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
