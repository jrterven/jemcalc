#!/usr/bin/env python3
"""Configure LAN TLS and debug-only pilot pairing without printing credentials."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--host', help='Mac LAN IPv4 address (default: en0)')
args = parser.parse_args()
host = args.host or subprocess.check_output(['ipconfig', 'getifaddr', 'en0'], text=True).strip()
try:
    from dotenv import dotenv_values
except ImportError:
    sys.exit('Run with server/.venv/bin/python after installing server requirements.')
values = dotenv_values(ROOT / 'server/.env')
if not values.get('PILOT_TOKEN'):
    sys.exit('Set a random PILOT_TOKEN in server/.env first. See server/.env.example.')
tls = ROOT / 'server/.tls'
if not (tls / 'cert.der').exists():
    subprocess.run([sys.executable, str(ROOT / 'server/scripts/make_dev_cert.py'), '--host', host], check=True)
else:
    info = subprocess.check_output(['openssl', 'x509', '-in', str(tls / 'cert.pem'), '-noout', '-text'], text=True)
    if f'IP Address:{host}' not in info and f'DNS:{host}' not in info:
        sys.exit('Existing TLS certificate does not cover this host. Move server/.tls aside to rotate it, then rerun setup.')
shutil.copyfile(tls / 'cert.der', ROOT / 'app/assets/pilot/server.der')
shutil.copyfile(tls / 'cert.pem', ROOT / 'app/assets/pilot/server.pem')
local = ROOT / '.local'
local.mkdir(exist_ok=True)
config = local / 'pilot.json'
config.write_text(json.dumps({'PILOT_URL': f'https://{host}:8443', 'PILOT_TOKEN': values['PILOT_TOKEN']}, indent=2) + '\n')
config.chmod(0o600)
print(f'Pilot configured: https://{host}:8443')
print('Provider keys remain on the Mac. Rebuild the app after rotating its TLS certificate.')
