import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/core/strings.dart';
import 'package:jem_calc/features/completion_hint.dart';
import 'package:jem_calc/math/completion.dart';

void main() {
  for (final source in [r'\int xyzt', r'\frac{1}{}', '(x+1']) {
    testWidgets(
      'completion actions fit 304px and require an explicit tap: $source',
      (tester) async {
        final suggestions = expressionCompletions(source);
        ExpressionCompletion? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 304,
                  child: CompletionHint(
                    suggestions: suggestions,
                    strings: const Strings('es'),
                    onSelected: (s) => selected = s,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(selected, isNull);
        await tester.tap(find.text(suggestions.first.label));
        expect(selected, same(suggestions.first));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
