import 'package:flutter/material.dart';
import '../core/model.dart';
import 'math_editor.dart';
import 'completion_hint.dart';

// A modal keeps the active input panel mounted, including a live voice session.
Future<void> showEquationEditor(BuildContext context, AppModel model) async {
  final height = (MediaQuery.sizeOf(context).height * .8)
      .clamp(0.0, 580.0)
      .toDouble();
  bool closed = false;
  // Flutter's bottom-sheet route adds an opaque semantics hit-test surface
  // over HTML platform views. A dialog route keeps the same compact sheet and
  // lets the web editor receive touch events with accessibility enabled.
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (sheetContext, animation, secondaryAnimation) {
      void closeEditor() {
        if (closed ||
            !sheetContext.mounted ||
            ModalRoute.of(sheetContext)?.isCurrent != true) {
          return;
        }
        closed = true;
        Navigator.of(sheetContext).pop();
      }

      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Material(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: height,
              child: SafeArea(
                top: false,
                child: AnimatedBuilder(
                  animation: model,
                  builder: (context, _) => Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.s.t('Editar', 'Edit'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              tooltip: model.s.t('Cerrar', 'Close'),
                              onPressed: closeEditor,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Expanded(
                          child: MathEditor(
                            latex: model.latex,
                            focusRequest: model.editorFocusRequest,
                            language: model.language,
                            showKeyboard: true,
                            onChanged: model.edit,
                            onSubmit: closeEditor,
                          ),
                        ),
                        if (model.completionSuggestions.isNotEmpty)
                          CompletionHint(
                            suggestions: model.completionSuggestions,
                            strings: model.s,
                            onSelected: model.applyCompletion,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
