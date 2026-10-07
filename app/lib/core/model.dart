import 'dart:async';
import 'package:http/http.dart' show ClientException;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../math/ast.dart';
import '../math/parser.dart';
import '../math/evaluator.dart';
import 'api.dart';
import 'draft.dart';
import 'store.dart';
import 'strings.dart';

final notebookProvider = ChangeNotifierProvider<AppModel>(
  (ref) => AppModel()..load(),
);

enum InputMode { keyboard, ink, camera, voice }

class AppModel extends ChangeNotifier {
  AppModel({
    NotebookStore? store,
    PilotApi Function(String baseUrl, String token)? apiFactory,
  }) : store = store ?? NotebookStore(),
       _apiFactory = apiFactory ?? PilotApi.new;

  final NotebookStore store;
  final PilotApi Function(String baseUrl, String token) _apiFactory;
  final secure = const FlutterSecureStorage();
  final draft = RevisionedDraft();
  String language = 'es',
      angleMode = 'rad',
      operation = 'evaluate',
      variable = 'x';
  ThemeMode themeMode = ThemeMode.system;
  InputMode mode = InputMode.keyboard;
  String baseUrl = defaultPilotUrl();
  String token = '';
  String voiceProvider = 'scribe';
  String? error, notice;
  bool busy = false, loaded = false, maximized = false;
  Map<String, dynamic>? result;
  List<Map<String, dynamic>> history = [];
  List<List<Offset>> ink = [];
  List<Map<String, dynamic>> curves = [];
  Uint8List? photo;
  List<String> ambiguities = [];
  Timer? _saveTimer;
  PilotApi? _api;
  String get latex => draft.latex;
  int get revision => draft.revision;
  int _calculationRevision = 0;
  int _inkRevision = 0, _photoRevision = 0;
  Strings get s => Strings(language);
  PilotApi get api => _api ??= _apiFactory(baseUrl, token);
  void Function(String source, String? segmentId)? onDraftChanged;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final p = await store.preferences();
      language = p['language'] as String? ?? 'es';
      angleMode = p['angleMode'] as String? ?? 'rad';
      operation = p['operation'] as String? ?? 'evaluate';
      variable = p['variable'] as String? ?? 'x';
      baseUrl = p['baseUrl'] as String? ?? baseUrl;
      voiceProvider = p['voiceProvider'] as String? ?? 'scribe';
      themeMode = ThemeMode.values.firstWhere(
        (v) => v.name == p['theme'],
        orElse: () => ThemeMode.system,
      );
      draft.edit(p['draft'] as String? ?? '');
      curves = (p['curves'] as List? ?? [])
          .map((curve) => Map<String, dynamic>.from(curve as Map))
          .take(4)
          .toList();
      if (p['ink'] is List) {
        ink = (p['ink'] as List)
            .map(
              (line) => (line as List)
                  .map(
                    (v) => Offset(
                      (v[0] as num).toDouble(),
                      (v[1] as num).toDouble(),
                    ),
                  )
                  .toList(),
            )
            .toList();
      }
      token =
          await secure.read(key: 'pilotToken') ??
          (kDebugMode ? const String.fromEnvironment('PILOT_TOKEN') : '');
      if (token.isNotEmpty) await secure.write(key: 'pilotToken', value: token);
      history = await store.history();
    } catch (e) {
      error =
          s.t('No se pudo abrir el historial: ', 'Could not open history: ') +
          e.toString();
    }
    loaded = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void edit(String value) {
    draft.edit(value);
    result = null;
    ambiguities = [];
    error = null;
    notice = null;
    onDraftChanged?.call('manual', null);
    scheduleSave();
    _notify();
  }

  bool acceptProposal(
    String value,
    int expectedRevision, {
    List<String> warnings = const [],
    String? segmentId,
  }) {
    if (_disposed || !draft.accept(value, expectedRevision)) return false;
    result = null;
    ambiguities = warnings;
    error = null;
    notice = s.t(
      'Revisa la ecuación y pulsa Resolver.',
      'Review the equation, then press Solve.',
    );
    onDraftChanged?.call('proposal', segmentId);
    scheduleSave();
    _notify();
    return true;
  }

  void setMode(InputMode next) {
    mode = next;
    if (next == InputMode.keyboard) maximized = false;
    error = null;
    _notify();
  }

  void updateInk(List<List<Offset>> value) {
    _inkRevision++;
    ink = value;
    scheduleSave();
    _notify();
  }

  void toggleAngle() {
    _calculationRevision++;
    angleMode = angleMode == 'rad' ? 'deg' : 'rad';
    result = null;
    scheduleSave();
    _notify();
  }

  void setOperation(String value) {
    operation = value;
    _calculationRevision++;
    result = null;
    scheduleSave();
    _notify();
  }

  void setVariable(String value) {
    variable = value;
    _calculationRevision++;
    result = null;
    scheduleSave();
    _notify();
  }

  void expand() {
    maximized = !maximized;
    _notify();
  }

  void report(Object e) {
    error = e.toString();
    _notify();
  }

  void clearMessage() {
    error = null;
    notice = null;
    _notify();
  }

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), save);
  }

  Future<void> save() async {
    try {
      await store.set('draft', latex);
      await store.set('curves', curves);
      await store.set(
        'ink',
        ink.map((line) => line.map((p) => [p.dx, p.dy]).toList()).toList(),
      );
      await store.set('language', language);
      await store.set('angleMode', angleMode);
      await store.set('operation', operation);
      await store.set('variable', variable);
      await store.set('theme', themeMode.name);
      await store.set('baseUrl', baseUrl);
      await store.set('voiceProvider', voiceProvider);
    } catch (e) {
      error = s.t('No se pudo guardar: ', 'Could not save: ') + e.toString();
      _notify();
    }
  }

  Future<void> configure({
    required String url,
    required String pilotToken,
    required String lang,
    required ThemeMode theme,
    required String provider,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !isAllowedPilotUri(uri)) {
      throw ApiException(
        s.t('Usa una URL https válida.', 'Use a valid https URL.'),
      );
    }
    baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    token = pilotToken.trim();
    language = lang;
    themeMode = theme;
    voiceProvider = provider;
    _api?.close();
    _api = null;
    await secure.write(key: 'pilotToken', value: token);
    await save();
    _notify();
  }

  Future<void> calculate() async {
    if (_disposed || busy || latex.trim().isEmpty) return;
    final base = revision, source = latex, angle = angleMode;
    final calculationRevision = ++_calculationRevision;
    final requestedVariable = variable;
    bool isCurrent() =>
        !_disposed &&
        base == revision &&
        calculationRevision == _calculationRevision;
    busy = true;
    error = null;
    notice = null;
    ambiguities = [];
    _notify();
    try {
      final ast = parseLatex(source);
      var op = operation;
      if (op == 'evaluate' &&
          (ast['type'] == 'equation' || ast['type'] == 'system')) {
        op = 'solve';
      }
      if (op == 'evaluate' &&
          requiresCas(ast) &&
          !['derivative', 'integral', 'limit'].contains(ast['type'])) {
        op = 'simplify';
      }
      final symbols = _symbols(ast);
      // Infer an equation's sole unknown for solving. Differentiation and
      // integration must respect the user's explicitly selected variable.
      final effectiveVariable =
          op == 'solve' &&
              !symbols.contains(requestedVariable) &&
              symbols.length == 1
          ? symbols.single
          : requestedVariable;
      Map<String, dynamic> answer;
      if (op == 'evaluate' && !requiresCas(ast)) {
        final local = evaluateLocal(ast, angleMode: angle);
        answer = {
          'status': local.exact ? 'exact' : 'approximate',
          'latex': local.latex,
          'text': local.text,
          'approximation': local.exact ? null : local.text,
          'conditions': <String>[],
          'verification': {'status': 'notApplicable', 'detail': ''},
          'engine': 'dart',
          'engineVersion': '1',
        };
      } else {
        answer = await api.post('/v1/calculate', {
          'ast': ast,
          'operation': op,
          'variable': effectiveVariable,
          'variables': ast['type'] == 'system' && symbols.isNotEmpty
              ? (symbols.toList()..sort())
              : [effectiveVariable],
          'angleMode': angle,
          'domain': 'real',
          'precision': 30,
        });
      }
      if (!isCurrent()) return;
      result = answer;
      await store.add({
        'source': source,
        'ast': ast,
        'operation': op,
        'angleMode': angle,
        'variable': effectiveVariable,
        'result': answer,
        'createdAt': DateTime.now().toIso8601String(),
      });
      history = await store.history();
    } on ClientException {
      if (isCurrent()) {
        error = s.t(
          'Servidor sin conexión. El cálculo numérico y las gráficas siguen disponibles.',
          'Server offline. Numeric calculations and graphs remain available.',
        );
      }
    } catch (e) {
      if (isCurrent()) {
        error = e.toString();
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> recognizeInk() async {
    if (_disposed || busy || ink.isEmpty) return;
    final base = revision, inkRevision = _inkRevision;
    bool isCurrent() =>
        !_disposed && base == revision && inkRevision == _inkRevision;
    busy = true;
    error = null;
    _notify();
    try {
      final r = await api.post('/v1/recognize/ink', {
        'strokes': ink
            .map(
              (line) => {
                'x': line.map((p) => p.dx).toList(),
                'y': line.map((p) => p.dy).toList(),
              },
            )
            .toList(),
        'revision': base,
      });
      if (!isCurrent()) return;
      if (acceptProposal(
        r['latex'] as String,
        base,
        warnings: List<String>.from(r['ambiguities'] ?? []),
      )) {
        mode = InputMode.keyboard;
        maximized = false;
      }
    } catch (e) {
      if (isCurrent()) report(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> recognizePhoto() async {
    if (_disposed || busy || photo == null) return;
    final base = revision, photoRevision = _photoRevision;
    bool isCurrent() =>
        !_disposed && base == revision && photoRevision == _photoRevision;
    busy = true;
    error = null;
    _notify();
    try {
      final r = await api.image(photo!, base);
      if (!isCurrent()) return;
      if (acceptProposal(
        r['latex'] as String,
        base,
        warnings: List<String>.from(r['ambiguities'] ?? []),
      )) {
        mode = InputMode.keyboard;
        maximized = false;
      }
    } catch (e) {
      if (isCurrent()) report(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  void setPhoto(Uint8List value) {
    _photoRevision++;
    photo = value;
    _notify();
  }

  void clearPhoto() {
    _photoRevision++;
    photo = null;
    _notify();
  }

  void restore(Map<String, dynamic> entry) {
    angleMode = entry['angleMode'] as String? ?? 'rad';
    operation = entry['operation'] as String? ?? 'evaluate';
    variable = entry['variable'] as String? ?? 'x';
    _calculationRevision++;
    edit(entry['source'] as String);
    result = Map<String, dynamic>.from(entry['result'] as Map);
    mode = InputMode.keyboard;
    _notify();
  }

  Future<void> clearHistory() async {
    await store.clear();
    history = [];
    _notify();
  }

  Set<String> _symbols(dynamic node) {
    if (node is List) return node.expand((v) => _symbols(v)).toSet();
    if (node is! Map) return {};
    if (node['type'] == 'symbol') return {node['name'] as String};
    return node.values.expand((v) => _symbols(v)).toSet();
  }

  MathNode graphExpression() {
    var ast = parseLatex(latex);
    if (ast['type'] == 'equation') {
      if ((ast['left'] as Map)['type'] != 'symbol' ||
          (ast['left'] as Map)['name'] != 'y') {
        throw MathParseException(
          s.t('Usa y=f(x) para graficar.', 'Use y=f(x) to graph.'),
        );
      }
      ast = Map<String, dynamic>.from(ast['right'] as Map);
    }
    if (_symbols(ast).difference({'x'}).isNotEmpty ||
        requiresCasStructure(ast)) {
      throw MathParseException(
        s.t(
          'La gráfica necesita una función numérica de x.',
          'The graph needs a numeric function of x.',
        ),
      );
    }
    // Domain holes are handled by the graph.
    return ast;
  }

  bool get hasBoundVariable {
    try {
      return [
        'derivative',
        'integral',
        'limit',
      ].contains(parseLatex(latex)['type']);
    } catch (_) {
      return false;
    }
  }

  bool requiresCasStructure(dynamic node) {
    if (node is List) return node.any(requiresCasStructure);
    if (node is! Map) return false;
    if ([
      'system',
      'equation',
      'derivative',
      'integral',
      'limit',
      'infinity',
    ].contains(node['type'])) {
      return true;
    }
    return node.values.any(requiresCasStructure);
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _api?.close();
    super.dispose();
  }
}
