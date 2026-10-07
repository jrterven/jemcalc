import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/math/plot.dart';
import 'package:jem_calc/math/parser.dart';
import 'package:jem_calc/math/evaluator.dart';

void main() {
  List<Map<String, dynamic>> plots(String text) =>
      preparePlots(parseLatex(text));
  double y(Map<String, dynamic> curve, double x) =>
      evaluateDouble(curve['ast'] as MathNode, variables: {'x': x});
  test(
    'the photographed system gives two lines intersecting at (8/5, 1/5)',
    () {
      final input = parseLatex(r'\begin{cases}3x+y=5\\2x-y=3\end{cases}');
      final curves = preparePlots(input);
      expect(curves, hasLength(2));
      for (final x in [-4.0, 0.0, 1.6, 8.0]) {
        expect(3 * x + y(curves[0], x), closeTo(5, 1e-12));
        expect(2 * x - y(curves[1], x), closeTo(3, 1e-12));
      }
      expect(y(curves[0], 1.6), closeTo(.2, 1e-12));
      expect(y(curves[1], 1.6), closeTo(.2, 1e-12));
      expect(input['type'], 'system');
      expect(curves.every((c) => c['label'].contains('=')), true);
    },
  );
  test(
    'both equation sides, fractions, negative coefficients and parentheses are linear',
    () {
      for (final expression in [
        '2*(x+y)=6',
        'x/3+y/3=1',
        '-x-y=-3',
        'y+2x=x+3',
        '3=x+y',
      ]) {
        final curve = plots(expression).single;
        for (final x in [-3.0, 0.0, 2.0]) {
          expect(y(curve, x), closeTo(3 - x, 1e-12), reason: expression);
        }
      }
    },
  );
  test('rational coefficients remain exact until plot sampling', () {
    final curve = plots('3y=1').single;
    expect(evaluateLocal(curve['ast'] as MathNode).text, '1/3');
  });
  test('vertical and horizontal equations are distinct', () {
    final curves = plots('2x=4;y=2');
    expect(curves[0]['kind'], 'vertical');
    expect(evaluateLocal(curves[0]['ast'] as MathNode).text, '2');
    expect(curves[1]['kind'], 'function');
    expect(y(curves[1], 99), 2);
  });
  test(
    'explicit functions retain poles and holes in both orientations of equality',
    () {
      for (final expression in ['y=x/x', 'x/x=y']) {
        final curve = plots(expression).single;
        expect(() => y(curve, 0), throwsA(isA<MathEvaluationException>()));
        expect(y(curve, 2), 1);
      }
      expect(y(plots('sin(x)').single, 0), 0);
      expect(y(plots('y=x^2').single, 3), 9);
    },
  );
  test(
    'nonlinear relations and variable denominators are not silently linearized',
    () {
      for (final expression in ['xy=1', 'y^2+x^2=1', '(x/x)+y=2', 'x^0+y=1']) {
        expect(
          () => plots(expression),
          throwsA(isA<PlotException>()),
          reason: expression,
        );
      }
    },
  );
  test(
    'identities, contradictions, unknown variables and calculus are explicit errors',
    () {
      for (final (expression, reason) in [
        ('x=x', 'identity'),
        ('x=x+1', 'empty'),
        ('y=z', 'variables'),
        (r'\int x dx', 'unsupported'),
      ]) {
        expect(
          () => plots(expression),
          throwsA(
            isA<PlotException>().having((e) => e.reason, 'reason', reason),
          ),
        );
      }
    },
  );
}
