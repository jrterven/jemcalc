"""Deterministic real mathematics constructed exclusively from a validated AST.

The original domain restrictions are recorded *before* SymPy can cancel terms.
No eval, sympify(string), parse_expr, or executable LaTeX is used here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import math
from typing import Any

import sympy as sp
from sympy.calculus.util import continuous_domain

from .models import CalculateRequest, CalculateResponse, Verification, MAX_DIGITS


class MathFailure(Exception):
    def __init__(self, status: str, message: str):
        self.status = status
        super().__init__(message)


def failure(status: str, message: str) -> CalculateResponse:
    return CalculateResponse(status=status, text=message, engineVersion=sp.__version__)


def check_size(expression: sp.Basic) -> None:
    # Check bit lengths before str(), which itself has a Python digit safety limit.
    for rational in expression.atoms(sp.Rational):
        for value in (rational.p, rational.q):
            if abs(value).bit_length() > 13608 or len(str(abs(value))) > MAX_DIGITS:
                raise MathFailure("unsupported", "Exact result exceeds 4096 digits")
    # count_ops treats some Set objects as iterables and can enumerate forever
    # (e.g. the infinite ImageSet returned by sin(x)=0). Walk structural args.
    pending = [expression]
    count = 0
    while pending:
        item = pending.pop()
        count += 1
        if count > 8192:
            raise MathFailure("unsupported", "Result is too large to display")
        if isinstance(item, sp.Basic):
            pending.extend(item.args)


@dataclass
class Builder:
    angle_mode: str
    symbols: dict[str, sp.Symbol] = field(default_factory=dict)
    restrictions: list[sp.Basic] = field(default_factory=list)

    def symbol(self, name: str) -> sp.Symbol:
        if name not in self.symbols:
            self.symbols[name] = sp.Symbol(name, real=True)
        return self.symbols[name]

    def require(self, condition: sp.Basic, message: str) -> None:
        if condition is sp.false or condition is False:
            raise MathFailure("domainError", message)
        if condition is not sp.true and condition is not True and condition not in self.restrictions:
            self.restrictions.append(condition)

    def expression(self, node: dict[str, Any], *, allow_infinity: bool = False) -> sp.Expr:
        kind = node["type"]
        if kind == "number":
            result = sp.Rational(node["value"])
        elif kind == "symbol":
            result = self.symbol(node["name"])
        elif kind == "constant":
            result = sp.pi if node["name"] == "pi" else sp.E
        elif kind == "infinity":
            if not allow_infinity:
                raise MathFailure("unsupported", "Infinity is only allowed as a bound or limit destination")
            result = sp.oo if node["sign"] == 1 else -sp.oo
        elif kind == "unary":
            value = self.expression(node["arg"])
            result = value if node["op"] == "+" else -value
        elif kind == "binary":
            left = self.expression(node["left"])
            right = self.expression(node["right"])
            op = node["op"]
            if op == "+":
                result = sp.Add(left, right, evaluate=False)
            elif op == "-":
                result = sp.Add(left, -right, evaluate=False)
            elif op == "*":
                result = sp.Mul(left, right, evaluate=False)
            elif op == "/":
                self.require(sp.Ne(right, 0), "Division by zero")
                result = sp.Mul(left, sp.Pow(right, -1, evaluate=False), evaluate=False)
            else:
                # Collapse constant arithmetic so 2^(1+1) has the same semantics as 2^2.
                right = sp.simplify(right)
                left = sp.simplify(left)
                # This must also cover a symbolic exponent: substituting x=0
                # into 0**x must not inherit SymPy's convention that 0**0=1.
                self.require(sp.Or(sp.Ne(left, 0), sp.Gt(right, 0)),
                             "A zero base requires a positive exponent")
                if right.is_integer is not True:
                    self.require(sp.Ge(left, 0), "Negative bases require an integer exponent; use an explicit odd root")
                if right.is_Integer and abs(right) > 16384:
                    if left not in (sp.S.NegativeOne, sp.S.Zero, sp.S.One):
                        raise MathFailure("unsupported", "Integer exponent exceeds 16384")
                if right.is_Integer and left.is_Rational:
                    exponent = abs(int(right))
                    if any((abs(part).bit_length() - 1) * exponent > 13608 for part in (left.p, left.q) if part):
                        raise MathFailure("unsupported", "Exact power exceeds 4096 digits")
                # On the recorded domain a zero base is identically zero.
                # Leaving 0**x to solveset can incorrectly produce EmptySet
                # for 0**x=0 instead of the positive-exponent domain.
                result = sp.S.Zero if left.is_zero is True else sp.Pow(left, right, evaluate=False)
        elif kind == "call":
            args = [self.expression(item) for item in node["args"]]
            arg = args[0]
            # Constant arguments must be reduced before testing domains or integer arity.
            if not arg.free_symbols:
                arg = sp.simplify(arg)
            fn = node["fn"]
            angle = arg * sp.pi / 180 if self.angle_mode == "deg" else arg
            if fn in ("sin", "cos", "tan"):
                if fn == "tan":
                    self.require(sp.Ne(sp.cos(angle), 0), "Tangent is undefined at this angle")
                result = {"sin": sp.sin, "cos": sp.cos, "tan": sp.tan}[fn](angle)
            elif fn in ("asin", "acos", "atan"):
                if fn != "atan":
                    self.require(sp.Ge(arg, -1), "Inverse trigonometric argument must lie in [-1, 1]")
                    self.require(sp.Le(arg, 1), "Inverse trigonometric argument must lie in [-1, 1]")
                result = {"asin": sp.asin, "acos": sp.acos, "atan": sp.atan}[fn](arg)
                if self.angle_mode == "deg":
                    result *= 180 / sp.pi
            elif fn == "sqrt":
                self.require(sp.Ge(arg, 0), "Square root requires a nonnegative real argument")
                result = sp.sqrt(arg)
            elif fn == "root":
                index = sp.simplify(args[1])
                if index.is_Integer is not True or not 1 <= index <= 1000:
                    raise MathFailure("domainError", "Root index must be a positive integer no greater than 1000")
                if int(index) % 2 == 0:
                    self.require(sp.Ge(arg, 0), "Even root requires a nonnegative argument")
                result = sp.real_root(arg, index)
            elif fn in ("ln", "log"):
                self.require(sp.Gt(arg, 0), "Logarithm requires a positive real argument")
                result = sp.log(arg) if fn == "ln" else sp.log(arg, 10)
            elif fn == "exp":
                result = sp.exp(arg)
            elif fn == "abs":
                result = sp.Abs(arg)
            else:
                if arg.free_symbols:
                    raise MathFailure("unsupported", "Factorial currently requires a constant integer")
                if arg.is_Integer is not True or not 0 <= arg <= 1000:
                    raise MathFailure("domainError", "Factorial argument must be an integer from 0 to 1000")
                result = sp.factorial(arg)
        else:
            raise MathFailure("unsupported", "An arithmetic expression is required here")
        check_size(result)
        return result

    def equations(self, node: dict[str, Any]) -> list[tuple[sp.Expr, sp.Expr]]:
        if node["type"] == "system":
            return [(self.expression(eq["left"]), self.expression(eq["right"])) for eq in node["equations"]]
        if node["type"] == "equation":
            return [(self.expression(node["left"]), self.expression(node["right"]))]
        return [(self.expression(node), sp.S.Zero)]

    def domain_for(self, variable: sp.Symbol) -> sp.Set:
        domain = sp.S.Reals
        for condition in self.restrictions:
            if condition.free_symbols - {variable}:
                continue
            try:
                if isinstance(condition, (sp.And, sp.Or)):
                    allowed = condition.as_set()
                elif isinstance(condition, sp.Unequality):
                    allowed = sp.Complement(sp.S.Reals, sp.solveset(condition.lhs - condition.rhs, variable, domain=sp.S.Reals))
                else:
                    allowed = sp.solve_univariate_inequality(condition, variable, relational=False)
                domain = sp.Intersection(domain, allowed)
            except (NotImplementedError, ValueError, TypeError):
                domain = sp.Intersection(domain, sp.ConditionSet(variable, condition, sp.S.Reals))
        return domain

    def condition_text(self) -> list[str]:
        return [sp.sstr(condition) for condition in self.restrictions]


def verification_for(equations: list[tuple[sp.Expr, sp.Expr]], substitutions: dict[sp.Symbol, sp.Expr], builder: Builder) -> tuple[bool | None, str]:
    uncertain = False
    for condition in builder.restrictions:
        tested = sp.simplify(condition.subs(substitutions, simultaneous=True))
        if tested is sp.false:
            return False, "Candidate violates the original expression domain"
        if tested is not sp.true:
            uncertain = True
    for left, right in equations:
        residual = sp.simplify(left.subs(substitutions, simultaneous=True) - right.subs(substitutions, simultaneous=True))
        if residual.has(sp.nan, sp.zoo) or residual.is_zero is False:
            return False, "Candidate does not satisfy the original equation"
        if residual != 0:
            uncertain = True
    return (None, "Verification remains conditional") if uncertain else (True, "Substitution satisfies every original equation and domain restriction")


def solve(node: dict[str, Any], request: CalculateRequest, builder: Builder) -> tuple[sp.Basic, Verification]:
    equations = builder.equations(node)
    expressions = [left - right for left, right in equations]
    if node["type"] != "system":
        variable = builder.symbol(request.variable)
        result = sp.solveset(expressions[0], variable, domain=builder.domain_for(variable))
        if isinstance(result, sp.FiniteSet):
            accepted = []
            uncertain = False
            for candidate in result:
                valid, _ = verification_for(equations, {variable: candidate}, builder)
                if valid is not False:
                    accepted.append(candidate)
                uncertain |= valid is None
            result = sp.FiniteSet(*accepted)
            verification = Verification(status="inconclusive" if uncertain else "verified", detail="Candidates checked against the original equation and its domain")
        else:
            verification = Verification(status="inconclusive", detail="The solution set is symbolic; no finite candidate check applies")
        return result, verification

    variables = [builder.symbol(name) for name in request.variables]
    if set().union(*(expr.free_symbols for expr in expressions)) - set(variables):
        raise MathFailure("unsupported", "System coefficients must be numeric; list all unknowns")
    try:
        polynomials = [sp.Poly(expr, *variables) for expr in expressions]
    except sp.PolynomialError:
        raise MathFailure("unsupported", "Only linear and two-variable quadratic polynomial systems are supported")
    degrees = [polynomial.total_degree() for polynomial in polynomials]
    if max(degrees) <= 1:
        result = sp.linsolve(expressions, variables)
    elif len(equations) == len(variables) == 2 and max(degrees) <= 2:
        result = sp.nonlinsolve(expressions, variables)
    else:
        raise MathFailure("unsupported", "Nonlinear systems support two equations and two variables, total degree at most two")
    uncertain = False
    if isinstance(result, sp.FiniteSet):
        accepted = []
        for values in result:
            if any(value.is_real is False for value in values):
                continue
            valid, _ = verification_for(equations, dict(zip(variables, values)), builder)
            if valid is not False:
                accepted.append(values)
            uncertain |= valid is None or any(value.is_real is None for value in values)
        result = sp.FiniteSet(*accepted)
    else:
        uncertain = result is not sp.S.EmptySet
    return result, Verification(status="inconclusive" if uncertain else "verified", detail="Real candidates checked in every original equation; free parameters are retained")


def numeric_derivative_check(body: sp.Expr, result: sp.Expr, variable: sp.Symbol, order: int, builder: Builder) -> Verification:
    if order != 1 or (body.free_symbols | result.free_symbols) - {variable}:
        return Verification(status="inconclusive", detail="No independent numerical check was available")
    checked = 0
    for point in (sp.Rational(-2), sp.Rational(-1, 2), sp.Rational(1, 2), sp.Rational(2)):
        step = sp.Rational(1, 10**6)
        try:
            if any(condition.subs(variable, sample) is not sp.true for condition in builder.restrictions for sample in (point - step, point, point + step)):
                continue
            finite_difference = ((body.subs(variable, point + step) - body.subs(variable, point - step)) / (2 * step)).evalf(30)
            reference = result.evalf(30, subs={variable: point})
            if finite_difference.is_real is not True or reference.is_real is not True:
                continue
            a, b = float(finite_difference), float(reference)
            if not (math.isfinite(a) and math.isfinite(b)):
                continue
            if abs(a - b) > 1e-7 * max(1.0, abs(a), abs(b)):
                return Verification(status="inconclusive", detail="A numerical sample was inconclusive; this is not a proof")
            checked += 1
        except (TypeError, ValueError, ArithmeticError):
            continue
    if checked >= 2:
        return Verification(status="numeric", detail=f"Central differences agreed at {checked} regular sample points; this is not a proof")
    return Verification(status="inconclusive", detail="Not enough regular sample points for an independent check")


def check_absolute_derivative(body: sp.Expr, result: sp.Expr, variable: sp.Symbol,
                              order: int, builder: Builder) -> sp.Expr:
    """Certify corners of the whole function, not each Abs in isolation.

    For example, x*Abs(x) is differentiable at zero although Abs(x) is not.
    Unknown or infinite corner sets are unsupported rather than falsely excluded.
    """
    absolutes = [item for item in body.atoms(sp.Abs) if item.has(variable)]
    if not absolutes:
        return result
    if order != 1:
        raise MathFailure("unsupported", "Higher derivatives at absolute-value boundaries require a separate analysis")
    points: set[sp.Expr] = set()
    for absolute in absolutes:
        zeros = sp.solveset(absolute.args[0], variable, domain=sp.S.Reals)
        if zeros is sp.S.EmptySet:
            continue
        if not isinstance(zeros, sp.FiniteSet) or len(zeros) > 32:
            raise MathFailure("unsupported", "Could not certify the absolute-value derivative boundaries")
        points.update(zeros)
    for point in sorted(points, key=sp.default_sort_key):
        if any(sp.simplify(condition.subs(variable, point)) is sp.false
               for condition in builder.restrictions):
            continue  # The original expression already excludes this point.
        value = sp.simplify(body.subs(variable, point))
        if value.has(sp.nan, sp.zoo) or value.is_finite is False:
            builder.require(sp.Ne(variable, point), "Derivative requires a defined function value")
            continue
        quotient = (body - value) / (variable - point)
        left = sp.limit(quotient, variable, point, dir="-")
        right = sp.limit(quotient, variable, point, dir="+")
        if any(slope.is_finite is False or slope.is_real is False for slope in (left, right)):
            builder.require(sp.Ne(variable, point), "Derivative has no finite real value at this point")
            continue
        difference = sp.simplify(left - right)
        if difference.is_zero is False:
            builder.require(sp.Ne(variable, point), "The one-sided derivatives differ at this corner")
        elif difference == 0 and left.is_finite is True and left.is_real is True:
            if sp.simplify(result.subs(variable, point) - left) != 0:
                result = sp.Piecewise((left, sp.Eq(variable, point)), (result, True))
        else:
            raise MathFailure("unsupported", "Could not certify the absolute-value derivative at a boundary")
    return result


def limit_value(body: sp.Expr, variable: sp.Symbol, target: sp.Expr, direction: str, builder: Builder) -> sp.Expr:
    if target.free_symbols:
        raise MathFailure("unsupported", "Limit destination must be constant")
    if target in (sp.oo, -sp.oo):
        domain = builder.domain_for(variable)
        try:
            edge = domain.sup if target is sp.oo else domain.inf
            if edge != target:
                raise MathFailure("domainError", "The real function domain does not approach the requested infinity")
        except NotImplementedError:
            raise MathFailure("unresolved", "Could not establish the real domain at infinity")
        value = sp.limit(body, variable, target)
        if value.has(sp.AccumBounds):
            raise MathFailure("unresolved", "The limit does not exist because the function oscillates")
        return value
    domain = builder.domain_for(variable)
    sides = ("-", "+") if direction == "both" else (direction,)
    values = []
    for side in sides:
        # Do not accidentally compute a complex continuation on a missing real side.
        interval = sp.Interval.open(-sp.oo, target) if side == "-" else sp.Interval.open(target, sp.oo)
        try:
            available = sp.Intersection(domain, interval).closure.contains(target)
            if available is sp.false:
                raise MathFailure("domainError", "The function has no real domain approaching from the requested side")
        except NotImplementedError:
            pass
        values.append(sp.limit(body, variable, target, dir=side))
    if any(value.has(sp.AccumBounds) for value in values):
        raise MathFailure("unresolved", "The limit does not exist because the function oscillates")
    if len(values) == 2 and values[0] != values[1]:
        difference = sp.simplify(values[0] - values[1])
        if difference != 0:
            raise MathFailure("unresolved", "The two-sided limit does not exist: the one-sided limits differ")
    return values[0]


def is_numeric_expression(node: dict[str, Any]) -> bool:
    """Inspect the original AST; cancellation must not erase an unknown/domain."""
    kind = node["type"]
    if kind in ("number", "constant"):
        return True
    if kind == "unary":
        return is_numeric_expression(node["arg"])
    if kind == "binary":
        return is_numeric_expression(node["left"]) and is_numeric_expression(node["right"])
    if kind == "call":
        return all(is_numeric_expression(arg) for arg in node["args"])
    return False


def compute(request: CalculateRequest) -> CalculateResponse:
    builder = Builder(request.angleMode)
    node = request.ast.model_dump()
    operation = request.operation
    # Older installed clients can send numeric arithmetic with Solve still
    # selected. Match the shared app's numeric fallback without inventing = 0.
    if operation == "solve" and is_numeric_expression(node):
        operation = "evaluate"
    variable = builder.symbol(request.variable)
    order = request.order
    lower = request.lower.model_dump() if request.lower else None
    upper = request.upper.model_dump() if request.upper else None
    approach = request.approach.model_dump() if request.approach else None
    direction = request.direction
    if node["type"] in ("derivative", "integral", "limit"):
        represented_operation = {"derivative": "differentiate", "integral": "integrate", "limit": "limit"}[node["type"]]
        if operation not in ("evaluate", "exact", represented_operation):
            raise MathFailure("unsupported", "Select the matching operation to execute this calculus expression")
        operation = represented_operation
        variable = builder.symbol(node["variable"])
        order = node.get("order", 1)
        lower, upper = node.get("lower"), node.get("upper")
        approach, direction = node.get("to"), node.get("direction", "both")
        node = node["body"]
    if node["type"] in ("equation", "system") and operation in ("evaluate", "exact"):
        operation = "solve"
    verification = Verification()
    indefinite_integral = False
    if operation == "solve":
        result, verification = solve(node, request, builder)
    else:
        body = builder.expression(node)
        if operation in ("evaluate", "exact", "simplify"):
            result = sp.simplify(body.doit())
        elif operation == "expand":
            result = sp.expand(body)
        elif operation == "factor":
            result = sp.factor(body)
        elif operation == "differentiate":
            # Original restrictions have already been recorded by the builder.
            # Simplification removes algebraically smooth Abs forms such as |x|².
            body = sp.simplify(body)
            result = sp.diff(body, variable, order)
            if result.has(sp.DiracDelta):
                raise MathFailure("unsupported", "A classical derivative across nonsmooth points is not supported")
            result = check_absolute_derivative(body, result, variable, order, builder)
            builder.require(sp.Ne(sp.denom(sp.together(result)), 0), "Derivative denominator must be nonzero")
            verification = numeric_derivative_check(body, result, variable, order, builder)
        elif operation == "integrate":
            if lower is None:
                indefinite_integral = True
                result = sp.integrate(body, variable)
                # SymPy's log(x) antiderivative uses a complex branch on x<0.
                # For a real integrand, log|u| gives the real antiderivative on
                # each connected component where a real u is nonzero.
                result = result.replace(
                    lambda item: item.func == sp.log and len(item.args) == 1 and item.args[0].is_real is True,
                    lambda item: sp.log(sp.Abs(item.args[0])),
                )
                if not result.has(sp.Integral):
                    residual = sp.simplify(sp.diff(result, variable) - body)
                    verification = Verification(status="verified" if residual == 0 else "inconclusive", detail="Differentiated the antiderivative and compared with the original integrand on its domain")
            else:
                a = builder.expression(lower, allow_infinity=True)
                b = builder.expression(upper, allow_infinity=True)
                if a.free_symbols or b.free_symbols:
                    raise MathFailure("unsupported", "Definite integral bounds must be constant")
                if a != b:
                    interval = sp.Interval.open(sp.Min(a, b), sp.Max(a, b))
                    try:
                        domain = sp.Intersection(builder.domain_for(variable), continuous_domain(body, variable, sp.S.Reals))
                        missing = sp.Complement(interval, domain)
                        if missing.is_empty is False:
                            raise MathFailure("unsupported", "Split the integral at interior domain boundaries or discontinuities")
                        if missing.is_empty is None:
                            raise MathFailure("unresolved", "Could not establish the real integration domain")
                    except NotImplementedError:
                        raise MathFailure("unresolved", "Could not establish the real integration domain")
                result = sp.integrate(body, (variable, a, b))
                if result in (sp.oo, -sp.oo) or result.has(sp.nan, sp.zoo):
                    raise MathFailure("domainError", "The definite integral does not converge to a finite real value")
                verification = Verification(status="inconclusive", detail="Symbolic definite integral; no independent quadrature proof was performed")
        elif operation == "limit":
            if approach is None:
                raise MathFailure("unsupported", "A limit destination is required")
            target = builder.expression(approach, allow_infinity=True)
            result = limit_value(body, variable, target, direction, builder)
            verification = Verification(status="inconclusive", detail="Computed the requested one-sided limits; no separate proof certificate is available")
        else:
            raise MathFailure("unsupported", "Unsupported operation")

    check_size(result)
    if result.has(sp.nan, sp.zoo) or (isinstance(result, sp.Expr) and result.is_real is False and result not in (sp.oo, -sp.oo)):
        raise MathFailure("domainError", "The operation has no defined real result")
    unresolved = result.has(sp.ConditionSet, sp.Integral, sp.Derivative, sp.Limit)
    status = "empty" if result is sp.S.EmptySet else "unresolved" if unresolved else "exact"
    approximation = None
    if isinstance(result, sp.Expr) and not result.free_symbols and result.is_finite and not unresolved:
        if not result.is_Rational:
            try:
                approximation = sp.sstr(result.evalf(request.precision, strict=True))
            except (ValueError, ArithmeticError):
                pass
    latex, text = sp.latex(result), sp.sstr(result)
    if indefinite_integral and not unresolved:
        latex += " + C"
        text += " + C"
    if len(latex) > 64_000 or len(text) > 64_000:
        raise MathFailure("unsupported", "Result is too large to display")
    conditions = builder.condition_text()
    if operation in ("differentiate", "integrate") and request.angleMode == "deg":
        conditions.append("Trigonometric arguments use degrees; pi/180 factors are included")
    if indefinite_integral:
        conditions.append("The integration constant may differ on disconnected domain intervals")
    return CalculateResponse(status=status, latex=latex, text=text, approximation=approximation, conditions=conditions, verification=verification, engineVersion=sp.__version__)


def calculate_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Worker boundary; validation is repeated after serialization."""
    try:
        response = compute(CalculateRequest.model_validate(payload))
    except MathFailure as exc:
        response = failure(exc.status, str(exc))
    except NotImplementedError:
        response = failure("unsupported", "This mathematical operation is not supported by the current engine")
    except (ArithmeticError, ValueError, TypeError):
        response = failure("error", "The engine could not complete this expression safely")
    except Exception:
        response = failure("error", "The engine could not complete this calculation")
    return response.model_dump()
