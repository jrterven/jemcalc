#!/usr/bin/env python3
"""Start the LAN pilot over HTTPS; HTTP is explicitly limited to loopback."""

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import uvicorn
from jemcalc.config import get_settings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8443)
    parser.add_argument("--cert", type=Path, default=ROOT / ".tls" / "cert.pem")
    parser.add_argument("--key", type=Path, default=ROOT / ".tls" / "key.pem")
    parser.add_argument("--http-loopback", action="store_true", help="Development tests on this Mac only")
    args = parser.parse_args()
    if not get_settings().pilot_token:
        parser.error("Set PILOT_TOKEN in server/.env before starting the pilot")
    if args.http_loopback:
        if args.host not in ("127.0.0.1", "::1", "localhost"):
            parser.error("Unencrypted HTTP is only allowed on loopback")
        tls = {}
    else:
        if not args.cert.is_file() or not args.key.is_file():
            parser.error("Generate a certificate with scripts/make_dev_cert.py first")
        tls = {"ssl_certfile": str(args.cert), "ssl_keyfile": str(args.key)}
    uvicorn.run("jemcalc.main:app", host=args.host, port=args.port, access_log=False, log_level="info", proxy_headers=False, **tls)


if __name__ == "__main__":
    main()
