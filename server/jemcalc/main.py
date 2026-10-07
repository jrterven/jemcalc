"""HTTP application. Start through scripts/run_server.py for LAN TLS."""

from contextlib import asynccontextmanager
import json

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.formparsers import MultiPartParser
from starlette.types import ASGIApp, Receive, Scope, Send

from .auth import require_pilot_token
from .config import get_settings
from .execution import CalculationRunner
from .models import CalculateRequest, CalculateResponse


class RequestBodyLimit:
    """Bound bodies before parsing or multipart spooling, even without Content-Length."""

    def __init__(self, app: ASGIApp):
        self.app = app
        self.limits = {"/v1/calculate": 256 * 1024, "/v1/recognize/ink": 1024 * 1024, "/v1/recognize/image": 9 * 1024 * 1024}

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope.get("path") not in self.limits:
            await self.app(scope, receive, send)
            return
        limit = self.limits[scope["path"]]
        chunks = []
        total = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            total += len(chunk)
            if total > limit:
                response = JSONResponse({"detail": "Request body exceeds the route size limit"}, status_code=413)
                await response(scope, receive, send)
                return
            chunks.append(chunk)
            if not message.get("more_body", False):
                break
        body = b"".join(chunks)
        if scope["path"] == "/v1/calculate":
            try:
                json.loads(body)
            except RecursionError:
                response = JSONResponse({"detail": "JSON nesting is too deep"}, status_code=422)
                await response(scope, receive, send)
                return
            except (ValueError, UnicodeDecodeError):
                pass  # FastAPI supplies its normal malformed-JSON response.
        delivered = False

        async def replay() -> dict:
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        await self.app(scope, replay, send)


@asynccontextmanager
async def lifespan(app: FastAPI):
    get_settings()
    app.state.calculation_runner = CalculationRunner()
    yield
    await app.state.calculation_runner.close()


app = FastAPI(title="Jem Calc private pilot", version="0.1.0", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
# The total image request limit is 9 MiB; raising the spool threshold above it
# prevents UploadFile from writing otherwise valid images to a temporary disk file.
MultiPartParser.spool_max_size = 9 * 1024 * 1024 + 1
app.add_middleware(RequestBodyLimit)


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError):
    # Do not echo request content (including possible tokens or OCR text).
    errors = [{"location": list(error["loc"]), "message": error["msg"]} for error in exc.errors()]
    return JSONResponse(status_code=422, content={"detail": errors})


@app.get("/health")
async def health():
    return {"status": "ok", "providers": get_settings().configured_providers}


@app.post("/v1/calculate", response_model=CalculateResponse, dependencies=[Depends(require_pilot_token)])
async def calculate(payload: CalculateRequest, request: Request) -> CalculateResponse:
    runner = request.app.state.calculation_runner
    return await runner.run(payload.model_dump(), timeout=get_settings().cas_timeout_seconds, request=request)


from .recognition import router as recognition_router

app.include_router(recognition_router)
