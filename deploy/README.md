# Private production pilot

Website: **https://calc.jemailabs.com**. Android/iOS API URL: **https://calc.jemailabs.com/api**.

The owner chose a private pilot with a shared access password on 6 October 2026. The browser password is distinct from the native pilot token. The password is saved locally in ignored `.local/production-access.txt`; the browser receives only a signed seven-day HttpOnly, Secure, SameSite=Strict cookie. Provider credentials and the native token never enter the web build. This deployment does not add individual accounts, billing, server-side history or cross-device sync.

## Server layout

- SSH: `juan@prod` (`144.126.131.104`).
- `/home/juan/jemcalc/releases/<release>` contains allowlisted deployment files.
- `/home/juan/jemcalc/current` points to the active release.
- The download mount was added in configuration release `20261007-android-installer`, reusing the existing `20261006-pilot-3` application image.
- `/home/juan/jemcalc/shared/.env` contains production credentials, mode 600; each release's `deploy/.env` is a symlink to it.
- Active Compose project: `jemcalc`; container: `jemcalc-app-1`; image: `jemcalc:20261006-pilot-3` (absolute HTTPS access redirects).
- Backend listener: **127.0.0.1:5188**, forwarded to container port 8080. This port was checked unused before deployment.
- Nginx virtual host: `/etc/nginx/sites-available/calc.jemailabs.com.conf`, linked from `sites-enabled`. The repository copy is `deploy/calc.jemailabs.com.conf`.
- Cloudflare: proxied A record `calc` → `144.126.131.104`; TTL Auto; zone encryption remains **Full (strict)**. Nginx uses the existing Cloudflare Origin CA wildcard certificate for `*.jemailabs.com`. Keep the record proxied: the origin certificate is intended for Cloudflare, while visitors use Cloudflare's publicly trusted edge certificate.

Docker restarts the service automatically (`unless-stopped`). Nginx limits login attempts, API requests and concurrent connections. The container is non-root, has a read-only filesystem, bounded temporary storage, CPU/memory/process limits and bounded log rotation. The existing CAS process timeouts, two-worker capacity, upload limits and dictation duration limits remain active. This is a small private pilot, not an unrestricted public service.

## Private Android downloads

Compose mounts `/home/juan/jemcalc/shared/downloads` read-only at `/srv/web/downloads`. Only verified release APKs and their public checksums belong in this directory; never place tokens, provider credentials or signing material there. The existing web access boundary protects `/downloads/` with the same signed browser session as the calculator. Nginx has no public alias or authentication bypass for these files.

The first signed Android installer is `/downloads/jemcalc-1.0.0-2.apk`. Users sign in to the website and then reopen the download link. The APK contains only the public API URL; the native pilot token is entered once in the app's settings.

Signing material is private and excluded from Git: local `.local/android-signing/` plus `app/android/key.properties`. Keep a secure backup and reuse the same key for future updates. Neither the signing key nor the native token is uploaded with the APK. Each update must increase Android's build number. The Android release signature differs from the earlier debug/profile test installations.

To add a download, upload it under a temporary name, verify its SHA-256 on the server, then rename it to its final versioned filename. Existing downloads do not require restarting the app. The first addition of the Compose mount requires recreating only the Jem Calc container; create the shared directory beforehand with permissions allowing the non-root container to read its public artifacts.

## Validate and update

1. Run appropriate tests, including `cd server && .venv/bin/pytest tests/test_production.py tests/test_api.py tests/test_recognition.py` for gateway changes.
2. Build the shared Flutter web UI: `cd app && flutter build web --no-web-resources-cdn`. Never use a file containing tokens as web Dart defines.
3. Verify the web build contains none of the configured secrets. Package only `.dockerignore`, `deploy/Dockerfile`, `deploy/compose.yaml`, `deploy/calc.jemailabs.com.conf`, `server/jemcalc` (excluding Python caches), `server/pyproject.toml`, requirements files and `app/build/web`. Do not transfer the entire workspace or `.local`.
4. Upload to a **new** release directory under `/home/juan/jemcalc/releases`, and link `deploy/.env` to the shared env file. Keep the current release for rollback.
5. From that release directory, with the new release name in `JEMCALC_RELEASE`:

   ```sh
   JEMCALC_RELEASE=NEW_RELEASE docker compose -f deploy/compose.yaml --env-file deploy/.env build
   JEMCALC_RELEASE=NEW_RELEASE docker compose -f deploy/compose.yaml --env-file deploy/.env up -d --wait --wait-timeout 45
   ```

6. Verify `https://calc.jemailabs.com/api/health`, private-page redirects, unauthenticated API rejection, a native authenticated calculation, browser login, CAS, recognition and dictation. Then update `current` and the `JEMCALC_RELEASE` entry in the private env file to the verified release.
7. Change Nginx only if needed. Preserve its current file, install the new virtual-host file, run `sudo nginx -t`, and reload only after validation succeeds. Do not change other sites or stop their containers.

Production browser checks reuse the real Flutter test harness with a private file containing `{ "password": "..." }`:

```sh
JEM_WEB_URL=https://calc.jemailabs.com \
WEB_TEST_ACCESS_FILE=.local/production-access.json \
PLAYWRIGHT_MODULE=/absolute/path/to/playwright/index.mjs \
node scripts/test_web.mjs
```

Opt-in `WEB_TEST_PROVIDERS=1 WEB_TEST_AUDIO=/absolute/path/to/synthetic.wav` tests Mathpix and streaming voice using synthetic fixtures and Chromium fake media devices. Never capture real camera/microphone input for deployment checks.

Native clients use the public API URL with their existing pilot token in Settings. A public HTTPS certificate is trusted through the platform's standard roots. Existing local preferences override build-time defaults; installing a new binary alone does not migrate a saved LAN URL. A build may use ignored `.local/production.json`, which contains only the public API URL.

## Operate and recover

From `/home/juan/jemcalc/current` on `prod`:

```sh
docker compose -f deploy/compose.yaml --env-file deploy/.env ps
docker compose -f deploy/compose.yaml --env-file deploy/.env logs --tail 80 app
docker compose -f deploy/compose.yaml --env-file deploy/.env up -d --wait
```

Logs must never contain credentials, uploaded images, audio or calculation bodies. Nginx access logs are separate under `/var/log/nginx/calc.jemailabs.com.*.log`.

To roll back, run Compose from a known-good release directory with its image tag explicitly in `JEMCALC_RELEASE`, wait for health, then repoint `current` and update the env release entry. Only Jem Calc is recreated. No application history lives in the container: histories stay in each browser/device, and the new domain has a different history from localhost.

To rotate access, replace `WEB_ACCESS_PASSWORD` **and** `WEB_SESSION_SECRET` in the protected env file, then recreate the container. The new session secret invalidates all browser sessions. Native `PILOT_TOKEN` rotation is separate and requires updating the enrolled devices. Browser logout is an authenticated same-origin POST to `/access/logout`; clearing this site's cookies also removes the session from that browser.
