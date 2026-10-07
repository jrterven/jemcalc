"""Authenticated recognition routes and revision-safe live dictation coordination."""
from __future__ import annotations

import asyncio
import contextlib
import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .auth import require_pilot_token, token_is_valid
from .config import get_settings
from .providers import Recognition, RecognitionProviders, StreamingASR, Transcript, ProviderError, clean_latex, require_key

router = APIRouter()


class Stroke(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)
    x: list[float] = Field(min_length=1, max_length=10000)
    y: list[float] = Field(min_length=1, max_length=10000)

    @field_validator("x", "y", mode="before")
    @classmethod
    def coordinates(cls, values):
        if not isinstance(values, list) or any(isinstance(v, bool) or not isinstance(v, (int, float)) or abs(v) > 1e7 for v in values):
            raise ValueError("Coordinates must be finite bounded numbers")
        return values

    @model_validator(mode="after")
    def matching(self):
        if len(self.x) != len(self.y):
            raise ValueError("Stroke coordinate arrays must have equal length")
        return self


class InkRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    strokes: list[Stroke] = Field(min_length=1, max_length=256)
    revision: int = Field(ge=0, strict=True)

    @model_validator(mode="after")
    def point_limit(self):
        if sum(len(s.x) for s in self.strokes) > 20000:
            raise ValueError("At most 20000 ink points per expression")
        return self


def _rest_error(exc: ProviderError) -> HTTPException:
    return HTTPException(exc.status, {"code": exc.code, "message": exc.message})


@router.post("/v1/recognize/ink", dependencies=[Depends(require_pilot_token)])
async def recognize_ink(request: InkRequest):
    try:
        result = await RecognitionProviders(get_settings()).ink([s.model_dump() for s in request.strokes])
        return result.payload(request.revision)
    except ProviderError as exc:
        raise _rest_error(exc) from exc


def image_mime(data: bytes) -> str:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    raise ProviderError("Use a PNG, JPEG, or WebP image.", "invalid_image", 415)


@router.post("/v1/recognize/image", dependencies=[Depends(require_pilot_token)])
async def recognize_image(image: Annotated[UploadFile, File()], revision: Annotated[int, Form(ge=0)],
                          provider: Annotated[Literal["mathpix", "openai"], Form()] = "mathpix"):
    try:
        content = await image.read(get_settings().max_image_bytes + 1)
        if len(content) > get_settings().max_image_bytes:
            raise ProviderError("Image exceeds 8 MiB.", "input_too_large", 413)
        result = await RecognitionProviders(get_settings()).image(content, image_mime(content), provider)
        return result.payload(revision)
    except ProviderError as exc:
        raise _rest_error(exc) from exc
    finally:
        await image.close()


@dataclass(frozen=True)
class IssuedProposal:
    revision: int
    latex: str
    fingerprint: tuple


class DraftCoordinator:
    """Rebuild from a stable base, never append a segment to its own earlier draft.

The client is authoritative for accepted document revisions. Manual contexts start
a new audio epoch; late ASR and interpretation results from the previous one cannot
modify it. Acknowledged provisional proposals retain the original base so later
partial revisions replace, rather than duplicate, their spoken segment.
"""
    def __init__(self, session_id: str, latex: str, revision: int, language: str,
                 interpret: Callable[[str, list[dict], str], Awaitable[Recognition]],
                 emit: Callable[[dict], Awaitable[None]], debounce: float = .4):
        self.session_id, self.latex, self.revision = session_id, latex, revision
        self.language, self.interpret, self.emit, self.debounce = language, interpret, emit, debounce
        self.base_latex = latex
        self.epoch = 0
        self.segments: dict[str, Transcript] = {}
        self.issued: list[IssuedProposal] = []
        self.generation = 0
        self.task: asyncio.Task | None = None
        self._tasks: set[asyncio.Task] = set()
        self.closed = False
        self.accepted_fingerprint: tuple | None = None
        self.context_changed = asyncio.Event()
        self._dirty_partial = False

    def fingerprint(self):
        return tuple((s.segment_id, s.text, s.final) for s in sorted(self.segments.values(), key=lambda s: s.order))

    def _invalidate(self):
        self.generation += 1
        if self.task is not None:
            self.task.cancel()
        self.task = None

    def _schedule(self, final: bool):
        self._invalidate()
        generation = self.generation
        self._dirty_partial = False

        async def run():
            try:
                if not final:
                    await asyncio.sleep(self.debounce)
                revision, fingerprint = self.revision, self.fingerprint()
                base = self.base_latex
                segments = [dict(text=s.text, final=s.final) for s in sorted(self.segments.values(), key=lambda s: s.order)]
                segment_id = max(self.segments.values(), key=lambda s: s.order).segment_id
                self._dirty_partial = False
                proposal = await self.interpret(base, segments, self.language)
                if self.closed or generation != self.generation or revision != self.revision:
                    return
                self.issued.append(IssuedProposal(revision, proposal.latex, fingerprint))
                self.issued = self.issued[-32:]
                await self.emit({"type": "proposal", "latex": proposal.latex,
                    "ambiguities": proposal.ambiguities, "baseRevision": revision,
                    "segmentId": segment_id, "sessionId": self.session_id})
            except asyncio.CancelledError:
                return
            except ProviderError as exc:
                if not self.closed and generation == self.generation:
                    await self.emit({"type": "error", "code": exc.code, "message": exc.message})

        self.task = asyncio.create_task(run())
        self._tasks.add(self.task)
        self.task.add_done_callback(self._tasks.discard)

        def completed(task):
            if self.task is task and self._dirty_partial and not self.closed:
                self._schedule(final=False)
        self.task.add_done_callback(completed)

    async def transcript(self, event: Transcript):
        if self.closed or event.epoch != self.epoch:
            return
        old = self.segments.get(event.segment_id)
        if old and (old.final or old == event):
            return
        if len(self.segments) >= 256 and event.segment_id not in self.segments:
            raise ProviderError("Dictation session is too long. Start another session.", "session_limit", 422)
        self.segments[event.segment_id] = event
        if sum(len(s.text) for s in self.segments.values()) > 16000:
            raise ProviderError("Dictation transcript is too long.", "session_limit", 422)
        await self.emit({"type": "transcript", "text": event.text, "final": event.final,
                         "segmentId": event.segment_id, "sessionId": self.session_id})
        if any(s.text.strip() for s in self.segments.values()):
            if not event.final and self.task is not None and not self.task.done():
                # Coalesce while one request runs. Repeated partials must not keep
                # cancelling every request and starve the live formula indefinitely.
                self._dirty_partial = True
            else:
                self._schedule(event.final)

    async def context(self, latex: str, revision: int, source: str | None = None) -> bool:
        """Return True if this is a manual edit requiring an ASR audio barrier."""
        if revision <= self.revision:
            if revision == self.revision and latex == self.latex:
                return False
            raise ProviderError("Context revision must increase.", "stale_revision", 409)
        if source not in {None, "manual", "proposal"}:
            raise ProviderError("Invalid context source.", "invalid_message", 422)
        accepted = None if source == "manual" else next((p for p in reversed(self.issued) if p.revision == revision - 1 and p.latex == latex), None)
        if source == "proposal" and accepted is None:
            raise ProviderError("Proposal acknowledgment does not match an issued draft.", "stale_revision", 409)
        self._invalidate()
        self.latex, self.revision = latex, revision
        self.issued.clear()
        self.context_changed.set()
        if accepted is not None:
            self.accepted_fingerprint = accepted.fingerprint
            if self.segments and self.fingerprint() != accepted.fingerprint:
                self._schedule(final=True)
            return False
        self.base_latex = latex
        self.accepted_fingerprint = None
        self.epoch += 1
        self.segments.clear()
        return True

    async def flush(self):
        while self.task is not None and not self.task.done():
            task = self.task
            await task

    async def settle(self):
        """Wait briefly for the final proposal's ACK while the socket still reads context."""
        while True:
            self.context_changed.clear()
            await self.flush()
            if not self.issued or self.accepted_fingerprint == self.fingerprint():
                return
            try:
                await asyncio.wait_for(self.context_changed.wait(), 3)
            except asyncio.TimeoutError:
                return

    async def close(self):
        self.closed = True
        self._invalidate()
        for task in tuple(self._tasks):
            task.cancel()
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)


def _revision(value: Any) -> int:
    if type(value) is not int or value < 0 or value > 2**53 - 1:
        raise ProviderError("Invalid document revision.", "invalid_message", 422)
    return value


def _json_message(raw: Any) -> dict:
    if not isinstance(raw, str) or len(raw) > 24000:
        raise ProviderError("Invalid dictation message.", "invalid_message", 422)
    try:
        message = json.loads(raw)
    except ValueError as exc:
        raise ProviderError("Invalid dictation JSON.", "invalid_message", 422) from exc
    if not isinstance(message, dict):
        raise ProviderError("Expected a dictation object.", "invalid_message", 422)
    return message


@router.websocket("/v1/dictation")
async def dictation(socket: WebSocket):
    await socket.accept()
    coordinator: DraftCoordinator | None = None
    tasks: set[asyncio.Task] = set()
    send_lock = asyncio.Lock()

    async def emit(event: dict):
        async with send_lock:
            await socket.send_json(event)

    try:
        first = await asyncio.wait_for(socket.receive(), 10)
        message = _json_message(first.get("text"))
        if message.get("type") != "start" or not token_is_valid(message.get("token", "")):
            await emit({"type": "error", "code": "unauthorized", "message": "Invalid pilot token."})
            await socket.close(code=4401)
            return
        session_id = message.get("sessionId")
        provider, language = message.get("provider", "scribe"), message.get("language", "es")
        if not isinstance(session_id, str) or not 1 <= len(session_id) <= 128 or language not in {"es", "en"} or provider not in {"scribe", "openai"}:
            raise ProviderError("Invalid dictation session settings.", "invalid_message", 422)
        settings = get_settings()
        require_key(settings.openai_api_key, "OpenAI interpreter")
        providers = RecognitionProviders(settings)
        coordinator = DraftCoordinator(session_id, clean_latex(message.get("latex", "")),
            _revision(message.get("revision", 0)), language, providers.interpret, emit)
        async with StreamingASR(settings, provider, language) as asr:
            await emit({"type": "ready", "sessionId": session_id})

            async def upstream():
                async for event in asr.events():
                    await coordinator.transcript(event)

            async def downstream():
                audio_bytes = 0
                finish_task: asyncio.Task | None = None
                receive_task: asyncio.Task | None = None

                async def finish():
                    await asr.commit()
                    await asr.drain()
                    await coordinator.settle()

                try:
                    while True:
                        receive_task = asyncio.create_task(socket.receive())
                        if finish_task is not None:
                            done, _ = await asyncio.wait({receive_task, finish_task}, return_when=asyncio.FIRST_COMPLETED)
                            if receive_task not in done:
                                finish_task.result()
                                return
                        packet = await receive_task
                        if packet["type"] == "websocket.disconnect":
                            return
                        if packet.get("bytes") is not None:
                            if finish_task is not None:
                                raise ProviderError("Audio cannot follow stop.", "invalid_message", 422)
                            audio = packet["bytes"]
                            audio_bytes += len(audio)
                            if audio_bytes > settings.max_audio_seconds * 48000:
                                raise ProviderError("Dictation reached the two-minute session limit.", "session_limit", 422)
                            await asr.send_audio(audio)
                            continue
                        msg = _json_message(packet.get("text"))
                        kind = msg.get("type")
                        if kind == "context":
                            manual = await coordinator.context(clean_latex(msg.get("latex")), _revision(msg.get("revision")), msg.get("source"))
                            if manual:
                                if finish_task is None:
                                    await asr.edit_barrier(coordinator.epoch)
                        elif kind == "commit":
                            if finish_task is None:
                                await asr.commit()
                        elif kind == "stop":
                            if finish_task is None:
                                finish_task = asyncio.create_task(finish())
                        else:
                            raise ProviderError("Unknown dictation message.", "invalid_message", 422)
                finally:
                    pending = [task for task in (receive_task, finish_task) if task is not None]
                    for task in pending:
                        task.cancel()
                    await asyncio.gather(*pending, return_exceptions=True)

            tasks = {asyncio.create_task(upstream()), asyncio.create_task(downstream())}
            done, _ = await asyncio.wait(tasks, timeout=settings.max_audio_seconds + 30,
                                         return_when=asyncio.FIRST_COMPLETED)
            if not done:
                raise ProviderError("Dictation session timed out.", "session_limit", 422)
            for task in done:
                task.result()
    except WebSocketDisconnect:
        pass
    except ProviderError as exc:
        with contextlib.suppress(RuntimeError, WebSocketDisconnect):
            await emit({"type": "error", "code": exc.code, "message": exc.message})
    except asyncio.TimeoutError:
        with contextlib.suppress(RuntimeError, WebSocketDisconnect):
            await emit({"type": "error", "code": "timeout", "message": "Dictation session timed out."})
    finally:
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        if coordinator:
            await coordinator.close()
        with contextlib.suppress(RuntimeError, WebSocketDisconnect):
            await socket.close()
