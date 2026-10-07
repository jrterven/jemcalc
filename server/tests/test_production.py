import json
from pathlib import Path

from fastapi.testclient import TestClient
import pytest
from starlette.websockets import WebSocketDisconnect

from jemcalc import auth, main, production
from jemcalc.config import Settings

TOKEN = "native-test-token-at-least-20"
PASSWORD = "web-test-password-at-least-20"
ORIGIN = "https://calc.example.com"
PAYLOAD = {"ast": {"type": "number", "value": "7"}}


@pytest.fixture
def setup(tmp_path, monkeypatch):
    (tmp_path / "index.html").write_text("<title>Jem Calc</title>PRIVATE_APP")
    settings = production.WebSettings(ORIGIN, PASSWORD, "session-test-secret-at-least-32-chars", TOKEN, tmp_path)
    api_settings = Settings(pilot_token=TOKEN)
    monkeypatch.setattr(main, "get_settings", lambda: api_settings)
    monkeypatch.setattr(auth, "get_settings", lambda: api_settings)
    with TestClient(production.create_app(settings), base_url=ORIGIN, follow_redirects=False) as client:
        yield client, settings


def login(client):
    return client.post("/access", data={"password": PASSWORD}, headers={"Origin": ORIGIN})


def test_private_page_login_and_logout(setup):
    client, _ = setup
    assert client.get("/").headers["location"] == ORIGIN + "/access"
    page = client.get("/access")
    assert "Clave de acceso" in page.text
    assert page.headers["referrer-policy"] == "strict-origin-when-cross-origin"
    assert PASSWORD not in page.text and TOKEN not in page.text
    assert client.post("/access", data={"password": "wrong"}, headers={"Origin": ORIGIN}).headers["location"] == ORIGIN + "/access?error=1"
    result = login(client)
    assert result.status_code == 303
    assert result.headers["location"] == ORIGIN + "/"
    cookie = result.headers["set-cookie"]
    assert "HttpOnly" in cookie and "Secure" in cookie and "SameSite=strict" in cookie
    assert "Domain=" not in cookie and "Path=/" in cookie
    assert PASSWORD not in cookie and TOKEN not in cookie
    assert client.get("/").text.endswith("PRIVATE_APP")
    assert "no-store" in client.get("/").headers["cache-control"]
    logout = client.post("/access/logout", headers={"Origin": ORIGIN})
    assert logout.status_code == 303
    assert logout.headers["location"] == ORIGIN + "/access"
    assert client.get("/").status_code == 303


def test_redirect_uses_configured_https_origin_not_forwarded_headers(setup):
    client, _ = setup
    result = client.get("/", headers={"X-Forwarded-Host": "foreign.example", "X-Forwarded-Proto": "file"})
    assert result.headers["location"] == ORIGIN + "/access"


def test_api_cookie_and_native_bearer_auth(setup):
    client, _ = setup
    assert client.post("/api/v1/calculate", json=PAYLOAD).status_code == 401
    assert client.post("/api/v1/calculate", json=PAYLOAD, headers={"Authorization": "Bearer wrong"}).status_code == 401
    result = client.post("/api/v1/calculate", json=PAYLOAD, headers={"Authorization": f"Bearer {TOKEN}"})
    assert result.status_code == 200 and result.json()["text"] == "7"
    login(client)
    # Flutter web sends an empty bearer; the signed same-origin session supplies it server-side.
    result = client.post("/api/v1/calculate", json=PAYLOAD, headers={"Origin": ORIGIN, "Authorization": "Bearer "})
    assert result.status_code == 200 and result.json()["engine"] == "sympy"
    assert TOKEN not in result.text


def test_csrf_host_and_body_limits(setup):
    client, _ = setup
    assert client.post("/access", data={"password": PASSWORD}).status_code == 403
    assert client.post("/access", data={"password": PASSWORD}, headers={"Origin": "https://foreign.example"}).status_code == 403
    assert client.get("/access", headers={"Host": "foreign.example"}).status_code == 403
    assert client.post("/access", content=b"a"*4097, headers={"Origin": ORIGIN}).status_code == 413
    login(client)
    for headers in [{}, {"Origin": "https://foreign.example"}, {"Origin": ORIGIN, "Sec-Fetch-Site": "cross-site"}]:
        assert client.post("/api/v1/calculate", json=PAYLOAD, headers=headers).status_code == 403
    assert client.post("/access/logout").status_code == 403
    # Mounting /api must not disable the original CAS body limits.
    assert client.post("/api/v1/calculate", content=b"x"*(256*1024+1), headers={"Origin": ORIGIN}).status_code == 413
    assert client.post("/api/v1/recognize/image", content=b"x"*(9*1024*1024+1), headers={"Origin": ORIGIN}).status_code == 413


def test_signed_session_expiry_and_tampering(setup):
    _, settings = setup
    cookie = production.issue_session(settings, now=1000)
    assert production.valid_session(cookie, settings, now=1001)
    assert not production.valid_session(cookie, settings, now=999)
    assert not production.valid_session(cookie, settings, now=1000+production.SESSION_SECONDS)
    assert not production.valid_session(cookie[:-1]+("a" if cookie[-1] != "a" else "b"), settings, now=1001)
    assert not production.valid_session("bogus", settings)


def test_websocket_cookie_injection_and_native_token_passthrough(setup, monkeypatch):
    client, _ = setup
    seen = []

    async def fake_api(scope, receive, send):
        assert scope["path"] == "/v1/dictation"
        assert (await receive())["type"] == "websocket.connect"
        await send({"type": "websocket.accept"})
        data = json.loads((await receive())["text"])
        seen.append(data)
        await send({"type": "websocket.send", "text": '{"type":"ready"}'})
        await send({"type": "websocket.close", "code": 1000})

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("wss://calc.example.com/api/v1/dictation", headers={"Origin": ORIGIN}):
            pass
    login(client)
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("wss://calc.example.com/api/v1/dictation", headers={"Origin": "https://foreign.example"}):
            pass
    # Lifespan is already entered, so replacing just the mounted ASGI callable is safe.
    monkeypatch.setattr(main, "app", fake_api)
    with client.websocket_connect("wss://calc.example.com/api/v1/dictation", headers={"Origin": ORIGIN}) as ws:
        ws.send_json({"type": "start", "token": "", "sessionId": "browser"})
        assert ws.receive_json() == {"type": "ready"}
    assert seen[-1]["token"] == TOKEN
    client.cookies.clear()
    with client.websocket_connect("wss://calc.example.com/api/v1/dictation") as ws:
        ws.send_json({"type": "start", "token": TOKEN, "sessionId": "native"})
        assert ws.receive_json() == {"type": "ready"}
    assert seen[-1]["token"] == TOKEN


def test_invalid_production_configuration_fails_closed(tmp_path):
    (tmp_path / "index.html").write_text("test")
    for origin, password in [("http://calc.example.com", PASSWORD), (ORIGIN+"/path", PASSWORD), (ORIGIN, "short")]:
        with pytest.raises(ValueError):
            production.create_app(production.WebSettings(origin, password, "s"*32, TOKEN, tmp_path))
