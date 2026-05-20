// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math';
import 'package:flutter/material.dart';

import 'mma_entry.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// IDS helpers
// ---------------------------------------------------------------------------

bool _isIdsOp(int cp) => cp >= 0x2FF0 && cp <= 0x2FFB;

/// Recursively parse an IDS string and return the leaf component characters.
List<String> _components(String ids) => ids.runes
    .where((cp) => !_isIdsOp(cp))
    .map(String.fromCharCode)
    .where((s) => s != '？')
    .toList();

/// Return the top-level IDS operator (first rune), or null if not an operator.
String? _topOp(String ids) {
  if (ids.isEmpty) return null;
  final cp = ids.runes.first;
  return _isIdsOp(cp) ? String.fromCharCode(cp) : null;
}

// ---------------------------------------------------------------------------
// Tree data model
// ---------------------------------------------------------------------------

enum _Role { semantic, phonetic, radical }

class _Node {
  _Node({
    required this.char,
    required this.pinyin,
    required this.children,
    this.idsOp,
    this.role,
    this.etymHint,
  });
  final String char;
  final String pinyin;
  final List<_Node> children;
  final String? idsOp;   // IDS operator used to split this node's children
  final _Role? role;
  final String? etymHint; // root only
}

_Node _build(
  String char,
  Map<String, MmaEntry> mmaData, {
  int depth = 0,
  _Role? role,
}) {
  final entry = mmaData[char];
  final pinyin =
      (entry?.pinyin.isNotEmpty ?? false) ? entry!.pinyin.first : '';
  String? idsOp;
  final children = <_Node>[];

  if (depth < 2 && entry != null && entry.decomposition != '？') {
    final ids = entry.decomposition;
    idsOp = _topOp(ids);
    final comps = _components(ids);
    final etym = entry.etymology;
    for (final comp in comps) {
      _Role? childRole;
      if (etym?.type == 'pictophonetic') {
        if (comp == etym?.semantic) {
          childRole = _Role.semantic;
        } else if (comp == etym?.phonetic) {
          childRole = _Role.phonetic;
        }
      }
      childRole ??= (entry.radical == comp ? _Role.radical : null);
      children.add(_build(comp, mmaData, depth: depth + 1, role: childRole));
    }
  }

  return _Node(
    char: char,
    pinyin: pinyin,
    children: children,
    idsOp: children.isNotEmpty ? idsOp : null,
    role: role,
    etymHint: depth == 0 ? entry?.etymology?.hint : null,
  );
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

const double _kW = 96;        // node chip width  (80 × 1.2)
const double _kH = 106;       // node chip height (88 × 1.2)
const double _kLevelH = 173;  // top-to-top distance between levels (144 × 1.2)
const double _kHGap = 14;     // horizontal gap between sibling subtrees (12 × 1.2)
const double _kOpSize = 31;   // op badge diameter (26 × 1.2)
// Vertical space above and below the op badge within the gap:
const double _kOpPad = (_kLevelH - _kH - _kOpSize) / 2; // = 18

class _LNode {
  _LNode(this.data) : kids = data.children.map(_LNode.new).toList();
  final _Node data;
  final List<_LNode> kids;
  double cx = 0;
  double top = 0;
  double sw = 0; // subtree width
}

void _layout(_LNode n, double left, double top) {
  n.top = top;
  if (n.kids.isEmpty) {
    n.sw = _kW;
    n.cx = left + _kW / 2;
    return;
  }
  double x = left;
  for (int i = 0; i < n.kids.length; i++) {
    _layout(n.kids[i], x, top + _kLevelH);
    x += n.kids[i].sw + (i < n.kids.length - 1 ? _kHGap : 0);
  }
  n.sw = max(_kW, x - left);
  n.cx = left + n.sw / 2;
}

void _collect(_LNode n, List<_LNode> out) {
  out.add(n);
  for (final k in n.kids) {
    _collect(k, out);
  }
}

int _maxDepth(_LNode n) =>
    n.kids.isEmpty ? 0 : 1 + n.kids.map(_maxDepth).reduce(max);

// ---------------------------------------------------------------------------
// Connector line painter
// ---------------------------------------------------------------------------

class _LinePainter extends CustomPainter {
  const _LinePainter(this.nodes);
  final List<_LNode> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final n in nodes) {
      if (n.kids.isEmpty) continue;
      // Centre-y of the op badge — the horizontal bar lives here.
      final opCy = n.top + _kH + _kOpPad + _kOpSize / 2;
      // Vertical stem from parent chip bottom down to op badge centre.
      canvas.drawLine(
        Offset(n.cx, n.top + _kH),
        Offset(n.cx, opCy),
        paint,
      );
      for (final k in n.kids) {
        // Horizontal branch from op badge centre to child's column.
        canvas.drawLine(Offset(n.cx, opCy), Offset(k.cx, opCy), paint);
        // Vertical drop from branch to child chip top.
        canvas.drawLine(Offset(k.cx, opCy), Offset(k.cx, k.top), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => false;
}

// ---------------------------------------------------------------------------
// Op badge — shown at each fork point
// ---------------------------------------------------------------------------

class _OpBadge extends StatelessWidget {
  const _OpBadge(this.op);
  final String op;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kOpSize,
      height: _kOpSize,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Center(
        child: Text(
          op,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Node chip
// ---------------------------------------------------------------------------

Color _roleColor(_Role r) => switch (r) {
      _Role.semantic => Colors.green.shade700,
      _Role.phonetic => Colors.blue.shade700,
      _Role.radical => kRed,
    };

String _roleLabel(_Role r) => switch (r) {
      _Role.semantic => 'sem',
      _Role.phonetic => 'pho',
      _Role.radical => 'rad',
    };

class _Chip extends StatelessWidget {
  const _Chip(this.n, {required this.isRoot, this.onSearch});
  final _LNode n;
  final bool isRoot;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final d = n.data;
    final role = d.role;
    final Color borderColor =
        role != null ? _roleColor(role) : Colors.grey.shade300;
    final Color bg = isRoot ? kRed.withValues(alpha: 0.07) : Colors.grey.shade50;

    return Container(
      width: _kW,
      height: _kH,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor, width: role != null ? 2 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(d.char, style: const TextStyle(fontSize: 36, height: 1.1)),
                  if (d.pinyin.isNotEmpty)
                    Text(
                      d.pinyin,
                      style: TextStyle(fontFamily: 'GentiumPlus', fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (role != null) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _roleColor(role).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        _roleLabel(role),
                        style: TextStyle(
                          fontSize: 11,
                          color: _roleColor(role),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (onSearch != null)
            Positioned(
              bottom: 2,
              right: 2,
              child: IconButton(
                icon: Icon(Icons.search, color: Colors.grey.shade600),
                iconSize: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                onPressed: onSearch,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

class DecompositionTree extends StatelessWidget {
  const DecompositionTree({
    super.key,
    required this.char,
    required this.mmaData,
    this.onSearch,
  });

  final String char;
  final Map<String, MmaEntry> mmaData;
  final void Function(String char)? onSearch;

  @override
  Widget build(BuildContext context) {
    final entry = mmaData[char];
    if (entry == null || entry.decomposition == '？') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No decomposition data.',
          style: TextStyle(
              fontSize: 13, color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    final root = _build(char, mmaData);
    final lRoot = _LNode(root);
    _layout(lRoot, 0, 0);

    final all = <_LNode>[];
    _collect(lRoot, all);

    final depth = _maxDepth(lRoot);
    final totalH = depth * _kLevelH + _kH;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (root.etymHint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              root.etymHint!,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final treeW = max(lRoot.sw, _kW);
            final canvas = SizedBox(
              width: treeW,
              height: totalH,
              child: Stack(
                children: [
                  // Connector lines (drawn first, behind everything)
                  Positioned.fill(
                    child: CustomPaint(painter: _LinePainter(all)),
                  ),
                  // Node chips
                  for (final n in all)
                    Positioned(
                      left: n.cx - _kW / 2,
                      top: n.top,
                      child: _Chip(
                        n,
                        isRoot: n == lRoot,
                        onSearch: (onSearch != null && n != lRoot)
                            ? () => onSearch!(n.data.char)
                            : null,
                      ),
                    ),
                  // Op badges at fork points (drawn on top of lines)
                  for (final n in all)
                    if (n.data.idsOp != null)
                      Positioned(
                        left: n.cx - _kOpSize / 2,
                        top: n.top + _kH + _kOpPad,
                        child: _OpBadge(n.data.idsOp!),
                      ),
                ],
              ),
            );
            if (treeW <= constraints.maxWidth) {
              return Center(child: canvas);
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: canvas,
            );
          },
        ),
      ],
    );
  }
}
