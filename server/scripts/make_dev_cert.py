#!/usr/bin/env python3
"""Generate a local development certificate without overwriting existing keys."""

import argparse
import ipaddress
from pathlib import Path
import subprocess
import os


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, help="LAN IP address or DNS hostname of the Mac")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / ".tls")
    args = parser.parse_args()
    host = args.host
    try:
        ipaddress.ip_address(host)
        san = f"IP:{host}"
    except ValueError:
        import re
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}", host):
            parser.error("Host must be an IP address or a DNS hostname")
        san = f"DNS:{host}"
    args.output.mkdir(parents=True, exist_ok=True)
    key, cert, der = (args.output / name for name in ("key.pem", "cert.pem", "cert.der"))
    if any(path.exists() for path in (key, cert, der)):
        parser.error("Certificate files already exist; use a new output directory to rotate them")
    previous_umask = os.umask(0o077)
    try:
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "30", "-nodes", "-keyout", str(key), "-out", str(cert), "-subj", "/CN=Jem Calc private pilot", "-addext", f"subjectAltName={san}", "-addext", "extendedKeyUsage=serverAuth"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["openssl", "x509", "-in", str(cert), "-outform", "der", "-out", str(der)], check=True)
    finally:
        os.umask(previous_umask)
    print(f"Created development certificate in {args.output.resolve()}")
    print("cert.pem and cert.der are public. Never copy key.pem to a mobile app.")


if __name__ == "__main__":
    main()
