import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/math/display_latex.dart';
import 'package:jem_calc/math/evaluator.dart';
import 'package:jem_calc/math/latex.dart';
import 'package:jem_calc/math/parser.dart';
import 'package:jem_calc/math/plot.dart';

void main() {
  test(
    'stored graph equations become readable without changing curve data',
    () {
      final curves = preparePlots(parseLatex('3x+y=5;2x-y=3'));
      final before = jsonEncode(curves);
      expect(curves.first['label'], contains(r'\cdot'));
      expect(curves.map(plotLabelLatex), ['3x + y = 5', '2x - y = 3']);
      expect(jsonEncode(curves), before);
      expect(plotLabelLatex(preparePlots(parseLatex('2x=4')).single), '2x = 4');
    },
  );

  test('legacy functions use their AST and the correct axis', () {
    final ast = parseLatex('x^2');
    final curve = {'ast': ast, 'latex': astToLatex(ast), 'angleMode': 'rad'};
    expect(plotLabelLatex(curve), 'y = x^{2}');
    expect(
      plotLabelLatex({...curve, 'kind': 'vertical', 'ast': parseLatex('2')}),
      'x = 2',
    );
    expect(plotLabelLatex({...curve, 'label': r'\unknown{x}'}), r'\unknown{x}');
  });

  test(
    'essential grouping, coefficient notation and functions are legible',
    () {
      for (final (source, expected) in [
        ('2*(x+1)', r'2\left(x + 1\right)'),
        ('3*x^2', '3x^{2}'),
        ('(x+1)^2', r'\left(x + 1\right)^{2}'),
        ('x-(y+1)', r'x - \left(y + 1\right)'),
        ('(-x)^2', r'\left(-x\right)^{2}'),
        ('-x^2', '-x^{2}'),
        ('(x^2)^3', r'\left(x^{2}\right)^{3}'),
        ('2*3', r'2 \cdot 3'),
        ('x*(-y)', r'x \cdot \left(-y\right)'),
        ('sin(x)', r'\sin\left(x\right)'),
        ('(x+1)/(x-1)', r'\frac{x + 1}{x - 1}'),
        ('sqrt(x+1)', r'\sqrt{x + 1}'),
        ('1.25e-2', r'1.25 \times 10^{-2}'),
      ]) {
        expect(astToDisplayLatex(parseLatex(source)), expected, reason: source);
      }
    },
  );

  test(
    'display notation preserves values, precedence and undefined domains',
    () {
      for (final source in [
        '3*x+1',
        '2*(x+1)',
        '3*x^2',
        '(x+1)^2',
        'x-(x+1)',
        'x+(x-1)',
        '(-x)^2',
        '-x^2',
        '(x^2)^3',
        'x^(2^3)',
        'x*(-x)',
        '-(-x)',
        '(x+1)/(x-1)',
        'x/x',
        '0*x^0',
        '2*3',
        'x*2',
        '2*pi',
        '1.25e-2*x',
        '(1.25e2)^2',
        'sin(x)+cos(x)',
        'tan(x)',
        'abs(x)',
        'sqrt(x)',
        'root(x,3)',
        '(x+1)!',
        '(x^2)!',
        '(x!)!',
        'asin(x)',
        'acos(x)',
        'atan(x)',
      ]) {
        final original = parseLatex(source);
        final display = astToDisplayLatex(original);
        final parsedDisplay = parseLatex(display);
        for (final x in [-2.0, 0.0, .5, 1.0, 2.0]) {
          LocalResult expected;
          try {
            expected = evaluateLocal(original, variables: {'x': x});
          } on MathEvaluationException {
            expect(
              () => evaluateLocal(parsedDisplay, variables: {'x': x}),
              throwsA(isA<MathEvaluationException>()),
              reason: '$source at $x',
            );
            continue;
          }
          final actual = evaluateLocal(parsedDisplay, variables: {'x': x});
          expect(actual.exact, expected.exact, reason: source);
          if (expected.exact) {
            expect(actual.text, expected.text, reason: '$source at $x');
          } else {
            expect(
              actual.value,
              closeTo(expected.value!, 1e-12),
              reason: source,
            );
          }
        }
      }
    },
  );
}
