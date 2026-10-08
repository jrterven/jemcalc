import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/strings.dart';

String resultDetails(Map<String, dynamic> result) => [
  ...(result['conditions'] as List? ?? []).map((c) => c.toString()),
  if ((result['verification'] as Map?)?['detail'] != null)
    (result['verification'] as Map)['detail'].toString(),
].where((line) => line.isNotEmpty).join('\n');

String _resultId(Map<String, dynamic> result) =>
    identityHashCode(result).toString();

bool matchesEditorResult(Map message, Map<String, dynamic>? result) =>
    result != null && message['resultId'] == _resultId(result);

Map<String, dynamic>? editorResultConfiguration(
  Map<String, dynamic>? result,
  String language,
) {
  if (result == null) return null;
  final strings = Strings(language);
  return {
    'id': _resultId(result),
    'status': strings.status(result['status'] as String),
    'latex': result['latex'] as String? ?? '',
    'text': result['text'] as String? ?? '',
    'approximation': result['status'] == 'exact'
        ? result['approximation']
        : null,
    'verified': (result['verification'] as Map?)?['status'] == 'verified',
    'hasDetails': resultDetails(result).isNotEmpty,
    'copyLabel': strings.t('Copiar resultado', 'Copy result'),
    'detailsLabel': strings.t(
      'Dominio y comprobación',
      'Domain and verification',
    ),
    'resultLabel': strings.t('Resultado', 'Result'),
  };
}

Future<void> copyResult(Map<String, dynamic> result) {
  final latex = result['latex'] as String? ?? '';
  return Clipboard.setData(
    ClipboardData(
      text: latex.isNotEmpty ? latex : result['text'] as String? ?? '',
    ),
  );
}

Future<void> showResultDetails(
  BuildContext context,
  Map<String, dynamic> result,
  Strings strings,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => Padding(
    padding: const EdgeInsets.all(24),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.t('Dominio y comprobación', 'Domain and verification'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          SelectableText(resultDetails(result)),
          const SizedBox(height: 16),
        ],
      ),
    ),
  ),
);
