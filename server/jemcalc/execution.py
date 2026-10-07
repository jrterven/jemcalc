"""Disposable CAS processes, bounded concurrency and cooperative HTTP cancellation."""

from __future__ import annotations

import asyncio
import math
import multiprocessing as mp
import sys
import time
from typing import Any

from fastapi import HTTPException, Request
import sympy as sp

from .models import CalculateResponse


def _worker_entry(connection: Any, payload: dict[str, Any], timeout: float) -> None:
    try:
        try:
            import resource
            seconds = max(1, math.ceil(timeout) + 1)
            resource.setrlimit(resource.RLIMIT_CPU, (seconds, seconds))
            # RLIMIT_AS is not a reliable process memory budget on macOS.
            if sys.platform.startswith("linux"):
                resource.setrlimit(resource.RLIMIT_AS, (1024**3, 1024**3))
        except (ImportError, OSError, ValueError):
            pass
        from .cas import calculate_payload
        connection.send(calculate_payload(payload))
    finally:
        connection.close()


class CalculationRunner:
    def __init__(self, capacity: int = 2):
        self._slots = asyncio.Semaphore(capacity)
        self._context = mp.get_context("spawn")
        self.active_processes: set[mp.Process] = set()

    async def run(self, payload: dict[str, Any], timeout: float = 10, request: Request | None = None) -> CalculateResponse:
        try:
            await asyncio.wait_for(self._slots.acquire(), timeout=0.1)
        except TimeoutError:
            raise HTTPException(503, "Calculation capacity is busy; retry shortly")
        receiver, sender = self._context.Pipe(duplex=False)
        process = self._context.Process(target=_worker_entry, args=(sender, payload, timeout), daemon=True)
        started = False
        try:
            process.start()
            started = True
            sender.close()
            self.active_processes.add(process)
            deadline = time.monotonic() + timeout
            while True:
                if receiver.poll():
                    try:
                        response = receiver.recv()
                    except EOFError:
                        return CalculateResponse(status="error", text="Calculation worker stopped before returning a result", engineVersion=sp.__version__)
                    return CalculateResponse.model_validate(response)
                if time.monotonic() >= deadline:
                    return CalculateResponse(status="timeout", text="Calculation exceeded the time limit", engineVersion=sp.__version__)
                if not process.is_alive():
                    return CalculateResponse(status="error", text="Calculation worker stopped before returning a result", engineVersion=sp.__version__)
                if request is not None and await request.is_disconnected():
                    raise HTTPException(499, "Calculation cancelled by client")
                await asyncio.sleep(0.02)
        finally:
            # A Python task timeout alone does not stop CPU-bound SymPy work.
            # Every exit path, including cancellation, destroys its worker.
            sender.close()
            receiver.close()
            if started:
                if process.is_alive():
                    process.terminate()
                await asyncio.to_thread(process.join, 0.5)
                if process.is_alive():
                    process.kill()
                    await asyncio.to_thread(process.join, 0.5)
                self.active_processes.discard(process)
                process.close()
            self._slots.release()

    async def close(self) -> None:
        for process in list(self.active_processes):
            if process.is_alive():
                process.terminate()
            await asyncio.to_thread(process.join, 0.5)
