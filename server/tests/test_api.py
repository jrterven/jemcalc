import asyncio
import os

from fastapi.testclient import TestClient
import pytest

from jemcalc import auth, main
from jemcalc.config import Settings
from jemcalc.execution import CalculationRunner


PAYLOAD = {"ast": {"type": "number", "value": "1"}}


@pytest.fixture
def client(monkeypatch):
    settings = Settings(pilot_token="test-pilot-token-do-not-use")
    monkeypatch.setattr(main, "get_settings", lambda: settings)
    monkeypatch.setattr(auth, "get_settings", lambda: settings)
    with TestClient(main.app) as instance:
        yield instance


def test_health_has_booleans_and_never_secrets(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "providers": {"mathpix": False, "openai": False, "scribe": False}}
    assert "token" not in response.text


def test_calculation_auth_and_worker_response(client):
    assert client.post("/v1/calculate", json=PAYLOAD).status_code == 401
    assert client.post("/v1/calculate", json=PAYLOAD, headers={"Authorization": "Bearer wrong"}).status_code == 401
    result = client.post("/v1/calculate", json=PAYLOAD, headers={"Authorization": "Bearer test-pilot-token-do-not-use"})
    assert result.status_code == 200
    assert result.json()["text"] == "1"
    assert result.json()["engine"] == "sympy"


def test_missing_token_configuration_is_fail_closed(monkeypatch, client):
    monkeypatch.setattr(auth, "get_settings", lambda: Settings())
    assert client.post("/v1/calculate", json=PAYLOAD).status_code == 503


def test_invalid_ast_validation_does_not_echo_input(client):
    response = client.post("/v1/calculate", json={"ast": {"type": "number", "value": "private-invalid-content"}}, headers={"Authorization": "Bearer test-pilot-token-do-not-use"})
    assert response.status_code == 422
    assert "private-invalid-content" not in response.text


def test_http_body_limit(client):
    response = client.post("/v1/calculate", content=b" " * (256 * 1024 + 1), headers={"Authorization": "Bearer test-pilot-token-do-not-use", "Content-Type": "application/json"})
    assert response.status_code == 413


def test_deep_raw_json_is_rejected_before_parser_crashes(client):
    body = b'{"ast":' + b'[' * 2000 + b'0' + b']' * 2000 + b'}'
    response = client.post("/v1/calculate", content=body, headers={"Authorization": "Bearer test-pilot-token-do-not-use", "Content-Type": "application/json"})
    assert response.status_code == 422


def test_image_body_is_bounded_before_multipart_parsing(client):
    response = client.post("/v1/recognize/image", content=b" " * (9 * 1024 * 1024 + 1))
    assert response.status_code == 413


@pytest.mark.asyncio
async def test_worker_timeout_disposes_process():
    runner = CalculationRunner()
    answer = await runner.run(PAYLOAD, timeout=0.001)
    assert answer.status == "timeout"
    assert not runner.active_processes
    # The same runner remains usable after terminating a timed-out process.
    assert (await runner.run(PAYLOAD)).text == "1"


@pytest.mark.asyncio
async def test_cancelled_request_disposes_process():
    runner = CalculationRunner()
    task = asyncio.create_task(runner.run(PAYLOAD))
    for _ in range(100):
        if runner.active_processes:
            break
        await asyncio.sleep(0.002)
    assert runner.active_processes
    pid = next(iter(runner.active_processes)).pid
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert not runner.active_processes
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


@pytest.mark.asyncio
async def test_client_disconnect_cancels_worker():
    class Disconnected:
        async def is_disconnected(self):
            return True
    runner = CalculationRunner()
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as error:
        await runner.run(PAYLOAD, request=Disconnected())
    assert error.value.status_code == 499
    assert not runner.active_processes
