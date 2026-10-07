#!/usr/bin/env node
// Full Flutter + MathLive + local deterministic plotting, using a fresh browser store.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';
const {chromium}=process.env.PLAYWRIGHT_MODULE
 ? await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href)
 : createRequire(import.meta.url)('playwright');
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:390,height:844},hasTouch:true});
const page=await context.newPage();page.setDefaultTimeout(20000);
const out='output/playwright';await mkdir(out,{recursive:true});
const base=process.env.JEM_WEB_URL||'http://localhost:5187';
const button=name=>page.getByRole('button',{name,exact:true});
const frame=()=>page.frames().find(f=>f.url().includes('/editor/index.html'));
const results=[],errors=[],api=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('request',r=>{if(r.url().includes('/api/v1/'))api.push(r.url());});
async function start(){
 await page.goto(base);
 if(new URL(page.url()).pathname==='/access'){
  const access=JSON.parse(await readFile(process.env.WEB_TEST_ACCESS_FILE,'utf8'));
  await page.getByLabel('Clave de acceso').fill(access.password);await button('Entrar').click();await page.waitForURL(u=>u.pathname==='/');
 }
 await page.locator('iframe').waitFor();const f=await(await page.locator('iframe').first().elementHandle()).contentFrame();await f.waitForURL('**/editor/index.html');
 const toggle=page.locator('flt-semantics-placeholder');if(await toggle.count())await toggle.evaluate(el=>el.click());
 await button('Graficar').waitFor();await f.waitForFunction(()=>typeof window.setDraft==='function');
}
async function input(latex){await frame().evaluate(value=>{window.setDraft(value);document.getElementById('mf').dispatchEvent(new Event('input',{bubbles:true}));},latex);}
async function firstChecked(value){await page.waitForFunction(expected=>document.querySelector('[role=checkbox]')?.getAttribute('aria-checked')===String(expected),value);}
async function check(name,run){await run();results.push(name);console.log('PASS',name);}
try{
 await start();
 await check('the pictured system opens as two separate curves without a server calculation',async()=>{
  await input('\\begin{cases}3x+y=5\\\\2x-y=3\\end{cases}');
  await button('Graficar').click();await page.getByRole('checkbox').nth(1).waitFor();
  assert.equal(await page.getByRole('checkbox').count(),2);
  assert.equal(await button('Eliminar ecuación').count(),2);
  assert.equal(api.length,0);
  // Allow the asynchronous bounded sampler to paint before visual review.
  await page.waitForTimeout(800);
  await page.screenshot({path:out+'/graph-system-mobile.png'});
 });
 await check('hiding, showing and reopening the system preserve both equations',async()=>{
  const first=page.getByRole('checkbox').first();await first.click();await firstChecked(false);
  await page.waitForTimeout(800);await start();await button('Graficar').click();await page.getByRole('checkbox').nth(1).waitFor();
  assert.equal(await page.getByRole('checkbox').count(),2);assert.equal(await page.getByRole('checkbox').first().isChecked(),false);
  await page.getByRole('checkbox').first().click();await firstChecked(true);
 });
 await check('a vertical line can join the system and each row can be removed independently',async()=>{
  await button('Añadir desde el editor').click();await button('Graficar').waitFor();await input('2x=4');await button('Graficar').click();await page.getByRole('checkbox').nth(2).waitFor();
  assert.equal(await page.getByRole('checkbox').count(),3);
  await page.waitForTimeout(400);await page.screenshot({path:out+'/graph-system-vertical-mobile.png'});
  await button('Eliminar ecuación').last().click();await page.waitForFunction(()=>document.querySelectorAll('[role=checkbox]').length===2);
 });
 await check('desktop layout and panning preserve the graph controls',async()=>{
  await page.setViewportSize({width:1200,height:850});await page.waitForTimeout(400);
  await page.mouse.move(850,430);await page.mouse.down();await page.mouse.move(900,460,{steps:8});await page.mouse.up();
  await button('Restablecer vista').click();await page.waitForTimeout(500);await page.screenshot({path:out+'/graph-system-desktop.png'});
  assert.equal(await page.getByRole('checkbox').count(),2);assert.deepEqual(errors,[]);assert.equal(api.length,0);
 });
 await writeFile(out+'/graph-system-web-results.json',JSON.stringify({base,results,errors,apiCalls:api.length},null,2));
}catch(error){await page.screenshot({path:out+'/graph-system-failure.png'});await writeFile(out+'/graph-system-failure.html',await page.content());throw error;}
finally{await browser.close();}
