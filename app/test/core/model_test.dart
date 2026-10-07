import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' show ClientException;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jem_calc/core/api.dart';
import 'package:jem_calc/core/model.dart';
import 'package:jem_calc/core/store.dart';

Map<String, dynamic> copyMap(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class MemoryNotebookStore extends NotebookStore {
  final entries = <Map<String, dynamic>>[];
  final values = <String, dynamic>{};
  @override
  Future<void> add(Map<String, dynamic> entry) async =>
      entries.insert(0, copyMap(entry));
  @override
  Future<List<Map<String, dynamic>>> history() async =>
      entries.map(copyMap).toList();
  @override
  Future<Map<String, dynamic>> preferences() async => copyMap(values);
  @override
  Future<void> set(String key, dynamic value) async {
    values[key] = value;
  }

  @override
  Future<void> clear() async => entries.clear();
}

class PendingCall {
  PendingCall(this.path, Map<String, dynamic> body) : body = copyMap(body);
  final String path;
  final Map<String, dynamic> body;
  final response = Completer<Map<String, dynamic>>();
}

class ControlledApi extends PilotApi {
  ControlledApi() : super('https://test.invalid', 'test-only');
  final calls = <PendingCall>[];
  bool closed = false;
  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) {
    final call = PendingCall(path, body);
    calls.add(call);
    return call.response.future;
  }

  @override
  Future<Map<String, dynamic>> image(Uint8List bytes, int revision) => post(
    '/v1/recognize/image',
    {'bytes': bytes.toList(), 'revision': revision},
  );

  @override
  void close() {
    closed = true;
  }
}

Map<String, dynamic> answer([String text = 'x+1']) => {
  'status': 'exact',
  'text': text,
  'latex': text,
  'engine': 'test-cas',
  'engineVersion': '1',
  'conditions': <String>[],
  'verification': {'status': 'notApplicable', 'detail': ''},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryNotebookStore store;
  late ControlledApi api;
  AppModel model() {
    store = MemoryNotebookStore();
    api = ControlledApi();
    final model = AppModel(store: store, apiFactory: (_, _) => api);
    addTearDown(model.dispose);
    return model;
  }

  test('variable picker offers actual letters, not functions or constants', () {
    final m = model()..edit(r'a+b+N+\sin(q)+\pi+e');
    expect(m.variableOptions, ['x', 'y', 'z', 't', 'a', 'b', 'N', 'q']);
    m.setVariable('q');
    m.edit(r'\frac{a}{');
    expect(m.variableOptions, contains('q'));
  });

  test('QWERTY variables can be selected for calculus and persist', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final m = model()
      ..edit('a^2+b')
      ..setOperation('differentiate')
      ..setVariable('a');
    final pending = m.calculate();
    expect(api.calls.single.body['variable'], 'a');
    expect(api.calls.single.body['operation'], 'differentiate');
    api.calls.single.response.complete(answer('2a'));
    await pending;
    await m.save();
    final reopened = AppModel(store: store);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.variable, 'a');
    expect(reopened.variableOptions, containsAll(['a', 'b']));
  });

  test(
    'curve visibility survives reopening without deleting calculation history',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final m = model();
      m.curves.add({
        'ast': {'type': 'symbol', 'name': 'x'},
        'latex': 'x',
        'angleMode': 'rad',
        'visible': false,
      });
      await store.add({'latex': '1+1', 'result': '2'});
      await m.save();
      final reopened = AppModel(store: store);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.error, isNull);
      expect(reopened.curves.single['visible'], false);
      expect(reopened.curves.single['latex'], 'x');
      reopened.curves.clear();
      await reopened.save();
      expect(store.values['curves'], isEmpty);
      expect(await store.history(), hasLength(1));
    },
  );

  group('Plotting equation systems', () {
    test(
      'adds both equations atomically, without solving or altering history/draft',
      () {
        final m = model()..edit('3x+y=5;2x-y=3');
        final revision = m.revision;
        m.addDraftToGraph();
        expect(m.curves, hasLength(2));
        expect(m.latex, '3x+y=5;2x-y=3');
        expect(m.revision, revision);
        expect(m.history, isEmpty);
        expect(api.calls, isEmpty);
        m.curves.first['visible'] = false;
        m.addDraftToGraph();
        expect(m.curves, hasLength(2));
        expect(m.curves.first['visible'], false);
      },
    );
    test('capacity failure never adds only part of a system', () {
      final m = model();
      for (final expression in ['x', 'x^2', 'x^3']) {
        m.edit(expression);
        m.addDraftToGraph();
      }
      final before = copyMap({'curves': m.curves});
      m.edit('3x+y=5;2x-y=3');
      expect(m.addDraftToGraph, throwsException);
      expect(m.curves, before['curves']);
    });
    test('an unsupported later row leaves previous curves intact', () {
      final m = model()..edit('x');
      m.addDraftToGraph();
      m.edit('3x+y=5;x^2+y^2=1');
      expect(m.addDraftToGraph, throwsException);
      expect(m.curves, hasLength(1));
    });
    test(
      'duplicates inside the same system count once, and old curves remain compatible',
      () {
        final m = model()..edit('y=x;y=x');
        m.curves.add({
          'ast': {'type': 'symbol', 'name': 'x'},
          'latex': 'x',
          'angleMode': 'rad',
        });
        m.addDraftToGraph();
        expect(m.curves, hasLength(1));
        m.edit('x=2;y=2');
        m.addDraftToGraph();
        expect(m.curves, hasLength(3));
      },
    );
    test('equation labels and vertical geometry survive reopening', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final m = model()..edit('x=2;3x+y=5');
      m.addDraftToGraph();
      await m.save();
      final reopened = AppModel(store: store);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.curves, m.curves);
      expect(reopened.curves.first['kind'], 'vertical');
    });
  });

  group('Confirmed expression completions', () {
    test(
      'dictation repair preserves mode, blocks stale proposals and never calculates',
      () {
        final m = model()..setMode(InputMode.voice);
        m.acceptProposal(r'\int x^2', m.revision);
        final prior = m.revision;
        final hint = m.completionSuggestions.single;
        final edits = <String>[];
        m.onDraftChanged = (source, _) => edits.add(source);
        expect(m.latex, r'\int x^2'); // Reading suggestions does not edit.
        expect(m.applyCompletion(hint), true);
        expect(m.mode, InputMode.voice);
        expect(m.revision, prior + 1);
        expect(edits, ['manual']);
        expect(m.acceptProposal(r'\int x^2', prior), false);
        expect(m.applyCompletion(hint), false);
        expect(m.latex, contains(r'\mathrm{d}x'));
        expect(api.calls, isEmpty);
        expect(m.history, isEmpty);
      },
    );
    test('stale hint cannot overwrite an edited draft', () {
      final m = model()..edit('(x+1');
      final hint = m.completionSuggestions.single;
      m.edit('y+2');
      expect(m.applyCompletion(hint), false);
      expect(m.latex, 'y+2');
    });
    test(
      'empty slot restores keyboard and asks editor to focus without guessing',
      () {
        final m = model()
          ..edit(r'\frac{1}{}')
          ..expand();
        expect(m.applyCompletion(m.completionSuggestions.single), true);
        expect(m.editorFocusRequest, 1);
        expect(m.maximized, false);
        expect(m.latex, r'\frac{1}{\placeholder{}}');
        expect(api.calls, isEmpty);
      },
    );
    test(
      'a repaired integral is submitted to the CAS only on Resolve',
      () async {
        final m = model()..edit(r'\int_0^1 x^2');
        m.applyCompletion(m.completionSuggestions.single);
        expect(api.calls, isEmpty);
        final pending = m.calculate();
        expect(api.calls.single.body['ast']['type'], 'integral');
        expect(api.calls.single.body['ast']['variable'], 'x');
        api.calls.single.response.complete(answer('1/3'));
        await pending;
        expect(m.result?['text'], '1/3');
      },
    );
  });

  group('Keyboard restoration', () {
    test('returning from handwriting restores the keyboard and draft', () {
      final m = model()..edit('y=2x+1');
      m.expand();
      m.setMode(InputMode.ink);
      m.setMode(InputMode.keyboard);
      expect(m.maximized, isFalse);
      expect(m.latex, 'y=2x+1');
    });

    test('tapping the selected keyboard mode exits the expanded display', () {
      final m = model()..expand();
      m.setMode(InputMode.keyboard);
      expect(m.maximized, isFalse);
    });

    for (final capture in ['ink', 'photo']) {
      test(
        '$capture recognition restores keyboard from an expanded screen',
        () async {
          final m = model()..expand();
          late Future<void> pending;
          if (capture == 'ink') {
            m.setMode(InputMode.ink);
            m.updateInk([
              [const Offset(10, 10), const Offset(20, 20)],
            ]);
            pending = m.recognizeInk();
          } else {
            m.setMode(InputMode.camera);
            m.setPhoto(Uint8List.fromList([1, 2, 3]));
            pending = m.recognizePhoto();
          }
          api.calls.single.response.complete({'latex': 'x+1=2'});
          await pending;
          expect(m.mode, InputMode.keyboard);
          expect(m.maximized, isFalse);
          expect(m.latex, 'x+1=2');
        },
      );
    }
  });

  group('Asynchronous calculation context', () {
    final changes = <String, void Function(AppModel)>{
      'angle mode': (m) => m.toggleAngle(),
      'operation': (m) => m.setOperation('factor'),
      'variable': (m) => m.setVariable('y'),
      'manual edit': (m) => m.edit('x+2'),
      'accepted proposal': (m) => m.acceptProposal('x+3', m.revision),
      'change then revert': (m) {
        m.toggleAngle();
        m.toggleAngle();
      },
    };
    for (final change in changes.entries) {
      test('late CAS result is discarded after ${change.key}', () async {
        final m = model()..edit('x+1');
        final computation = m.calculate();
        expect(m.busy, isTrue);
        expect(api.calls.single.path, '/v1/calculate');
        change.value(m);
        api.calls.single.response.complete(answer());
        await computation;
        expect(m.result, isNull);
        expect(m.error, isNull);
        expect(m.busy, isFalse);
        expect(m.history, isEmpty);
        expect(store.entries, isEmpty);
      });
    }
    for (final failure in [
      ClientException('offline'),
      ApiException('old request failed'),
    ]) {
      test('late $failure cannot replace a current draft message', () async {
        final m = model()..edit('x+1');
        final computation = m.calculate();
        m.edit('x+2');
        m.report('current draft warning');
        api.calls.single.response.completeError(failure);
        await computation;
        expect(m.error, 'current draft warning');
        expect(m.result, isNull);
        expect(store.entries, isEmpty);
      });
    }
    test(
      'current offline response still reports an actionable error',
      () async {
        final m = model()..edit('x+1');
        final computation = m.calculate();
        api.calls.single.response.completeError(ClientException('offline'));
        await computation;
        expect(m.error, contains('sin conexión'));
        expect(m.busy, isFalse);
      },
    );
    test(
      'disposing during a request prevents results and history writes',
      () async {
        final store = MemoryNotebookStore(), api = ControlledApi();
        final m = AppModel(store: store, apiFactory: (_, _) => api)
          ..edit('x+1');
        final computation = m.calculate();
        m.dispose();
        api.calls.single.response.complete(answer());
        await computation;
        expect(m.result, isNull);
        expect(store.entries, isEmpty);
        expect(api.closed, isTrue);
      },
    );
  });

  group('CAS variable semantics', () {
    test(
      'a system sends its actual unknowns, independent of the selected variable',
      () async {
        final m = model()
          ..edit('b+a=3;b-a=1')
          ..setVariable('z');
        final computation = m.calculate();
        final body = api.calls.single.body;
        expect(body['operation'], 'solve');
        expect(body['variables'], ['a', 'b']);
        api.calls.single.response.complete(answer('a=1,b=2'));
        await computation;
        expect(m.result?['status'], 'exact');
      },
    );
    test(
      'ordinary expressions with more than four symbols do not fill the system-only field',
      () async {
        final m = model()
          ..edit('a+b+c+d+f+g')
          ..setVariable('g');
        final computation = m.calculate();
        final body = api.calls.single.body;
        expect(body['operation'], 'simplify');
        expect(body['variables'], ['g']);
        expect(body['variable'], 'g');
        api.calls.single.response.complete(answer('a+b+c+d+f+g'));
        await computation;
        expect(m.error, isNull);
        expect(m.result?['text'], 'a+b+c+d+f+g');
      },
    );
    test(
      'solving infers a sole unknown and records the variable actually used',
      () async {
        final m = model()..edit('y^2=4');
        final computation = m.calculate();
        expect(api.calls.single.body['operation'], 'solve');
        expect(api.calls.single.body['variable'], 'y');
        expect(api.calls.single.body['variables'], ['y']);
        api.calls.single.response.complete(answer('y=-2,2'));
        await computation;
        expect(m.history.single['variable'], 'y');
        m.restore(m.history.single);
        expect(m.variable, 'y');
      },
    );
    for (final operation in ['differentiate', 'integrate']) {
      test(
        '$operation respects an explicitly selected variable absent from the expression',
        () async {
          final m = model()
            ..edit('y^2')
            ..setOperation(operation)
            ..setVariable('x');
          final computation = m.calculate();
          expect(api.calls.single.body['variable'], 'x');
          api.calls.single.response.complete(
            answer(operation == 'differentiate' ? '0' : 'xy^2'),
          );
          await computation;
          expect(m.error, isNull);
        },
      );
    }
  });

  test(
    'history restores expression, operation, variable, angle, and result together',
    () async {
      final m = model()
        ..edit('sin(y)')
        ..setOperation('differentiate')
        ..setVariable('y')
        ..toggleAngle();
      final computation = m.calculate();
      expect(api.calls.single.body['angleMode'], 'deg');
      api.calls.single.response.complete(answer('pi*cos(pi*y/180)/180'));
      await computation;
      final entry = m.history.single;
      m.edit('99');
      m.setOperation('evaluate');
      m.setVariable('x');
      m.toggleAngle();
      m.setMode(InputMode.camera);
      m.restore(entry);
      expect(m.latex, 'sin(y)');
      expect(m.operation, 'differentiate');
      expect(m.variable, 'y');
      expect(m.angleMode, 'deg');
      expect(m.mode, InputMode.keyboard);
      expect(m.result?['text'], 'pi*cos(pi*y/180)/180');
      expect(api.calls, hasLength(1));
      await m.save();
      expect(store.values['operation'], 'differentiate');
      expect(store.values['variable'], 'y');
      expect(store.values['angleMode'], 'deg');
    },
  );

  test('history restore invalidates an older pending calculation', () async {
    final m = model()..edit('x+1');
    final computation = m.calculate();
    m.restore({
      'source': '2+2',
      'angleMode': 'deg',
      'operation': 'evaluate',
      'variable': 'z',
      'result': answer('4'),
    });
    api.calls.single.response.complete(answer('x+1'));
    await computation;
    expect(m.latex, '2+2');
    expect(m.result?['text'], '4');
    expect(store.entries, isEmpty);
  });

  group('Recognition capture revisions', () {
    void prepare(AppModel m, InputMode mode) {
      m.edit('previous draft');
      m.setMode(mode);
      if (mode == InputMode.ink) {
        m.updateInk([
          [const Offset(1, 2), const Offset(3, 4)],
        ]);
      } else {
        m.setPhoto(Uint8List.fromList([1, 2, 3]));
      }
    }

    Future<void> recognize(AppModel m, InputMode mode) =>
        mode == InputMode.ink ? m.recognizeInk() : m.recognizePhoto();

    final changes = [
      (
        name: 'editing ink',
        mode: InputMode.ink,
        change: (AppModel m) => m.updateInk([
          [const Offset(9, 8), const Offset(7, 6)],
        ]),
      ),
      (
        name: 'clearing ink',
        mode: InputMode.ink,
        change: (AppModel m) => m.updateInk([]),
      ),
      (
        name: 'replacing photo',
        mode: InputMode.camera,
        change: (AppModel m) => m.setPhoto(Uint8List.fromList([9, 8, 7])),
      ),
      (
        name: 'clearing photo',
        mode: InputMode.camera,
        change: (AppModel m) => m.clearPhoto(),
      ),
    ];
    for (final change in changes) {
      test(
        '${change.name} discards the pending recognition without changing the draft',
        () async {
          final m = model();
          prepare(m, change.mode);
          final base = m.revision;
          var draftEvents = 0;
          m.onDraftChanged = (_, _) => draftEvents++;
          final pending = recognize(m, change.mode);
          change.change(m);
          api.calls.single.response.complete({
            'latex': 'stale OCR',
            'ambiguities': ['old warning'],
          });
          await pending;
          expect(m.latex, 'previous draft');
          expect(m.revision, base);
          expect(m.mode, change.mode);
          expect(m.notice, isNull);
          expect(m.ambiguities, isEmpty);
          expect(m.busy, isFalse);
          expect(draftEvents, 0);
        },
      );
    }
    for (final mode in [InputMode.ink, InputMode.camera]) {
      test(
        'a failed stale $mode request cannot replace a newer message',
        () async {
          final m = model();
          prepare(m, mode);
          final pending = recognize(m, mode);
          if (mode == InputMode.ink) {
            m.updateInk([]);
          } else {
            m.clearPhoto();
          }
          m.report('current capture warning');
          api.calls.single.response.completeError(
            ApiException('old capture failed'),
          );
          await pending;
          expect(m.error, 'current capture warning');
          expect(m.latex, 'previous draft');
        },
      );
      test(
        'an unchanged $mode capture still becomes an editable proposal',
        () async {
          final m = model();
          prepare(m, mode);
          final base = m.revision;
          final pending = recognize(m, mode);
          expect(api.calls.single.body['revision'], base);
          api.calls.single.response.complete({
            'latex': 'x^2',
            'ambiguities': ['Check exponent'],
          });
          await pending;
          expect(m.latex, 'x^2');
          expect(m.revision, base + 1);
          expect(m.mode, InputMode.keyboard);
          expect(m.ambiguities, ['Check exponent']);
          expect(m.notice, isNotNull);
          expect(m.result, isNull);
          expect(store.entries, isEmpty);
        },
      );
    }
  });

  test(
    'proposal revisions preserve manual edits, reject duplicate segments, and never calculate automatically',
    () {
      final m = model();
      final events = <List<Object?>>[];
      m.onDraftChanged = (source, id) => events.add([source, id, m.revision]);
      final base = m.revision;
      expect(
        m.acceptProposal(
          'x+1',
          base,
          warnings: ['Check exponent'],
          segmentId: 'speech-1',
        ),
        isTrue,
      );
      expect(m.revision, base + 1);
      expect(m.ambiguities, ['Check exponent']);
      expect(m.notice, isNotNull);
      expect(
        m.acceptProposal('wrong duplicate', base, segmentId: 'speech-1'),
        isFalse,
      );
      m.edit('x+2');
      expect(m.acceptProposal('late OCR', base + 1), isFalse);
      expect(m.latex, 'x+2');
      expect(m.ambiguities, isEmpty);
      expect(m.notice, isNull);
      expect(events, [
        ['proposal', 'speech-1', base + 1],
        ['manual', null, base + 2],
      ]);
      expect(api.calls, isEmpty);
      expect(m.result, isNull);
    },
  );
}
