import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/features/graph.dart';
import 'package:jem_calc/core/strings.dart';
import 'package:jem_calc/math/parser.dart';
import 'package:jem_calc/math/plot.dart';

Map<String, dynamic> request(
  String expression, {
  double xmin = -4,
  double xmax = 4,
  double ymin = -10,
  double ymax = 10,
  String angle = 'rad',
}) => {
  'ast': parseExpression(expression),
  'angle': angle,
  'xmin': xmin,
  'xmax': xmax,
  'ymin': ymin,
  'ymax': ymax,
};

void main() {
  test('hidden curves keep their list positions and return when enabled', () {
    final curves = [
      {'ast': parseExpression('x'), 'angleMode': 'rad', 'visible': false},
      {'ast': parseExpression('x^2'), 'angleMode': 'rad'},
    ];
    final job = {...request('x'), 'curves': curves};
    expect(sampleCurves(job).keys, [1]);
    curves.first['visible'] = true;
    expect(sampleCurves(job).keys, [0, 1]);
    curves.first['visible'] = false;
    curves.last['visible'] = false;
    expect(sampleCurves(job), isEmpty);
    expect(curves, hasLength(2));
  });

  testWidgets(
    'checkboxes preserve equations; cursors follow visibility; trash deletes',
    (tester) async {
      final curves = <Map<String, dynamic>>[
        {'ast': parseExpression('x'), 'latex': 'x', 'angleMode': 'rad'},
        {'ast': parseExpression('x^2'), 'latex': 'x^2', 'angleMode': 'rad'},
      ];
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GraphScreen(
            curves: curves,
            strings: const Strings('es'),
            onChanged: () => changes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(2));
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(curves, hasLength(2));
      expect(find.text('A  (-2.0000, 4.0000)'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      expect(curves, hasLength(2));
      expect(find.text('A  (-2.0000, —)'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('A  (-2.0000, -2.0000)'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(curves, hasLength(1));
      expect(curves.single['latex'], 'x^2');
      expect(curves.single['visible'], false);
      expect(changes, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  void excludesPole(CurveSegments segments, double pole) {
    expect(segments, isNotEmpty);
    for (final segment in segments) {
      expect(segment.first[0] <= pole && segment.last[0] >= pole, isFalse);
    }
  }

  test('vertical lines span and clip to the current viewport', () {
    final plot = preparePlots(parseLatex('2x=4')).single;
    final result = sampleCurves({
      ...request('x'),
      'curves': [plot],
    });
    expect(result[0], [
      [
        [2.0, -10.0],
        [2.0, 10.0],
      ],
    ]);
    expect(
      sampleCurves({
        ...request('x', xmin: 3, xmax: 4),
        'curves': [plot],
      })[0],
      isEmpty,
    );
  });
  test('sampled lines satisfy the original system', () {
    final curves = preparePlots(parseLatex('3x+y=5;2x-y=3'));
    final result = sampleCurves({...request('x'), 'curves': curves});
    expect(result.keys, [0, 1]);
    for (final p in result[0]!.expand((line) => line)) {
      expect(3 * p[0] + p[1], closeTo(5, 1e-11));
    }
    for (final p in result[1]!.expand((line) => line)) {
      expect(2 * p[0] - p[1], closeTo(3, 1e-11));
    }
  });
  testWidgets('system rows have independent visibility and deletion controls', (
    tester,
  ) async {
    final curves = preparePlots(parseLatex('3x+y=5;2x-y=3'));
    await tester.pumpWidget(
      MaterialApp(
        home: GraphScreen(curves: curves, strings: const Strings('es')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(2));
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(curves.first['visible'], false);
    expect(curves, hasLength(2));
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).last);
    await tester.pumpAndSettle();
    expect(curves, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  group('Adaptive real-domain plotting', () {
    test('reciprocal poles split paths even between initial samples', () {
      for (final pole in [0.0, 0.1234567]) {
        final segments = sampleCurve(request('1/(x-$pole)'));
        excludesPole(segments, pole);
        expect(segments.any((s) => s.last[0] < pole), isTrue);
        expect(segments.any((s) => s.first[0] > pole), isTrue);
      }
    });
    test('tangent poles split in radians and degrees', () {
      final rad = sampleCurve(request('tan(x)'));
      excludesPole(rad, math.pi / 2);
      excludesPole(rad, -math.pi / 2);
      final deg = sampleCurve(
        request('tan(x)', xmin: -180, xmax: 180, angle: 'deg'),
      );
      excludesPole(deg, 90);
      excludesPole(deg, -90);
    });
    test(
      'square root preserves zero and never invents negative-domain points',
      () {
        final segments = sampleCurve(request('sqrt(x)'));
        expect(segments, hasLength(1));
        expect(segments.single.first, [0.0, 0.0]);
        for (final p in segments.single) {
          expect(p[0], greaterThanOrEqualTo(0));
          expect(p[1], closeTo(math.sqrt(p[0]), 1e-12));
        }
        expect(sampleCurve(request('sqrt(-1)')), isEmpty);
      },
    );
    test('smooth curves remain connected and exact holes remain gaps', () {
      final sinusoid = sampleCurve(request('sin(x)', ymin: -2, ymax: 2));
      expect(sinusoid, hasLength(1));
      for (final p in sinusoid.single) {
        expect(p[1], closeTo(math.sin(p[0]), 1e-12));
      }
      excludesPole(sampleCurve(request('x/x')), 0);
    });
    test(
      'steep continuous lines are clipped without being mistaken for poles',
      () {
        final segments = sampleCurve(request('1000x', xmin: -1, xmax: 1));
        expect(segments, hasLength(1));
        expect(segments.single.first[0], closeTo(-0.01, 1e-12));
        expect(segments.single.last[0], closeTo(0.01, 1e-12));
        for (final p in segments.single) {
          expect(p[1], inInclusiveRange(-10, 10));
          expect(p[1], closeTo(1000 * p[0], 1e-10));
        }
      },
    );
    test('invalid viewports return no points', () {
      expect(sampleCurve(request('x', xmin: 4, xmax: -4)), isEmpty);
      expect(sampleCurve(request('x', ymin: 0, ymax: 0)), isEmpty);
    });
  });

  group('Latest viewport scheduling', () {
    test(
      'one batch runs while intermediate requests are dropped and latest is snapshotted',
      () async {
        final started = <Map<String, dynamic>>[];
        final gates = <Completer<CurveBatch>>[];
        final sampler = LatestCurveSampler(
          worker: (job) {
            started.add(job);
            final gate = Completer<CurveBatch>();
            gates.add(gate);
            return gate.future;
          },
        );
        final first = sampler.sample({'frame': 1});
        final second = sampler.sample({'frame': 2});
        final data = {'frame': 3, 'ast': parseExpression('x+1')};
        final latest = sampler.sample(data);
        (data['ast'] as Map)['type'] = 'mutated';
        expect(started, hasLength(1));
        expect(await second, isNull);
        gates.first.complete({0: []});
        expect(await first, isNull);
        await Future<void>.delayed(Duration.zero);
        expect(started, hasLength(2));
        expect(started.last['frame'], 3);
        expect(started.last['ast']['type'], 'binary');
        gates.last.complete({2: []});
        expect(await latest, {2: []});
        sampler.dispose();
      },
    );
    test(
      'disposing drops pending work and suppresses in-flight results',
      () async {
        var count = 0;
        final gate = Completer<CurveBatch>();
        final sampler = LatestCurveSampler(
          worker: (_) {
            count++;
            return gate.future;
          },
        );
        final active = sampler.sample({'frame': 1});
        final pending = sampler.sample({'frame': 2});
        sampler.dispose();
        expect(await pending, isNull);
        gate.complete({0: []});
        expect(await active, isNull);
        expect(await sampler.sample({'frame': 3}), isNull);
        expect(count, 1);
      },
    );
  });

  group('Touch viewport transforms', () {
    test('pinch and simultaneous pan preserve the focal world point', () {
      const viewport = GraphViewport(2, -3, 20, Size(800, 400));
      const start = Offset(100, 300), current = Offset(210, 260);
      final anchor = viewport.worldAt(start);
      final next = viewport.gesture(start, current, 2);
      expect(next.span, 10);
      expect(next.worldAt(current).dx, closeTo(anchor.dx, 1e-12));
      expect(next.worldAt(current).dy, closeTo(anchor.dy, 1e-12));
    });
    test(
      'pan uses screen direction and cursor mapping uses world coordinates',
      () {
        const viewport = GraphViewport(0, 0, 20, Size(400, 200));
        final next = viewport.gesture(
          const Offset(200, 100),
          const Offset(240, 120),
          1,
        );
        expect(next.cx, closeTo(-2, 1e-12));
        expect(next.cy, closeTo(1, 1e-12));
        final origin = next.worldAt(const Offset(240, 120));
        expect(origin.dx, closeTo(0, 1e-12));
        expect(origin.dy, closeTo(0, 1e-12));
        expect(viewport.gesture(Offset.zero, Offset.zero, 1e30).span, 1e-6);
      },
    );
  });
}
