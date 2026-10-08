# Jem Calc contract v1

All numeric literals are decimal strings. The AST is the only computational input; LaTeX is display/editing only. Reject unknown node types, operators and functions.

## AST nodes

- `{"type":"number","value":"0.125"}` (integers, decimal or scientific notation)
- `{"type":"symbol","name":"x"}` (single Latin letters)
- `{"type":"constant","name":"pi"}` (`pi`, `e`)
- `{"type":"unary","op":"-","arg":NODE}` (`+`, `-`)
- `{"type":"binary","op":"+","left":NODE,"right":NODE}` (`+`, `-`, `*`, `/`, `^`)
- `{"type":"call","fn":"sin","args":[NODE]}` (`sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`, `abs`, `ln`, `log`, `exp`, `factorial`; `root` has arguments radicand, integer index)
- `{"type":"equation","left":NODE,"right":NODE}`
- `{"type":"system","equations":[EQUATION,...]}`
- `{"type":"derivative","body":NODE,"variable":"x","order":1}`
- `{"type":"integral","body":NODE,"variable":"x","lower":NODE_OR_NULL,"upper":NODE_OR_NULL}`
- `{"type":"limit","body":NODE,"variable":"x","to":NODE,"direction":"both"}` (`both`, `+`, `-`; limit destination also allows `{"type":"infinity","sign":1}`)

## POST /v1/calculate

Request: `{"ast":NODE,"operation":"exact","variable":"x","variables":["x","y"],"angleMode":"rad","domain":"real","precision":30,"order":1,"lower":null,"upper":null,"approach":null,"direction":"both"}`. Optional fields use these defaults. Operations: `evaluate`, `exact`, `simplify`, `expand`, `factor`, `solve`, `differentiate`, `integrate`, `limit`. Angle mode `rad` or `deg`. `evaluate` on a calculus AST executes the represented operation.

`solve` evaluates a purely numeric expression (numbers/constants and numeric unary, binary or function arguments), matching the app when Solve remains selected after an earlier equation. Explicit equations/systems and expressions containing symbols retain equation-solving semantics, even when symbols cancel. Calculus operations remain explicit. For example, numeric `18.33 * 12` returns the exact rational `5499/25`; `2 = 3` still returns `empty`.

Response: `{"status":"exact","latex":"...","text":"...","approximation":null,"conditions":[],"verification":{"status":"notApplicable","detail":"..."},"engine":"sympy","engineVersion":"..."}`.

Statuses: `exact`, `approximate`, `empty`, `unresolved`, `domainError`, `timeout`, `unsupported`, `error`. Verification statuses: `verified`, `numeric`, `inconclusive`, `notApplicable`. Human-readable provider errors may be English; app maps known statuses to localized labels.

## Recognition

POST `/v1/recognize/ink`: `{"strokes":[{"x":[1,2],"y":[1,2]}],"revision":1}`.

POST `/v1/recognize/image`: multipart `image` file, `revision` string integer, `provider` default `mathpix` or `openai` for benchmark. Images normalized/cropped in app. Max image 8 MiB.

Both return `{"latex":"...","revision":1,"ambiguities":[],"provider":"mathpix","confidence":0.9}`; confidence may be null. These are proposals, never calculation results.

## WS /v1/dictation

Authentication is the initial message `{"type":"start","token":"...","sessionId":"...","provider":"scribe","language":"es","latex":"","revision":0}`. No credentials in URL. Providers `scribe` and `openai`. Server rejects any other messages until authenticated.

Context source is `manual` for user changes and `proposal` with its `segmentId` when acknowledging an accepted server proposal.

Client streams binary signed PCM16 mono 24000 Hz. Other messages: `{"type":"context","latex":"...","revision":1,"source":"manual","segmentId":null}`, `{"type":"commit"}`, `{"type":"stop"}`.

Server events:
- `{"type":"ready","sessionId":"..."}`
- `{"type":"transcript","text":"...","final":false,"segmentId":"...","sessionId":"..."}`
- `{"type":"proposal","latex":"...","baseRevision":0,"segmentId":"...","sessionId":"...","ambiguities":[]}`
- `{"type":"error","message":"...","code":"..."}`

Interpreter emits a proposed complete draft LaTeX, not results; only replaces current draft if its baseRevision is current. Manual edits increment revision, send context, and invalidate all older proposals. A server-generated accepted draft also increments revision and is acknowledged by context. Server must not repeatedly incorporate an already applied segment; keep committed base and provisional segment separate. Debounce partials 400 ms, process finals immediately; cancel or invalidate older interpretation responses. Stop/cancellation terminates upstream ASR.

## Server configuration

`PILOT_TOKEN`, `MATHPIX_APP_ID`, `MATHPIX_APP_KEY`, `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, `OPENAI_INTERPRETER_MODEL` (default `gpt-6-luna`). REST uses `Authorization: Bearer TOKEN`. `/health` is unauthenticated and reports configured provider booleans only. Missing credentials produce 503, never demo output. No API keys in mobile app. TLS configured via Uvicorn runner. Server does not retain audio or images.

## Local math interface (Dart)

Implement `app/lib/math/ast.dart`, `parser.dart`, `evaluator.dart`, `latex.dart` with entry points:
- `typedef MathNode = Map<String, dynamic>;`
- `MathNode parseLatex(String latex)` throws `MathParseException` with readable `message`.
- `MathNode parseExpression(String input)` for plain math text.
- `String astToLatex(MathNode node)`.
- `LocalResult evaluateLocal(MathNode ast, {String angleMode = 'rad', Map<String,double> variables = const {}})`; result fields `String text`, `String latex`, `bool exact`, `double? value`.
- `double evaluateDouble(MathNode ast, {String angleMode = 'rad', Map<String,double> variables = const {}})` throws on nonnumeric/domain errors.
- `bool requiresCas(MathNode ast)` true for symbols not bound locally, equations, systems, calculus.

Local errors use `MathEvaluationException` with `message`. Exact rational arithmetic, approximate doubles only when required. Preserve input AST. Limits: depth 64, 512 nodes, rational output 4096 digits, factorial argument <=1000. 0^0 is domain error. Explicit nth root supports negative radicands for odd positive integer degree; negative base powers only integer exponent. Root limits and domains shared with CAS.
