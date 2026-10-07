"""Deterministic provider contracts and editing races; no paid network calls."""
import asyncio
import contextlib
import json
from dataclasses import replace

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from jemcalc import auth, recognition
from jemcalc.config import Settings
from jemcalc.providers import Recognition, RecognitionProviders, ProviderError, Transcript, StreamingASR, validate_proposal
from jemcalc.recognition import DraftCoordinator, InkRequest


@pytest.fixture
def settings():
    return Settings(pilot_token="test-pilot", mathpix_app_id="test-id", mathpix_app_key="test-key",
                    openai_api_key="test-openai", elevenlabs_api_key="test-eleven")


@pytest.fixture
def api(monkeypatch, settings):
    monkeypatch.setattr(recognition, "get_settings", lambda: settings)
    monkeypatch.setattr(auth, "get_settings", lambda: settings)
    app = FastAPI()
    app.include_router(recognition.router)
    with TestClient(app) as client:
        yield client


async def collect(events, event):
    events.append(event)


def sse_proposal(latex="x^{2}", **extra):
    data = json.dumps(dict(latex=latex, ambiguities=[], **extra))
    events = [{"type": "response.output_text.delta", "delta": data[:10]},
              {"type": "response.output_text.delta", "delta": data[10:]},
              {"type": "response.completed", "response": {"status": "completed"}}]
    return "".join("data: " + json.dumps(event) + "\n\n" for event in events)


async def test_mathpix_ink_exact_wire_shape(settings):
    async def handle(request):
        assert request.url.path == "/v3/strokes"
        assert request.headers["app_id"] == "test-id"
        body = json.loads(request.content)
        assert body["strokes"] == {"strokes": {"x": [[1, 2], [3]], "y": [[4, 5], [6]]}}
        assert body["metadata"] == {"improve_mathpix": False}
        return httpx.Response(200, json={"latex_styled": r"\(x^2\)", "confidence": .91})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        result = await RecognitionProviders(settings, client).ink([{"x": [1, 2], "y": [4, 5]}, {"x": [3], "y": [6]}])
    assert result.payload(7) == {"latex": "x^2", "confidence": .91, "revision": 7, "provider": "mathpix", "ambiguities": []}


@pytest.mark.parametrize("data,valid", [({"text": r"\[x+1\]"}, True),
    ({"text": "Find the result " + r"\(x+1\)"}, False), ({"text": ""}, False),
    ({"error": "some sensitive provider details"}, False)])
async def test_mathpix_text_fallback_only_one_expression(settings, data, valid):
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json=data))) as client:
        if valid:
            assert (await RecognitionProviders(settings, client).image(b"png", "image/png", "mathpix")).latex == "x+1"
        else:
            with pytest.raises(ProviderError, match="expression"):
                await RecognitionProviders(settings, client).image(b"png", "image/png", "mathpix")


async def test_openai_stream_schema_and_no_calculator_tools(settings):
    async def handle(request):
        body = json.loads(request.content)
        assert body["model"] == "gpt-6-luna"
        assert body["store"] is False and body["stream"] is True
        assert "tools" not in body
        assert "Never calculate" in body["instructions"]
        assert body["text"]["format"]["strict"] is True
        assert set(body["text"]["format"]["schema"]["properties"]) == {"latex", "ambiguities"}
        assert "baseLatex" in body["input"][0]["content"][0]["text"]
        return httpx.Response(200, content=sse_proposal("2+2"), headers={"content-type": "text/event-stream"})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        result = await RecognitionProviders(settings, client).interpret("", [{"text": "resuelve dos más dos", "final": True}], "es")
    assert result.latex == "2+2"


async def test_photo_comparator_sends_inline_image(settings):
    async def handle(request):
        image = json.loads(request.content)["input"][0]["content"][1]
        assert image == {"type": "input_image", "image_url": "data:image/png;base64,YWJj", "detail": "high"}
        return httpx.Response(200, content=sse_proposal())
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        assert (await RecognitionProviders(settings, client).image(b"abc", "image/png", "openai")).latex == "x^{2}"


@pytest.mark.parametrize("body", ["data: {}\n\n", sse_proposal(answer="4"),
    'data: {"type":"response.incomplete"}\n\n'])
async def test_incomplete_or_extra_fields_rejected(settings, body):
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=body))) as client:
        with pytest.raises(ProviderError):
            await RecognitionProviders(settings, client).interpret("", [], "es")


async def test_provider_errors_redacted_and_not_retried(settings):
    calls = 0
    def handle(_):
        nonlocal calls
        calls += 1
        return httpx.Response(403, json={"error": "DO-NOT-ECHO secret project and key"})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        with pytest.raises(ProviderError) as error:
            await RecognitionProviders(settings, client).image(b"abc", "image/png", "openai")
    assert "DO-NOT-ECHO" not in str(error.value)
    assert calls == 1


async def test_missing_credentials_fail_before_network(settings):
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: pytest.fail("network call"))) as client:
        with pytest.raises(ProviderError) as error:
            await RecognitionProviders(replace(settings, openai_api_key=""), client).interpret("", [], "es")
    assert error.value.status == 503


@pytest.mark.parametrize("bad", [{"strokes": [{"x": [1], "y": [1, 2]}], "revision": 0},
    {"strokes": [{"x": [True], "y": [1]}], "revision": 0},
    {"strokes": [{"x": [float("nan")], "y": [1]}], "revision": 0},
    {"strokes": [], "revision": 0}, {"strokes": [{"x": [1], "y": [1]}], "revision": True}])
def test_invalid_ink_rejected(bad):
    with pytest.raises(ValueError):
        InkRequest.model_validate(bad)


def test_auth_required_and_image_validation(api):
    assert api.post("/v1/recognize/ink", json={}).status_code == 401
    response = api.post("/v1/recognize/image", headers={"Authorization": "Bearer test-pilot"},
        files={"image": ("fake.jpg", b"text", "image/jpeg")}, data={"revision": "2"})
    assert response.status_code == 415


def test_route_preserves_revision(api, monkeypatch):
    async def ink(self, strokes):
        return Recognition("x+1", [], "mathpix", .9)
    monkeypatch.setattr(RecognitionProviders, "ink", ink)
    response = api.post("/v1/recognize/ink", headers={"Authorization": "Bearer test-pilot"},
        json={"strokes": [{"x": [1], "y": [2]}], "revision": 19})
    assert response.status_code == 200 and response.json()["revision"] == 19


async def test_partial_debounce_and_final_immediate():
    events, calls = [], []
    async def interpret(base, segments, language):
        calls.append(segments)
        return Recognition(segments[-1]["text"], [], "openai")
    draft = DraftCoordinator("s", "", 0, "es", interpret, lambda e: collect(events, e), debounce=.03)
    await draft.transcript(Transcript("a", "x", False, 0))
    await draft.transcript(Transcript("a", "x+", False, 0))
    await draft.transcript(Transcript("a", "x+1", True, 0))
    await draft.flush()
    assert len(calls) == 1 and events[-1]["latex"] == "x+1"
    await draft.close()


async def test_continuous_partials_do_not_starve_live_proposals():
    events = []
    async def interpret(base, segments, language):
        await asyncio.sleep(.02)
        return Recognition(segments[-1]["text"], [], "openai")
    draft = DraftCoordinator("s", "", 0, "es", interpret, lambda e: collect(events, e), debounce=.02)
    for n in range(12):
        await draft.transcript(Transcript("a", "x+" + str(n), False, 0))
        await asyncio.sleep(.01)
    assert any(e["type"] == "proposal" for e in events)
    await draft.transcript(Transcript("a", "x+12", True, 0))
    await draft.flush()
    assert events[-1]["latex"] == "x+12"
    await draft.close()


async def test_cancel_resistant_out_of_order_interpretation_cannot_overwrite():
    events = []
    started, release = asyncio.Event(), asyncio.Event()
    async def interpret(base, segments, language):
        if segments[-1]["text"] == "old":
            started.set()
            try:
                await release.wait()
            except asyncio.CancelledError:
                await release.wait()  # Simulate an upstream that ignored cancellation.
            return Recognition("OLD", [], "openai")
        return Recognition("NEW", [], "openai")
    draft = DraftCoordinator("s", "", 0, "es", interpret, lambda e: collect(events, e), debounce=0)
    await draft.transcript(Transcript("a", "old", False, 0))
    await started.wait()
    await draft.transcript(Transcript("a", "new", True, 0))
    await draft.flush()
    release.set()
    await asyncio.sleep(.01)
    assert [e["latex"] for e in events if e["type"] == "proposal"] == ["NEW"]
    await draft.close()


async def test_manual_edit_invalidates_inflight_and_late_asr():
    events, calls = [], []
    started, release = asyncio.Event(), asyncio.Event()
    async def interpret(base, segments, language):
        calls.append((base, segments))
        if base == "":
            started.set()
            with contextlib.suppress(asyncio.CancelledError):
                await release.wait()
        return Recognition(base + "1", [], "openai")
    draft = DraftCoordinator("s", "", 0, "es", interpret, lambda e: collect(events, e), debounce=0)
    await draft.transcript(Transcript("a", "one", False, 0))
    await started.wait()
    assert await draft.context("y+", 1, "manual")
    release.set()
    await draft.transcript(Transcript("a", "old final", True, 0, epoch=0))
    await draft.transcript(Transcript("b", "one", True, 1, epoch=1))
    await draft.flush()
    proposals = [e for e in events if e["type"] == "proposal"]
    assert len(proposals) == 1 and proposals[0]["latex"] == "y+1" and proposals[0]["baseRevision"] == 1
    assert calls[-1][0] == "y+" and len(calls[-1][1]) == 1
    await draft.close()


async def test_partial_ack_never_duplicates_already_applied_segment():
    events, bases = [], []
    async def interpret(base, segments, language):
        bases.append(base)
        return Recognition(base + "".join(s["text"] for s in segments), [], "openai")
    draft = DraftCoordinator("s", "y+", 0, "es", interpret, lambda e: collect(events, e), debounce=0)
    await draft.transcript(Transcript("a", "x", False, 0))
    await draft.flush()
    assert not await draft.context("y+x", 1, "proposal")
    await draft.transcript(Transcript("a", "x^2", True, 0))
    await draft.flush()
    assert bases == ["y+", "y+"]
    assert events[-1]["latex"] == "y+x^2" and events[-1]["baseRevision"] == 1
    await draft.close()


async def test_final_order_and_duplicates():
    events = []
    async def interpret(base, segments, language):
        return Recognition("|".join(s["text"] for s in segments), [], "openai")
    draft = DraftCoordinator("s", "", 0, "es", interpret, lambda e: collect(events, e))
    await draft.transcript(Transcript("b", "second", True, 1))
    await draft.transcript(Transcript("a", "first", True, 0))
    await draft.flush()
    assert events[-1]["latex"] == "first|second"
    count = len(events)
    await draft.transcript(Transcript("a", "first", True, 0))
    await draft.transcript(Transcript("a", "late partial", False, 0))
    assert len(events) == count
    await draft.close()


async def test_explicit_manual_wins_even_when_latex_matches_issued():
    async def interpret(*_):
        return Recognition("x", [], "openai")
    draft = DraftCoordinator("s", "", 0, "es", interpret, lambda e: asyncio.sleep(0))
    await draft.transcript(Transcript("a", "x", True, 0))
    await draft.flush()
    assert await draft.context("x", 1, "manual")
    assert draft.base_latex == "x" and not draft.segments and draft.epoch == 1
    await draft.close()


def test_ws_rejects_audio_before_auth(api, monkeypatch):
    monkeypatch.setattr(recognition, "StreamingASR", lambda *_: pytest.fail("provider opened"))
    with api.websocket_connect("/v1/dictation") as ws:
        ws.send_bytes(b"\0\0")
        assert ws.receive_json()["code"] == "invalid_message"


def test_ws_stop_flushes_final_and_closes_provider(api, monkeypatch):
    closed = []
    class FakeASR:
        def __init__(self, *_):
            self.queue = asyncio.Queue()
            self.has_audio = False
        async def __aenter__(self):
            return self
        async def __aexit__(self, *_):
            closed.append(True)
        async def send_audio(self, _):
            self.has_audio = True
        async def commit(self):
            if self.has_audio:
                self.has_audio = False
                await self.queue.put(Transcript("final", "equis al cuadrado", True, 0))
        async def drain(self):
            await self.queue.join()
        async def events(self):
            while True:
                item = await self.queue.get()
                try:
                    yield item
                finally:
                    self.queue.task_done()
    async def interpret(*_):
        return Recognition("x^{2}", [], "openai")
    monkeypatch.setattr(recognition, "StreamingASR", FakeASR)
    monkeypatch.setattr(RecognitionProviders, "interpret", interpret)
    with api.websocket_connect("/v1/dictation") as ws:
        ws.send_json({"type": "start", "token": "test-pilot", "sessionId": "test", "provider": "scribe", "revision": 0})
        assert ws.receive_json()["type"] == "ready"
        ws.send_bytes(b"\0" * 4800)
        ws.send_json({"type": "stop"})
        assert ws.receive_json()["type"] == "transcript"
        proposal = ws.receive_json()
        assert proposal["latex"] == "x^{2}"
        ws.send_json({"type": "context", "latex": "x^{2}", "revision": 1, "source": "proposal"})
        assert ws.receive()["type"] == "websocket.close"
    assert closed == [True]


async def test_asr_commit_wire_and_cleanup(settings):
    class FakeSocket:
        def __init__(self):
            self.sent = []
            self.closed = False
        async def send(self, message):
            event = json.loads(message)
            self.sent.append(event)
            if event.get("commit"):
                asr._commit_done.set_result(None)
        async def close(self):
            self.closed = True
    asr = StreamingASR(settings, "scribe", "es")
    asr.socket = FakeSocket()
    await asr.send_audio(b"\0" * 4800)
    await asr.commit()
    await asr.commit()
    assert len(asr.socket.sent) == 2 and asr.socket.sent[1]["commit"] is True
    await asr.close()
    assert asr.socket.closed


@pytest.mark.parametrize("value", [r"\input{/etc/passwd}", "```latex x```", "x\0"])
def test_unsafe_display_markup_rejected(value):
    with pytest.raises(ProviderError):
        validate_proposal({"latex": value, "ambiguities": []})
