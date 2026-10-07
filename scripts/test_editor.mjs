#!/usr/bin/env node
// Real Chromium + the checked-in MathLive bundle. No application logic is mocked.
// JemBridge only records the messages that Flutter normally receives.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, realpath } from 'node:fs/promises';
import { dirname, extname, join, resolve, sep } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const assetRoot = await realpath(join(root, 'app/assets'));
const output = join(root, 'output/playwright');
await mkdir(output, { recursive: true });
let chromium;
try {
  if (process.env.PLAYWRIGHT_MODULE) {
    ({ chromium } = await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href));
  } else {
    ({ chromium } = createRequire(import.meta.url)('playwright'));
  }
} catch {
  console.error('Use an already installed Playwright: PLAYWRIGHT_MODULE=/absolute/path/playwright/index.mjs node scripts/test_editor.mjs');
  process.exit(2);
}

const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }
    const target = await realpath(join(assetRoot, pathname));
    if (!target.startsWith(assetRoot + sep)) throw new Error('outside assets');
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff' };
    res.writeHead(200, { 'Content-Type': types[extname(target)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(await readFile(target));
  } catch {
    res.writeHead(404); res.end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
// Use the installed Chrome channel by default; this script never downloads browsers.
const browser = await chromium.launch({ headless: true,
  ...(process.env.PLAYWRIGHT_BROWSER_EXECUTABLE
    ? { executablePath: process.env.PLAYWRIGHT_BROWSER_EXECUTABLE }
    : { channel: process.env.PLAYWRIGHT_BROWSER_CHANNEL || 'chrome' }),
}).catch(async error => {
  await new Promise(resolve => server.close(resolve));
  throw error;
});
const results = [];
const externalRequests = [];
const errors = [];
const context = await browser.newContext({ viewport: { width: 360, height: 560 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true });
context.setDefaultTimeout(10000);
await context.route('**/*', route => {
  const url = route.request().url();
  if (!url.startsWith(origin + '/') && !url.startsWith('data:')) {
    externalRequests.push(url);
    return route.abort();
  }
  return route.continue();
});
await context.addInitScript(() => {
  window.jemEvents = [];
  window.JemBridge = { postMessage: text => window.jemEvents.push(JSON.parse(text)) };
});
const page = await context.newPage();
page.on('pageerror', e => errors.push(e.message));

async function check(name, run) {
  try { const details = await run(); results.push({ name, status: 'passed', ...(details ? { details } : {}) }); }
  catch (e) { results.push({ name, status: 'failed', message: e.message }); }
}
// CSS labels come from the inspected real MathLive accessibility tree.
const visibleKey = label => page.locator(`.MLK__layer.is-visible [aria-label=${JSON.stringify(label)}]`);
const toolbar = () => page.locator('.MLK__layer.is-visible .MLK__toolbar');
const value = () => page.locator('#mf').evaluate(el => el.value);
const submits = () => page.evaluate(() => jemEvents.filter(e => e.type === 'submit').length);
async function config(patch = {}) {
  const wanted = { dark: false, language: 'es', keyboard: true, ...patch };
  await page.evaluate(c => window.configure(c), wanted);
  await page.waitForFunction(expected => mathVirtualKeyboard.visible === expected, wanted.keyboard);
}
async function scientificTab() {
  await toolbar().getByText('Científico', { exact: true }).click();
  await visibleKey('\\sin').waitFor({ state: 'visible' });
}

try {
  await check('bundled assets load without any external network', async () => {
    await page.goto(origin + '/editor/index.html');
    await page.waitForFunction(() => typeof window.configure === 'function' && customElements.get('math-field'));
    await config({ latex: '' });
    await page.waitForFunction(() => mathVirtualKeyboard.visible);
    await page.locator('#keyboard .MLK__keycap').first().waitFor({ state: 'visible' });
    await page.screenshot({ path: join(output, 'editor-mobile.png') });
    assert.equal(externalRequests.length, 0);
    assert.deepEqual(errors, []);
    assert(await page.evaluate(() => jemEvents.some(e => e.type === 'ready')));
    return { mathlive: JSON.parse(await readFile(join(assetRoot, 'mathlive/package.json'), 'utf8')).version };
  });

  await check('virtual number keys insert 1+2 and submit once', async () => {
    await page.evaluate(() => window.setDraft(''));
    for (const label of ['1', '+', '2']) await visibleKey(label).click();
    assert.equal(await value(), '1+2');
    const before = await submits();
    await scientificTab();
    await visibleKey('↵').click();
    assert.equal(await submits() - before, 1);
  });

  await check('physical Enter submits exactly once', async () => {
    await page.locator('#mf').evaluate(el => el.focus());
    const before = await submits();
    await page.keyboard.press('Enter');
    assert.equal(await submits() - before, 1);
  });

  await check('both editable surfaces request no native IME and retain physical input after refocus', async () => {
    const inputs = await page.locator('#mf').evaluate(el => {
      const sink = el.shadowRoot.querySelector('[part=keyboard-sink]');
      return { host: el.inputMode, sink: sink?.inputMode, editable: el.isContentEditable && sink?.isContentEditable };
    });
    assert.deepEqual(inputs, { host: 'none', sink: 'none', editable: true });
    await page.evaluate(() => {
      window.setDraft('');
      const other = document.createElement('button');
      other.id = 'focus-test';
      other.textContent = 'Other focus target';
      document.body.append(other);
      other.focus();
    });
    await page.waitForFunction(() => !document.getElementById('mf').hasFocus());
    await page.locator('#mf').evaluate(el => el.focus());
    await page.waitForFunction(() => {
      const field = document.getElementById('mf');
      return field.shadowRoot.activeElement?.getAttribute('part') === 'keyboard-sink';
    });
    await page.locator('#focus-test').evaluate(el => el.remove());
    await page.keyboard.type('x+1=2');
    assert.equal(await value(), 'x+1=2');
    const before = await submits();
    await page.keyboard.press('Enter');
    assert.equal(await submits() - before, 1);
  });

  await check('C clears the expression', async () => {
    await toolbar().getByText('Básico', { exact: true }).click();
    await page.evaluate(() => window.setDraft('123+4'));
    await visibleKey('C').click();
    assert.equal(await value(), '');
  });

  await check('scientific tab survives configure updates and typing', async () => {
    await scientificTab();
    await config({ latex: 'x+1', dark: true });
    assert(await visibleKey('\\sin').isVisible());
    await visibleKey('x').click();
    await config({ latex: await value() });
    assert(await visibleKey('\\sin').isVisible());
  });

  await check('hide and restore keeps draft and selected keyboard tab', async () => {
    await page.evaluate(() => window.setDraft('x^{2}+1'));
    const before = await value();
    await config({ keyboard: false });
    assert.equal(await page.evaluate(() => mathVirtualKeyboard.visible), false);
    assert.equal(await page.locator('#keyboard').isVisible(), false);
    await config({ keyboard: true });
    assert.equal(await value(), before);
    assert.equal(await page.evaluate(() => mathVirtualKeyboard.visible), true);
    assert(await visibleKey('\\sin').isVisible());
  });

  await check('restore after a short handwriting viewport preserves input and tab', async () => {
    await config({ keyboard: false });
    await page.setViewportSize({ width: 304, height: 120 });
    await config({ latex: 'y=2x+1', keyboard: false });
    await page.setViewportSize({ width: 304, height: 400 });
    await config({ keyboard: true });
    assert.equal(await value(), 'y=2x+1');
    await visibleKey('x').click();
    assert((await value()).endsWith('x'));
    assert(await visibleKey('\\sin').isVisible());
  });

  await check('restore an unexpectedly hidden keyboard even if the requested mode did not change', async () => {
    await page.evaluate(() => mathVirtualKeyboard.hide({ animate: false }));
    assert.equal(await page.evaluate(() => mathVirtualKeyboard.visible), false);
    await config({ keyboard: true });
    assert(await visibleKey('\\sin').isVisible());
  });

  await check('scientific inverse labels fit their keys and insert inverse functions', async () => {
    await page.setViewportSize({ width: 304, height: 400 });
    await scientificTab();
    for (const [label, latex] of [['sin⁻¹', '\\arcsin'], ['cos⁻¹', '\\arccos'], ['tan⁻¹', '\\arctan']]) {
      const key = visibleKey(label);
      const size = await key.evaluate(el => {
        const range = document.createRange(); range.selectNodeContents(el);
        return { content: range.getBoundingClientRect().width, key: el.getBoundingClientRect().width };
      });
      assert(size.content <= size.key - 6, JSON.stringify({ label, ...size }));
      await page.evaluate(() => window.setDraft(''));
      await key.click();
      assert.equal(await value(), latex);
    }
    await page.screenshot({ path: join(output, 'editor-scientific-mobile.png') });
  });


  await check('calculus differentials fit on mobile and append to a dictated integral', async () => {
    await toolbar().getByText('Cálculo', { exact: true }).click();
    for (const variable of ['x', 'y', 'z', 't']) {
      await page.evaluate(v => window.setDraft('\\int ' + v + '^2'), variable);
      const before = await page.evaluate(() => jemEvents.filter(e => e.type === 'input').length);
      const key = visibleKey('d' + variable);
      await key.click();
      const latex = await value();
      assert(latex.includes('\\mathrm{d}' + variable), latex);
      await page.waitForFunction(before => jemEvents.filter(e => e.type === 'input').length > before, before);
      const fit = await key.evaluate(el => {
        const r = document.createRange(); r.selectNodeContents(el);
        return r.getBoundingClientRect().width < el.getBoundingClientRect().width - 6;
      });
      assert(fit);
    }
    assert.equal(await page.locator('.MLK__layer.is-visible .MLK__row').count(), 5);
    await page.screenshot({ path: join(output, 'editor-calculus-differentials.png') });
  });

  await check('confirmed missing denominator focuses its slot; later configure preserves caret', async () => {
    await toolbar().getByText('Básico', { exact: true }).click();
    await config({ latex: '\\frac{1}{\\placeholder{}}', focusRequest: 1 });
    await visibleKey('2').click();
    assert.equal(await value(), '\\frac12');
    await config({ focusRequest: 1 });
    await visibleKey('3').click();
    assert.equal(await value(), '\\frac{1}{23}');
  });

  await check('multiple empty slots focus the first, and explicit completion focuses the next', async () => {
    await config({ latex: '\\frac{\\placeholder{}}{\\placeholder{}}', focusRequest: 2 });
    await visibleKey('1').click();
    assert.equal(await value(), '\\frac{1}{\\placeholder{}}');
    await config({ focusRequest: 3 });
    await visibleKey('2').click();
    assert.equal(await value(), '\\frac12');
  });

  await check('hidden editor does not consume the slot-focus request', async () => {
    await config({ keyboard: false, latex: 'x^{\\placeholder{}}', focusRequest: 4 });
    await config({ keyboard: true, focusRequest: 4 });
    await visibleKey('2').click();
    assert.equal(await value(), 'x^2');
  });

  await check('host setDraft never echoes an input event', async () => {
    const before = await page.evaluate(() => jemEvents.filter(e => e.type === 'input').length);
    await page.evaluate(() => window.setDraft('y+9'));
    assert.equal(await value(), 'y+9');
    assert.equal(await page.evaluate(() => jemEvents.filter(e => e.type === 'input').length), before);
  });

  await check('language switching and repeated configure preserve interaction', async () => {
    await config({ language: 'en' });
    await toolbar().getByText('Scientific', { exact: true }).waitFor({ state: 'visible' });
    await config({ language: 'es' });
    await toolbar().getByText('Básico', { exact: true }).click();
    await page.evaluate(() => window.setDraft(''));
    await visibleKey('7').click();
    assert.equal(await value(), '7');
  });

  for (const size of [{ width: 304, height: 380 }, { width: 360, height: 560 }, { width: 768, height: 560 }]) {
    await check(`touch targets fill the four-column keyboard at ${size.width}x${size.height}`, async () => {
      await page.setViewportSize(size);
      const boxes = await page.locator('.MLK__layer.is-visible .MLK__row').first().locator('.MLK__keycap').evaluateAll(els => els.map(el => {
        const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height };
      }));
      assert.equal(boxes.length, 4);
      assert(boxes.every(b => b.width >= 62 && b.height >= 44 && b.height <= 50), JSON.stringify(boxes));
      const occupied = boxes.at(-1).x + boxes.at(-1).width - boxes[0].x;
      assert(occupied >= size.width * .8, `Only ${occupied}px of ${size.width}px occupied`);
      return { key: boxes[0], rowWidth: occupied };
    });
  }
  await check('no JavaScript errors or external asset requests', async () => {
    assert.deepEqual(errors, []);
    assert.deepEqual(externalRequests, []);
  });
  await page.setViewportSize({ width: 360, height: 560 });
  await page.screenshot({ path: join(output, 'editor-final.png') });
  console.log(JSON.stringify({ results, externalRequests, javascriptErrors: errors }, null, 2));
  if (results.some(r => r.status !== 'passed')) process.exitCode = 1;
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
