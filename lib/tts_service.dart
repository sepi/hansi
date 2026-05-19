// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_tts/flutter_tts.dart';

/// Thin singleton wrapper around FlutterTts.
/// Stops any in-progress speech before starting a new utterance.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final _tts = FlutterTts();

  /// Speak [text] in Mandarin Chinese.
  /// Uses zh-TW when [traditional] is true, zh-CN otherwise.
  Future<void> speak(String text, {bool traditional = false}) async {
    await _tts.stop();
    await _tts.setLanguage(traditional ? 'zh-TW' : 'zh-CN');
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
