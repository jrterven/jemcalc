"""Strict wire types. No string expression is evaluated by Python."""

from __future__ import annotations

import re
from typing import Annotated, Literal, Union

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

MAX_NODES = 512
MAX_DEPTH = 64
MAX_DIGITS = 4096
SYMBOL_PATTERN = r"^[A-Za-z]$"
NUMBER_PATTERN = re.compile(r"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$")


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class NumberNode(StrictModel):
    type: Literal["number"]
    value: str = Field(min_length=1, max_length=4104)

    @field_validator("value")
    @classmethod
    def safe_number(cls, value: str) -> str:
        if not NUMBER_PATTERN.fullmatch(value):
            raise ValueError("Invalid decimal literal")
        parts = re.split("[eE]", value)
        exponent_text = parts[1].lstrip("+-") if len(parts) == 2 else "0"
        if len(exponent_text) > 5:
            raise ValueError("Numeric exponent is too large")
        exponent = int(parts[1]) if len(parts) == 2 else 0
        if abs(exponent) + len(parts[0]) > MAX_DIGITS:
            raise ValueError("Numeric literal exceeds 4096 digits")
        return value


class SymbolNode(StrictModel):
    type: Literal["symbol"]
    name: str = Field(pattern=SYMBOL_PATTERN)


class ConstantNode(StrictModel):
    type: Literal["constant"]
    name: Literal["pi", "e"]


class InfinityNode(StrictModel):
    type: Literal["infinity"]
    sign: Literal[1, -1]

    @field_validator("sign", mode="before")
    @classmethod
    def integer_sign(cls, value: object) -> object:
        if type(value) is not int:
            raise ValueError("Infinity sign must be the integer 1 or -1")
        return value


class UnaryNode(StrictModel):
    type: Literal["unary"]
    op: Literal["+", "-"]
    arg: Node


class BinaryNode(StrictModel):
    type: Literal["binary"]
    op: Literal["+", "-", "*", "/", "^"]
    left: Node
    right: Node


class CallNode(StrictModel):
    type: Literal["call"]
    fn: Literal["sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "abs", "ln", "log", "exp", "factorial", "root"]
    args: list[Node] = Field(min_length=1, max_length=2)

    @model_validator(mode="after")
    def arity(self) -> CallNode:
        if len(self.args) != (2 if self.fn == "root" else 1):
            raise ValueError("Incorrect number of function arguments")
        return self


class EquationNode(StrictModel):
    type: Literal["equation"]
    left: Node
    right: Node


class SystemNode(StrictModel):
    type: Literal["system"]
    equations: list[EquationNode] = Field(min_length=1, max_length=4)


class DerivativeNode(StrictModel):
    type: Literal["derivative"]
    body: Node
    variable: str = Field(pattern=SYMBOL_PATTERN)
    order: int = Field(default=1, ge=1, le=3)


class IntegralNode(StrictModel):
    type: Literal["integral"]
    body: Node
    variable: str = Field(pattern=SYMBOL_PATTERN)
    lower: Node | None = None
    upper: Node | None = None

    @model_validator(mode="after")
    def bounds_pair(self) -> IntegralNode:
        if (self.lower is None) != (self.upper is None):
            raise ValueError("Provide both integral bounds or neither")
        return self


class LimitNode(StrictModel):
    type: Literal["limit"]
    body: Node
    variable: str = Field(pattern=SYMBOL_PATTERN)
    to: Node
    direction: Literal["both", "+", "-"] = "both"


Node = Annotated[Union[NumberNode, SymbolNode, ConstantNode, InfinityNode, UnaryNode, BinaryNode, CallNode, EquationNode, SystemNode, DerivativeNode, IntegralNode, LimitNode], Field(discriminator="type")]

for _model in (UnaryNode, BinaryNode, CallNode, EquationNode, SystemNode, DerivativeNode, IntegralNode, LimitNode):
    _model.model_rebuild()


class CalculateRequest(StrictModel):
    ast: Node
    operation: Literal["evaluate", "exact", "simplify", "expand", "factor", "solve", "differentiate", "integrate", "limit"] = "exact"
    variable: str = Field(default="x", pattern=SYMBOL_PATTERN)
    variables: list[Annotated[str, Field(pattern=SYMBOL_PATTERN)]] = Field(default_factory=lambda: ["x", "y"], min_length=1, max_length=4)
    angleMode: Literal["rad", "deg"] = "rad"
    domain: Literal["real"] = "real"
    precision: int = Field(default=30, ge=2, le=100)
    order: int = Field(default=1, ge=1, le=3)
    lower: Node | None = None
    upper: Node | None = None
    approach: Node | None = None
    direction: Literal["both", "+", "-"] = "both"

    @model_validator(mode="before")
    @classmethod
    def tree_budget(cls, data: object) -> object:
        if not isinstance(data, dict):
            return data
        pending = [(data.get(key), 1) for key in ("ast", "lower", "upper", "approach") if data.get(key) is not None]
        count = 0
        while pending:
            item, depth = pending.pop()
            if isinstance(item, dict):
                if depth > MAX_DEPTH:
                    raise ValueError("Expression exceeds depth 64")
                count += 1
                if count > MAX_NODES:
                    raise ValueError("Expression exceeds 512 nodes")
                for value in item.values():
                    if isinstance(value, dict):
                        pending.append((value, depth + 1))
                    elif isinstance(value, list):
                        pending.extend((child, depth + 1) for child in value if isinstance(child, (dict, list)))
            elif isinstance(item, list):
                pending.extend((child, depth + 1) for child in item)
        return data

    @model_validator(mode="after")
    def options(self) -> CalculateRequest:
        if len(set(self.variables)) != len(self.variables):
            raise ValueError("System variables must be distinct")
        if (self.lower is None) != (self.upper is None):
            raise ValueError("Provide both integral bounds or neither")
        return self


class Verification(StrictModel):
    status: Literal["verified", "numeric", "inconclusive", "notApplicable"] = "notApplicable"
    detail: str = ""


class CalculateResponse(StrictModel):
    status: Literal["exact", "approximate", "empty", "unresolved", "domainError", "timeout", "unsupported", "error"]
    latex: str = ""
    text: str = ""
    approximation: str | None = None
    conditions: list[str] = Field(default_factory=list)
    verification: Verification = Field(default_factory=Verification)
    engine: str = "sympy"
    engineVersion: str
