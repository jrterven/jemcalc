import 'ast.dart';

/// Serialize the editable structure; never simplify or change its domain.
String astToLatex(MathNode node) {
  validateAst(node);
  return _latex(node);
}

String _latex(MathNode n) {
  String at(String key) => _latex(n[key] as MathNode);
  String group(String s) => r'\left(' + s + r'\right)';
  switch (n['type']) {
    case 'number':
      return n['value'] as String;
    case 'symbol':
      return n['name'] as String;
    case 'constant':
      return n['name'] == 'pi' ? r'\pi' : 'e';
    case 'unary':
      return '${n['op']}${group(at('arg'))}';
    case 'binary':
      final a = at('left'), b = at('right');
      return switch (n['op']) {
        '/' => '\\frac{$a}{$b}',
        '^' => '${group(a)}^{$b}',
        '*' => '${group(a)} \\cdot ${group(b)}',
        _ => '${group(a)} ${n['op']} ${group(b)}',
      };
    case 'call':
      final args = (n['args'] as List).cast<MathNode>();
      final a = _latex(args.first);
      return switch (n['fn']) {
        'sqrt' => '\\sqrt{$a}',
        'root' => '\\sqrt[${_latex(args[1])}]{$a}',
        'abs' => r'\left|' + a + r'\right|',
        'factorial' => '${group(a)}!',
        'asin' => '\\arcsin${group(a)}',
        'acos' => '\\arccos${group(a)}',
        'atan' => '\\arctan${group(a)}',
        _ => '\\${n['fn']}${group(a)}',
      };
    case 'equation':
      return '${at('left')}=${at('right')}';
    case 'system':
      return r'\begin{cases}' +
          (n['equations'] as List)
              .map((e) => _latex(e as MathNode))
              .join(r'\\') +
          r'\end{cases}';
    case 'derivative':
      final order = n['order'] as int;
      final power = order == 1 ? '' : '^{$order}';
      return '\\frac{d$power}{d${n['variable']}$power}${group(at('body'))}';
    case 'integral':
      final bounds = n['lower'] == null
          ? ''
          : '_{${at('lower')}}^{${at('upper')}}';
      return '\\int$bounds ${group(at('body'))}\\,\\mathrm{d}${n['variable']}';
    case 'limit':
      final direction = n['direction'] == 'both' ? '' : '^{${n['direction']}}';
      return '\\lim_{${n['variable']}\\to ${at('to')}$direction}${group(at('body'))}';
    case 'infinity':
      return n['sign'] == -1 ? r'-\infty' : r'\infty';
    default:
      throw const MathEvaluationException('Unsupported expression node.');
  }
}
