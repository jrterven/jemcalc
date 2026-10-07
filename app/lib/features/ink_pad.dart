import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/strings.dart';

class InkPad extends StatefulWidget {
  const InkPad({
    super.key,
    required this.strokes,
    required this.onChanged,
    required this.onRecognize,
    required this.strings,
    required this.busy,
  });
  final List<List<Offset>> strokes;
  final ValueChanged<List<List<Offset>>> onChanged;
  final VoidCallback onRecognize;
  final Strings strings;
  final bool busy;
  @override
  State<InkPad> createState() => _InkPadState();
}

class _InkPadState extends State<InkPad> {
  final List<List<Offset>> redo = [];
  List<Offset>? current;
  bool stylusOnly = false, eraser = false;
  int? pointer;
  List<List<Offset>> get lines => widget.strokes;
  void changed(List<List<Offset>> value) {
    widget.onChanged(value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final color = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: s.t('Deshacer', 'Undo'),
              onPressed: lines.isEmpty
                  ? null
                  : () {
                      redo.add(lines.last);
                      changed(lines.sublist(0, lines.length - 1));
                    },
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: s.t('Rehacer', 'Redo'),
              onPressed: redo.isEmpty
                  ? null
                  : () => changed([...lines, redo.removeLast()]),
              icon: const Icon(Icons.redo_rounded),
            ),
            IconButton(
              tooltip: s.t('Borrador por trazo', 'Stroke eraser'),
              isSelected: eraser,
              onPressed: () => setState(() => eraser = !eraser),
              icon: const Icon(Icons.auto_fix_normal_rounded),
            ),
            IconButton(
              tooltip: s.t('Limpiar lienzo', 'Clear canvas'),
              onPressed: lines.isEmpty
                  ? null
                  : () {
                      redo.clear();
                      changed([]);
                    },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            const Spacer(),
            FilterChip(
              label: Text(s.t('Solo lápiz', 'Pen only')),
              selected: stylusOnly,
              onSelected: (v) => setState(() => stylusOnly = v),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final scale = (width / 1000).clamp(0.0, height / 600);
              final canvasSize = Size(1000 * scale, 600 * scale);
              return Center(
                child: Semantics(
                  label: s.t(
                    'Lienzo para escribir una ecuación',
                    'Canvas for handwriting an equation',
                  ),
                  child: SizedBox.fromSize(
                    size: canvasSize,
                    child: Listener(
                      key: const ValueKey('ink-canvas'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (event) {
                        if (pointer != null ||
                            (stylusOnly &&
                                event.kind != PointerDeviceKind.stylus &&
                                event.kind !=
                                    PointerDeviceKind.invertedStylus)) {
                          return;
                        }
                        pointer = event.pointer;
                        final p = event.localPosition / scale;
                        if (eraser ||
                            event.kind == PointerDeviceKind.invertedStylus) {
                          changed(
                            lines
                                .where(
                                  (line) =>
                                      !line.any((q) => (q - p).distance < 25),
                                )
                                .toList(),
                          );
                          return;
                        }
                        setState(() => current = [p]);
                      },
                      onPointerMove: (event) {
                        if (event.pointer != pointer) return;
                        final p = event.localPosition / scale;
                        if (eraser) {
                          changed(
                            lines
                                .where(
                                  (line) =>
                                      !line.any((q) => (q - p).distance < 25),
                                )
                                .toList(),
                          );
                        } else if (current != null) {
                          setState(() => current!.add(p));
                        }
                      },
                      onPointerUp: (event) {
                        if (event.pointer != pointer) return;
                        pointer = null;
                        if (current != null && current!.isNotEmpty) {
                          redo.clear();
                          changed([...lines, current!]);
                          current = null;
                        }
                      },
                      onPointerCancel: (event) {
                        if (event.pointer == pointer) {
                          setState(() {
                            pointer = null;
                            current = null;
                          });
                        }
                      },
                      child: CustomPaint(
                        painter: _InkPainter(
                          [...lines, ?current],
                          color.onSurface,
                          color.primary,
                          scale,
                        ),
                        child: lines.isEmpty && current == null
                            ? Center(
                                child: IgnorePointer(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.draw_outlined,
                                        size: 36,
                                        color: color.primary.withValues(
                                          alpha: .5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        s.t(
                                          'Escribe una ecuación',
                                          'Write an equation',
                                        ),
                                        style: TextStyle(
                                          color: color.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: widget.busy || lines.isEmpty ? null : widget.onRecognize,
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(s.t('Reconocer ecuación', 'Recognize equation')),
        ),
      ],
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.lines, this.ink, this.accent, this.scale);
  final List<List<Offset>> lines;
  final Color ink, accent;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = accent.withValues(alpha: .14);
    for (double x = 12; x < size.width; x += 22) {
      for (double y = 12; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), .85, grid);
      }
    }
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.length == 1) {
        canvas.drawCircle(line.first * scale, 1.3, Paint()..color = ink);
        continue;
      }
      final p = Path()..moveTo(line.first.dx * scale, line.first.dy * scale);
      for (final point in line.skip(1)) {
        p.lineTo(point.dx * scale, point.dy * scale);
      }
      canvas.drawPath(p, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
