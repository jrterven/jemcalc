import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/core/api.dart';

void main() {
  test(
    'API paths retain the deployment prefix and discard query fragments',
    () {
      final api = PilotApi('https://calc.example/api/?unused=1#section', '');
      addTearDown(api.close);
      expect(api.uri('/health').toString(), 'https://calc.example/api/health');
      expect(
        api.uri('/v1/dictation').toString(),
        'https://calc.example/api/v1/dictation',
      );
    },
  );

  test('native clients still require HTTPS', () {
    for (final base in [
      'http://localhost:5187/api',
      'http://192.168.1.2:8443',
      'https:',
    ]) {
      final api = PilotApi(base, '');
      addTearDown(api.close);
      expect(() => api.uri('/health'), throwsA(isA<ApiException>()));
    }
  });
}
