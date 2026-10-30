// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'menu_sheet.dart';
import 'theme.dart';

/// Display settings shared by every screen. Setting a value notifies
/// listeners, so all open screens update, and saves it.
class AppSettings extends ChangeNotifier {
  HanziFont _font = HanziFont.sans;
  AppTextSize _textSize = AppTextSize.md;
  List<Color>? _toneColors; // null = disabled
  bool _showTraditional = false;
  double _strokeSpeed = 1.2;

  HanziFont get font => _font;
  set font(HanziFont v) => _set(() => _font = v);

  AppTextSize get textSize => _textSize;
  set textSize(AppTextSize v) => _set(() => _textSize = v);

  List<Color>? get toneColors => _toneColors;
  set toneColors(List<Color>? v) => _set(() => _toneColors = v);

  bool get showTraditional => _showTraditional;
  set showTraditional(bool v) => _set(() => _showTraditional = v);

  double get strokeSpeed => _strokeSpeed;
  set strokeSpeed(double v) => _set(() => _strokeSpeed = v);

  void _set(VoidCallback change) {
    change();
    notifyListeners();
    _save();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fontIdx = prefs.getInt('font') ?? 0;
    final sizeIdx = prefs.getInt('text_size') ?? 2;
    _font = HanziFont.values[fontIdx.clamp(0, HanziFont.values.length - 1)];
    _textSize =
        AppTextSize.values[sizeIdx.clamp(0, AppTextSize.values.length - 1)];
    final toneEnabled = prefs.getBool('tone_colors') ?? false;
    _toneColors = toneEnabled
        ? List.generate(5, (i) =>
            Color(prefs.getInt('tone_color_$i') ?? kDefaultToneColors[i].toARGB32()))
        : null;
    _showTraditional = prefs.getBool('show_traditional') ?? false;
    _strokeSpeed = prefs.getDouble('stroke_speed') ?? 1.2;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('font', _font.index);
    await prefs.setInt('text_size', _textSize.index);
    await prefs.setBool('tone_colors', _toneColors != null);
    final colors = _toneColors ?? kDefaultToneColors;
    for (var i = 0; i < 5; i++) {
      await prefs.setInt('tone_color_$i', colors[i].toARGB32());
    }
    await prefs.setBool('show_traditional', _showTraditional);
    await prefs.setDouble('stroke_speed', _strokeSpeed);
  }
}

/// App bar gear button that opens the settings sheet.
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    required this.settings,
    required this.ankiInstalled,
  });

  final AppSettings settings;
  final bool ankiInstalled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Settings',
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => MenuSheet(
          font: settings.font,
          textSize: settings.textSize,
          toneColors: settings.toneColors,
          showTraditional: settings.showTraditional,
          strokeSpeed: settings.strokeSpeed,
          onFontChanged: (v) => settings.font = v,
          onSizeChanged: (v) => settings.textSize = v,
          onToneColorsChanged: (v) => settings.toneColors = v,
          onTraditionalChanged: (v) => settings.showTraditional = v,
          onStrokeSpeedChanged: (v) => settings.strokeSpeed = v,
          ankiInstalled: ankiInstalled,
        ),
      ),
    );
  }
}
