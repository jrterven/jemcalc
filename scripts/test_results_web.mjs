#!/usr/bin/env node
// Real Flutter/MathLive: result presentation must never reposition the keys.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=process.env.PLAYWRIGHT_MODULE
  ? await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href)
  : createRequire(import.meta.url)('playwright');
const base=process.env.JEM_WEB_URL||'http://localhost:5187';
const out='output/playwright';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true});
const results=[];
try {
 for(const colorScheme of ['light','dark']) {
  const context=await browser.newContext({viewport:{width:390,height:844},colorScheme,hasTouch:true,permissions:['clipboard-read','clipboard-write']});
  const page=await context.newPage();page.setDefaultTimeout(20000);
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  const button=name=>page.getByRole('button',{name,exact:true});
  try {
   await page.goto(base);
   if(new URL(page.url()).pathname==='/access') {
    const {password}=JSON.parse(await readFile(process.env.WEB_TEST_ACCESS_FILE,'utf8'));
    await page.getByLabel('Clave de acceso').fill(password);await button('Entrar').click();await page.waitForURL(u=>u.pathname==='/');
   }
   await page.locator('iframe').waitFor();
   const frame=await(await page.locator('iframe').first().elementHandle()).contentFrame();await frame.waitForURL('**/editor/index.html');
   const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.evaluate(e=>e.click());
   await button('Resolver').waitFor();await frame.waitForFunction(()=>typeof window.configure==='function');
   const key=label=>frame.locator(`.MLK__layer.is-visible [aria-label=${JSON.stringify(label)}]`);
   const control=name=>frame.getByRole('button',{name,exact:true});
   const panel=frame.locator('#result');
   async function input(value){await frame.evaluate(v=>{window.setDraft(v);document.getElementById('mf').dispatchEvent(new Event('input',{bubbles:true}));},value);}
   async function geometry(){return {key:await key('1').boundingBox(),editor:await page.locator('iframe').first().boundingBox()};}
   async function fixed(before){const after=await geometry();for(const item of ['key','editor'])for(const dim of ['x','y','width','height'])assert(Math.abs(before[item][dim]-after[item][dim])<1,`${item}.${dim} moved: ${before[item][dim]} → ${after[item][dim]}`);}
   for(const viewport of [{width:320,height:600},{width:390,height:844},{width:1200,height:850}]) {
    await input('');await page.setViewportSize(viewport);await page.waitForTimeout(250);
    const before=await geometry();
    await input('18.33\\times12');await button('Resolver').click();await panel.waitFor();
    await frame.waitForFunction(()=>document.getElementById('result-math').dataset.latex.includes('5499'));
    await fixed(before);
    const resultBox=await panel.boundingBox(),keyboardBox=await frame.locator('#keyboard').boundingBox();
    assert(resultBox.y+resultBox.height<=keyboardBox.y+1,'result must sit above keyboard');
    assert.equal(await frame.locator('#result-math').evaluate(el=>el.isContentEditable),false);
    await control('Copiar resultado').click();
    for(let attempt=0;attempt<40;attempt++) {
      if(await page.evaluate(()=>navigator.clipboard.readText())==='\\frac{5499}{25}')break;
      await page.waitForTimeout(50);
    }
    assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'\\frac{5499}{25}');
    await key('+').click();await panel.waitFor({state:'hidden'});await control('Completar').waitFor();await fixed(before);
    await key('1').click();await control('Completar').waitFor({state:'hidden'});await button('Resolver').click();await panel.waitFor();await fixed(before);
    await page.mouse.move(1,1);await page.screenshot({path:`${out}/result-stable-${viewport.width}-${colorScheme}.png`});
    await input('80!');await button('Resolver').click();await panel.waitFor();
    await frame.waitForFunction(()=>document.getElementById('result-math').dataset.latex.length>100);
    await fixed(before);
    assert(await frame.locator('#result-expression').evaluate(el=>el.scrollWidth>el.clientWidth),'long exact answer must scroll inside result');
    await frame.locator('#result-expression').evaluate(el=>el.scrollLeft=el.scrollWidth);await fixed(before);
    await button('Nueva ecuación').click();await panel.waitFor({state:'hidden'});await fixed(before);
   }
   if(process.env.WEB_TEST_OFFLINE_ONLY!=='1') {
    await page.setViewportSize({width:390,height:844});await input('x^2');
    await button('Calcular').click();await page.getByRole('menuitem',{name:'Derivar',exact:true}).click();await page.waitForTimeout(200);
    const before=await geometry();
    let release;const gate=new Promise(r=>release=r);
    await page.route('**/api/v1/calculate',async route=>{await gate;await route.continue();});
    const requestPromise=page.waitForRequest(r=>r.url().endsWith('/api/v1/calculate'));
    try {
     await button('Resolver').click();await requestPromise;
     // Flutter's unlabeled spinner has no progressbar semantics in CanvasKit.
     await button('Resolver').waitFor({state:'hidden'});await page.waitForTimeout(150);await fixed(before);
    } catch(error) { release();throw error; }
    const responsePromise=page.waitForResponse(r=>r.url().endsWith('/api/v1/calculate'));
    release();const response=await responsePromise;assert.equal(response.status(),200);assert.equal((await response.json()).text,'2*x');
    await panel.waitFor();await fixed(before);
    await control('Dominio y comprobación').click();await page.getByText('Dominio y comprobación',{exact:true}).waitFor();
    // Tap the dismiss barrier above the sheet. Focus remains in the iframe,
    // so Escape would be sent to MathLive instead.
    await page.mouse.click(10,10);
    await page.getByText('Dominio y comprobación',{exact:true}).waitFor({state:'hidden'});await fixed(before);
    await page.unroute('**/api/v1/calculate');
   }
   assert.deepEqual(errors,[]);results.push({colorScheme,checks:['result appears above fixed keys','copy exact LaTeX','editing and suggestions keep keys fixed','long answer scrolls','clear keeps keys fixed',...(process.env.WEB_TEST_OFFLINE_ONLY==='1'?[]:['CAS loading keeps keys fixed','result details remain available'])]});
  }catch(error){await page.screenshot({path:`${out}/result-failure.png`});await writeFile(`${out}/result-failure.html`,await page.content());throw error;}
  finally{await context.close();}
 }
 await writeFile(`${out}/result-web-results.json`,JSON.stringify({base,results},null,2));console.log(JSON.stringify({base,results},null,2));
}finally{await browser.close();}
