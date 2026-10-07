import 'ast.dart';
import 'latex.dart';

/// Readable notation only: never evaluate, cancel terms or alter the stored AST.
/// Keep [astToLatex] as the canonical editable/storage representation.
String astToDisplayLatex(MathNode node) {
  validateAst(node);
  return _display(node);
}

String _group(String text) => r'\left(' + text + r'\right)';
bool _scientific(MathNode n) =>
    n['type'] == 'number' && RegExp('[eE]').hasMatch(n['value'] as String);
bool _signed(MathNode n) =>
    n['type'] == 'unary' ||
    (n['type'] == 'number' && RegExp(r'^[+-]').hasMatch(n['value'] as String));

int _precedence(MathNode n) {
  if (_scientific(n)) return 20;
  if (_signed(n)) return 30;
  if (n['type'] == 'binary') {
    return switch (n['op']) {
      '+' || '-' => 10,
      '*' => 20,
      '^' => 40,
      _ => 50, // The fraction bar already groups numerator and denominator.
    };
  }
  return 50;
}

String _at(MathNode n, int minimum) {
  final text = _display(n);
  return _precedence(n) < minimum ? _group(text) : text;
}

bool _coefficient(MathNode n) =>
    (n['type'] == 'number' && !_scientific(n)) ||
    (n['type'] == 'unary' && _coefficient(n['arg'] as MathNode));

// Omit the multiplication dot for coefficients such as 3x, 2x² and 2(x+1).
// Keep it between numeric factors and wherever juxtaposition is ambiguous.
bool _coefficientTarget(MathNode n) =>
    n['type'] == 'symbol' ||
    n['type'] == 'constant' ||
    (n['type'] == 'binary' &&
        (n['op'] == '+' ||
            n['op'] == '-' ||
            (n['op'] == '^' &&
                {'symbol', 'constant'}.contains(n['left']['type']))));

String _display(MathNode n) {
  String child(String key) => _display(n[key] as MathNode);
  switch (n['type']) {
    case 'number':
      final parts = (n['value'] as String).split(RegExp('[eE]'));
      return parts.length == 1
          ? parts.first
          : '${parts.first} \\times 10^{${parts.last}}';
    case 'symbol':
      return n['name'] as String;
    case 'constant':
      return n['name'] == 'pi' ? r'\pi' : 'e';
    case 'unary':
      final arg = n['arg'] as MathNode;
      return '${n['op']}${_signed(arg) ? _group(_display(arg)) : _at(arg, 30)}';
    case 'binary':
      final a = n['left'] as MathNode, b = n['right'] as MathNode;
      switch (n['op']) {
        case '/':
          return '\\frac{${_display(a)}}{${_display(b)}}';
        case '^':
          return '${_at(a, 41)}^{${_display(b)}}';
        case '*':
          final right = _signed(b) ? _group(_display(b)) : _at(b, 21);
          final join = _coefficient(a) && _coefficientTarget(b)
              ? ''
              : r' \cdot ';
          return '${_at(a, 20)}$join$right';
        default:
          final right = _signed(b) ? _group(_display(b)) : _at(b, 11);
          return '${_at(a, 10)} ${n['op']} $right';
      }
    case 'call':
      final args = (n['args'] as List).cast<MathNode>();
      final a = _display(args.first);
      return switch (n['fn']) {
        'sqrt' => '\\sqrt{$a}',
        'root' => '\\sqrt[${_display(args[1])}]{$a}',
        'abs' => r'\left|' + a + r'\right|',
        'factorial' =>
          '${args.first['fn'] == 'factorial' ? _group(a) : _at(args.first, 41)}!',
        'asin' => '\\arcsin${_group(a)}',
        'acos' => '\\arccos${_group(a)}',
        'atan' => '\\arctan${_group(a)}',
        _ => '\\${n['fn']}${_group(a)}',
      };
    case 'equation':
      return '${child('left')} = ${child('right')}';
    default:
      return astToLatex(n);
  }
}
