import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/math/evaluator.dart';
import 'package:jem_calc/math/latex.dart';
import 'package:jem_calc/math/parser.dart';

void main() {
  // The backend consumes this same fixture. Test both the interchange AST and
  // its editor source, since equivalent literals need not have identical trees.
  final fixture =
      jsonDecode(
            File(
              '../server/tests/fixtures/math_contract.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final raw in fixture['cases'] as List) {
    final item = raw as Map<String, dynamic>;
    test('Shared CAS contract: ${item['id']}', () {
      final ast = item['ast'] as MathNode;
      final expected = item['local'] as Map<String, dynamic>;
      for (final candidate in [
        ast,
        parseLatex(item['source'] as String),
        parseLatex(astToLatex(ast)),
      ]) {
        LocalResult evaluate() =>
            evaluateLocal(candidate, angleMode: item['angleMode'] as String);
        switch (expected['kind']) {
          case 'exact':
            final result = evaluate();
            expect(result.exact, isTrue);
            expect(result.text, expected['text']);
          case 'numeric':
            final result = evaluate();
            expect(result.exact, isFalse);
            expect(
              result.value,
              closeTo(expected['value'], expected['tolerance']),
            );
          case 'error':
            expect(evaluate, throwsA(isA<MathEvaluationException>()));
          case 'cas':
            expect(requiresCas(candidate), isTrue);
            expect(candidate, ast);
            expect(evaluate, throwsA(isA<MathEvaluationException>()));
          default:
            fail('Unknown fixture kind ${expected['kind']}');
        }
      }
    });
  }
}
