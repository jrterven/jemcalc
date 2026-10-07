import importlib.util
import asyncio
from contextlib import asynccontextmanager
import json
from pathlib import Path
import ssl

import httpx
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('run_web', ROOT / 'scripts/run_web.py')
web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web)


def client(tmp_path, seen):
    (tmp_path / 'index.html').write_text('<title>Jem Calc</title>')
    def upstream(request):
        seen.append(request)
        return httpx.Response(200, json={'status': 'exact', 'text': '2'})
    app = web.create_app(tmp_path, 'https://private.invalid:8443', 'server-only-secret',
                         ssl.create_default_context(), transport=httpx.MockTransport(upstream))
    return TestClient(app, base_url='http://localhost:5187')


def test_web_proxy_keeps_token_server_side_and_preserves_requests(tmp_path):
    seen = []
    with client(tmp_path, seen) as browser:
        static = browser.get('/')
        assert static.status_code == 200
        assert 'server-only-secret' not in static.text
        response = browser.post('/api/v1/calculate', json={'revision': 2},
                                headers={'Origin': 'http://localhost:5187', 'Authorization': 'Bearer untrusted'})
        assert response.status_code == 200
        assert response.json()['text'] == '2'
        assert str(seen[0].url) == 'https://private.invalid:8443/v1/calculate'
        assert seen[0].headers['Authorization'] == 'Bearer server-only-secret'
        assert json.loads(seen[0].content) == {'revision': 2}
        assert browser.post('/api/not-allowed').status_code == 404
        assert len(seen) == 1


def test_web_proxy_rejects_foreign_origins_hosts_and_oversized_bodies(tmp_path):
    seen = []
    with client(tmp_path, seen) as browser:
        for headers in [{'Origin': 'https://foreign.invalid'}, {'Host': 'foreign.invalid'},
                        {'Sec-Fetch-Site': 'cross-site'}]:
            assert browser.post('/api/v1/calculate', content=b'{}', headers=headers).status_code == 403
        assert browser.post('/api/v1/recognize/image', content=b'x'*(web.MAX_BODY+1)).status_code == 413
        assert seen == []


def test_web_proxy_requires_https_upstream(tmp_path):
    import pytest
    with pytest.raises(ValueError):
        web.create_app(tmp_path, 'http://private.invalid', 'token', ssl.create_default_context())


def test_web_dictation_injects_token_and_relays_audio_and_transcript(tmp_path, monkeypatch):
    seen = []

    class Remote:
        def __init__(self):
            self.messages = asyncio.Queue()

        async def send(self, message):
            seen.append(message)
            if isinstance(message, str):
                await self.messages.put('{"type":"ready"}')
            else:
                await self.messages.put('{"type":"transcript","text":"x plus one"}')
                await self.messages.put(None)

        def __aiter__(self):
            return self

        async def __anext__(self):
            message = await self.messages.get()
            if message is None:
                raise StopAsyncIteration
            return message

    @asynccontextmanager
    async def connect(endpoint, **kwargs):
        assert endpoint == 'wss://private.invalid:8443/v1/dictation'
        assert isinstance(kwargs['ssl'], ssl.SSLContext)
        yield Remote()

    monkeypatch.setattr(web, 'connect', connect)
    with client(tmp_path, []) as browser:
        with browser.websocket_connect('ws://localhost:5187/api/v1/dictation', headers={'Origin': 'http://localhost:5187'}) as ws:
            ws.send_json({'type': 'start', 'token': 'browser-token', 'provider': 'scribe'})
            assert ws.receive_json() == {'type': 'ready'}
            ws.send_bytes(b'\x00\x01' * 100)
            assert ws.receive_json()['text'] == 'x plus one'
            assert ws.receive()['type'] == 'websocket.close'
    assert json.loads(seen[0])['token'] == 'server-only-secret'
    assert seen[1] == b'\x00\x01' * 100


def test_web_dictation_rejects_foreign_origin_and_invalid_start(tmp_path):
    import pytest
    from starlette.websockets import WebSocketDisconnect
    with client(tmp_path, []) as browser:
        with pytest.raises(WebSocketDisconnect) as denied:
            with browser.websocket_connect('ws://localhost:5187/api/v1/dictation', headers={'Origin': 'https://foreign.invalid'}):
                pass
        assert denied.value.code == 1008
        with browser.websocket_connect('ws://localhost:5187/api/v1/dictation', headers={'Origin': 'http://localhost:5187'}) as ws:
            ws.send_json({'type': 'context'})
            with pytest.raises(WebSocketDisconnect) as invalid:
                ws.receive_json()
            assert invalid.value.code == 1008
