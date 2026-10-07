import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../core/strings.dart';
import '../core/palette.dart';
import '../math/evaluator.dart';
import '../math/plot.dart';

typedef CurveSegments = List<List<List<double>>>;
typedef CurveBatch = Map<int, CurveSegments>;

/// Adaptive real-domain samples, clipped to the viewport before reaching Skia.
/// This is a bounded numerical plot, not a proof of continuity: unresolved
/// intervals are left as gaps rather than connected through a possible pole.
CurveSegments sampleCurve(Map<String, dynamic> request) {
  final ast = Map<String, dynamic>.from(request['ast'] as Map);
  final xmin = request['xmin'] as double, xmax = request['xmax'] as double;
  final ymin = request['ymin'] as double,
      ymax = request['ymax'] as double,
      yr = ymax - ymin;
  final angle = request['angle'] as String;
  if (![xmin, xmax, ymin, ymax].every((v) => v.isFinite) ||
      xmax <= xmin ||
      ymax <= ymin) {
    return [];
  }
  if (request['kind'] == 'vertical') {
    try {
      final x = evaluateDouble(ast, angleMode: angle);
      return x >= xmin && x <= xmax
          ? [
              [
                [x, ymin],
                [x, ymax],
              ],
            ]
          : [];
    } catch (_) {
      return [];
    }
  }
  var evaluations = 0;
  double? at(double x) {
    if (++evaluations > 12000) return null;
    try {
      final y = evaluateDouble(ast, angleMode: angle, variables: {'x': x});
      return y.isFinite && y.abs() < 1e100 ? y : null;
    } catch (_) {
      return null;
    }
  }

  final segments = <List<List<double>>>[];
  var current = <List<double>>[];
  void gap() {
    if (current.length > 1) segments.add(current);
    current = [];
  }

  void edge(double x0, double y0, double x1, double y1) {
    final dy = y1 - y0;
    var lo = 0.0, hi = 1.0;
    if (dy == 0) {
      if (y0 < ymin || y0 > ymax) {
        gap();
        return;
      }
    } else {
      final a = (ymin - y0) / dy, b = (ymax - y0) / dy;
      lo = math.max(lo, math.min(a, b));
      hi = math.min(hi, math.max(a, b));
      if (hi < lo) {
        gap();
        return;
      }
    }
    final start = lo == 0
        ? [x0, y0]
        : [x0 + (x1 - x0) * lo, (y0 + dy * lo).clamp(ymin, ymax)];
    final end = hi == 1
        ? [x1, y1]
        : [x0 + (x1 - x0) * hi, (y0 + dy * hi).clamp(ymin, ymax)];
    if (current.isNotEmpty &&
        (current.last[0] != start[0] || current.last[1] != start[1])) {
      gap();
    }
    if (current.isEmpty) current.add(start);
    if (current.last[0] != end[0] || current.last[1] != end[1]) {
      current.add(end);
    }
    if (hi < 1) gap();
  }

  void refine(double x0, double? y0, double x1, double? y1, int depth) {
    final xm = (x0 + x1) / 2, ym = at((x0 + x1) / 2);
    if (evaluations > 12000 || (y0 == null && ym == null && y1 == null)) {
      gap();
      return;
    }
    final invalid = y0 == null || y1 == null || ym == null;
    if (!invalid &&
        ((y0 > ymax && ym > ymax && y1 > ymax) ||
            (y0 < ymin && ym < ymin && y1 < ymin))) {
      gap();
      return;
    }
    final error = invalid ? double.infinity : (ym - (y0 + y1) / 2).abs();
    if (depth < 10 && error > yr * .001 && xm != x0 && xm != x1) {
      refine(x0, y0, xm, ym, depth + 1);
      refine(xm, ym, x1, y1, depth + 1);
      return;
    }
    if (invalid || error > yr * .01) {
      gap();
      return;
    }
    edge(x0, y0, xm, ym);
    edge(xm, ym, x1, y1);
  }

  var x0 = xmin, y0 = at(xmin);
  for (int i = 0; i < 96; i++) {
    final x1 = xmin + (xmax - xmin) * (i + 1) / 96, y1 = at(x1);
    refine(x0, y0, x1, y1, 0);
    x0 = x1;
    y0 = y1;
  }
  gap();
  return segments;
}

/// One isolate samples an entire viewport, so four curves cannot launch four
/// independent workers on every gesture update.
CurveBatch sampleCurves(Map<String, dynamic> request) {
  final result = <int, CurveSegments>{};
  final curves = request['curves'] as List;
  for (var i = 0; i < curves.length; i++) {
    if (curves[i]['visible'] == false) continue;
    result[i] = sampleCurve({
      ...request,
      'ast': curves[i]['ast'],
      'angle': curves[i]['angleMode'],
      'kind': curves[i]['kind'],
    });
  }
  return result;
}

class _SamplingJob {
  _SamplingJob(this.id, this.request);
  final int id;
  final Map<String, dynamic> request;
  final done = Completer<CurveBatch?>();
}

/// At most one batch runs and one latest viewport waits. Superseded requests
/// complete with null; neither stale results nor mutable curve maps can leak in.
class LatestCurveSampler {
  LatestCurveSampler({
    Future<CurveBatch> Function(Map<String, dynamic>)? worker,
  }) : _worker = worker ?? ((request) => compute(sampleCurves, request));
  final Future<CurveBatch> Function(Map<String, dynamic>) _worker;
  _SamplingJob? _pending;
  var _active = false, _disposed = false;
  var _latest = 0;

  Future<CurveBatch?> sample(Map<String, dynamic> request) {
    if (_disposed) return Future.value(null);
    final snapshot = jsonDecode(jsonEncode(request)) as Map<String, dynamic>;
    final job = _SamplingJob(++_latest, snapshot);
    _pending?.done.complete(null);
    _pending = job;
    if (!_active) unawaited(_drain());
    return job.done.future;
  }

  Future<void> _drain() async {
    _active = true;
    while (!_disposed && _pending != null) {
      final job = _pending!;
      _pending = null;
      try {
        final result = await _worker(job.request);
        job.done.complete(!_disposed && job.id == _latest ? result : null);
      } catch (error, stack) {
        if (!_disposed && job.id == _latest) {
          job.done.completeError(error, stack);
        } else {
          job.done.complete(null);
        }
      }
    }
    _active = false;
  }

  void dispose() {
    _disposed = true;
    _pending?.done.complete(null);
    _pending = null;
  }
}

/// Gesture transforms retain the world point under the initial finger focus.
class GraphViewport {
  const GraphViewport(this.cx, this.cy, this.span, this.size);
  final double cx, cy, span;
  final Size size;
  double get yspan => span * size.height / size.width;
  Offset worldAt(Offset screen) => Offset(
    cx + (screen.dx / size.width - .5) * span,
    cy + (.5 - screen.dy / size.height) * yspan,
  );
  GraphViewport gesture(Offset start, Offset current, double scale) {
    if (size.isEmpty || !scale.isFinite || scale <= 0) return this;
    final anchor = worldAt(start);
    final nextSpan = (span / scale).clamp(1e-6, 1e8);
    return GraphViewport(
      (anchor.dx - (current.dx / size.width - .5) * nextSpan).clamp(-1e9, 1e9),
      (anchor.dy -
              (.5 - current.dy / size.height) *
                  nextSpan *
                  size.height /
                  size.width)
          .clamp(-1e9, 1e9),
      nextSpan,
      size,
    );
  }
}

class GraphScreen extends StatefulWidget {
  const GraphScreen({
    super.key,
    required this.curves,
    required this.strings,
    this.onChanged,
  });
  final List<Map<String, dynamic>> curves;
  final Strings strings;
  final VoidCallback? onChanged;
  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  double cx = 0, cy = 0, span = 20;
  Size view = Size.zero;
  Offset? focal;
  GraphViewport? gestureStart;
  int? cursorDrag;
  final cursors = [-2.0, 2.0];
  final sampler = LatestCurveSampler();
  final Map<int, List<List<List<double>>>> paths = {};
  double get yspan => view.width > 0 ? span * view.height / view.width : span;
  Offset screen(double x, double y) => Offset(
    (x - cx) / span * view.width + view.width / 2,
    view.height / 2 - (y - cy) / yspan * view.height,
  );
  double xAt(double sx) => cx + (sx / view.width - .5) * span;
  Future<void> resample() async {
    if (view.isEmpty) return;
    try {
      final value = await sampler.sample({
        'curves': widget.curves,
        'xmin': cx - span / 2,
        'xmax': cx + span / 2,
        'ymin': cy - yspan / 2,
        'ymax': cy + yspan / 2,
      });
      if (!mounted || value == null) return;
      setState(() {
        paths.clear();
        paths.addAll(value);
      });
    } catch (_) {
      if (mounted) setState(paths.clear);
    }
  }

  @override
  void dispose() {
    sampler.dispose();
    super.dispose();
  }

  double? cursorY(double x) {
    final visible = widget.curves.where((curve) => curve['visible'] != false);
    if (visible.isEmpty) return null;
    final curve = visible.first;
    if (curve['kind'] == 'vertical') return null;
    try {
      return evaluateDouble(
        Map<String, dynamic>.from(curve['ast'] as Map),
        variables: {'x': x},
        angleMode: curve['angleMode'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final colors = Theme.of(context).colorScheme;
    final values = cursors.map(cursorY).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Gráfica', 'Graph')),
        actions: [
          IconButton(
            tooltip: s.t('Añadir desde el editor', 'Add from editor'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: s.t('Restablecer vista', 'Reset view'),
            onPressed: () {
              setState(() {
                cx = cy = 0;
                span = 20;
                cursors[0] = -2;
                cursors[1] = 2;
              });
              resample();
            },
            icon: const Icon(Icons.center_focus_strong_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: widget.curves
                    .asMap()
                    .entries
                    .map(
                      (entry) => Row(
                        children: [
                          Tooltip(
                            message: entry.value['visible'] != false
                                ? s.t('Ocultar ecuación', 'Hide equation')
                                : s.t('Mostrar ecuación', 'Show equation'),
                            child: Checkbox(
                              value: entry.value['visible'] != false,
                              activeColor: JemPalette.curves(
                                colors.brightness,
                              )[entry.key % 4],
                              semanticLabel:
                                  '${s.t('Mostrar ecuación', 'Show equation')} ${entry.key + 1}',
                              onChanged: (visible) {
                                setState(() {
                                  entry.value['visible'] = visible ?? false;
                                  paths.remove(entry.key);
                                });
                                widget.onChanged?.call();
                                resample();
                              },
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Math.tex(
                                plotLabelLatex(entry.value),
                                textStyle: TextStyle(
                                  fontSize: 21,
                                  color: entry.value['visible'] != false
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                ),
                                onErrorFallback: (e) =>
                                    Text(plotLabelLatex(entry.value)),
                              ),
                            ),
                          ),
                          Text(
                            (entry.value['angleMode'] as String).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            tooltip: s.t(
                              'Eliminar ecuación',
                              'Delete equation',
                            ),
                            onPressed: () {
                              setState(() {
                                widget.curves.removeAt(entry.key);
                                paths.clear();
                              });
                              widget.onChanged?.call();
                              resample();
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final size = Size(c.maxWidth, c.maxHeight);
                  if (view != size) {
                    view = size;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) resample();
                    });
                  }
                  return ClipRect(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (d) {
                        focal = d.localFocalPoint;
                        gestureStart = GraphViewport(cx, cy, span, view);
                        cursorDrag = null;
                        var distance = 22.0;
                        for (int i = 0; i < 2; i++) {
                          final candidate =
                              (screen(cursors[i], 0).dx - d.localFocalPoint.dx)
                                  .abs();
                          if (candidate < distance && d.pointerCount == 1) {
                            cursorDrag = i;
                            distance = candidate;
                          }
                        }
                      },
                      onScaleUpdate: (d) {
                        if (cursorDrag != null && d.pointerCount == 1) {
                          setState(
                            () => cursors[cursorDrag!] = xAt(
                              d.localFocalPoint.dx,
                            ),
                          );
                          return;
                        }
                        final next = gestureStart!.gesture(
                          focal!,
                          d.localFocalPoint,
                          d.scale,
                        );
                        setState(() {
                          span = next.span;
                          cx = next.cx;
                          cy = next.cy;
                        });
                        resample();
                      },
                      onScaleEnd: (_) {
                        focal = null;
                        gestureStart = null;
                        cursorDrag = null;
                      },
                      child: CustomPaint(
                        size: size,
                        painter: _GraphPainter(
                          cx,
                          cy,
                          span,
                          paths,
                          cursors,
                          values,
                          colors,
                          widget.strings,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (int i = 0; i < 2; i++)
                        Expanded(
                          child: Text(
                            '${i == 0 ? 'A' : 'B'}  (${cursors[i].toStringAsPrecision(5)}, ${values[i]?.toStringAsPrecision(5) ?? '—'})',
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Δx ${(cursors[1] - cursors[0]).toStringAsPrecision(5)}    Δy ${values[0] != null && values[1] != null ? (values[1]! - values[0]!).toStringAsPrecision(5) : '—'}   ≈',
                    style: TextStyle(color: colors.primary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.t(
                      'Arrastra A/B · Pellizca para acercar',
                      'Drag A/B · Pinch to zoom',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(
    this.cx,
    this.cy,
    this.span,
    this.paths,
    this.cursors,
    this.cursorValues,
    this.colors,
    this.strings,
  );
  final double cx, cy, span;
  final Map<int, List<List<List<double>>>> paths;
  final List<double> cursors;
  final List<double?> cursorValues;
  final ColorScheme colors;
  final Strings strings;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final yspan = span * size.height / size.width;
    Offset p(double x, double y) => Offset(
      (x - cx) / span * size.width + size.width / 2,
      size.height / 2 - (y - cy) / yspan * size.height,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.surface);
    final raw = span / 7;
    final power = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / power;
    final step =
        (n < 2
            ? 2
            : n < 5
            ? 5
            : 10) *
        power;
    final grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: .45)
      ..strokeWidth = .7;
    void text(String value, Offset at) {
      final t = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, at);
    }

    final firstX = ((cx - span / 2) / step).ceil();
    final nx = (span / step).ceil() + 1;
    for (var i = 0; i < nx; i++) {
      final x = (firstX + i) * step;
      final sx = p(x, 0).dx;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), grid);
      text(
        x.abs() < step * 1e-7 ? '0' : x.toStringAsPrecision(3),
        Offset(
          sx + 3,
          (p(0, 0).dy + 4).clamp(4, math.max(4, size.height - 18)),
        ),
      );
    }
    final firstY = ((cy - yspan / 2) / step).ceil();
    final ny = (yspan / step).ceil() + 1;
    for (var i = 0; i < ny; i++) {
      final y = (firstY + i) * step;
      final sy = p(0, y).dy;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), grid);
      if (y.abs() > step * 1e-7) {
        text(
          y.toStringAsPrecision(3),
          Offset(
            (p(0, 0).dx + 4).clamp(4, math.max(4, size.width - 38)),
            sy + 3,
          ),
        );
      }
    }
    final axis = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: .55)
      ..strokeWidth = 1;
    canvas.drawLine(p(cx - span / 2, 0), p(cx + span / 2, 0), axis);
    canvas.drawLine(p(0, cy - yspan / 2), p(0, cy + yspan / 2), axis);
    for (final entry in paths.entries) {
      final paint = Paint()
        ..color = JemPalette.curves(colors.brightness)[entry.key % 4]
        ..strokeWidth = 2.3
        ..style = PaintingStyle.stroke;
      for (final line in entry.value) {
        if (line.length < 2) continue;
        final path = Path();
        for (int i = 0; i < line.length; i++) {
          final point = p(line[i][0], line[i][1]);
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
    for (int i = 0; i < 2; i++) {
      final sx = p(cursors[i], 0).dx;
      if (sx < -14 || sx > size.width + 14) continue;
      final paint = Paint()
        ..color = colors.primary.withValues(alpha: .6)
        ..strokeWidth = 1;
      for (double y = 0; y < size.height; y += 10) {
        canvas.drawLine(Offset(sx, y), Offset(sx, y + 5), paint);
      }
      canvas.drawCircle(Offset(sx, 22), 13, Paint()..color = colors.primary);
      final label = TextPainter(
        text: TextSpan(
          text: i == 0 ? 'A' : 'B',
          style: TextStyle(
            color: colors.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(sx - label.width / 2, 22 - label.height / 2));
      final value = cursorValues[i];
      if (value != null && value >= cy - yspan / 2 && value <= cy + yspan / 2) {
        canvas.drawCircle(
          p(cursors[i], value),
          5,
          Paint()..color = colors.primary,
        );
        canvas.drawCircle(
          p(cursors[i], value),
          2,
          Paint()..color = colors.surface,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
