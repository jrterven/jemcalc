import 'package:flutter_test/flutter_test.dart';
import 'package:jem_calc/core/draft.dart';

void main() {
  test('manual corrections cannot be replaced by late OCR or dictation', () {
    final draft = RevisionedDraft()..edit('x^2');
    final request = draft.revision;
    draft.edit('x^3');
    expect(draft.accept('x^2+1', request), false);
    expect(draft.latex, 'x^3');
  });
  test(
    'accepted proposal advances revision so duplicate messages cannot apply',
    () {
      final draft = RevisionedDraft();
      expect(draft.accept('x', 0), true);
      expect(draft.accept('y', 0), false);
      expect(draft.latex, 'x');
    },
  );
}
