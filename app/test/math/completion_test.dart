import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/math/completion.dart';
import 'package:jem_calc/math/parser.dart';

void main() {
  test(
    'compact fractions emitted after filling a MathLive slot keep TeX atom boundaries',
    () {
      expect(parseLatex(r'\frac12'), parseLatex(r'\frac{1}{2}'));
      expect(parseLatex(r'\frac1{23}'), parseLatex(r'\frac{1}{23}'));
      expect(parseLatex(r'\frac{12}3'), parseLatex(r'\frac{12}{3}'));
      expect(
        parseLatex(r'\frac{1}{\frac23}'),
        parseLatex(r'\frac{1}{\frac{2}{3}}'),
      );
    },
  );
  test('missing differential is offered using variables in the integrand', () {
    final one = expressionCompletions(r'\int_0^1 x^2').single;
    expect(one.label, 'Añadir dx');
    expect(one.focusSlot, false);
    expect(parseLatex(one.latex)['variable'], 'x');
    expect(expressionCompletions(r'\int xy').map((s) => s.label), [
      'Añadir dx',
      'Añadir dy',
    ]);
    expect(
      expressionCompletions(r'\int 3', preferredVariable: 't').single.label,
      'Añadir dt',
    );
    expect(expressionCompletions(r'\(\int y^2\)').single.label, 'Añadir dy');
  });

  for (final source in ['(x+1', r'\frac{1}{(x+2', r'\sqrt{2', '((3+4)*2']) {
    test('closing groups yields a parseable expression: $source', () {
      final suggestion = expressionCompletions(source).single;
      expect(suggestion.focusSlot, false);
      expect(suggestion.latex.startsWith(source), true);
      expect(() => parseLatex(suggestion.latex), returnsNormally);
    });
  }
  final missing = {
    r'\frac{x}': r'\frac{x}{\placeholder{}}',
    r'\frac{}{2}': r'\frac{\placeholder{}}{2}',
    r'\frac': r'\frac{\placeholder{}}{\placeholder{}}',
    r'x^': r'x^{\placeholder{}}',
    r'x^{}': r'x^{\placeholder{}}',
    'x=': r'x={\placeholder{}}',
    'x+': r'x+{\placeholder{}}',
    '(x+)': r'(x+{\placeholder{}})',
    r'\sqrt': r'\sqrt{\placeholder{}}',
    r'\sin()': r'\sin(\placeholder{})',
    r'\log_{}(x)': r'\log_{\placeholder{}}(x)',
    r'\lim_{x\to} x^2': r'\lim_{x\to \placeholder{}} x^2',
    r'\lim_{\to 0} x': r'\lim_{\placeholder{}\to 0} x',
    r'\lim x^2': r'\lim_{\placeholder{}\to \placeholder{}} x^2',
    r'\lim_{x\to 0}': r'\lim_{x\to 0} \placeholder{}',
    r'\int_{0} x\,\mathrm{d}x': r'\int_{0}^{\placeholder{}} x\,\mathrm{d}x',
    r'\int^{2} x\,\mathrm{d}x': r'\int^{2}_{\placeholder{}} x\,\mathrm{d}x',
    r'\frac{1}{\placeholder{}}': r'\frac{1}{\placeholder{}}',
  };
  for (final entry in missing.entries) {
    test(
      'missing values stay empty and cannot be calculated: ${entry.key}',
      () {
        final suggestion = expressionCompletions(entry.key).single;
        expect(suggestion.source, entry.key);
        expect(suggestion.latex, entry.value);
        expect(suggestion.focusSlot, true);
        expect(
          () => parseLatex(suggestion.latex),
          throwsA(isA<MathParseException>()),
        );
      },
    );
  }
  for (final valid in [
    r'\int x dx',
    r'\int y dy',
    'x^2',
    '(x+1)',
    r'\frac{1}{0}',
    r'\lim_{x\to0^+}x',
    r'\frac{d}{d}x',
    'x',
  ]) {
    test(
      'complete formula is not changed, including domain errors: $valid',
      () {
        expect(expressionCompletions(valid), isEmpty);
      },
    );
  }
  for (final invalid in [
    '',
    '([x)]',
    r'\int \int x',
    r'\int x d',
    r'\unknown{x}',
    'x++*',
    r'\begin{cases}x=1',
    'x' * 32769,
    '(' * 65,
  ]) {
    test(
      'no speculative repair for unsupported or ambiguous input (${invalid.length} chars)',
      () {
        expect(expressionCompletions(invalid), isEmpty);
      },
    );
  }
}
