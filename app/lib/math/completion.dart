import 'parser.dart';

/// A grammar repair proposed to the user, never an automatic edit or calculation.
class ExpressionCompletion {
  const ExpressionCompletion({
    required this.source,
    required this.latex,
    required this.message,
    required this.messageEn,
    required this.label,
    required this.labelEn,
    this.focusSlot = false,
  });
  final String source, latex, message, messageEn, label, labelEn;
  final bool focusSlot;
}

const _hole = r'\placeholder{}';
final _slots = RegExp(
  r'\\placeholder(?:\[[^\]]*\])?\{[^{}]*\}|\\Box(?![a-zA-Z])|#\?|\{\s*\}',
);

bool _valid(String source) {
  try {
    parseLatex(source);
    return true;
  } on MathParseException {
    return false;
  }
}

/// Conservative, local syntax checks, shared by all input modes and platforms.
/// Unknown operands remain visible holes. Probe symbols validate grammar only;
/// they are never returned as a proposed value or sent to the calculation engine.
List<ExpressionCompletion> expressionCompletions(
  String source, {
  String preferredVariable = 'x',
}) {
  if (source.length > 32768 || source.trim().isEmpty || _valid(source)) {
    return const [];
  }
  var formula = source.trim();
  for (final (open, close) in [
    (r'\(', r'\)'),
    (r'\[', r'\]'),
    (r'$$', r'$$'),
    (r'$', r'$'),
  ]) {
    if (formula.length >= open.length + close.length &&
        formula.startsWith(open) &&
        formula.endsWith(close)) {
      formula = formula.substring(open.length, formula.length - close.length);
      break;
    }
  }
  formula = formula
      .replaceAll(RegExp(r'\\(?:displaystyle|textstyle)\b'), '')
      .trim();
  final differential = _differentials(source, formula, preferredVariable);
  if (differential.isNotEmpty) return differential;

  final closed = _closeGroups(formula);
  if (closed == null) {
    return const []; // Mismatched or excessively nested groups.
  }
  if (closed != formula && _valid(closed)) {
    return [
      ExpressionCompletion(
        source: source,
        latex: closed,
        message: 'Falta cerrar la expresión.',
        messageEn: 'The expression is not closed.',
        label: 'Cerrar',
        labelEn: 'Close',
      ),
    ];
  }

  var candidate = closed;
  // Empty MathLive slots, including empty groups emitted by its serializer.
  candidate = candidate.replaceAllMapped(
    _slots,
    (m) => m[0]!.startsWith('{') ? '{$_hole}' : _hole,
  );
  candidate = candidate.replaceAllMapped(RegExp(r'\(\s*\)'), (_) => '($_hole)');
  candidate = candidate.replaceAllMapped(RegExp(r'\[\s*\]'), (_) => '[$_hole]');

  // A terminal operator, exponent or equation side needs an operand, not a guess.
  candidate = candidate.replaceAllMapped(
    RegExp(r'([+\-*/=^]|\\(?:cdot|times|div)\b)\s*(?=[)}\]]|$)'),
    (m) => '${m[0]}{$_hole}',
  );

  // Complete missing arguments of fractions and elementary functions at a boundary.
  candidate = _missingArguments(candidate);

  // Limits require both a variable and destination, followed by a body.
  if (RegExp(r'^\\lim(?![a-zA-Z])').hasMatch(candidate)) {
    var rest = candidate.substring(4).trim();
    if (!rest.startsWith('_')) {
      candidate =
          '${r'\lim_{'}$_hole${r'\to '}$_hole} ${rest.isEmpty ? _hole : rest}';
    } else {
      final unit = _group(rest, 1);
      if (unit != null) {
        var approach = unit.content;
        if (approach == _hole || approach.trim().isEmpty) {
          approach = '$_hole${r'\to '}$_hole';
        } else {
          approach = approach.replaceFirstMapped(
            RegExp(r'^\s*(?=\\(?:to|rightarrow)\b|->)'),
            (_) => _hole,
          );
          approach = approach.replaceFirstMapped(
            RegExp(r'(\\(?:to|rightarrow)\b|->)\s*$'),
            (m) => '${m[0]} $_hole',
          );
        }
        final body = rest.substring(unit.end).trim();
        candidate = '${r'\lim_{'}$approach} ${body.isEmpty ? _hole : body}';
      }
    }
  }

  // A definite integral needs both bounds. Add an empty slot for the absent one.
  if (RegExp(r'^\\int(?![a-zA-Z])').hasMatch(candidate)) {
    final rest = candidate.substring(4).trimLeft();
    if (rest.startsWith('_') || rest.startsWith('^')) {
      final first = _group(rest, 1);
      if (first != null) {
        final tail = rest.substring(first.end).trimLeft();
        if (!tail.startsWith('_') && !tail.startsWith('^')) {
          final other = rest[0] == '_' ? '^' : '_';
          candidate =
              '${r'\int'}${rest.substring(0, first.end)}$other{$_hole} $tail';
        }
      }
    }
  }
  if (!candidate.contains(_hole)) return const [];
  // Validate the whole repaired structure. Unsupported syntax remains an error.
  final probe = candidate.replaceAll(_hole, 'x');
  if (!_valid(probe)) return const [];
  final (message, messageEn) = _slotMessage(candidate);
  return [
    ExpressionCompletion(
      source: source,
      latex: candidate,
      message: message,
      messageEn: messageEn,
      label: 'Completar',
      labelEn: 'Complete',
      focusSlot: true,
    ),
  ];
}

(String, String) _slotMessage(String s) {
  if (s.startsWith(r'\lim')) {
    return ('Faltan datos del límite.', 'The limit needs more information.');
  }
  if (s.startsWith(r'\int')) {
    return (
      'Hay espacios vacíos en la integral.',
      'The integral has empty slots.',
    );
  }
  if (s.contains('^{$_hole}')) {
    return ('Falta el exponente.', 'Missing exponent.');
  }
  final frac = RegExp(r'\\(?:dfrac|tfrac|frac)\b').firstMatch(s);
  if (frac != null) {
    final a = _group(s, frac.end);
    final b = a == null ? null : _group(s, a.end);
    if (a?.content == _hole && b?.content != _hole) {
      return ('Falta el numerador.', 'Missing numerator.');
    }
    if (b?.content == _hole && a?.content != _hole) {
      return ('Falta el denominador.', 'Missing denominator.');
    }
  }
  if (RegExp(r'=\s*\{?\\placeholder').hasMatch(s)) {
    return ('Falta un lado de la ecuación.', 'Missing side of the equation.');
  }
  return ('Hay un espacio por completar.', 'There is an empty slot to fill.');
}

String _missingArguments(String s) {
  // Walk backwards so inserting a slot does not shift preceding command offsets.
  final commands = RegExp(
    r'\\(?:dfrac|tfrac|frac|sqrt|sin|cos|tan|ln|log|exp|arcsin|arccos|arctan)\b',
  ).allMatches(s).toList();
  for (final command in commands.reversed) {
    var end = command.end;
    final count = command[0]!.endsWith('frac') ? 2 : 1;
    for (var i = 0; i < count; i++) {
      final unit = _group(s, end);
      if (unit != null) {
        end = unit.end;
        continue;
      }
      while (end < s.length && s[end].trim().isEmpty) {
        end++;
      }
      if (end == s.length || ')}]'.contains(s[end])) {
        s = '${s.substring(0, end)}{$_hole}${s.substring(end)}';
        end += _hole.length + 2;
      } else {
        break;
      } // Unbraced arguments are legal; don't reinterpret them.
    }
  }
  return s;
}

({String content, int end})? _group(String s, int offset) {
  var i = offset;
  while (i < s.length && s[i].trim().isEmpty) {
    i++;
  }
  if (i >= s.length || s[i] != '{') return null;
  final start = ++i;
  var depth = 1;
  for (; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}') depth--;
    if (depth == 0) return (content: s.substring(start, i), end: i + 1);
  }
  return null;
}

String? _closeGroups(String s) {
  final stack = <String>[];
  const pairs = {'(': ')', '[': ']', '{': '}'};
  for (var i = 0; i < s.length; i++) {
    // Don't interpret escaped delimiters or environments as arithmetic groups.
    if (s[i] == r'\' && i + 1 < s.length && '{}()[]'.contains(s[i + 1])) {
      return null;
    }
    final c = s[i];
    if (pairs.containsKey(c)) {
      stack.add(pairs[c]!);
      if (stack.length > 64) return null;
    } else if (')]}'.contains(c)) {
      if (stack.isEmpty || stack.removeLast() != c) return null;
    }
  }
  return s + stack.reversed.join();
}

List<ExpressionCompletion> _differentials(
  String source,
  String formula,
  String preferredVariable,
) {
  final integral = RegExp(r'\\int(?![a-zA-Z])');
  if (integral.allMatches(formula).length != 1 ||
      !integral.hasMatch(formula) ||
      !formula.startsWith(r'\int')) {
    return const [];
  }
  try {
    final candidate = parseLatex('$formula${r'\,\mathrm{d}x'}');
    if (candidate['type'] != 'integral') return const [];
    final variables = <String>{};
    bool expressionOnly(dynamic node) {
      if (node is List) return node.every(expressionOnly);
      if (node is! Map) return true;
      if (!{
        'number',
        'symbol',
        'constant',
        'unary',
        'binary',
        'call',
      }.contains(node['type'])) {
        return false;
      }
      if (node['type'] == 'symbol') variables.add(node['name'] as String);
      return node.values.every(expressionOnly);
    }

    if (!expressionOnly(candidate['body']) || variables.contains('d')) {
      return const [];
    }
    final choices = variables.toList()..sort();
    if (choices.isEmpty) {
      choices.add(
        RegExp(r'^[a-zA-Z]$').hasMatch(preferredVariable)
            ? preferredVariable
            : 'x',
      );
    }
    return [
      for (final variable in choices)
        ExpressionCompletion(
          source: source,
          latex: '$formula${r'\,\mathrm{d}'}$variable',
          message: choices.length == 1
              ? 'Falta el diferencial.'
              : 'Elige el diferencial.',
          messageEn: choices.length == 1
              ? 'Missing differential.'
              : 'Choose the differential.',
          label: 'Añadir d$variable',
          labelEn: 'Add d$variable',
        ),
    ];
  } on MathParseException {
    return const [];
  }
}
