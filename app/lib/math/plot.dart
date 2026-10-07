import 'ast.dart';
import 'evaluator.dart';
import 'latex.dart';
import 'parser.dart';

class PlotException implements Exception {
  const PlotException(this.reason);
  final String reason;
}

/// Prepare all rows before changing the graph. Algebra is local and preserves
/// exact rational coefficients; no recognition model or network is involved.
List<Map<String, dynamic>> preparePlots(
  MathNode input, {
  String angleMode = 'rad',
}) {
  validateAst(input);
  final equations = input['type'] == 'system'
      ? (input['equations'] as List).cast<MathNode>()
      : [input];
  return equations.map((node) => _prepare(node, angleMode)).toList();
}

Set<String> _symbols(dynamic node) {
  if (node is List) return node.expand(_symbols).toSet();
  if (node is! Map) return {};
  if (node['type'] == 'symbol') return {node['name'] as String};
  return node.values.expand(_symbols).toSet();
}

bool _numeric(dynamic node) {
  if (node is List) return node.every(_numeric);
  if (node is! Map) return true;
  return {
        'number',
        'symbol',
        'constant',
        'unary',
        'binary',
        'call',
      }.contains(node['type']) &&
      node.values.every(_numeric);
}

Map<String, dynamic> _prepare(MathNode node, String angle) {
  Map<String, dynamic> curve(MathNode ast, {bool vertical = false}) => {
    'ast': ast,
    'latex': astToLatex(ast),
    'angleMode': angle,
    'kind': vertical ? 'vertical' : 'function',
    if (node['type'] == 'equation') 'label': astToLatex(node),
  };
  if (_symbols(node).difference({'x', 'y'}).isNotEmpty) {
    throw const PlotException('variables');
  }
  if (node['type'] != 'equation') {
    if (!_numeric(node) || _symbols(node).contains('y')) {
      throw const PlotException('unsupported');
    }
    return curve(node);
  }
  final left = node['left'] as MathNode, right = node['right'] as MathNode;
  // Explicit functions keep their original domain, including poles and holes.
  for (final (lhs, rhs) in [(left, right), (right, left)]) {
    if (lhs['type'] == 'symbol' &&
        lhs['name'] == 'y' &&
        !_symbols(rhs).contains('y') &&
        _numeric(rhs)) {
      return curve(rhs);
    }
  }
  final algebra = _LinearAlgebra(angle);
  final line = algebra.subtract(algebra.read(left), algebra.read(right));
  if (!algebra.zero(line.y)) {
    final slope = algebra.scalar('/', algebra.negate(line.x), line.y);
    final intercept = algebra.scalar('/', algebra.negate(line.c), line.y);
    final term = algebra.zero(slope)
        ? _n('0')
        : algebra.one(slope)
        ? _x
        : _binary('*', slope, _x);
    final function = algebra.zero(term)
        ? intercept
        : algebra.zero(intercept)
        ? term
        : _binary('+', term, intercept);
    return curve(function);
  }
  if (!algebra.zero(line.x)) {
    return curve(
      algebra.scalar('/', algebra.negate(line.c), line.x),
      vertical: true,
    );
  }
  throw PlotException(algebra.zero(line.c) ? 'identity' : 'empty');
}

MathNode _n(String value) => {'type': 'number', 'value': value};
final MathNode _x = {'type': 'symbol', 'name': 'x'};
MathNode _binary(String op, MathNode a, MathNode b) => {
  'type': 'binary',
  'op': op,
  'left': a,
  'right': b,
};

class _Linear {
  const _Linear(this.x, this.y, this.c);
  final MathNode x, y, c;
}

class _LinearAlgebra {
  _LinearAlgebra(this.angle);
  final String angle;
  bool zero(MathNode n) {
    if (_symbols(n).isNotEmpty) return false;
    return evaluateLocal(n, angleMode: angle).text == '0';
  }

  bool one(MathNode n) => evaluateLocal(n, angleMode: angle).text == '1';
  bool constant(_Linear a) => zero(a.x) && zero(a.y);
  MathNode negate(MathNode a) => scalar('-', _n('0'), a);
  MathNode scalar(String op, MathNode a, MathNode b) {
    final expression = _binary(op, a, b);
    final result = evaluateLocal(expression, angleMode: angle);
    // Keep inexact constants symbolic, rather than rounding coefficients.
    return result.exact ? parseExpression(result.text) : expression;
  }

  _Linear subtract(_Linear a, _Linear b) => _Linear(
    scalar('-', a.x, b.x),
    scalar('-', a.y, b.y),
    scalar('-', a.c, b.c),
  );
  _Linear scale(_Linear a, MathNode b, String op) =>
      _Linear(scalar(op, a.x, b), scalar(op, a.y, b), scalar(op, a.c, b));
  _Linear read(MathNode n) {
    if (!_numeric(n)) throw const PlotException('unsupported');
    if (_symbols(n).isEmpty) {
      evaluateLocal(n, angleMode: angle); // Reject undefined constant domains.
      return _Linear(_n('0'), _n('0'), n);
    }
    if (n['type'] == 'symbol') {
      return _Linear(
        _n(n['name'] == 'x' ? '1' : '0'),
        _n(n['name'] == 'y' ? '1' : '0'),
        _n('0'),
      );
    }
    if (n['type'] == 'unary') {
      final a = read(n['arg'] as MathNode);
      return n['op'] == '+' ? a : scale(a, _n('-1'), '*');
    }
    if (n['type'] == 'binary') {
      final a = read(n['left'] as MathNode), b = read(n['right'] as MathNode);
      switch (n['op']) {
        case '+':
          return _Linear(
            scalar('+', a.x, b.x),
            scalar('+', a.y, b.y),
            scalar('+', a.c, b.c),
          );
        case '-':
          return subtract(a, b);
        case '*':
          if (constant(a)) return scale(b, a.c, '*');
          if (constant(b)) return scale(a, b.c, '*');
        case '/':
          // Never cancel a variable denominator: that could erase domain holes.
          if (_symbols(n['right']).isEmpty) return scale(a, b.c, '/');
        case '^':
          if (_symbols(n['right']).isEmpty && one(b.c)) return a;
      }
    }
    throw const PlotException('nonlinear');
  }
}
