#!/usr/bin/env node
// Regression: a remembered Solve selection must not turn arithmetic into = 0.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
const {chromium} = process.env.PLAYWRIGHT_MODULE
  ? await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href)
  : createRequire(import.meta.url)('playwright');
const browser = await chromium.launch({channel: 'chrome', headless: true});
const base = process.env.JEM_WEB_URL || 'http://localhost:5187';
const out = 'output/playwright';
await mkdir(out, {recursive: true});
const results = [];
try {
  for (const colorScheme of ['light', 'dark']) {
    const context = await browser.newContext({
      viewport: {width: 390, height: 844}, colorScheme, hasTouch: true,
      permissions: ['clipboard-read', 'clipboard-write'],
    });
    const page = await context.newPage();
    page.setDefaultTimeout(20000);
    const errors = [], requests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => {
      if (request.url().endsWith('/api/v1/calculate')) requests.push(request);
    });
    const button = name => page.getByRole('button', {name, exact: true});
    try {
      await page.goto(base);
      if (new URL(page.url()).pathname === '/access') {
        const {password} = JSON.parse(await readFile(process.env.WEB_TEST_ACCESS_FILE, 'utf8'));
        await page.getByLabel('Clave de acceso').fill(password);
        await button('Entrar').click();
        await page.waitForURL(url => url.pathname === '/');
      }
      await page.locator('iframe').waitFor();
      const frame = await (await page.locator('iframe').first().elementHandle()).contentFrame();
      await frame.waitForURL('**/editor/index.html');
      const semantics = page.locator('flt-semantics-placeholder');
      if (await semantics.count()) await semantics.evaluate(el => el.click());
      await button('Resolver').waitFor();
      await frame.waitForFunction(() => typeof window.setDraft === 'function');
      await button('Calcular').click();
      await page.getByRole('menuitem', {name: 'Resolver', exact: true}).click();
      for (const label of ['1', '8', '.', '3', '3', '×', '1', '2']) {
        await frame.locator(`.MLK__layer.is-visible [aria-label=${JSON.stringify(label)}]`).click();
      }
      assert.equal(await frame.locator('#mf').evaluate(el => el.value), '18.33\\times12');
      // Once loaded, arithmetic must work even with the entire network offline.
      await context.setOffline(true);
      await button('Resolver').last().click();
      await frame.getByText('Exacto', {exact: true}).waitFor();
      await frame.getByRole('button',{name:'Copiar resultado',exact:true}).click();
      for(let attempt=0;attempt<40;attempt++) {
        if(await page.evaluate(()=>navigator.clipboard.readText())==='\\frac{5499}{25}')break;
        await page.waitForTimeout(50);
      }
      assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'\\frac{5499}{25}');
      assert.equal(requests.length, 0, 'numeric arithmetic must stay local');
      assert.equal(await frame.getByText('Sin solución real', {exact: true}).count(), 0);
      await page.screenshot({path: `${out}/numeric-solve-${colorScheme}.png`});
      await context.setOffline(false);

      if (process.env.WEB_TEST_OFFLINE_ONLY !== '1') {
        await frame.evaluate(() => {
          window.setDraft('x+1=2');
          document.getElementById('mf').dispatchEvent(new Event('input', {bubbles: true}));
        });
        const [response] = await Promise.all([
          page.waitForResponse(r => r.url().endsWith('/api/v1/calculate')),
          button('Resolver').last().click(),
        ]);
        assert.equal(response.status(), 200);
        assert.equal(response.request().postDataJSON().operation, 'solve');
        assert.equal((await response.json()).text, '{1}');
        await frame.getByRole('button',{name:'Copiar resultado',exact:true}).waitFor();
      }

      if (process.env.WEB_TEST_NUMERIC_API === '1') {
        // Older APKs still submit operation=solve for the screenshot's input.
        const response = await context.request.post(`${base}/api/v1/calculate`, {
          headers: {Origin: base},
          data: {operation: 'solve', ast: {type: 'binary', op: '*',
            left: {type: 'number', value: '18.33'}, right: {type: 'number', value: '12'}}},
        });
        assert.equal(response.status(), 200);
        const answer = await response.json();
        assert.equal(answer.status, 'exact');
        assert.equal(answer.text, '5499/25');
      }
      assert.deepEqual(errors, []);
      results.push({colorScheme, offlineProduct: '5499/25 = 219.96', equation: process.env.WEB_TEST_OFFLINE_ONLY === '1' ? 'not requested' : 'x+1=2 → {1}'});
    } catch (error) {
      await page.screenshot({path: `${out}/numeric-solve-failure.png`});
      await writeFile(`${out}/numeric-solve-failure.html`, await page.content());
      throw error;
    } finally {
      await context.close();
    }
  }
  await writeFile(`${out}/numeric-solve-results.json`, JSON.stringify({base, results}, null, 2));
  console.log(JSON.stringify({base, results}, null, 2));
} finally {
  await browser.close();
}
