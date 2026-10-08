import pytest
import sympy as sp
from pydantic import ValidationError

from jemcalc.cas import calculate_payload
from jemcalc.models import CalculateRequest


def n(value):
    return {"type": "number", "value": str(value)}


def s(name="x"):
    return {"type": "symbol", "name": name}


def b(op, left, right):
    return {"type": "binary", "op": op, "left": left, "right": right}


def f(name, *args):
    return {"type": "call", "fn": name, "args": list(args)}


def eq(left, right):
    return {"type": "equation", "left": left, "right": right}


def run(ast, **options):
    request = CalculateRequest.model_validate({"ast": ast, **options})
    return calculate_payload(request.model_dump())


def test_exact_decimal_and_rational_arithmetic():
    assert run(b("+", n("0.1"), n("0.2")))["text"] == "3/10"
    assert run(b("+", b("/", n(1), n(3)), b("/", n(1), n(6))))["text"] == "1/2"
    assert run(b("+", n("123456789012345678901234567890"), n(1)))["text"] == "123456789012345678901234567891"
    assert run(n("1.2e-3"))["text"] == "3/2500"


def test_constants_exact_and_approximation_separate():
    assert run(f("sin", {"type": "constant", "name": "pi"}))["text"] == "0"
    answer = run(f("sqrt", n(2)))
    assert answer["text"] == "sqrt(2)"
    assert answer["status"] == "exact"
    assert answer["approximation"].startswith("1.41421356237")


@pytest.mark.parametrize("ast, expected", [
    (b("*", n("18.33"), n(12)), "5499/25"),
    (n(0), "0"),
    (b("/", n(1), n(3)), "1/3"),
    ({"type": "unary", "op": "-", "arg": n(2)}, "-2"),
    (f("sin", {"type": "constant", "name": "pi"}), "0"),
])
def test_solve_evaluates_numeric_expressions_from_older_clients(ast, expected):
    answer = run(ast, operation="solve")
    assert answer["status"] == "exact"
    assert answer["text"] == expected


def test_numeric_solve_preserves_angles_and_domain_errors():
    assert run(f("sin", n(30)), operation="solve", angleMode="deg")["text"] == "1/2"
    assert run(b("/", n(1), n(0)), operation="solve")["status"] == "domainError"
    assert run(f("sqrt", n(-1)), operation="solve")["status"] == "domainError"


def test_numeric_fallback_does_not_change_equations_or_cancelled_symbols():
    assert run(eq(n(2), n(3)), operation="solve")["status"] == "empty"
    assert run(eq(n(2), n(2)), operation="solve")["text"] == "Reals"
    assert run(b("-", s(), s()), operation="solve")["text"] == "Reals"
    assert run(b("/", s(), s()), operation="solve")["status"] == "empty"
    assert run(b("-", s(), n(2)), operation="solve")["text"] == "{2}"
    assert run(n(12), operation="differentiate")["text"] == "0"
    assert run(n(12), operation="integrate")["text"] == "12*x + C"


@pytest.mark.parametrize("ast", [
    b("/", n(1), n(0)), b("/", n(1), b("-", n(2), n(2))),
    b("^", n(0), n(0)), b("^", n(0), n(-1)),
    b("^", n(-8), b("/", n(1), n(3))),
    f("sqrt", n(-1)), f("ln", n(0)), f("log", n(-1)),
    f("asin", n(2)), f("acos", n(-2)), f("factorial", n("0.5")),
    f("factorial", n(1001)), f("root", n(2), n(0)), f("root", n(-2), n(2)),
    f("root", n(2), n(1001)),
])
def test_domain_errors(ast):
    assert run(ast)["status"] == "domainError"


def test_integer_and_odd_roots_and_boundaries():
    assert run(f("root", n(-8), n(3)))["text"] == "-2"
    assert run(f("root", n(16), n(4)))["text"] == "2"
    assert run(f("factorial", n(0)))["text"] == "1"
    assert run(f("factorial", n(1000)))["status"] == "exact"
    assert run(b("^", n(10), n(4096)))["status"] == "unsupported"
    assert run(b("^", n("1e400"), n(16384)))["status"] == "unsupported"


def test_angle_mode_is_part_of_mathematics():
    assert run(f("sin", n(30)), angleMode="deg")["text"] == "1/2"
    assert run(f("asin", n(1)), angleMode="deg")["text"] == "90"
    assert run(f("tan", n(90)), angleMode="deg")["status"] == "domainError"
    answer = run(f("sin", s()), operation="differentiate", angleMode="deg")
    assert answer["text"] == "pi*cos(pi*x/180)/180"
    assert answer["verification"]["status"] == "numeric"


def test_real_solver_and_infinite_sets():
    answer = run(eq(b("^", s(), n(2)), n(2)), operation="solve")
    assert answer["text"] == "{-sqrt(2), sqrt(2)}"
    assert answer["verification"]["status"] == "verified"
    assert run(eq(b("^", s(), n(2)), n(-1)), operation="solve")["status"] == "empty"
    assert run(eq(f("sqrt", s()), n(-1)), operation="solve")["status"] == "empty"
    assert run(eq(f("sin", s()), n(0)), operation="solve")["status"] == "exact"


def test_original_denominator_exclusion_survives_cancellation():
    original = b("/", b("-", b("^", s(), n(2)), n(1)), b("-", s(), n(1)))
    answer = run(eq(original, n(0)), operation="solve")
    assert answer["text"] == "{-1}"
    assert answer["conditions"]
    simplified = run(b("/", s(), s()), operation="simplify")
    assert simplified["text"] == "1"
    assert simplified["conditions"] == ["Ne(x, 0)"]


def test_symbolic_zero_power_preserves_positive_exponent_domain():
    power = b("^", n(0), s())
    simplified = run(power, operation="simplify")
    assert simplified["text"] == "0"
    assert simplified["conditions"] == ["x > 0"]
    # SymPy's 0**0=1 convention must never produce a candidate x=0.
    impossible = run(eq(power, n(1)), operation="solve")
    assert impossible["status"] == "empty"
    assert impossible["conditions"] == ["x > 0"]
    valid = run(eq(power, n(0)), operation="solve")
    assert valid["text"] == "Interval.open(0, oo)"
    assert valid["conditions"] == ["x > 0"]
    shifted = run(eq(b("^", n(0), b("-", s(), n(2))), n(0)), operation="solve")
    assert shifted["text"] == "Interval.open(2, oo)"


def test_symbolic_power_domain_survives_algebraic_cancellation():
    power = b("^", s(), s())
    identity = run(eq(b("-", power, power), n(0)), operation="solve")
    assert identity["text"] == "Interval.open(0, oo)"


def test_sqrt_square_keeps_real_absolute_value():
    assert run(f("sqrt", b("^", s(), n(2))))["text"] == "Abs(x)"


def test_condition_set_is_not_empty():
    answer = run(eq(b("+", s(), f("sin", s())), n(1)), operation="solve")
    assert answer["status"] == "unresolved"
    assert "ConditionSet" in answer["text"]


def test_linear_system_and_parametric_solution():
    system = {"type": "system", "equations": [eq(b("+", s(), s("y")), n(3)), eq(b("-", s(), s("y")), n(1))]}
    answer = run(system, operation="solve")
    assert answer["text"] == "{(2, 1)}"
    assert answer["verification"]["status"] == "verified"
    parametric = run({"type": "system", "equations": [eq(b("+", s(), s("y")), n(3))]}, operation="solve")
    assert parametric["text"] == "{(3 - y, y)}"
    contradictory = {"type": "system", "equations": [eq(s(), n(1)), eq(s(), n(2))]}
    assert run(contradictory, operation="solve", variables=["x"])["status"] == "empty"


def test_quadratic_system_and_unsupported_scope():
    system = {"type": "system", "equations": [eq(b("+", b("^", s(), n(2)), b("^", s("y"), n(2))), n(1)), eq(s(), s("y"))]}
    answer = run(system, operation="solve")
    assert answer["status"] == "exact"
    assert answer["verification"]["status"] == "verified"
    assert "sqrt(2)" in answer["text"]
    unsupported = {"type": "system", "equations": [eq(f("sin", s()), s("y")), eq(s("y"), n(0))]}
    assert run(unsupported, operation="solve")["status"] == "unsupported"


def test_calculus_ast_execution():
    derivative = {"type": "derivative", "body": b("^", s(), n(3)), "variable": "x", "order": 2}
    assert run(derivative, operation="evaluate")["text"] == "6*x"
    assert run(derivative, operation="differentiate")["text"] == "6*x"
    integral = {"type": "integral", "body": b("^", s(), n(2)), "variable": "x", "lower": None, "upper": None}
    answer = run(integral, operation="evaluate")
    assert answer["text"] == "x**3/3 + C"
    assert answer["verification"]["status"] == "verified"
    integral.update(lower=n(0), upper=n(1))
    assert run(integral, operation="evaluate")["text"] == "1/3"
    assert run(integral, operation="integrate")["text"] == "1/3"


def test_derivative_does_not_claim_corner_is_differentiable():
    derivative = run(f("abs", s()), operation="differentiate")
    assert derivative["text"] == "sign(x)"
    assert derivative["conditions"] == ["Ne(x, 0)"]
    assert run(f("abs", s()), operation="differentiate", order=2)["status"] == "unsupported"


def test_smooth_absolute_value_compositions_keep_their_derivative_at_zero():
    square = run(b("^", f("abs", s()), n(2)), operation="differentiate")
    assert square["text"] == "2*x"
    assert square["conditions"] == []
    assert run(b("^", f("abs", s()), n(2)), operation="differentiate", order=2)["text"] == "2"
    product = run(b("*", s(), f("abs", s())), operation="differentiate")
    assert product["text"] == "x*sign(x) + Abs(x)"
    assert product["conditions"] == []
    cubic = run(f("abs", b("^", s(), n(3))), operation="differentiate")
    assert cubic["conditions"] == []
    assert cubic["status"] == "exact"


def test_absolute_value_derivative_checks_real_corners_and_preserves_holes():
    corners = run(f("abs", b("-", b("^", s(), n(2)), n(1))), operation="differentiate")
    assert corners["conditions"] == ["Ne(x, -1)", "Ne(x, 1)"]
    hole = run(b("/", b("^", f("abs", s()), n(2)), s()), operation="differentiate")
    assert hole["text"] == "1"
    assert hole["conditions"] == ["Ne(x, 0)"]
    # An uncertified infinite boundary set must not invent domain exclusions.
    unbounded = run(f("abs", f("sin", s())), operation="differentiate")
    assert unbounded["status"] == "unsupported"


def test_integral_improper_endpoint_and_interior_singularity():
    integrand = b("/", n(1), f("sqrt", s()))
    assert run(integrand, operation="integrate", lower=n(0), upper=n(1))["text"] == "2"
    answer = run(b("/", n(1), s()), operation="integrate", lower=n(-1), upper=n(1))
    assert answer["status"] == "unsupported"
    divergent = run(b("/", n(1), s()), operation="integrate", lower=n(0), upper=n(1))
    assert divergent["status"] == "domainError"
    primitive = run(b("/", n(1), s()), operation="integrate")
    assert primitive["text"] == "log(Abs(x)) + C"


def test_two_sided_and_one_sided_limits():
    sine_limit = {"type": "limit", "body": b("/", f("sin", s()), s()), "variable": "x", "to": n(0), "direction": "both"}
    assert run(sine_limit, operation="evaluate")["text"] == "1"
    assert run(sine_limit, operation="limit")["text"] == "1"
    assert run(b("/", n(1), s()), operation="limit", approach=n(0))["status"] == "unresolved"
    assert run(b("/", n(1), s()), operation="limit", approach=n(0), direction="+")["text"] == "oo"
    assert run(b("/", n(1), s()), operation="limit", approach={"type": "infinity", "sign": 1})["text"] == "0"
    assert run(f("sqrt", s()), operation="limit", approach=n(0), direction="-")["status"] == "domainError"
    assert run(f("sin", s()), operation="limit", approach={"type": "infinity", "sign": 1})["status"] == "unresolved"
    assert run(b("^", f("sqrt", s()), n(2)), operation="limit", approach={"type": "infinity", "sign": -1})["status"] == "domainError"


def test_simplified_integer_exponent_uses_real_power_rule():
    exponent = b("+", b("-", s(), s()), n(2))
    assert run(b("^", n(-2), exponent))["text"] == "4"


@pytest.mark.parametrize("sign", [True, 1.0, "1"])
def test_infinity_sign_is_strictly_integer(sign):
    with pytest.raises(ValidationError):
        CalculateRequest.model_validate({"ast": {"type": "limit", "body": s(), "variable": "x", "to": {"type": "infinity", "sign": sign}}})


@pytest.mark.parametrize("ast", [
    {"type": "python", "code": "__import__('os')"},
    {"type": "number", "value": "__import__('os').system('id')"},
    {"type": "number", "value": "1e999999999"},
    {"type": "number", "value": 1.0},
    {"type": "number", "value": "1", "extra": "unsafe"},
    {"type": "symbol", "name": "__class__"},
    {"type": "call", "fn": "eval", "args": [n(1)]},
    f("sin", n(1), n(2)),
])
def test_ast_validation_rejects_untrusted_input(ast):
    with pytest.raises(ValidationError):
        CalculateRequest.model_validate({"ast": ast})


def test_depth_and_node_budgets():
    ast = n(1)
    for _ in range(64):
        ast = {"type": "unary", "op": "-", "arg": ast}
    with pytest.raises(ValidationError, match="depth 64"):
        CalculateRequest.model_validate({"ast": ast})
    level = [n(1) for _ in range(512)]
    while len(level) > 1:
        level = [b("+", level[i], level[i + 1]) for i in range(0, len(level), 2)]
    with pytest.raises(ValidationError, match="512 nodes"):
        CalculateRequest.model_validate({"ast": level[0]})


def test_deterministic_repeated_result():
    payload = {"ast": b("+", b("/", n(7), n(9)), f("sqrt", n(2)))}
    assert calculate_payload(payload) == calculate_payload(payload)
