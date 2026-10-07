import os
from pathlib import Path
import subprocess
import sys


SERVER = Path(__file__).resolve().parents[1]


def test_certificate_has_san_and_does_not_overwrite(tmp_path):
    command = [sys.executable, str(SERVER / "scripts/make_dev_cert.py"), "--host", "127.0.0.1", "--output", str(tmp_path)]
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "cert.der").is_file()
    assert (tmp_path / "key.pem").stat().st_mode & 0o077 == 0
    san = subprocess.check_output(["openssl", "x509", "-in", str(tmp_path / "cert.pem"), "-noout", "-ext", "subjectAltName"], text=True)
    assert "127.0.0.1" in san
    original = (tmp_path / "key.pem").read_bytes()
    assert subprocess.run(command, capture_output=True).returncode != 0
    assert (tmp_path / "key.pem").read_bytes() == original


def test_runner_refuses_cleartext_lan():
    env = dict(os.environ, PILOT_TOKEN="test-pilot-token")
    result = subprocess.run([sys.executable, str(SERVER / "scripts/run_server.py"), "--host", "0.0.0.0", "--http-loopback"], env=env, capture_output=True, text=True)
    assert result.returncode != 0
    assert "only allowed on loopback" in result.stderr


def test_certificate_hostname_validation(tmp_path):
    result = subprocess.run([sys.executable, str(SERVER / "scripts/make_dev_cert.py"), "--host", "bad,IP:0.0.0.0", "--output", str(tmp_path)], capture_output=True)
    assert result.returncode != 0
    assert not (tmp_path / "key.pem").exists()
