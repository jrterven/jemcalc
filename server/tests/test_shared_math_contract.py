"""Shared with the Dart evaluator tests; preserves intentional exact/approx differences."""

import json
from pathlib import Path

import pytest

from jemcalc.cas import calculate_payload


CASES = json.loads((Path(__file__).parent / "fixtures/math_contract.json").read_text())["cases"]


@pytest.mark.parametrize("case", CASES, ids=lambda case: case["id"])
def test_cross_engine_contract(case):
    result = calculate_payload({key: case[key] for key in ("ast", "operation", "angleMode")})
    for key, expected in case["expected"].items():
        assert result[key] == expected
