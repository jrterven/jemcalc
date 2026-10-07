"""Private HTTPS web deployment. Native clients retain their bearer-token API.

Run behind the dedicated Nginx virtual host, never the loopback development proxy.
Browser sessions are signed, expiring HttpOnly cookies; provider/pilot keys stay here.
"""
from contextlib import asynccontextmanager
from dataclasses import dataclass
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import time
from urllib.parse import urlsplit

from fastapi import FastAPI, Request
from starlette.datastructures import Headers
from starlette.requests import HTTPConnection
from starlette.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from starlette.staticfiles import StaticFiles

from . import main
from .config import get_settings

COOKIE = "__Host-jemcalc"
SESSION_SECONDS = 7 * 24 * 3600
HERE = Path(__file__).parent
ANDROID_APK = "jemcalc-1.0.2-4.apk"


def login_destination(value: str | None):
    # Only known pages can be resumed after login; never redirect to user URLs.
    return "/android" if value == "/android" else "/"


@dataclass(frozen=True)
class WebSettings:
    origin: str
    password: str
    session_secret: str
    pilot_token: str
    static_dir: Path

    def validate(self):
        url = urlsplit(self.origin)
        if (url.scheme != "https" or not url.hostname or url.path or url.query
                or url.fragment or url.username or url.password):
            raise ValueError("WEB_ORIGIN must be an HTTPS origin without a path")
        if min(len(self.password), len(self.session_secret), len(self.pilot_token)) < 20:
            raise ValueError("Production access keys must each contain at least 20 characters")
        if not (self.static_dir / "index.html").is_file():
            raise ValueError("Missing Flutter web build")


def issue_session(settings: WebSettings, *, now=None):
    timestamp = int(time.time() if now is None else now)
    payload = f"{timestamp}.{secrets.token_urlsafe(24)}"
    signature = hmac.new(settings.session_secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{signature}"


def valid_session(value: str, settings: WebSettings, *, now=None):
    if not isinstance(value, str) or len(value) > 200:
        return False
    try:
        payload, signature = value.rsplit(".", 1)
        timestamp, nonce = payload.split(".", 1)
        age = int(time.time() if now is None else now) - int(timestamp)
    except (ValueError, TypeError):
        return False
    expected = hmac.new(settings.session_secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return bool(nonce) and 0 <= age < SESSION_SECONDS and hmac.compare_digest(signature.encode(), expected.encode())


def same_origin(headers: Headers, settings: WebSettings):
    return (headers.get("origin") == settings.origin
            and headers.get("sec-fetch-site") not in {"cross-site", "same-site"})


class AccessBoundary:
    def __init__(self, app, settings: WebSettings):
        self.app, self.settings = app, settings

    async def __call__(self, scope, receive, send):
        if scope["type"] not in {"http", "websocket"}:
            return await self.app(scope, receive, send)
        headers = Headers(scope=scope)
        path = scope["path"]
        is_api = path.startswith("/api/")
        cookie_ok = valid_session(HTTPConnection(scope).cookies.get(COOKIE, ""), self.settings)
        host_ok = headers.get("host") == urlsplit(self.settings.origin).netloc
        origin_ok = headers.get("origin") in {None, self.settings.origin}

        async def reject(status, message):
            if scope["type"] == "websocket":
                await send({"type": "websocket.close", "code": 1008})
            else:
                await JSONResponse({"detail": message}, status_code=status)(scope, receive, secure_send)

        async def secure_send(message):
            if message["type"] == "http.response.start":
                message = dict(message)
                message["headers"] = list(message.get("headers", [])) + [
                    (b"cache-control", b"no-store"),
                    (b"x-content-type-options", b"nosniff"),
                    (b"x-frame-options", b"SAMEORIGIN"),
                    # no-referrer makes native form POSTs send Origin: null.
                    # Keep same-origin form login compatible with the CSRF check.
                    (b"referrer-policy", b"strict-origin-when-cross-origin"),
                    (b"x-robots-tag", b"noindex, nofollow"),
                ]
            await send(message)

        if not host_ok or not origin_ok or headers.get("sec-fetch-site") == "cross-site" and (is_api or scope["type"] == "websocket"):
            return await reject(403, "Same-origin access required")
        if scope["type"] == "websocket":
            if path != "/api/v1/dictation":
                return await reject(404, "Unknown WebSocket route")
            # Browsers always send Origin. Native clients authenticate in their first frame.
            if headers.get("origin") is not None:
                if not cookie_ok or not same_origin(headers, self.settings):
                    return await reject(401, "Inicia sesión para usar el dictado.")
                first_frame = True
                upstream_receive = receive

                async def authenticated_receive():
                    nonlocal first_frame
                    message = await upstream_receive()
                    if first_frame and message["type"] == "websocket.receive":
                        first_frame = False
                        raw = message.get("text", "")
                        if len(raw) <= 24000:
                            try:
                                data = json.loads(raw)
                            except (ValueError, RecursionError):
                                data = None
                            if isinstance(data, dict) and data.get("type") == "start":
                                data["token"] = self.settings.pilot_token
                                message = {**message, "text": json.dumps(data)}
                    return message

                receive = authenticated_receive
        elif is_api:
            if cookie_ok:
                if scope["method"] not in {"GET", "HEAD"} and not same_origin(headers, self.settings):
                    return await reject(403, "Same-origin access required")
                scope = dict(scope)
                scope["headers"] = [(k, v) for k, v in scope["headers"] if k.lower() != b"authorization"]
                scope["headers"].append((b"authorization", f"Bearer {self.settings.pilot_token}".encode()))
            # Without a cookie the existing API validates the native bearer token.
        elif path not in {"/access", "/access/logout", "/access/logo.png", "/favicon.png", "/robots.txt"} and not cookie_ok:
            # Desktop link openers may resolve a relative Location as a local file.
            # Always redirect to the configured HTTPS origin, never a request header.
            resume = "?next=/android" if path == "/android" or path.startswith("/downloads/") else ""
            return await RedirectResponse(self.settings.origin + "/access" + resume, status_code=303)(scope, receive, secure_send)
        return await self.app(scope, receive, secure_send)


class ApiMount:
    """Remove /api before existing route body limits and the CAS see the request."""
    async def __call__(self, scope, receive, send):
        prefix = scope.get("root_path", "")
        path = scope["path"][len(prefix):] if prefix else scope["path"]
        scope = {**scope, "path": path, "raw_path": path.encode(), "root_path": ""}
        await main.app(scope, receive, send)


def create_app(settings: WebSettings | None = None):
    if settings is None:
        settings = WebSettings(
            origin=os.environ["WEB_ORIGIN"], password=os.environ["WEB_ACCESS_PASSWORD"],
            session_secret=os.environ["WEB_SESSION_SECRET"], pilot_token=get_settings().pilot_token,
            static_dir=Path(os.environ.get("WEB_STATIC_DIR", "/srv/web")),
        )
    settings.validate()

    @asynccontextmanager
    async def lifespan(app):
        async with main.lifespan(main.app):
            yield

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.add_middleware(AccessBoundary, settings=settings)

    @app.get("/access", response_class=HTMLResponse)
    async def login_page(request: Request):
        destination = login_destination(request.query_params.get("next"))
        if destination == "/android" and valid_session(request.cookies.get(COOKIE, ""), settings):
            return RedirectResponse(settings.origin + destination, status_code=303)
        return HTMLResponse((HERE / "templates/access.html").read_text().replace(
            "{{message}}", "Clave incorrecta. Intenta otra vez." if request.query_params.get("error") else ""
        ).replace("{{next}}", destination))

    @app.post("/access")
    async def login(request: Request):
        if not same_origin(request.headers, settings):
            return JSONResponse({"detail": "Same-origin access required"}, status_code=403)
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 4096:
                return JSONResponse({"detail": "Request too large"}, status_code=413)
        from urllib.parse import parse_qs
        try:
            form = parse_qs(body.decode(), max_num_fields=4)
        except (UnicodeDecodeError, ValueError):
            form = {}
        password = form.get("password", [""])[0]
        destination = login_destination(form.get("next", [""])[0])
        if not secrets.compare_digest(password.encode(), settings.password.encode()):
            resume = "&next=/android" if destination == "/android" else ""
            return RedirectResponse(settings.origin + "/access?error=1" + resume, status_code=303)
        response = RedirectResponse(settings.origin + destination, status_code=303)
        response.set_cookie(COOKIE, issue_session(settings), max_age=SESSION_SECONDS,
                            secure=True, httponly=True, samesite="strict", path="/")
        return response

    @app.post("/access/logout")
    async def logout(request: Request):
        if not same_origin(request.headers, settings):
            return JSONResponse({"detail": "Same-origin access required"}, status_code=403)
        response = RedirectResponse(settings.origin + "/access", status_code=303)
        response.delete_cookie(COOKIE, secure=True, httponly=True, samesite="strict", path="/")
        return response

    @app.get("/access/logo.png")
    async def logo():
        return FileResponse(settings.static_dir / "icons/jem-calc-192.png")

    @app.get("/favicon.png")
    async def favicon():
        return FileResponse(settings.static_dir / "favicon.png")

    @app.get("/robots.txt")
    async def robots():
        from starlette.responses import PlainTextResponse
        return PlainTextResponse("User-agent: *\nDisallow: /\n")

    @app.get("/android", response_class=HTMLResponse)
    async def android_page():
        return HTMLResponse((HERE / "templates/android.html").read_text().replace("{{apk}}", ANDROID_APK))

    @app.api_route("/downloads/" + ANDROID_APK, methods=["GET", "HEAD"])
    async def android_installer():
        apk = settings.static_dir / "downloads" / ANDROID_APK
        if not apk.is_file():
            return JSONResponse({"detail": "El instalador no está disponible."}, status_code=404)
        return FileResponse(apk, filename=ANDROID_APK, media_type="application/vnd.android.package-archive")

    app.mount("/api", ApiMount())
    app.mount("/", StaticFiles(directory=settings.static_dir, html=True))
    return app
