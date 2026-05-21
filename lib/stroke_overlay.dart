// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stroke_order_animator/stroke_order_animator.dart';

import 'mma_entry.dart';
import 'pinyin_utils.dart';
import 'theme.dart';

const _kCellSize = 88.0;   // per-character stroke animator tile
const _kDialogSize = 240.0; // stroke animator inside the dialog

StrokeOrderAnimationController _makeController(
  String strokeJson,
  TickerProvider vsync, {
  double speed = 1.2,
}) =>
    StrokeOrderAnimationController(
      StrokeOrder(strokeJson),
      vsync,
      strokeAnimationSpeed: speed,
      strokeColor: kRed,
      showOutline: false,
      showBackground: true,
      backgroundColor: kStrokeBg,
    );

// ---------------------------------------------------------------------------
// Dialog overlay — shown when the user taps a character
// ---------------------------------------------------------------------------

class StrokeOverlay extends StatefulWidget {
  const StrokeOverlay({
    super.key,
    required this.char,
    required this.pinyin,
    required this.strokeJson,
    this.strokeSpeed = 1.2,
  });

  final String char;
  final String pinyin;
  final String strokeJson;
  final double strokeSpeed;

  @override
  State<StrokeOverlay> createState() => _StrokeOverlayState();
}

class _StrokeOverlayState extends State<StrokeOverlay>
    with TickerProviderStateMixin {
  late final StrokeOrderAnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        _makeController(widget.strokeJson, this, speed: widget.strokeSpeed);
    _controller.addListener(() => setState(() {}));
    _controller.startAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = _controller.isAnimating;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(widget.char,
                    style: const TextStyle(fontSize: 38, height: 1.1)),
                const SizedBox(width: 12),
                Text(widget.pinyin,
                    style: TextStyle(fontFamily: 'GentiumPlus', fontSize: 18)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            StrokeOrderAnimator(
              _controller,
              size: const Size(_kDialogSize, _kDialogSize),
              key: ValueKey(widget.char),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded),
                  iconSize: 30,
                  tooltip: 'Previous stroke',
                  onPressed: _controller.previousStroke,
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: playing
                      ? _controller.stopAnimation
                      : _controller.startAnimation,
                  icon: Icon(playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(playing ? 'Pause' : 'Play'),
                  style: FilledButton.styleFrom(backgroundColor: kRed),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  iconSize: 30,
                  tooltip: 'Next stroke',
                  onPressed: _controller.nextStroke,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline animator used in single-character tappable grids
// ---------------------------------------------------------------------------

class CharStrokeAnimator extends StatefulWidget {
  const CharStrokeAnimator({
    super.key,
    required this.strokeJson,
    this.size = 88,
    this.strokeSpeed = 1.2,
  });

  final String strokeJson;
  final double size;
  final double strokeSpeed;

  @override
  State<CharStrokeAnimator> createState() => _CharStrokeAnimatorState();
}


class _CharStrokeAnimatorState extends State<CharStrokeAnimator>
    with TickerProviderStateMixin {
  late final StrokeOrderAnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _makeController(widget.strokeJson, this, speed: widget.strokeSpeed);
    _controller.startAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StrokeOrderAnimator(_controller, size: Size(widget.size, widget.size));
}

// ---------------------------------------------------------------------------
// Sequential animator — plays characters one after another, then loops
// ---------------------------------------------------------------------------

class SequentialStrokeRow extends StatefulWidget {
  const SequentialStrokeRow({
    super.key,
    required this.chars,
    required this.syllables,
    required this.strokeData,
    required this.mmaData,
    required this.strokeSpeed,
    required this.onDecomposeTap,
    required this.onSearchTap,
  });

  /// Characters to animate, in order.
  final List<String> chars;

  /// Numbered pinyin syllables parallel to [chars] (e.g. 'ni3').
  final List<String> syllables;

  final Map<String, String> strokeData;
  final Map<String, MmaEntry> mmaData;
  final double strokeSpeed;

  /// Tap the tree icon — opens the decomposition dialog.
  final void Function(int index) onDecomposeTap;

  /// Tap the search icon — searches for that character.
  final void Function(int index) onSearchTap;

  @override
  State<SequentialStrokeRow> createState() => _SequentialStrokeRowState();
}

class _SequentialStrokeRowState extends State<SequentialStrokeRow>
    with TickerProviderStateMixin {
  late final List<StrokeOrderAnimationController?> _controllers;
  int _current = 0;
  bool _advancing = false;
  Timer? _pendingTimer;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final c in widget.chars)
        () {
          final json = widget.strokeData[c];
          return json != null
              ? _makeController(json, this, speed: widget.strokeSpeed)
              : null;
        }(),
    ];
    if (_controllers.any((c) => c != null)) {
      _pendingTimer = Timer(const Duration(milliseconds: 400), () {
        _pendingTimer = null;
        if (mounted) _playFrom(0);
      });
    }
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    for (final ctrl in _controllers) {
      ctrl?.removeListener(_onCtrlChanged);
      ctrl?.dispose();
    }
    super.dispose();
  }

  void _playFrom(int idx) {
    if (!mounted) return;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    // Chars before idx → end state (all strokes visible, stopped).
    for (int i = 0; i < idx; i++) {
      final ctrl = _controllers[i];
      if (ctrl == null) continue;
      ctrl.removeListener(_onCtrlChanged);
      ctrl.stopAnimation();
      _advanceToEnd(ctrl);
    }
    // Chars from idx onward → start state (blank, waiting).
    for (int i = idx; i < _controllers.length; i++) {
      final ctrl = _controllers[i];
      if (ctrl == null) continue;
      ctrl.removeListener(_onCtrlChanged);
      ctrl.stopAnimation();
      while (ctrl.currentStroke > 0) { ctrl.previousStroke(); }
    }
    setState(() => _current = idx);
    _startAt(idx);
  }

  void _advanceToEnd(StrokeOrderAnimationController ctrl) {
    final total = ctrl.strokeOrder.nStrokes;
    while (ctrl.currentStroke < total) {
      ctrl.nextStroke();
    }
  }

  void _startAt(int idx) {
    if (!mounted) return;
    _current = idx;
    _advancing = false;

    final ctrl = _controllers[idx];
    if (ctrl == null) {
      // No data for this character — skip after a brief delay.
      _pendingTimer = Timer(const Duration(milliseconds: 150), () {
        _pendingTimer = null;
        if (mounted) _advance();
      });
      return;
    }
    ctrl.addListener(_onCtrlChanged);
    ctrl.startAnimation();
  }

  void _onCtrlChanged() {
    if (_advancing) return;
    final ctrl = _controllers[_current];
    if (ctrl == null) return;
    // Detect natural end: animation stopped with strokes drawn.
    if (!ctrl.isAnimating && ctrl.currentStroke > 0) {
      _advancing = true;
      ctrl.removeListener(_onCtrlChanged);
      _pendingTimer = Timer(const Duration(milliseconds: 300), () {
        _pendingTimer = null;
        if (mounted) _advance();
      });
    }
  }

  void _advance() {
    final next = _current + 1;
    if (next >= widget.chars.length) {
      // All done — pause then loop from the start.
      _pendingTimer = Timer(const Duration(milliseconds: 700), () {
        _pendingTimer = null;
        if (mounted) _playFrom(0);
      });
    } else {
      _startAt(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: List.generate(widget.chars.length, (i) {
        final char = widget.chars[i];
        final syl = i < widget.syllables.length ? widget.syllables[i] : '';
        final ctrl = _controllers[i];
        final mmaEntry = widget.mmaData[char];
        final hasDecomp =
            mmaEntry != null && mmaEntry.decomposition != '？';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tap restarts the sequential animation from this character.
            GestureDetector(
              onTap: ctrl != null ? () => _playFrom(i) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ctrl != null
                      ? StrokeOrderAnimator(
                          ctrl,
                          size: const Size(_kCellSize, _kCellSize),
                        )
                      : Container(
                          width: _kCellSize,
                          height: _kCellSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: kStrokeBg,
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Text(char,
                              style: const TextStyle(fontSize: 52, height: 1)),
                        ),
                  Text(
                    toUnicodePinyin(syl),
                    style: TextStyle(fontFamily: 'GentiumPlus', fontSize: 13),
                  ),
                ],
              ),
            ),
            // Action icons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.account_tree_outlined,
                    color: hasDecomp
                        ? Colors.grey.shade600
                        : Colors.grey.shade300,
                  ),
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 24),
                  tooltip: 'Decomposition',
                  onPressed:
                      hasDecomp ? () => widget.onDecomposeTap(i) : null,
                ),
                IconButton(
                  icon: Icon(Icons.search, color: Colors.grey.shade600),
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 24),
                  tooltip: 'Search',
                  onPressed: () => widget.onSearchTap(i),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
