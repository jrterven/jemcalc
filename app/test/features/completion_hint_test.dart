import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/core/strings.dart';
import 'package:jem_calc/features/completion_hint.dart';
import 'package:jem_calc/features/editor_completion.dart';
import 'package:jem_calc/math/completion.dart';

void main() {
  test(
    'editor suggestions are localized and only current proposals can apply',
    () {
      final suggestions = expressionCompletions(r'\int xy');
      final configuration = editorCompletionConfiguration(suggestions, 'es')!;
      final actions = configuration['actions'] as List;
      expect(actions.map((a) => a['label']), ['Añadir dx', 'Añadir dy']);
      final message = <String, dynamic>{
        'source': configuration['source'],
        ...actions.last as Map<String, dynamic>,
      };
      expect(
        selectedEditorCompletion(message, suggestions),
        same(suggestions.last),
      );
      expect(
        selectedEditorCompletion({...message, 'source': 'x+1'}, suggestions),
        isNull,
      );
      expect(
        selectedEditorCompletion({...message, 'latex': '42'}, suggestions),
        isNull,
      );
      expect(
        selectedEditorCompletion({...message, 'focusSlot': true}, suggestions),
        isNull,
      );
      expect(selectedEditorCompletion(message, const []), isNull);
      expect(editorCompletionConfiguration(const [], 'es'), isNull);
      final english = editorCompletionConfiguration(
        expressionCompletions('x+'),
        'en',
      )!;
      expect((english['actions'] as List).single['label'], 'Complete');
    },
  );

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
