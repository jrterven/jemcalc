import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/math/ast.dart';
import 'package:jem_calc/math/evaluator.dart';
import 'package:jem_calc/math/latex.dart';
import 'package:jem_calc/math/parser.dart';

void main() {
  LocalResult calc(String input, {String angle = 'rad'}) =>
      evaluateLocal(parseExpression(input), angleMode: angle);

  group('Exact rational arithmetic', () {
    test('decimal arithmetic preserves exact values and original AST', () {
      final ast = parseExpression('0.1+0.2');
      final before = jsonEncode(ast);
      final result = evaluateLocal(ast);
      expect(result.text, '3/10');
      expect(result.exact, isTrue);
      expect(result.value, closeTo(0.3, 1e-15));
      expect(jsonEncode(ast), before);
    });
    test('division, scientific literals, precedence and associativity', () {
      expect(calc('1/3+1/6').text, '1/2');
      expect(calc('1.25e-2*80').text, '1');
      expect(calc('-2^2').text, '-4');
      expect(calc('(-2)^2').text, '4');
      expect(calc('2^3^2').text, '512');
      expect(calc('2^-3').text, '1/8');
      expect(calc('6/2*3').text, '9');
      expect(calc('2(3+4)').text, '14');
    });
    test('large integers and factorial are not rounded to doubles', () {
      expect(calc('9007199254740993+1').text, '9007199254740994');
      expect(calc('30!').text, '265252859812191058636308480000000');
      expect(calc('1000!').text.length, 2568);
      expect(calc('1000!').value, isNull);
      expect(calc('(10^400)/(3*10^399)').value, closeTo(10 / 3, 1e-14));
    });
    test('exact roots and real odd roots', () {
      expect(calc('sqrt(4/9)').text, '2/3');
      expect(calc('root(-8,3)').text, '-2');
      expect(evaluateLocal(parseLatex(r'\sqrt[3]{-8}')).text, '-2');
      expect(calc('sqrt(2)').exact, isFalse);
      expect(calc('sqrt(2)').value, closeTo(math.sqrt2, 1e-14));
      expect(calc('root(-2,3)').value, closeTo(-1.2599210498948732, 1e-14));
      expect(calc('sqrt(10^400)').text, '1${List.filled(200, '0').join()}');
      expect(calc('sqrt(10^400+1)').value! / 1e200, closeTo(1, 1e-12));
      expect(calc('ln(1e-400)').value, closeTo(-400 * math.ln10, 1e-10));
    });
  });

  group('Domains and resource limits', () {
    for (final expression in [
      '1/0',
      '0^0',
      '0^-1',
      '0^(-1e-400)',
      'sqrt(-1)',
      'root(-8,2)',
      'root(2,0)',
      'root(2,1001)',
      'root(2,1.5)',
      '(-8)^(1/3)',
      'ln(0)',
      'log(-2)',
      'asin(2)',
      'asin(1+1e-400)',
      'acos(-2)',
      '(-1)!',
      '1.5!',
      '1001!',
      '10^4096',
      '2^16385',
      '(10^400)^16384',
      'exp(1000)',
    ]) {
      test('rejects $expression', () {
        expect(() => calc(expression), throwsA(isA<MathEvaluationException>()));
      });
    }
    test('poles become graph gaps', () {
      expect(
        () => calc('tan(90)', angle: 'deg'),
        throwsA(isA<MathEvaluationException>()),
      );
      expect(() => calc('tan(pi/2)'), throwsA(isA<MathEvaluationException>()));
      expect(
        () => calc('tan(3*pi/2)'),
        throwsA(
          isA<MathEvaluationException>().having(
            (e) => e.message,
            'message',
            contains('undefined'),
          ),
        ),
      );
      expect(
        () => calc('tan(1.5707963267948965)'),
        throwsA(
          isA<MathEvaluationException>().having(
            (e) => e.message,
            'message',
            contains('precision'),
          ),
        ),
      );
      expect(
        () => calc('tan(89.999999999999999999)', angle: 'deg'),
        throwsA(
          isA<MathEvaluationException>().having(
            (e) => e.message,
            'message',
            contains('precision'),
          ),
        ),
      );
      expect(
        () => evaluateDouble(parseExpression('1/x'), variables: {'x': 0}),
        throwsA(isA<MathEvaluationException>()),
      );
    });
    test('validator rejects untrusted AST shapes and excess nodes', () {
      expect(
        () => evaluateLocal({'type': 'call', 'fn': 'exec', 'args': []}),
        throwsA(isA<MathEvaluationException>()),
      );
      expect(
        () => evaluateLocal({'type': 'number', 'value': 'NaN'}),
        throwsA(isA<MathEvaluationException>()),
      );
      expect(
        () =>
            evaluateLocal({'type': 'number', 'value': '1', 'code': 'anything'}),
        throwsA(isA<MathEvaluationException>()),
      );
      expect(
        () => parseExpression(
          '${List.filled(70, '(').join()}1${List.filled(70, ')').join()}',
        ),
        throwsA(isA<MathParseException>()),
      );
      MathNode balanced(int depth) => depth == 0
          ? {'type': 'number', 'value': '1'}
          : {
              'type': 'binary',
              'op': '+',
              'left': balanced(depth - 1),
              'right': balanced(depth - 1),
            };
      expect(
        () => evaluateLocal(balanced(9)),
        throwsA(isA<MathEvaluationException>()),
      );
    });
    test('no implicit execution or ignored suffixes', () {
      for (final expression in [
        '1+2 garbage()',
        r'\href{url}{x}',
        '2+',
        '2)',
        r'\sqrt{}',
        r'\placeholder{}',
        '1=2=3',
        r'\operatorname{unknown}(2)',
        'diff(x,x,',
        'diff(x,x,4)',
        'limit(x,x,0,',
        '${List.filled(100, 'sqrt ').join()}1',
      ]) {
        expect(
          () => parseLatex(expression),
          throwsA(isA<MathParseException>()),
          reason: expression,
        );
      }
    });
  });

  group('Scientific functions and binding', () {
    test('trig input and inverse trig output respect angle mode', () {
      expect(calc('sin(30)', angle: 'deg').value, closeTo(0.5, 1e-14));
      expect(calc('asin(0.5)', angle: 'deg').value, closeTo(30, 1e-12));
      expect(calc('sin(pi/2)').value, closeTo(1, 1e-14));
      expect(calc('ln(e)').value, closeTo(1, 1e-14));
      expect(calc('log(100)').value, closeTo(2, 1e-14));
      expect(
        evaluateLocal(parseLatex(r'\log_{2}(8)')).value,
        closeTo(3, 1e-14),
      );
      expect(
        evaluateLocal(parseLatex(r'\sin^{-1}(1)')).value,
        closeTo(math.pi / 2, 1e-14),
      );
      expect(
        evaluateLocal(parseLatex(r'\sin^{2}(\pi/2)')).value,
        closeTo(1, 1e-14),
      );
    });
    test('graph variables bind without mutating expression', () {
      final ast = parseExpression('2x^2+3x-1');
      expect(requiresCas(ast), isTrue);
      expect(evaluateDouble(ast, variables: {'x': 2}), 13);
      expect(evaluateDouble(ast, variables: {'x': -1}), -2);
      expect(() => evaluateLocal(ast), throwsA(isA<MathEvaluationException>()));
      expect(requiresCas(parseExpression('sin(1)+2/3')), isFalse);
    });
  });

  group('MathLive templates and roundtrip', () {
    final examples = [
      r'\frac{x+1}{\sqrt{x^2+2}}',
      r'\left|x-1\right|',
      r'\sqrt[3]{-8}',
      r'\sin^{-1}(x)',
      r'\frac{d}{dx}\left(x^2+1\right)',
      r'\frac{d^{2}}{dx^{2}}\left(\sin(x)\right)',
      r'\int_{0}^{1} x^2\,\mathrm{d}x',
      r'\int \sin(x)\,\mathrm{d}x',
      r'\lim_{x\to 0}\frac{\sin(x)}{x}',
      r'\lim_{x\to 0^{+}}\frac{1}{x}',
      r'\lim_{x\to -\infty}\frac{1}{x}',
      r'\begin{cases}x+y=3\\x-y=1\end{cases}',
      r'\left\{\begin{array}{l}x+y=3\\x-y=1\end{array}\right.',
    ];
    for (final input in examples) {
      test('preserves structure: $input', () {
        final ast = parseLatex(input);
        expect(parseLatex(astToLatex(ast)), ast);
      });
    }
    test('plain calculus helpers and systems', () {
      expect(parseExpression('diff(x^2,x)')['type'], 'derivative');
      expect(parseExpression('diff(sin(x),x,2)')['order'], 2);
      expect(
        parseExpression('integrate(x^2,x,0,1)'),
        parseLatex(r'\int_0^1 x^2 dx'),
      );
      expect(
        parseExpression('limit(sin(x)/x,x,0)'),
        parseLatex(r'\lim_{x\to0}\sin(x)/x'),
      );
      expect(parseExpression('x+y=3;x-y=1')['type'], 'system');
      expect(requiresCas(parseExpression('x=2')), isTrue);
      expect(requiresCas(parseExpression('diff(x^2,x)')), isTrue);
    });
  });
}
