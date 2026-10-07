import 'package:flutter/material.dart';
import '../core/strings.dart';
import '../math/completion.dart';

class CompletionHint extends StatelessWidget {
  const CompletionHint({
    super.key,
    required this.suggestions,
    required this.strings,
    required this.onSelected,
  });

  final List<ExpressionCompletion> suggestions;
  final Strings strings;
  final ValueChanged<ExpressionCompletion> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final message = Text(
      strings.t(suggestions.first.message, suggestions.first.messageEn),
      style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
    );
    final actions = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  suggestion.focusSlot ? Icons.edit_rounded : Icons.add_rounded,
                  size: 17,
                ),
                label: Text(strings.t(suggestion.label, suggestion.labelEn)),
                onPressed: () => onSelected(suggestion),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: suggestions.length == 1
          ? Row(
              children: [
                Expanded(child: message),
                const SizedBox(width: 8),
                Flexible(child: actions),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [message, actions],
            ),
    );
  }
}
