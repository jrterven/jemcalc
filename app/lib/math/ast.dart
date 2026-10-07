/// The version-one interchange AST. No source text is executed as code.
typedef MathNode = Map<String, dynamic>;

class MathParseException implements Exception {
  const MathParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MathEvaluationException implements Exception {
  const MathEvaluationException(this.message);
  final String message;
  @override
  String toString() => message;
}

const mathFunctions = {
  'sin',
  'cos',
  'tan',
  'asin',
  'acos',
  'atan',
  'sqrt',
  'abs',
  'ln',
  'log',
  'exp',
  'factorial',
  'root',
};
const maxMathDepth = 64;
const maxMathNodes = 512;
const maxRationalDigits = 4096;
const maxRootIndex = 1000;

final numberLiteralPattern = RegExp(
  r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$',
);

/// Validate untrusted ASTs before rendering or calculation, including bounds.
void validateAst(MathNode node) {
  var count = 0;
  void visit(dynamic raw, int depth, {bool allowInfinity = false}) {
    if (depth > maxMathDepth || ++count > maxMathNodes) {
      throw const MathEvaluationException('Expression is too complex.');
    }
    if (raw is! Map<String, dynamic>) {
      throw const MathEvaluationException('Invalid expression node.');
    }
    final n = raw;
    void child(String key) => visit(n[key], depth + 1);
    void symbol(dynamic value) {
      if (value is! String || !RegExp(r'^[a-zA-Z]$').hasMatch(value)) {
        throw const MathEvaluationException(
          'Variables must be single letters.',
        );
      }
    }

    void keys(Set<String> expected) {
      if (n.keys.any((k) => !expected.contains(k))) {
        throw const MathEvaluationException('Unknown expression property.');
      }
    }

    switch (n['type']) {
      case 'number':
        keys({'type', 'value'});
        final value = n['value'];
        if (value is! String ||
            value.length > maxRationalDigits + 16 ||
            !numberLiteralPattern.hasMatch(value)) {
          throw const MathEvaluationException(
            'Invalid or excessively large number.',
          );
        }
        final exponent = value.split(RegExp('[eE]'));
        if (exponent.length == 2 &&
            (int.tryParse(exponent[1]) == null ||
                int.parse(exponent[1]).abs() > maxRationalDigits)) {
          throw const MathEvaluationException('Number exponent is too large.');
        }
      case 'symbol':
        keys({'type', 'name'});
        symbol(n['name']);
      case 'constant':
        keys({'type', 'name'});
        if (n['name'] != 'pi' && n['name'] != 'e') {
          throw const MathEvaluationException('Unknown constant.');
        }
      case 'unary':
        keys({'type', 'op', 'arg'});
        if (!{'+', '-'}.contains(n['op'])) {
          throw const MathEvaluationException('Unknown unary operator.');
        }
        child('arg');
      case 'binary':
        keys({'type', 'op', 'left', 'right'});
        if (!{'+', '-', '*', '/', '^'}.contains(n['op'])) {
          throw const MathEvaluationException('Unknown binary operator.');
        }
        child('left');
        child('right');
      case 'call':
        keys({'type', 'fn', 'args'});
        final args = n['args'];
        if (!mathFunctions.contains(n['fn']) ||
            args is! List ||
            args.length != (n['fn'] == 'root' ? 2 : 1)) {
          throw const MathEvaluationException(
            'Unknown function or invalid arguments.',
          );
        }
        for (final arg in args) {
          visit(arg, depth + 1);
        }
      case 'equation':
        keys({'type', 'left', 'right'});
        child('left');
        child('right');
      case 'system':
        keys({'type', 'equations'});
        final equations = n['equations'];
        if (equations is! List ||
            equations.isEmpty ||
            equations.any((e) => e is! Map || e['type'] != 'equation')) {
          throw const MathEvaluationException(
            'A system must contain equations.',
          );
        }
        for (final eq in equations) {
          visit(eq, depth + 1);
        }
      case 'derivative':
        keys({'type', 'body', 'variable', 'order'});
        symbol(n['variable']);
        if (n['order'] is! int || n['order'] < 1 || n['order'] > 3) {
          throw const MathEvaluationException(
            'Derivative order must be 1 to 3.',
          );
        }
        child('body');
      case 'integral':
        keys({'type', 'body', 'variable', 'lower', 'upper'});
        symbol(n['variable']);
        child('body');
        if ((n['lower'] == null) != (n['upper'] == null)) {
          throw const MathEvaluationException(
            'Both integral bounds are required.',
          );
        }
        if (n['lower'] != null) {
          child('lower');
          child('upper');
        }
      case 'limit':
        keys({'type', 'body', 'variable', 'to', 'direction'});
        symbol(n['variable']);
        if (!{'both', '+', '-'}.contains(n['direction'])) {
          throw const MathEvaluationException('Invalid limit direction.');
        }
        child('body');
        visit(n['to'], depth + 1, allowInfinity: true);
      case 'infinity':
        keys({'type', 'sign'});
        if (!allowInfinity || (n['sign'] != 1 && n['sign'] != -1)) {
          throw const MathEvaluationException(
            'Infinity is only a limit destination.',
          );
        }
      default:
        throw const MathEvaluationException('Unsupported expression node.');
    }
  }

  visit(node, 0);
}

/// Symbols require the CAS unless explicitly bound by evaluateLocal/Double.
bool requiresCas(MathNode ast) {
  validateAst(ast);
  bool inspect(MathNode node) {
    switch (node['type']) {
      case 'number':
      case 'constant':
        return false;
      case 'unary':
        return inspect(node['arg'] as MathNode);
      case 'binary':
        return inspect(node['left'] as MathNode) ||
            inspect(node['right'] as MathNode);
      case 'call':
        return (node['args'] as List).any((a) => inspect(a as MathNode));
      default:
        return true;
    }
  }

  return inspect(ast);
}
