import 'dart:math' as math;
import 'ast.dart';

export 'ast.dart' show MathNode, MathEvaluationException, requiresCas;

class LocalResult {
  const LocalResult({
    required this.text,
    required this.latex,
    required this.exact,
    this.value,
  });
  final String text;
  final String latex;
  final bool exact;
  final double? value;
}

LocalResult evaluateLocal(
  MathNode ast, {
  String angleMode = 'rad',
  Map<String, double> variables = const {},
}) {
  validateAst(ast);
  _validateSettings(angleMode, variables);
  final result = _evaluate(ast, angleMode, variables);
  final rational = result.rational;
  if (rational != null) {
    final value = rational.toDouble();
    return LocalResult(
      text: rational.denominator == BigInt.one
          ? '${rational.numerator}'
          : '${rational.numerator}/${rational.denominator}',
      latex: rational.denominator == BigInt.one
          ? '${rational.numerator}'
          : '\\frac{${rational.numerator}}{${rational.denominator}}',
      exact: true,
      value: value.isFinite ? value : null,
    );
  }
  final value = _finite(result.number!);
  final text = _formatDouble(value);
  return LocalResult(text: text, latex: text, exact: false, value: value);
}

/// Numeric projection for plotting. Invalid domains throw rather than drawing
/// invented points; callers should break the curve at those samples.
double evaluateDouble(
  MathNode ast, {
  String angleMode = 'rad',
  Map<String, double> variables = const {},
}) {
  validateAst(ast);
  _validateSettings(angleMode, variables);
  return _finite(_evaluate(ast, angleMode, variables).asDouble);
}

void _validateSettings(String angleMode, Map<String, double> variables) {
  if (angleMode != 'rad' && angleMode != 'deg') {
    throw const MathEvaluationException('Angle mode must be rad or deg.');
  }
  if (variables.entries.any(
    (e) => !RegExp(r'^[a-zA-Z]$').hasMatch(e.key) || !e.value.isFinite,
  )) {
    throw const MathEvaluationException(
      'Variable values must be finite real numbers.',
    );
  }
}

String _formatDouble(double value) {
  if (value == 0) return '0';
  final parts = value.toStringAsPrecision(15).split('e');
  var first = parts[0];
  if (first.contains('.')) {
    first = first
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return parts.length == 1 ? first : '${first}e${parts[1]}';
}

double _finite(double value) {
  if (!value.isFinite) {
    throw const MathEvaluationException(
      'The result is outside the finite real domain.',
    );
  }
  return value;
}

class _Value {
  const _Value.exact(this.rational) : number = null;
  _Value.approximate(double value) : rational = null, number = _finite(value);
  final _Rational? rational;
  final double? number;
  double get asDouble => rational?.toDouble() ?? number!;
  bool get isZero => rational?.numerator == BigInt.zero || number == 0;
}

class _Rational {
  factory _Rational(BigInt numerator, [BigInt? denominator]) {
    var d = denominator ?? BigInt.one;
    if (d == BigInt.zero) {
      throw const MathEvaluationException('Division by zero.');
    }
    if (d.isNegative) {
      numerator = -numerator;
      d = -d;
    }
    final divisor = numerator.gcd(d);
    final n = numerator ~/ divisor;
    d ~/= divisor;
    if (n.abs().toString().length > maxRationalDigits ||
        d.toString().length > maxRationalDigits) {
      throw const MathEvaluationException('Exact result exceeds 4096 digits.');
    }
    return _Rational._(n, d);
  }
  const _Rational._(this.numerator, this.denominator);
  factory _Rational.fromLiteral(String literal) {
    final scientific = literal.split(RegExp('[eE]'));
    final exponent = scientific.length == 2 ? int.parse(scientific[1]) : 0;
    final decimal = scientific[0].split('.');
    final digits = decimal.join();
    final scale = (decimal.length == 2 ? decimal[1].length : 0) - exponent;
    if (scale.abs() > maxRationalDigits) {
      throw const MathEvaluationException(
        'Number precision exceeds 4096 digits.',
      );
    }
    final numerator = BigInt.parse(digits);
    if (scale >= 0) return _Rational(numerator, BigInt.from(10).pow(scale));
    return _Rational(numerator * BigInt.from(10).pow(-scale));
  }
  final BigInt numerator;
  final BigInt denominator;
  bool get isInteger => denominator == BigInt.one;
  _Rational operator -() => _Rational(-numerator, denominator);
  _Rational operator +(_Rational b) => _Rational(
    numerator * b.denominator + b.numerator * denominator,
    denominator * b.denominator,
  );
  _Rational operator -(_Rational b) => this + (-b);
  _Rational operator *(_Rational b) =>
      _Rational(numerator * b.numerator, denominator * b.denominator);
  _Rational operator /(_Rational b) =>
      _Rational(numerator * b.denominator, denominator * b.numerator);
  _Rational abs() => _Rational(numerator.abs(), denominator);
  double logAbs() {
    double logInteger(BigInt value) {
      final digits = value.abs().toString();
      final take = math.min(digits.length, 16);
      return math.log(double.parse(digits.substring(0, take))) +
          (digits.length - take) * math.ln10;
    }

    return logInteger(numerator) - logInteger(denominator);
  }

  double toDouble() {
    // Avoid Infinity/Infinity for exact fractions with large components.
    final n = numerator.abs().toString(), d = denominator.toString();
    final ns = math.min(n.length, 16), ds = math.min(d.length, 16);
    final ratio =
        double.parse(n.substring(0, ns)) / double.parse(d.substring(0, ds));
    return (numerator.isNegative ? -1 : 1) *
        ratio *
        math.pow(10.0, (n.length - ns) - (d.length - ds)).toDouble();
  }

  _Rational pow(BigInt exponent) {
    if (numerator == BigInt.zero) {
      if (exponent == BigInt.zero) {
        throw const MathEvaluationException('0^0 is undefined.');
      }
      if (exponent.isNegative) {
        throw const MathEvaluationException('Division by zero.');
      }
      return this;
    }
    if (numerator.abs() == denominator) {
      return _Rational(
        numerator.isNegative && exponent.isOdd ? -BigInt.one : BigInt.one,
      );
    }
    if (exponent.abs() > BigInt.from(16384)) {
      throw const MathEvaluationException(
        'Integer exponent exceeds the computation limit.',
      );
    }
    final e = exponent.abs().toInt();
    // Reject a provably oversized result before allocating its BigInts.
    // The final constructor checks the exact decimal length at the boundary.
    final bitLimit = (maxRationalDigits * math.ln10 / math.ln2).ceil() + 1;
    if ((numerator.abs().bitLength - 1) * e > bitLimit ||
        (denominator.bitLength - 1) * e > bitLimit) {
      throw const MathEvaluationException('Exact result exceeds 4096 digits.');
    }
    return exponent.isNegative
        ? _Rational(denominator.pow(e), numerator.pow(e))
        : _Rational(numerator.pow(e), denominator.pow(e));
  }
}

_Value _evaluate(MathNode n, String angle, Map<String, double> variables) {
  _Value at(String key) => _evaluate(n[key] as MathNode, angle, variables);
  switch (n['type']) {
    case 'number':
      return _Value.exact(_Rational.fromLiteral(n['value'] as String));
    case 'constant':
      return _Value.approximate(n['name'] == 'pi' ? math.pi : math.e);
    case 'symbol':
      final value = variables[n['name']];
      if (value == null) {
        throw MathEvaluationException(
          'Variable ${n['name']} needs a value or the CAS.',
        );
      }
      return _Value.approximate(value);
    case 'unary':
      final value = at('arg');
      if (n['op'] == '+') return value;
      return value.rational != null
          ? _Value.exact(-value.rational!)
          : _Value.approximate(-value.number!);
    case 'binary':
      final a = at('left'), b = at('right');
      final op = n['op'];
      if (op == '/' && b.isZero) {
        throw const MathEvaluationException('Division by zero.');
      }
      if (op == '^') return _power(a, b);
      if (a.rational != null && b.rational != null) {
        final ra = a.rational!, rb = b.rational!;
        return _Value.exact(switch (op) {
          '+' => ra + rb,
          '-' => ra - rb,
          '*' => ra * rb,
          '/' => ra / rb,
          _ => throw const MathEvaluationException('Unsupported operator.'),
        });
      }
      final da = _finite(a.asDouble), db = _finite(b.asDouble);
      return _Value.approximate(switch (op) {
        '+' => da + db,
        '-' => da - db,
        '*' => da * db,
        '/' => da / db,
        _ => throw const MathEvaluationException('Unsupported operator.'),
      });
    case 'call':
      final args = (n['args'] as List)
          .map((e) => _evaluate(e as MathNode, angle, variables))
          .toList();
      if (n['fn'] == 'tan' && angle == 'rad') {
        final coefficient = _piMultiple((n['args'] as List).first as MathNode);
        if (coefficient != null) {
          final twice = coefficient * _Rational(BigInt.two);
          if (twice.isInteger && twice.numerator.isOdd) {
            throw const MathEvaluationException(
              'Tangent is undefined at this angle.',
            );
          }
        }
      }
      return _function(n['fn'] as String, args, angle);
    default:
      throw const MathEvaluationException(
        'This operation needs the symbolic CAS.',
      );
  }
}

/// Recognize exact rational multiples of pi without inferring equality from
/// rounded floating-point values (a nearby rational is not an exact pole).
_Rational? _piMultiple(MathNode n) {
  _Rational? constant(MathNode value) {
    try {
      return _evaluate(value, 'rad', const {}).rational;
    } on MathEvaluationException {
      return null;
    }
  }

  if (n['type'] == 'constant' && n['name'] == 'pi') {
    return _Rational(BigInt.one);
  }
  if (n['type'] == 'number' &&
      _Rational.fromLiteral(n['value']).numerator == BigInt.zero) {
    return _Rational(BigInt.zero);
  }
  if (n['type'] == 'unary') {
    final a = _piMultiple(n['arg'] as MathNode);
    return a == null
        ? null
        : n['op'] == '-'
        ? -a
        : a;
  }
  if (n['type'] != 'binary') return null;
  final left = n['left'] as MathNode, right = n['right'] as MathNode;
  final a = _piMultiple(left), b = _piMultiple(right);
  if (n['op'] == '+' && a != null && b != null) return a + b;
  if (n['op'] == '-' && a != null && b != null) return a - b;
  if (n['op'] == '*') {
    final ra = constant(left), rb = constant(right);
    if (a != null && rb != null) return a * rb;
    if (b != null && ra != null) return b * ra;
  }
  if (n['op'] == '/' && a != null) {
    final denominator = constant(right);
    if (denominator != null && denominator.numerator != BigInt.zero) {
      return a / denominator;
    }
  }
  return null;
}

_Value _power(_Value a, _Value b) {
  if (a.isZero && b.isZero) {
    throw const MathEvaluationException('0^0 is undefined.');
  }
  if (a.isZero && b.rational != null) {
    if (b.rational!.numerator.isNegative) {
      throw const MathEvaluationException('Division by zero.');
    }
    return _Value.exact(_Rational(BigInt.zero));
  }
  if (a.rational?.numerator == a.rational?.denominator && a.rational != null) {
    return _Value.exact(_Rational(BigInt.one));
  }
  if (a.rational != null && b.rational?.isInteger == true) {
    return _Value.exact(a.rational!.pow(b.rational!.numerator));
  }
  if (a.rational != null &&
      b.rational?.isInteger == false &&
      a.rational!.numerator > BigInt.zero) {
    final exponent = _finite(b.asDouble);
    return _Value.approximate(math.exp(a.rational!.logAbs() * exponent));
  }
  final base = _finite(a.asDouble), exponent = _finite(b.asDouble);
  final integral = b.rational != null
      ? b.rational!.isInteger
      : exponent == exponent.truncateToDouble();
  if (base < 0 && !integral) {
    throw const MathEvaluationException(
      'A negative base requires an integer exponent in real mode.',
    );
  }
  if (base == 0 && exponent < 0) {
    throw const MathEvaluationException('Division by zero.');
  }
  if (integral && exponent.abs() > 16384 && base.abs() != 1 && base != 0) {
    throw const MathEvaluationException(
      'Integer exponent exceeds the computation limit.',
    );
  }
  return _Value.approximate(math.pow(base, exponent).toDouble());
}

_Value _function(String fn, List<_Value> args, String angle) {
  final a = args.first;
  final rational = a.rational;
  if ({'asin', 'acos'}.contains(fn) &&
      rational != null &&
      rational.numerator.abs() > rational.denominator) {
    throw const MathEvaluationException(
      'Inverse sine/cosine require an argument in [-1, 1].',
    );
  }
  if (fn == 'abs' && rational != null) return _Value.exact(rational.abs());
  if (fn == 'factorial') {
    final integer = rational?.isInteger == true
        ? rational!.numerator
        : a.number != null && a.number! == a.number!.truncateToDouble()
        ? BigInt.from(a.number!)
        : null;
    if (integer == null ||
        integer < BigInt.zero ||
        integer > BigInt.from(1000)) {
      throw const MathEvaluationException(
        'Factorial requires an integer from 0 to 1000.',
      );
    }
    var result = BigInt.one;
    for (var i = 2; i <= integer.toInt(); i++) {
      result *= BigInt.from(i);
    }
    // A bound variable remains an approximation even if it happens to be integer.
    return rational != null
        ? _Value.exact(_Rational(result))
        : _Value.approximate(result.toDouble());
  }
  if (fn == 'sqrt' || fn == 'root') {
    var degree = 2;
    if (fn == 'root') {
      final index = args[1];
      final v = _finite(index.asDouble);
      if ((index.rational != null && !index.rational!.isInteger) ||
          v != v.truncateToDouble() ||
          v < 1 ||
          v > maxRootIndex) {
        throw const MathEvaluationException(
          'Root index must be an integer from 1 to 1000.',
        );
      }
      degree = v.toInt();
    }
    final negative = rational?.numerator.isNegative ?? (a.asDouble < 0);
    if (negative && degree.isEven) {
      throw const MathEvaluationException(
        'An even root of a negative number is not real.',
      );
    }
    if (rational != null) {
      final nr = _integerRoot(rational.numerator.abs(), degree);
      final dr = _integerRoot(rational.denominator, degree);
      if (nr != null &&
          dr != null &&
          (fn == 'sqrt' || args[1].rational != null)) {
        return _Value.exact(_Rational(negative ? -nr : nr, dr));
      }
    }
    if (rational != null && rational.numerator != BigInt.zero) {
      return _Value.approximate(
        (negative ? -1 : 1) * math.exp(rational.logAbs() / degree),
      );
    }
    final x = _finite(a.asDouble);
    return _Value.approximate(
      (negative ? -1 : 1) * math.pow(x.abs(), 1 / degree).toDouble(),
    );
  }
  if ({'ln', 'log'}.contains(fn) && rational != null) {
    if (rational.numerator <= BigInt.zero) {
      throw const MathEvaluationException(
        'Logarithms require a positive real argument.',
      );
    }
    return _Value.approximate(
      rational.logAbs() / (fn == 'log' ? math.ln10 : 1),
    );
  }
  final x = _finite(a.asDouble);
  final radians = angle == 'deg' ? x * math.pi / 180 : x;
  final inverseFactor = angle == 'deg' ? 180 / math.pi : 1;
  if ({'ln', 'log'}.contains(fn) && x <= 0) {
    throw const MathEvaluationException(
      'Logarithms require a positive real argument.',
    );
  }
  if ({'asin', 'acos'}.contains(fn) && x.abs() > 1) {
    throw const MathEvaluationException(
      'Inverse sine/cosine require an argument in [-1, 1].',
    );
  }
  if (fn == 'tan') {
    final exactDegreePole =
        angle == 'deg' &&
        (rational != null
            ? (rational.numerator - BigInt.from(90) * rational.denominator) %
                      (BigInt.from(180) * rational.denominator) ==
                  BigInt.zero
            : (x - 90) % 180 == 0);
    if (exactDegreePole) {
      throw const MathEvaluationException(
        'Tangent is undefined at this angle.',
      );
    }
    if (math.cos(radians).abs() < 1e-15) {
      throw const MathEvaluationException(
        'Insufficient local precision near a tangent pole. Use the symbolic CAS.',
      );
    }
  }
  return _Value.approximate(switch (fn) {
    'sin' => math.sin(radians),
    'cos' => math.cos(radians),
    'tan' => math.tan(radians),
    'asin' => math.asin(x) * inverseFactor,
    'acos' => math.acos(x) * inverseFactor,
    'atan' => math.atan(x) * inverseFactor,
    'ln' => math.log(x),
    'log' => math.log(x) / math.ln10,
    'exp' => math.exp(x),
    'abs' => x.abs(),
    _ => throw const MathEvaluationException('Unsupported function.'),
  });
}

/// Exact integer roots, bounded by the 4096 digit operand limit.
BigInt? _integerRoot(BigInt value, int degree) {
  if (value == BigInt.zero || value == BigInt.one || degree == 1) return value;
  if (degree > value.bitLength) return null;
  final d = BigInt.from(degree);
  var root = BigInt.one << ((value.bitLength + degree - 1) ~/ degree);
  while (true) {
    final next = ((d - BigInt.one) * root + value ~/ root.pow(degree - 1)) ~/ d;
    if (next >= root) break;
    root = next;
  }
  return root.pow(degree) == value ? root : null;
}
