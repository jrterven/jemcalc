# Jem Calc backend

Private pilot gateway for a Flutter calculator. Python/SymPy computes mathematics deterministically; recognition providers only propose an editable equation. The wire format is in [the contract](../docs/contract.md).

## Install and test

From the repository root, using Python 3.11 or newer:

```sh
python3 -m venv server/.venv
server/.venv/bin/python -m pip install -e 'server[test]'
server/.venv/bin/python -m pytest server/tests
```

SymPy is pinned to 1.14.0. `requirements-lock.txt` records the complete environment validated during development; use it before installing the editable package when reproducing that environment.

Copy `.env.example` to `.env` only if `.env` does not already exist. Set a random `PILOT_TOKEN` and only the provider credentials you intend to use. `.env` and `.tls` are ignored by Git. Existing process environment values override `.env`. Restart the server after changing configuration. Never include provider API keys or the TLS private key in mobile assets, screenshots, logs or source control.

## Start on the Mac

Replace `192.168.1.20` with the Mac's LAN address. Keep both devices on the same network.

```sh
server/.venv/bin/python server/scripts/make_dev_cert.py --host 192.168.1.20
server/.venv/bin/python server/scripts/run_server.py --host 192.168.1.20
```

The endpoint is `https://192.168.1.20:8443`. The 30-day certificate is specific to the supplied address; generate a new certificate in a new directory if the address changes. The generator refuses to overwrite existing keys. Add **only `server/.tls/cert.der`** as a trusted public certificate to the pilot app's Dart `SecurityContext`; iOS requires DER. Never accept arbitrary invalid certificates. `key.pem` stays on the Mac. No router port forwarding is needed.

For tests running on this Mac only:

```sh
server/.venv/bin/python server/scripts/run_server.py --http-loopback --port 8000
```

The runner refuses cleartext HTTP on a LAN interface and refuses to start without a pilot token. `GET /health` is public and reveals only configured-provider booleans. All `/v1/calculate` and recognition REST requests use `Authorization: Bearer <pilot token>`. Dictation authenticates in its first WebSocket message. Enter the pilot token once in the app and retain it in secure device storage. iPad needs the local-network permission; see [backend notes](../docs/backend.md).

## Operational limits

- Maximum calculation request: 256 KiB, 512 AST nodes, depth 64.
- Exact numbers/results: 4096 digits; factorial 0–1000; positive root index 1–1000; integer exponent magnitude 16384 except bases −1, 0 and 1. Undefined arithmetic is rejected.
- CAS runs in a disposable process, two simultaneous calculations maximum. The default 10-second deadline includes process startup. Cancellation, timeout and client disconnect terminate that worker; no Python thread is left computing in the background.
- Linux additionally applies a 1 GiB address-space cap. macOS uses CPU/time and input/output bounds; it does not claim a hard resident-memory cap.
- Health does not probe or charge external services. Missing provider credentials return a service error; there are no fabricated fallback results.
- Calculations, media and audio are not persisted by this service. Access logs are disabled by the runner. Provider retention is governed separately by the provider account settings.

This is a private LAN pilot, not a public multi-tenant deployment. Stop it with Ctrl-C. When the Mac sleeps or leaves Wi-Fi, the app's local arithmetic and graphing remain available.
