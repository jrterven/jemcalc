import 'ast.dart';

export 'ast.dart' show MathNode, MathParseException;

MathNode parseLatex(String latex) => _parse(latex);
MathNode parseExpression(String input) => _parse(input);

MathNode _parse(String input) {
  if (input.length > 32768) {
    throw const MathParseException('Expression is too long.');
  }
  try {
    final result = _parseSource(_normalize(input), 0);
    validateAst(result);
    return result;
  } on MathEvaluationException catch (e) {
    throw MathParseException(e.message);
  }
}

String _normalize(String input) {
  var s = input.trim();
  if (s.startsWith(r'\(') && s.endsWith(r'\)') ||
      s.startsWith(r'\[') && s.endsWith(r'\]')) {
    s = s.substring(2, s.length - 2);
  } else if (s.startsWith(r'$$') && s.endsWith(r'$$') && s.length >= 4) {
    s = s.substring(2, s.length - 2);
  } else if (s.startsWith(r'$') && s.endsWith(r'$') && s.length >= 2) {
    s = s.substring(1, s.length - 1);
  }
  s = s.replaceAll(RegExp(r'\\(?:left|right|displaystyle|textstyle)\b'), '');
  s = s.replaceAll(RegExp(r'\\[,!;: ]'), ' ');
  s = s.replaceAll(RegExp(r'\\(?:quad|qquad)\b'), ' ');
  s = s.replaceAllMapped(
    RegExp(r'\\(?:mathrm|operatorname|mathit)\{([a-zA-Z]+)\}'),
    (m) {
      final name = m[1]!;
      if (name.length == 1 ||
          mathFunctions.contains(name) ||
          {
            'arcsin',
            'arccos',
            'arctan',
            'diff',
            'integrate',
            'limit',
          }.contains(name)) {
        return name;
      }
      throw MathParseException('Unsupported named operator: $name.');
    },
  );
  s = s.replaceAll(r'\dfrac', r'\frac').replaceAll(r'\tfrac', r'\frac');
  s = _expandFractionArguments(s);
  s = s.replaceAll(r'\rightarrow', r'\to');
  s = s
      .replaceAll('−', '-')
      .replaceAll('×', '*')
      .replaceAll('·', '*')
      .replaceAll('÷', '/')
      .replaceAll('π', r'\pi')
      .replaceAll('∞', r'\infty')
      .replaceAll('²', '^{2}')
      .replaceAll('³', '^{3}');
  if (s.contains(r'\placeholder') || s.contains(r'\Box') || s.contains('#?')) {
    throw const MathParseException(
      'Complete all empty expression slots first.',
    );
  }
  return s.trim();
}

// MathLive omits braces around single TeX atoms: \frac12 means 1/2,
// not one argument containing the decimal integer 12. Preserve TeX boundaries
// before the expression lexer combines adjacent digits into numbers.
String _expandFractionArguments(String source) {
  final matches = RegExp(r'\\frac(?![a-zA-Z])').allMatches(source).toList();
  var s = source;
  for (final match in matches.reversed) {
    var offset = match.end;
    final arguments = <String>[];
    for (var arg = 0; arg < 2; arg++) {
      while (offset < s.length && s[offset].trim().isEmpty) {
        offset++;
      }
      if (offset == s.length) break;
      if (s[offset] == '{') {
        final start = offset++;
        var depth = 1;
        while (offset < s.length && depth > 0) {
          if (s[offset] == '{') depth++;
          if (s[offset] == '}') depth--;
          offset++;
        }
        if (depth != 0) break;
        arguments.add(s.substring(start, offset));
      } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(s[offset])) {
        arguments.add('{${s[offset++]}}');
      } else {
        // Keep complex command arguments with their original parser behavior.
        break;
      }
    }
    if (arguments.length == 2) {
      s = '${s.substring(0, match.end)}${arguments.join()}${s.substring(offset)}';
    }
  }
  return s;
}

MathNode _parseSource(String source, int depth) {
  if (depth > maxMathDepth) {
    throw const MathParseException('Expression is too deeply nested.');
  }
  var s = source.trim();
  if (s.isEmpty) throw const MathParseException('Enter an expression.');
  // Mathpix often wraps systems with a brace and an invisible right delimiter.
  if (s.startsWith(r'\{') && s.contains(r'\begin{')) {
    s = s.substring(2).trim();
    if (s.endsWith(r'\}')) {
      s = s.substring(0, s.length - 2).trim();
    } else if (s.endsWith('.')) {
      s = s.substring(0, s.length - 1).trim();
    }
  }
  final environment = RegExp(
    r'^\\begin\{(cases|aligned|array)\}',
  ).firstMatch(s);
  if (environment != null) {
    final end = '\\end{${environment[1]}}';
    if (!s.endsWith(end)) {
      throw const MathParseException('Unclosed equation system.');
    }
    s = s.substring(environment.end, s.length - end.length).trim();
    if (environment[1] == 'array' && s.startsWith('{')) {
      s = s.substring(_readUnit(s, 0).end).trim();
    }
    s = s.replaceAll('&', '');
  }
  if (s.startsWith('system(') && s.endsWith(')')) {
    s = s.substring(7, s.length - 1);
  }
  final rows = _splitRows(s);
  if (rows.length > 1 || environment != null) {
    final equations = rows.map((r) => _parseSource(r, depth + 1)).toList();
    if (equations.any((n) => n['type'] != 'equation')) {
      throw const MathParseException(
        'Every row of a system must be an equation.',
      );
    }
    return {'type': 'system', 'equations': equations};
  }

  final derivative = RegExp(
    r'^\\frac\s*\{d(?:\^\{?(\d+)\}?)?\}\s*\{d\s*([a-zA-Z])(?:\^\{?(\d+)\}?)?\}\s*(.+)$',
    dotAll: true,
  ).firstMatch(s);
  if (derivative != null) {
    final order = int.parse(derivative[1] ?? '1');
    if (order != int.parse(derivative[3] ?? '1')) {
      throw const MathParseException('Derivative orders must agree.');
    }
    return {
      'type': 'derivative',
      'body': _parseSource(derivative[4]!, depth + 1),
      'variable': derivative[2],
      'order': order,
    };
  }

  if (RegExp(r'^\\int(?![a-zA-Z])').hasMatch(s)) {
    var rest = s.substring(4).trim();
    MathNode? lower, upper;
    for (var i = 0; i < 2; i++) {
      if (!rest.startsWith('_') && !rest.startsWith('^')) break;
      final isLower = rest[0] == '_';
      final unit = _readUnit(rest, 1);
      final bound = _parseSource(unit.content, depth + 1);
      if (isLower) {
        if (lower != null) {
          throw const MathParseException('Duplicate lower bound.');
        }
        lower = bound;
      } else {
        if (upper != null) {
          throw const MathParseException('Duplicate upper bound.');
        }
        upper = bound;
      }
      rest = rest.substring(unit.end).trim();
    }
    final differential = RegExp(
      r'^(.*?)\s*d\s*([a-zA-Z])\s*$',
      dotAll: true,
    ).firstMatch(rest);
    if (differential == null || differential[1]!.trim().isEmpty) {
      throw const MathParseException(
        'An integral needs a body and differential, e.g. dx.',
      );
    }
    return {
      'type': 'integral',
      'body': _parseSource(differential[1]!, depth + 1),
      'variable': differential[2],
      'lower': lower,
      'upper': upper,
    };
  }

  if (RegExp(r'^\\lim(?![a-zA-Z])').hasMatch(s)) {
    var rest = s.substring(4).trim();
    if (!rest.startsWith('_')) {
      throw const MathParseException(
        'A limit needs a variable and destination.',
      );
    }
    final unit = _readUnit(rest, 1);
    final approach = RegExp(
      r'^\s*([a-zA-Z])\s*(?:\\to|->)\s*(.+)$',
    ).firstMatch(unit.content);
    if (approach == null) {
      throw const MathParseException('Use a limit such as x → 0.');
    }
    var destination = approach[2]!.trim();
    var direction = 'both';
    final side = RegExp(r'\^\{?([+-])\}?$').firstMatch(destination);
    if (side != null) {
      direction = side[1]!;
      destination = destination.substring(0, side.start).trim();
    }
    return {
      'type': 'limit',
      'body': _parseSource(rest.substring(unit.end), depth + 1),
      'variable': approach[1],
      'to': _destination(destination, depth + 1),
      'direction': direction,
    };
  }

  return _Parser(_lex(s), depth).parse();
}

MathNode _destination(String s, int depth) {
  final compact = s.replaceAll(' ', '');
  if ({r'\infty', r'+\infty', 'infinity', '+infinity'}.contains(compact)) {
    return {'type': 'infinity', 'sign': 1};
  }
  if ({r'-\infty', '-infinity'}.contains(compact)) {
    return {'type': 'infinity', 'sign': -1};
  }
  return _parseSource(s, depth);
}

List<String> _splitRows(String s) {
  var level = 0, start = 0;
  final rows = <String>[];
  for (var i = 0; i < s.length; i++) {
    if ('({['.contains(s[i])) level++;
    if (')}]'.contains(s[i])) level--;
    if (level > maxMathDepth || level < 0) {
      throw const MathParseException(
        'Unbalanced or deeply nested parentheses.',
      );
    }
    if (level == 0 &&
        (s[i] == ';' ||
            (s[i] == r'\' && i + 1 < s.length && s[i + 1] == r'\'))) {
      rows.add(s.substring(start, i));
      if (s[i] == r'\') i++;
      start = i + 1;
    }
  }
  rows.add(s.substring(start));
  return rows;
}

({String content, int end}) _readUnit(String s, int offset) {
  var i = offset;
  while (i < s.length && s[i].trim().isEmpty) {
    i++;
  }
  if (i >= s.length) throw const MathParseException('Missing argument.');
  if (s[i] == '{') {
    final start = ++i;
    var nesting = 1;
    while (i < s.length && nesting > 0) {
      if (s[i] == '{') nesting++;
      if (s[i] == '}') nesting--;
      if (nesting > maxMathDepth) {
        throw const MathParseException('Expression is too complex.');
      }
      i++;
    }
    if (nesting != 0) throw const MathParseException('Unclosed argument.');
    return (content: s.substring(start, i - 1), end: i);
  }
  final m = RegExp(
    r'^(?:\\[a-zA-Z]+|[+-]?(?:\d+(?:\.\d+)?|[a-zA-Z]))',
  ).firstMatch(s.substring(i));
  if (m == null) throw const MathParseException('Invalid argument.');
  return (content: m[0]!, end: i + m.end);
}

class _Token {
  const _Token(this.value, this.position, {this.number = false});
  final String value;
  final int position;
  final bool number;
}

List<_Token> _lex(String input) {
  final tokens = <_Token>[];
  final number = RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?');
  final letters = RegExp(r'^[a-zA-Z]+');
  final knownWords = {
    ...mathFunctions,
    'pi',
    'e',
    'arcsin',
    'arccos',
    'arctan',
    'diff',
    'integrate',
    'limit',
    'infinity',
  };
  const aliases = {
    'cdot': '*',
    'times': '*',
    'div': '/',
    'arcsin': 'asin',
    'arccos': 'acos',
    'arctan': 'atan',
    'lvert': '|',
    'rvert': '|',
    'vert': '|',
  };
  for (var i = 0; i < input.length;) {
    final char = input[i];
    if (char.trim().isEmpty) {
      i++;
      continue;
    }
    final nm = number.firstMatch(input.substring(i));
    if (nm != null) {
      tokens.add(_Token(nm[0]!, i, number: true));
      i += nm.end;
    } else if (char == r'\') {
      final match = letters.firstMatch(input.substring(i + 1));
      if (match == null) {
        throw MathParseException('Unsupported symbol at position ${i + 1}.');
      }
      final command = match[0]!;
      if (!knownWords.contains(command) &&
          !aliases.containsKey(command) &&
          command != 'frac') {
        throw MathParseException('Unsupported command: \\$command.');
      }
      tokens.add(_Token(aliases[command] ?? command, i));
      i += match.end + 1;
    } else if (letters.hasMatch(input.substring(i))) {
      final word = letters.firstMatch(input.substring(i))![0]!;
      if (knownWords.contains(word)) {
        tokens.add(_Token(aliases[word] ?? word, i));
      } else {
        // Adjacent one-letter variables are conventional implicit products.
        for (var j = 0; j < word.length; j++) {
          tokens.add(_Token(word[j], i + j));
        }
      }
      i += word.length;
    } else if ('+-*/^!(){}[],=|_'.contains(char)) {
      tokens.add(_Token(char, i));
      i++;
    } else {
      throw MathParseException(
        'Unsupported symbol "$char" at position ${i + 1}.',
      );
    }
    if (tokens.length > 4096) {
      throw const MathParseException('Expression is too long.');
    }
  }
  tokens.add(_Token('EOF', input.length));
  return tokens;
}

class _Parser {
  _Parser(this.tokens, this.depth);
  final List<_Token> tokens;
  int depth;
  int index = 0;
  String get current => tokens[index].value;
  bool match(String value) {
    if (current != value) return false;
    index++;
    return true;
  }

  void expect(String value) {
    if (!match(value)) {
      throw MathParseException(
        'Expected "$value" at position ${tokens[index].position + 1}.',
      );
    }
  }

  MathNode parse() {
    final result = equation();
    if (current != 'EOF') {
      throw MathParseException(
        'Unexpected "$current" at position ${tokens[index].position + 1}.',
      );
    }
    return result;
  }

  MathNode equation() {
    var result = expression();
    if (match('=')) {
      result = {'type': 'equation', 'left': result, 'right': expression()};
    }
    return result;
  }

  MathNode expression() {
    if (++depth > maxMathDepth) {
      throw const MathParseException('Expression is too deeply nested.');
    }
    var result = product();
    while (current == '+' || current == '-') {
      final op = current;
      index++;
      result = _binary(op, result, product());
    }
    depth--;
    return result;
  }

  MathNode product() {
    var result = unary();
    while (true) {
      if (current == '*' || current == '/') {
        final op = current;
        index++;
        result = _binary(op, result, unary());
      } else if (_startsImplicit()) {
        result = _binary('*', result, unary());
      } else {
        break;
      }
    }
    return result;
  }

  bool _startsImplicit() =>
      tokens[index].number ||
      current == '(' ||
      current == '{' ||
      current == 'frac' ||
      current == 'pi' ||
      current == 'e' ||
      mathFunctions.contains(current) ||
      RegExp(r'^[a-zA-Z]$').hasMatch(current);
  MathNode unary() {
    if (current == '+' || current == '-') {
      final op = current;
      index++;
      if (++depth > maxMathDepth) {
        throw const MathParseException('Expression is too deeply nested.');
      }
      final arg = unary();
      depth--;
      return {'type': 'unary', 'op': op, 'arg': arg};
    }
    return power();
  }

  MathNode power() {
    var result = primary();
    while (match('!')) {
      result = _call('factorial', [result]);
    }
    if (match('^')) {
      if (++depth > maxMathDepth) {
        throw const MathParseException('Expression is too deeply nested.');
      }
      result = _binary('^', result, unary());
      depth--;
    }
    return result;
  }

  MathNode primary() {
    if (++depth > maxMathDepth) {
      throw const MathParseException('Expression is too deeply nested.');
    }
    try {
      return _primary();
    } finally {
      depth--;
    }
  }

  MathNode _primary() {
    final token = tokens[index];
    if (token.number) {
      index++;
      return {'type': 'number', 'value': token.value};
    }
    if (current == '(' || current == '{' || current == '[') {
      final close = {'(': ')', '{': '}', '[': ']'}[current]!;
      index++;
      final value = expression();
      expect(close);
      return value;
    }
    if (match('|')) {
      final value = expression();
      expect('|');
      return _call('abs', [value]);
    }
    if (match('frac')) {
      final a = argument(), b = argument();
      return _binary('/', a, b);
    }
    if (current == 'pi' || current == 'e') {
      index++;
      return {'type': 'constant', 'name': token.value};
    }
    if ({'diff', 'integrate', 'limit'}.contains(current)) return calculus();
    if (mathFunctions.contains(current)) {
      var fn = current;
      index++;
      MathNode? exponent, base, rootIndex;
      if (fn == 'sqrt' && match('[')) {
        rootIndex = expression();
        expect(']');
      }
      if (fn == 'log' && match('_')) base = argument();
      if (match('^')) {
        exponent = argument();
        if (_isNegativeOne(exponent) && {'sin', 'cos', 'tan'}.contains(fn)) {
          fn = 'a$fn';
          exponent = null;
        }
      }
      MathNode result;
      if (fn == 'root') {
        expect('(');
        final radicand = expression();
        expect(',');
        final degree = expression();
        expect(')');
        result = _call('root', [radicand, degree]);
      } else {
        final value = argument();
        result = rootIndex == null
            ? _call(fn, [value])
            : _call('root', [value, rootIndex]);
      }
      if (base != null) {
        result = _binary(
          '/',
          _call('ln', [((result['args']) as List).first as MathNode]),
          _call('ln', [base]),
        );
      }
      return exponent == null ? result : _binary('^', result, exponent);
    }
    if (RegExp(r'^[a-zA-Z]$').hasMatch(current)) {
      index++;
      return {'type': 'symbol', 'name': token.value};
    }
    throw MathParseException(
      current == 'EOF'
          ? 'The expression is incomplete.'
          : 'Expected an expression, found "$current".',
    );
  }

  MathNode argument() {
    if (current == '{' || current == '(' || current == '[') return primary();
    return unary();
  }

  MathNode calculus() {
    final fn = current;
    index++;
    expect('(');
    final body = expression();
    expect(',');
    final variable = current;
    if (!RegExp(r'^[a-zA-Z]$').hasMatch(variable)) {
      throw const MathParseException(
        'Choose a single-letter calculus variable.',
      );
    }
    index++;
    if (fn == 'diff') {
      var order = 1;
      if (match(',')) {
        if (!tokens[index].number) {
          throw const MathParseException(
            'A derivative needs an integer order.',
          );
        }
        final orderToken = tokens[index++];
        order = int.tryParse(orderToken.value) ?? 0;
      }
      expect(')');
      return {
        'type': 'derivative',
        'body': body,
        'variable': variable,
        'order': order,
      };
    }
    if (fn == 'integrate') {
      MathNode? lower, upper;
      if (match(',')) {
        lower = expression();
        expect(',');
        upper = expression();
      }
      expect(')');
      return {
        'type': 'integral',
        'body': body,
        'variable': variable,
        'lower': lower,
        'upper': upper,
      };
    }
    expect(',');
    MathNode destination;
    if (current == 'infinity') {
      index++;
      destination = {'type': 'infinity', 'sign': 1};
    } else if (current == '-' && tokens[index + 1].value == 'infinity') {
      index += 2;
      destination = {'type': 'infinity', 'sign': -1};
    } else {
      destination = expression();
    }
    var direction = 'both';
    if (match(',')) {
      if (current != '+' && current != '-') {
        throw const MathParseException('Limit direction must be + or -.');
      }
      direction = current;
      index++;
    }
    expect(')');
    return {
      'type': 'limit',
      'body': body,
      'variable': variable,
      'to': destination,
      'direction': direction,
    };
  }
}

bool _isNegativeOne(MathNode n) =>
    n['type'] == 'unary' &&
    n['op'] == '-' &&
    n['arg']['type'] == 'number' &&
    n['arg']['value'] == '1';
MathNode _binary(String op, MathNode a, MathNode b) => {
  'type': 'binary',
  'op': op,
  'left': a,
  'right': b,
};
MathNode _call(String fn, List<MathNode> args) => {
  'type': 'call',
  'fn': fn,
  'args': args,
};
