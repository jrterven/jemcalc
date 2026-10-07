# Backend and mathematical behavior

## Computation boundary

`POST /v1/calculate` accepts the version-one JSON AST and explicit operation from [contract.md](contract.md). Python constructs SymPy objects from an allowlist; it does not evaluate Python source or parse raw LaTeX. Schema validation rejects unknown fields, names, operations, function arities, excess depth and excess size. Numbers enter as decimal strings and become exact rationals.

The API returns a result state separately from the display expression: `exact`, `approximate`, `empty`, `unresolved`, `domainError`, `timeout`, `unsupported` or `error`. `ConditionSet` and unevaluated calculus remain `unresolved`, never “no solution”. Approximate decimal output does not replace the exact expression. SymPy version is recorded in every mathematical response.

All current operations use real numbers. `ln` means natural logarithm; `log` means base 10. A negative base with a noninteger exponent is rejected; use an explicit odd `root` for a real negative radicand. `0^0` is undefined. Decimal literals are exact, so `0.1+0.2` is `3/10`.

Domain restrictions are collected before simplification. Cancelling `x/x` produces `1` with `x≠0`; solving `(x²−1)/(x−1)=0` cannot introduce `x=1`. Candidate solutions are substituted into the original expression, not only a transformed polynomial. A result with unresolved restrictions stays conditional; verification does not silently discard them.

## University pilot coverage

- Evaluate exactly, simplify, expand and factor elementary expressions.
- Solve one-variable real equations, including finite and infinite solution sets when SymPy supports them.
- Linear systems: up to four equations and four specified variables, including inconsistent and parametric solutions. Coefficients must be numeric.
- Nonlinear systems: two polynomial equations in two variables, total degree at most two. Nonreal candidates are filtered; other system classes return `unsupported`.
- Single-variable derivatives of order one through three. Nonsmooth corner exclusions are retained; distributional derivatives are not presented as classical derivatives.
- Definite and indefinite single-variable integrals. Indefinite results include `+ C`, real logarithmic primitives use `log|u|`, and constants can differ across disconnected intervals. Improper endpoints are allowed when the integral converges. Split an integral at interior singularities/domain boundaries; the current service deliberately returns `unsupported` there.
- Finite/infinite and one-sided/two-sided limits. A finite two-sided limit is checked from both directions; disagreeing sides report nonexistence. A side outside the real domain is not replaced by complex continuation.

DEG and RAD apply consistently to evaluation, graphs and calculus. Internally degree trig arguments are multiplied by π/180, and inverse trig results by 180/π. Differentiating `sin(x)` in DEG therefore includes π/180. Returned CAS formulas use the normalized radian arguments; do not reinterpret them as new degree-mode input.

“Comprobación” is not a universal proof certificate. Algebra uses exact substitution and domain checks. Indefinite integrals are differentiated back. First derivatives use independent central-difference samples where possible and label that check `numeric`. Definite integrals, higher derivatives and limits can correctly report `inconclusive` verification alongside a CAS result. Never display an inconclusive or numeric check as a proof.

## Isolation and pilot security

Each CAS request has its own spawned process. The parent enforces a ten-second deadline, kills the worker on cancellation/disconnect, and allows two simultaneous jobs. Input/output budgets limit expression growth. Linux has an additional address-space cap; macOS does not provide the same reliable memory-bound behavior. No untrusted source is evaluated inside the worker.

Use [the server README](../server/README.md) to create a private `.env`, certificate and TLS server. Provider credentials stay only on the Mac. The app receives the pilot token and public certificate, not provider keys or TLS private keys. Use one fixed LAN address during the pilot; a changed address/certificate requires updating the app's trust configuration. The startup script enables no access logs and never prints environment values.

For iPad, add an ES/EN `NSLocalNetworkUsageDescription` explaining connection to the private calculator service. Test permission denied/allowed on the physical iPad; the simulator does not reproduce this privacy boundary. Android needs Internet permission and the same trusted development certificate. Do not enable universal cleartext access or a callback that trusts every certificate.

The server does not write received images, strokes, audio or formulas to disk. Recognition and streaming adapters are separately testable with fake transports. A configured-provider flag means credentials exist, not that billing, connectivity or recognition quality has been verified.

## Validation commands

```sh
server/.venv/bin/python -m pytest server/tests
```

Tests cover exact decimals/rationals, domains, denominator cancellation, DEG/RAD, finite/infinite/unresolved solutions, linear/quadratic systems, calculus, malicious AST rejection, authentication, body limits and actual worker termination on timeout/cancellation. Provider tests never require paid service calls.
