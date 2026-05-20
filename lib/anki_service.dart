// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnkiService {
  AnkiService._();
  static final AnkiService instance = AnkiService._();

  static const _ch = MethodChannel('com.example.hansi/anki');

  Future<bool> get isInstalled async {
    try {
      return await _ch.invokeMethod<bool>('isInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      return await _ch.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _ch.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> addNote(String hanzi, String pinyin, String english) =>
      _ch.invokeMethod('addNote', {
        'hanzi': hanzi,
        'pinyin': pinyin,
        'english': english,
      });
}

/// Shows an explanation dialog then requests the AnkiDroid permission.
/// Returns true if permission is granted (either already or after the request).
Future<bool> ensureAnkiPermission(BuildContext context) async {
  if (await AnkiService.instance.hasPermission()) return true;
  if (!context.mounted) return false;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('AnkiDroid Access'),
      content: const Text(
          'Allow Hansi to add flashcards directly to AnkiDroid?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  if (proceed != true) return false;
  return AnkiService.instance.requestPermission();
}
