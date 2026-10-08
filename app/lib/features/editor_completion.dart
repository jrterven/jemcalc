import '../core/strings.dart';
import '../math/completion.dart';

// The shared editor only displays suggestions; the model still validates and
// applies a confirmed repair. Match the full proposal so delayed taps are safe.
Map<String, dynamic>? editorCompletionConfiguration(
  List<ExpressionCompletion> suggestions,
  String language,
) {
  if (suggestions.isEmpty) return null;
  final strings = Strings(language);
  return {
    'source': suggestions.first.source,
    'message': strings.t(
      suggestions.first.message,
      suggestions.first.messageEn,
    ),
    'actions': [
      for (final suggestion in suggestions)
        {
          'label': strings.t(suggestion.label, suggestion.labelEn),
          'latex': suggestion.latex,
          'focusSlot': suggestion.focusSlot,
        },
    ],
  };
}

ExpressionCompletion? selectedEditorCompletion(
  Map<dynamic, dynamic> message,
  List<ExpressionCompletion> suggestions,
) {
  for (final suggestion in suggestions) {
    if (message['source'] == suggestion.source &&
        message['latex'] == suggestion.latex &&
        message['focusSlot'] == suggestion.focusSlot) {
      return suggestion;
    }
  }
  return null;
}
