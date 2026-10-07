#!/usr/bin/env python3
"""Loopback-only web pilot: Flutter files + authenticated TLS proxy on port 5187."""
import argparse
import asyncio
from contextlib import asynccontextmanager, suppress
import json
from pathlib import Path
import socket
import ssl
from urllib.parse import urlsplit

import httpx
import uvicorn
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from starlette.responses import Response
from starlette.staticfiles import StaticFiles
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, WebSocketException

ROOT = Path(__file__).resolve().parents[1]
PORT = 5187
MAX_BODY = 9 * 1024 * 1024
ROUTES = {('/health', 'GET'), ('/v1/calculate', 'POST'),
          ('/v1/recognize/ink', 'POST'), ('/v1/recognize/image', 'POST')}


def trusted_request(headers, port=PORT):
    hosts = {f'localhost:{port}', f'127.0.0.1:{port}'}
    origins = {f'http://{host}' for host in hosts}
    return (headers.get('host') in hosts
            and headers.get('origin') in (None, *origins)
            and headers.get('sec-fetch-site') != 'cross-site')


def create_app(static_dir: Path, upstream: str, token: str, tls: ssl.SSLContext,
               *, port=PORT, transport=None):
    parsed = urlsplit(upstream)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('The private backend must use HTTPS.')
    if not token:
        raise ValueError('Missing private pilot token.')
    upstream = upstream.rstrip('/')

    @asynccontextmanager
    async def lifespan(app):
        async with httpx.AsyncClient(verify=tls, transport=transport, trust_env=False,
                                    timeout=40, follow_redirects=False) as client:
            app.state.client = client
            yield

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware('http')
    async def local_only(request: Request, call_next):
        if not trusted_request(request.headers, port):
            return JSONResponse({'detail': 'Local same-origin access required'}, status_code=403)
        response = await call_next(request)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-Frame-Options'] = 'SAMEORIGIN'
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.api_route('/api/{path:path}', methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'])
    async def proxy(path: str, request: Request):
        path = '/' + path
        if (path, request.method) not in ROUTES:
            return JSONResponse({'detail': 'Unknown API route'}, status_code=404)
        chunks, size = [], 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > MAX_BODY:
                return JSONResponse({'detail': 'Request too large'}, status_code=413)
            chunks.append(chunk)
        headers = {'Authorization': f'Bearer {token}'}
        if 'content-type' in request.headers:
            headers['Content-Type'] = request.headers['content-type']
        try:
            result = await app.state.client.request(request.method, upstream + path,
                                                    headers=headers, content=b''.join(chunks))
        except httpx.HTTPError:
            return JSONResponse({'detail': 'El servidor privado no está disponible.'}, status_code=502)
        return Response(result.content, status_code=result.status_code,
                        media_type=result.headers.get('content-type', 'application/json'))

    @app.websocket('/api/v1/dictation')
    async def dictation(browser: WebSocket):
        if not trusted_request(browser.headers, port):
            await browser.close(code=1008)
            return
        await browser.accept()
        tasks = []
        try:
            # No token is delivered to or accepted from the browser in the local pilot.
            first = await asyncio.wait_for(browser.receive_json(), timeout=10)
            if not isinstance(first, dict) or first.get('type') != 'start':
                await browser.close(code=1008)
                return
            first['token'] = token
            endpoint = 'wss://' + parsed.netloc + parsed.path.rstrip('/') + '/v1/dictation'
            async with connect(endpoint, ssl=tls, open_timeout=12, max_size=1024*1024,
                               proxy=None) as remote:
                await remote.send(json.dumps(first))

                async def send_audio():
                    while True:
                        message = await browser.receive()
                        if message['type'] == 'websocket.disconnect':
                            return
                        data = message.get('bytes')
                        if data is None:
                            data = message.get('text', '')
                        if len(data) > 1024*1024:
                            await browser.close(code=1009)
                            return
                        await remote.send(data)

                async def receive_transcript():
                    async for message in remote:
                        if isinstance(message, bytes):
                            await browser.send_bytes(message)
                        else:
                            await browser.send_text(message)

                tasks = [asyncio.create_task(send_audio()), asyncio.create_task(receive_transcript())]
                await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        except (WebSocketDisconnect, ConnectionClosed):
            pass
        except (OSError, TimeoutError, ValueError, httpx.HTTPError, WebSocketException):
            with suppress(RuntimeError, WebSocketDisconnect):
                await browser.send_json({'type': 'error', 'message': 'No se pudo conectar el dictado.'})
        finally:
            for task in tasks:
                task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            with suppress(RuntimeError, WebSocketDisconnect):
                await browser.close()

    app.mount('/', StaticFiles(directory=static_dir, html=True), name='web')
    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify configuration and port without starting')
    args = parser.parse_args()
    static_dir = ROOT / 'app/build/web'
    if not (static_dir / 'index.html').is_file():
        raise SystemExit('Build first: cd app && flutter build web --no-web-resources-cdn')
    config = json.loads((ROOT / '.local/pilot.json').read_text())
    tls = ssl.create_default_context(cafile=str(ROOT / 'app/assets/pilot/server.pem'))
    app = create_app(static_dir, config['PILOT_URL'], config['PILOT_TOKEN'], tls)
    # Keep ownership of the socket after checking; never kill or replace another service.
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.bind(('127.0.0.1', PORT))
    except OSError:
        sock.close()
        raise SystemExit(f'Port {PORT} is occupied. Inspect lsof -nP -iTCP:{PORT} -sTCP:LISTEN; do not stop another project.')
    if args.check:
        sock.close()
        print(f'Configuration ready; localhost:{PORT} is free.')
        return
    print(f'Jem Calc web: http://localhost:{PORT}')
    server = uvicorn.Server(uvicorn.Config(app, log_level='warning', ws_max_size=MAX_BODY))
    try:
        asyncio.run(server.serve(sockets=[sock]))
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()


if __name__ == '__main__':
    main()
