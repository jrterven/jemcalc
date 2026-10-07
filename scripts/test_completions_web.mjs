#!/usr/bin/env node
// Full Flutter app + real MathLive. Fixtures enter through the editor input bridge.
// No recognition providers or physical microphone/camera are used.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const { chromium } = await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href);
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
const page = await context.newPage();
page.setDefaultTimeout(20000);
const out = 'output/playwright';
await mkdir(out, {recursive:true});
const results = [], errors = [];
page.on('pageerror', error => errors.push(error.message));
const base = process.env.JEM_WEB_URL || 'http://localhost:5187';
const button = name => page.getByRole('button', {name, exact:true});
const frame = () => page.frames().find(f => f.url().includes('/editor/index.html'));
const math = f => f.locator('#mf');
const value = f => math(f).evaluate(el => el.value);
const key = (f,label) => f.locator(`.MLK__layer.is-visible [aria-label=${JSON.stringify(label)}]`);
async function input(latex) {
  await frame().evaluate(latex => {
    window.setDraft(latex);
    document.getElementById('mf').dispatchEvent(new Event('input', {bubbles:true}));
  }, latex);
}
async function check(name, fn) { await fn(); results.push(name); console.log('PASS',name); }
try {
  await page.goto(base);
  if (new URL(page.url()).pathname === '/access') {
    const access = JSON.parse(await readFile(process.env.WEB_TEST_ACCESS_FILE, 'utf8'));
    await page.getByLabel('Clave de acceso').fill(access.password);
    await button('Entrar').click();
    await page.waitForURL(url => url.pathname === '/');
  }
  await page.locator('iframe').waitFor();
  const initialFrame = await (await page.locator('iframe').first().elementHandle()).contentFrame();
  await initialFrame.waitForURL('**/editor/index.html');
  const toggle = page.locator('flt-semantics-placeholder');
  if (await toggle.count()) await toggle.evaluate(el=>el.click());
  await button('Resolver').waitFor();
  await frame().waitForFunction(() => typeof window.setDraft === 'function');
  await check('integral hint requires a tap and CAS calculates 1/3 only on Resolve', async () => {
    await input('\\int_0^1 x^2');
    await button('Añadir dx').waitFor();
    assert.equal(await value(frame()), '\\int_0^1 x^2');
    await page.screenshot({path:out+'/completion-integral-mobile.png'});
    await button('Añadir dx').click();
    await frame().waitForFunction(() => document.getElementById('mf').value.includes('\\mathrm{d}x'));
    const [response] = await Promise.all([
      page.waitForResponse(r=>r.url().endsWith('/api/v1/calculate')),
      button('Resolver').click(),
    ]);
    assert.equal(response.status(),200);
    assert.equal((await response.json()).text,'1/3');
  });
  await check('missing denominator opens and focuses its slot, then computes 1/2', async () => {
    await input('\\frac{1}{}');
    await button('Completar').click();
    await frame().waitForFunction(() => lastFocusRequest === 1);
    await frame().waitForFunction(() => mf.shadowRoot.activeElement?.getAttribute('part') === 'keyboard-sink');
    await key(frame(),'2').click();
    await frame().waitForFunction(() => document.getElementById('mf').value === '\\frac12');
    await button('Resolver').click();
    await page.getByText('Exacto',{exact:true}).waitFor();
    assert.equal(await button('Completar').count(),0);
    await page.screenshot({path:out+'/completion-fraction-mobile.png'});
  });
  await check('multiple integral variables remain explicit choices', async () => {
    await input('\\int xy');
    await button('Añadir dx').waitFor();
    await button('Añadir dy').click();
    await frame().waitForFunction(() => document.getElementById('mf').value.endsWith('\\mathrm{d}y'));
  });
  await check('voice-mode completion opens manual sheet, retains mode and fills exponent', async () => {
    await button('Voz Voz').click();
    await input('x^{}');
    await button('Completar').click();
    await page.waitForFunction(() => document.querySelectorAll('iframe').length === 2);
    const modal = await (await page.locator('iframe').last().elementHandle()).contentFrame();
    await modal.waitForURL('**/editor/index.html');
    await modal.waitForFunction(() => lastFocusRequest === 2);
    await modal.waitForFunction(() => mf.shadowRoot.activeElement?.getAttribute('part') === 'keyboard-sink');
    await key(modal,'3').click();
    await modal.waitForFunction(() => document.getElementById('mf').value === 'x^3');
    await button('Cerrar').click();
    await button('Comenzar dictado').waitFor();
    assert.equal(await value(frame()),'x^3');
    await page.screenshot({path:out+'/completion-voice-mobile.png'});
    await button('Teclado Teclado').click();
    await key(frame(),'1').waitFor();
  });
  await check('limit destination is editable and all keyboard labels fit', async () => {
    await input('\\lim_{x\\to} x^2');
    await button('Completar').click();
    await frame().waitForFunction(() => lastFocusRequest === 3);
    await frame().waitForFunction(() => mf.shadowRoot.activeElement?.getAttribute('part') === 'keyboard-sink');
    await key(frame(),'0').click();
    await frame().waitForFunction(() => document.getElementById('mf').value.includes('\\to0'));
    await frame().locator('.MLK__layer.is-visible .MLK__toolbar').getByText('Cálculo',{exact:true}).click();
    for (const label of ['dx','dy','dz','dt']) assert(await key(frame(),label).isVisible());
    await page.screenshot({path:out+'/completion-calculus-mobile.png'});
    await page.setViewportSize({width:1200,height:850});
    await input('\\int xy');
    await button('Añadir dy').waitFor();
    await page.screenshot({path:out+'/completion-desktop.png'});
  });
  assert.deepEqual(errors,[]);
  await writeFile(out+'/completion-web-results.json',JSON.stringify({results,errors,base},null,2));
} catch(error) {
  await page.screenshot({path:out+'/completion-failure.png'});
  await writeFile(out+'/completion-failure.txt',await page.locator('body').innerText());
  await writeFile(out+'/completion-failure.html',await page.content());
  throw error;
} finally { await browser.close(); }
