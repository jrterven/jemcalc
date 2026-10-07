#!/usr/bin/env python3
"""Run a supplied, labeled recognition corpus through the actual Jem Calc gateway.

Default is validation only. --run performs paid provider calls via the configured
server. This harness supplies no corpus and claims no mathematical equivalence.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import time
import uuid
import wave
from pathlib import Path

import httpx
from dotenv import load_dotenv
from websockets.asyncio.client import connect

ROOT = Path(__file__).resolve().parents[1]


def manifest(path: Path) -> list[dict]:
    raw = json.loads(path.read_text())
    if not isinstance(raw, list) or not raw:
        raise ValueError("Manifest must be a nonempty JSON array")
    ids = set()
    rows = []
    for row in raw:
        if not isinstance(row, dict) or set(row) - {"id", "kind", "file", "language", "expected_latex", "providers"}:
            raise ValueError("Invalid manifest fields")
        if not isinstance(row.get("id"), str) or row["id"] in ids:
            raise ValueError("Every case needs a unique string id")
        ids.add(row["id"])
        kind = row.get("kind")
        allowed = {"image": ["mathpix", "openai"], "ink": ["mathpix"], "voice": ["scribe", "openai"]}
        if kind not in allowed:
            raise ValueError("Case kind must be image, ink, or voice")
        source = (path.parent / row["file"]).resolve()
        if not source.is_file():
            raise ValueError(f"Missing source for {row['id']}")
        row = dict(row, file=str(source))
        row["providers"] = row.get("providers", allowed[kind])
        if not row["providers"] or any(p not in allowed[kind] for p in row["providers"]):
            raise ValueError("Invalid providers for case kind")
        if row.get("language", "es") not in {"es", "en"}:
            raise ValueError("Language must be es or en")
        if "expected_latex" in row and not isinstance(row["expected_latex"], str):
            raise ValueError("expected_latex must be a string")
        if kind == "voice":
            with wave.open(str(source), "rb") as wav:
                if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getcomptype()) != (1, 2, 24000, "NONE"):
                    raise ValueError("Voice fixtures must be uncompressed WAV PCM16 mono 24000 Hz")
                if not 0 < wav.getnframes() / 24000 <= 120:
                    raise ValueError("Voice fixtures must contain audio and not exceed 120 seconds")
        elif kind == "ink":
            ink = json.loads(source.read_text())
            if not isinstance(ink, dict) or not isinstance(ink.get("strokes"), list):
                raise ValueError("Ink fixture must contain a strokes array")
        elif source.stat().st_size > 8 * 1024 * 1024:
            raise ValueError("Image fixture exceeds 8 MiB")
        rows.append(row)
    return rows


def literal_match(actual: str, expected: str | None) -> bool | None:
    # Only whitespace is ignored. This is deliberately not a CAS equivalence test.
    if expected is None:
        return None
    return re.sub(r"\s+", "", actual) == re.sub(r"\s+", "", expected)


async def voice(base: str, token: str, case: dict, provider: str) -> dict:
    url = re.sub(r"^http", "ws", base.rstrip("/")) + "/v1/dictation"
    with wave.open(case["file"], "rb") as wav:
        audio = wav.readframes(wav.getnframes())
    started = time.monotonic()
    result = {"latex": "", "first_transcript_ms": None, "first_proposal_ms": None, "final_proposal_after_audio_ms": None}
    audio_end = None
    revision = 0
    session = str(uuid.uuid4())
    async with connect(url, max_size=1024 * 1024, open_timeout=15) as ws:
        await ws.send(json.dumps({"type": "start", "token": token, "sessionId": session,
            "provider": provider, "language": case.get("language", "es"), "latex": "", "revision": 0}))
        ready = json.loads(await asyncio.wait_for(ws.recv(), 30))
        if ready.get("type") != "ready":
            raise RuntimeError(ready.get("code", "session_failed"))

        async def receive():
            nonlocal revision
            async for raw in ws:
                event = json.loads(raw)
                elapsed = round((time.monotonic() - started) * 1000)
                if event.get("type") == "error":
                    raise RuntimeError(event.get("code", "recognition_failed"))
                if event.get("type") == "transcript" and result["first_transcript_ms"] is None:
                    result["first_transcript_ms"] = elapsed
                if event.get("type") == "proposal" and event.get("baseRevision") == revision:
                    result["latex"] = event["latex"]
                    if result["first_proposal_ms"] is None:
                        result["first_proposal_ms"] = elapsed
                    if audio_end is not None:
                        result["final_proposal_after_audio_ms"] = round((time.monotonic() - audio_end) * 1000)
                    revision += 1
                    await ws.send(json.dumps({"type": "context", "latex": event["latex"], "revision": revision,
                        "source": "proposal", "segmentId": event["segmentId"]}))

        listener = asyncio.create_task(receive())
        try:
            audio_start = time.monotonic()
            for offset in range(0, len(audio), 4800):
                if listener.done():
                    listener.result()
                    raise RuntimeError("session_closed_before_audio_completed")
                await ws.send(audio[offset:offset + 4800])
                await asyncio.sleep(max(0, audio_start + (offset + 4800) / 48000 - time.monotonic()))
            audio_end = time.monotonic()
            await ws.send(json.dumps({"type": "stop"}))
            await asyncio.wait_for(listener, 60)
        finally:
            listener.cancel()
            await asyncio.gather(listener, return_exceptions=True)
    result["audio_seconds"] = round(len(audio) / 48000, 3)
    if not result["latex"]:
        raise RuntimeError("no_proposal_received")
    return result


async def run(cases: list[dict], base: str, token: str) -> list[dict]:
    results = []
    async with httpx.AsyncClient(base_url=base.rstrip("/"), headers={"Authorization": f"Bearer {token}"}, timeout=60) as client:
        for case in cases:
            for provider in case["providers"]:
                started = time.monotonic()
                row = {"id": case["id"], "kind": case["kind"], "provider": provider}
                try:
                    if case["kind"] == "voice":
                        row.update(await voice(base, token, case, provider))
                    else:
                        if case["kind"] == "ink":
                            payload = json.loads(Path(case["file"]).read_text())
                            response = await client.post("/v1/recognize/ink", json={"strokes": payload["strokes"], "revision": 0})
                        else:
                            with open(case["file"], "rb") as source:
                                response = await client.post("/v1/recognize/image", files={"image": (Path(case["file"]).name, source)},
                                    data={"provider": provider, "revision": "0"})
                        if response.status_code >= 400:
                            raise RuntimeError(f"http_{response.status_code}")
                        row.update(response.json())
                    row.update(status="ok", literal_match=literal_match(row["latex"], case.get("expected_latex")))
                except (httpx.HTTPError, RuntimeError, OSError, ValueError, asyncio.TimeoutError) as exc:
                    # Avoid logging response bodies, headers, signed URLs, or token values.
                    row.update(status="failed", error_type=type(exc).__name__)
                row["duration_ms"] = round((time.monotonic() - started) * 1000)
                results.append(row)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--run", action="store_true", help="Send the supplied corpus; this incurs provider charges")
    parser.add_argument("--output", type=Path, help="Save JSON results instead of printing them")
    args = parser.parse_args()
    try:
        cases = manifest(args.manifest.resolve())
        if not args.run:
            print(json.dumps({"mode": "validation_only", "cases": len(cases), "planned_provider_calls": sum(len(c["providers"]) for c in cases)}))
            return
        load_dotenv(ROOT / "server" / ".env", override=False)
        token = os.getenv("PILOT_TOKEN", "")
        if not token:
            raise ValueError("Configure PILOT_TOKEN in the environment or server/.env")
        results = asyncio.run(run(cases, args.base_url, token))
        output = json.dumps({"measurement": "literal_latex_match_whitespace_ignored", "results": results}, ensure_ascii=False, indent=2)
        if args.output:
            args.output.write_text(output + "\n")
        else:
            print(output)
        if any(r["status"] == "failed" for r in results):
            sys.exit(1)
    except (ValueError, OSError, KeyError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
