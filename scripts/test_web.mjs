#!/usr/bin/env node
// Full Flutter web build, real browser, IndexedDB and local CAS proxy.
// Camera/microphone use Chromium's synthetic devices, never physical devices.
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
const output = resolve('output/playwright');
await mkdir(output, { recursive: true });
const { chromium } = process.env.PLAYWRIGHT_MODULE
  ? await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href)
  : createRequire(import.meta.url)('playwright');
const browser = await chromium.launch({ channel: 'chrome', headless: true,
  args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
    ...(process.env.WEB_TEST_AUDIO ? [`--use-file-for-fake-audio-capture=${resolve(process.env.WEB_TEST_AUDIO)}`] : [])] });
const context = await browser.newContext({ viewport: { width: 1200, height: 850 } });
context.setDefaultTimeout(15000);
const page = await context.newPage();
const errors = [], results = [];
const voice = { received: [], audioBytes: 0 };
page.on('websocket', ws => {
  if (!ws.url().includes('/v1/dictation')) return;
  ws.on('framereceived', event => {
    if (typeof event.payload === 'string') voice.received.push(JSON.parse(event.payload));
  });
  ws.on('framesent', event => {
    if (Buffer.isBuffer(event.payload)) voice.audioBytes += event.payload.length;
  });
});
page.on('pageerror', error => errors.push(error.message));
const origin = process.env.JEM_WEB_URL || 'http://localhost:5187';
const access = process.env.WEB_TEST_ACCESS_FILE
  ? JSON.parse(await readFile(process.env.WEB_TEST_ACCESS_FILE, 'utf8')) : null;
const button = name => page.getByRole('button', { name, exact: true });
const frame = () => page.frames().find(f => f.url().includes('/editor/index.html'));
const body = () => page.locator('body').innerText();
async function start() {
  await page.goto(origin);
  if (new URL(page.url()).pathname === '/access') {
    assert(access?.password, 'Private deployment needs WEB_TEST_ACCESS_FILE');
    await page.getByLabel('Clave de acceso').fill(access.password);
    await page.getByRole('button', { name: 'Entrar', exact: true }).click();
    await page.waitForURL(url => url.pathname === '/');
  }
  await page.locator('iframe').waitFor();
  const semantics = page.locator('flt-semantics-placeholder');
  if (await semantics.count()) await semantics.evaluate(el => el.click());
  await button('Resolver').waitFor();
  await frame().waitForFunction(() => typeof mathVirtualKeyboard !== 'undefined' && mathVirtualKeyboard.visible);
}
async function type(expression) {
  await button('Nueva ecuación').click();
  await frame().waitForFunction(() => document.getElementById('mf').value === '');
  await page.waitForTimeout(350);
  await frame().locator('#mf').evaluate(el => el.focus());
  await frame().waitForFunction(() => document.getElementById('mf').shadowRoot.activeElement?.getAttribute('part') === 'keyboard-sink');
  await page.keyboard.type(expression);
  await page.waitForTimeout(250);
}
async function check(name, fn) {
  if (process.env.WEB_TEST_ONLY && !name.includes(process.env.WEB_TEST_ONLY)) return;
  await fn();
  results.push({ name, status: 'passed' });
  console.log(`PASS ${name}`);
}
async function crop() {
  const target = button('Recortar');
  await target.waitFor();
  await page.waitForTimeout(400);
  // Flutter's modal semantics barrier may overlap its buttons in the DOM.
  // Use a real pointer at the visible button, exercising Flutter's hit testing.
  const box = await target.boundingBox();
  await page.mouse.click(box.x + box.width/2, box.y + box.height/2);
}
try {
  await start();
  await check('virtual keyboard and local calculation', async () => {
    // A remote iframe can finish loading after Flutter exposes its controls.
    // Focus the actual MathLive input before sending the first virtual key.
    await frame().locator('#mf').evaluate(el => el.focus());
    await frame().waitForFunction(() => document.getElementById('mf').shadowRoot.activeElement?.getAttribute('part') === 'keyboard-sink');
    let expected = '';
    for (const label of ['1', '+', '2']) {
      await frame().locator(`.MLK__layer.is-visible [aria-label=${JSON.stringify(label)}]`).click();
      expected += label;
      await frame().waitForFunction(value => document.getElementById('mf').value === value, expected);
    }
    await button('Resolver').click();
    await page.getByText('Exacto', { exact: true }).waitFor();
    assert((await body()).includes('3'));
  });
  await check('symbolic equation through TLS backend proxy', async () => {
    await type('x+1=2');
    const [r] = await Promise.all([
      page.waitForResponse(r => r.url().endsWith('/api/v1/calculate'), { timeout: 45000 }),
      button('Resolver').click(),
    ]);
    assert.equal(r.status(), 200);
    const data = await r.json();
    assert.equal(data.latex, '\\left\\{1\\right\\}');
    assert.equal(data.verification.status, 'verified');
    await button('Copiar resultado').waitFor();
  });
  await check('graphs hide/show without deleting and survive reload', async () => {
    await type('x^2');
    await button('Graficar').click();
    const first = page.getByRole('checkbox').first();
    await first.waitFor();
    assert.equal(await first.isChecked(), true);
    await first.click();
    await page.waitForTimeout(250);
    assert.equal(await first.isChecked(), false);
    assert.equal(await button('Eliminar ecuación').count(), 1);
    await page.screenshot({ path: join(output, 'web-graph-hidden.png') });
    await button('Añadir desde el editor').click();
    await type('x');
    await button('Graficar').click();
    await page.getByRole('checkbox').nth(1).waitFor();
    assert.equal(await page.getByRole('checkbox').count(), 2);
    assert.equal(await first.isChecked(), false);
    await page.waitForTimeout(800);
    await start();
    // Current curve is deduplicated; opening it again retains both entries.
    await button('Graficar').click();
    await page.getByRole('checkbox').nth(1).waitFor();
    assert.equal(await page.getByRole('checkbox').count(), 2);
    assert.equal(await first.isChecked(), false);
    await first.click();
    await page.waitForTimeout(250);
    await button('Eliminar ecuación').last().click();
    await page.waitForTimeout(250);
    assert.equal(await page.getByRole('checkbox').count(), 1);
    await page.screenshot({ path: join(output, 'web-graph.png') });
    await button('Añadir desde el editor').click();
    await button('Resolver').waitFor();
    await page.waitForTimeout(350);
    assert((await body()).includes('3'));
    assert((await body()).includes('1'));
  });
  await check('handwriting strokes and keyboard restoration', async () => {
    await button('Escribir Escribir').click();
    const canvas = page.getByText(/Lienzo para escribir una ecuación/).locator('..');
    const box = await canvas.boundingBox();
    assert(box);
    const strokes = [ [[0,0],[1,1]], [[0,1],[1,0]], [[1.5,.5],[2.3,.5]], [[1.9,.1],[1.9,.9]],
      [[2.8,0],[2.8,1]], [[3.4,.3],[4.2,.3]], [[3.4,.7],[4.2,.7]], [[4.8,0],[4.8,1]] ];
    const scale = Math.min(box.width/7, box.height/3);
    for (const line of strokes) {
      await page.mouse.move(box.x+scale*(1+line[0][0]), box.y+scale*(1+line[0][1]));
      await page.mouse.down();
      for (const p of line.slice(1)) await page.mouse.move(box.x+scale*(1+p[0]), box.y+scale*(1+p[1]), { steps: 10 });
      await page.mouse.up();
    }
    assert.equal(await button('Deshacer').isEnabled(), true);
    await page.screenshot({ path: join(output, 'web-ink.png') });
    if (process.env.WEB_TEST_PROVIDERS === '1') {
      const [r] = await Promise.all([
        page.waitForResponse(r => r.url().endsWith('/api/v1/recognize/ink'), { timeout: 45000 }),
        button('Reconocer ecuación').click(),
      ]);
      assert.equal(r.status(), 200);
      const proposal = await r.json();
      assert(proposal.latex.length > 0);
      console.log('INK', proposal.latex);
      await page.waitForTimeout(500);
    }
    await button('Teclado Teclado').click();
    await frame().waitForFunction(() => typeof mathVirtualKeyboard !== 'undefined' && mathVirtualKeyboard.visible);
  });
  await check('web camera capture and crop', async () => {
    await button('Cámara Cámara').click();
    await button('Capturar').click();
    await button('Recortar').waitFor();
    await page.screenshot({ path: join(output, 'web-camera-crop.png') });
    await crop();
    await button('Repetir').waitFor();
    await button('Repetir').click();
    // Generate a reproducible test equation locally; no personal image is used.
    const data = await page.evaluate(() => {
      const canvas = document.createElement('canvas'); canvas.width=900; canvas.height=300;
      const ctx=canvas.getContext('2d'); ctx.fillStyle='white';ctx.fillRect(0,0,900,300);
      ctx.fillStyle='black';ctx.font='72px Arial';ctx.textAlign='center';ctx.fillText('x + 1 = 2',450,180);
      return canvas.toDataURL('image/png').split(',')[1];
    });
    const path=join(output, 'web-equation-fixture.png');
    await writeFile(path, Buffer.from(data, 'base64'));
    const [chooser] = await Promise.all([page.waitForEvent('filechooser'), button('Abrir imagen').click()]);
    await chooser.setFiles(path);
    await crop();
    await button('Repetir').waitFor();
    if (process.env.WEB_TEST_PROVIDERS === '1') {
      const [r] = await Promise.all([
        page.waitForResponse(r => r.url().endsWith('/api/v1/recognize/image'), { timeout: 45000 }),
        button('Reconocer').click(),
      ]);
      assert.equal(r.status(), 200);
      const proposal = await r.json();
      assert(proposal.latex.replaceAll(' ', '').includes('x+1=2'));
      await page.waitForTimeout(500);
      await page.screenshot({ path: join(output, 'web-photo-proposal.png') });
    }
    await button('Teclado Teclado').click();
  });
  if (process.env.WEB_TEST_PROVIDERS === '1') {
    await check('voice PCM stream and editable equation from synthetic speech', async () => {
      assert(process.env.WEB_TEST_AUDIO, 'Supply a synthetic WAV with WEB_TEST_AUDIO');
      await button('Nueva ecuación').click();
      await button('Voz Voz').click();
      await button('Comenzar dictado').click();
      await button('Terminar dictado').waitFor({ timeout: 25000 });
      await page.waitForTimeout(7000);
      await button('Terminar dictado').click();
      await button('Comenzar dictado').waitFor({ timeout: 30000 });
      assert(voice.received.some(e => e.type === 'ready'));
      assert(voice.audioBytes > 24000, `PCM bytes: ${voice.audioBytes}`);
      const proposals = voice.received.filter(e => e.type === 'proposal');
      assert(proposals.length > 0, JSON.stringify(voice.received));
      assert(proposals.some(p => p.latex.toLowerCase().replaceAll(' ', '').includes('x+1=2')));
      assert.equal(voice.received.some(e => e.type === 'error'), false);
      await page.screenshot({ path: join(output, 'web-voice.png') });
      await button('Teclado Teclado').click();
      await frame().waitForFunction(() => typeof mathVirtualKeyboard !== 'undefined' && mathVirtualKeyboard.visible);
    });
  }
  await check('compact browser viewport', async () => {
    await page.screenshot({ path: join(output, 'web-desktop.png') });
    await page.setViewportSize({ width: 360, height: 800 });
    await frame().waitForFunction(() => typeof mathVirtualKeyboard !== 'undefined' && mathVirtualKeyboard.visible);
    await frame().locator('.MLK__layer.is-visible').getByText('Científico', { exact: true }).click();
    await page.waitForTimeout(300);
    await page.screenshot({ path: join(output, 'web-mobile.png') });
    assert.equal(await button('Resolver').isVisible(), true);
  });
  } catch (error) {
  results.push({ status: 'failed', message: error.stack });
  console.log(await body());
  await page.screenshot({ path: join(output, 'web-failure.png') });
  await writeFile(join(output, 'web-failure-dom.html'), await page.locator('body').innerHTML());
  process.exitCode = 1;
} finally {
  if (errors.length) process.exitCode = 1;
  await writeFile(join(output, 'web-results.json'), JSON.stringify({ results, errors,
    voice: { audioBytes: voice.audioBytes, receivedTypes: voice.received.map(e => e.type) } }, null, 2));
  await browser.close();
}
