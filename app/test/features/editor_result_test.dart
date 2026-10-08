import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/features/editor_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'result presentation preserves exact value, approximation and conditions',
    () {
      final result = <String, dynamic>{
        'status': 'exact',
        'latex': r'\sqrt{2}',
        'text': 'sqrt(2)',
        'approximation': '1.41421356237',
        'conditions': ['x > 0'],
        'verification': {'status': 'verified', 'detail': 'Checked'},
      };
      final view = editorResultConfiguration(result, 'es')!;
      expect(view['status'], 'Exacto');
      expect(view['latex'], r'\sqrt{2}');
      expect(view['approximation'], '1.41421356237');
      expect(view['verified'], isTrue);
      expect(view['hasDetails'], isTrue);
      expect(resultDetails(result), 'x > 0\nChecked');
      expect(
        editorResultConfiguration(result, 'en')!['copyLabel'],
        'Copy result',
      );
      final message = {'resultId': view['id']};
      expect(matchesEditorResult(message, result), isTrue);
      expect(matchesEditorResult(message, {...result}), isFalse);
      expect(matchesEditorResult(message, null), isFalse);
      expect(editorResultConfiguration(null, 'es'), isNull);
    },
  );

  test(
    'errors and approximations are not labeled as verified exact answers',
    () {
      final result = <String, dynamic>{
        'status': 'domainError',
        'text': 'Undefined',
      };
      final view = editorResultConfiguration(result, 'es')!;
      expect(view['status'], 'Fuera del dominio');
      expect(view['latex'], '');
      expect(view['text'], 'Undefined');
      expect(view['verified'], isFalse);
      expect(view['hasDetails'], isFalse);
      expect(
        editorResultConfiguration({
          'status': 'approximate',
          'text': '1.4',
          'approximation': '1.4',
        }, 'es')!['approximation'],
        isNull,
      );
    },
  );

  test('copy retains the exact LaTeX and falls back to plain text', () async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await copyResult({'latex': r'\frac{1}{3}', 'text': '1/3'});
    await copyResult({'latex': '', 'text': 'Undefined'});
    expect(copied, [r'\frac{1}{3}', 'Undefined']);
  });
}
