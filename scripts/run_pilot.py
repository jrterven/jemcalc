#!/usr/bin/env python3
"""Start the configured private HTTPS server."""
import json
import os
from pathlib import Path
from urllib.parse import urlparse
ROOT = Path(__file__).resolve().parents[1]
config = ROOT / '.local/pilot.json'
if not config.is_file():
    raise SystemExit('Run scripts/setup_pilot.py first.')
url = urlparse(json.loads(config.read_text())['PILOT_URL'])
python = str(ROOT / 'server/.venv/bin/python')
os.execv(python, [python, str(ROOT / 'server/scripts/run_server.py'), '--host', url.hostname, '--port', str(url.port or 8443)])
