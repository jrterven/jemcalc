#!/usr/bin/env node
// Full Flutter editor, real virtual key presses, variable selection and CAS.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=process.env.PLAYWRIGHT_MODULE
  ? await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href)
  : createRequire(import.meta.url)('playwright');
const browser=await chromium.launch({channel:'chrome',headless:true});
const base=process.env.JEM_WEB_URL||'http://localhost:5187';
const out='output/playwright';await mkdir(out,{recursive:true});const results=[];
try {
 for(const colorScheme of ['light','dark']) {
  const context=await browser.newContext({viewport:{width:390,height:844},colorScheme,hasTouch:true});
  const page=await context.newPage();page.setDefaultTimeout(20000);
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  const button=name=>page.getByRole('button',{name,exact:true});
  try {
   await page.goto(base);
   if(new URL(page.url()).pathname==='/access') {
    const {password}=JSON.parse(await readFile(process.env.WEB_TEST_ACCESS_FILE,'utf8'));
    await page.getByLabel('Clave de acceso').fill(password);await button('Entrar').click();await page.waitForURL(u=>u.pathname==='/');
   }
   await page.locator('iframe').waitFor();const frame=await(await page.locator('iframe').first().elementHandle()).contentFrame();await frame.waitForURL('**/editor/index.html');
   const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.evaluate(e=>e.click());
   await button('Resolver').waitFor();await frame.waitForFunction(()=>typeof window.setDraft==='function');
   const key=label=>frame.locator(`.MLK__layer.is-visible [aria-label=${JSON.stringify(label)}]`);
   const tab=name=>frame.locator('.MLK__layer.is-visible .MLK__toolbar').getByText(name,{exact:true});
   const value=()=>frame.locator('#mf').evaluate(e=>e.value);
   async function input(latex){await frame.evaluate(v=>{window.setDraft(v);document.getElementById('mf').dispatchEvent(new Event('input',{bubbles:true}));},latex);}
   async function calculate(variable,expected) {
    const [response]=await Promise.all([page.waitForResponse(r=>r.url().endsWith('/api/v1/calculate')&&r.request().method()==='POST'),button('Resolver').click()]);
    assert.equal(response.status(),200);assert.equal(response.request().postDataJSON().variable,variable);
    assert.equal((await response.json()).text,expected);await frame.getByRole('button',{name:'Copiar resultado',exact:true}).waitFor();await button('Resolver').click({trial:true});
   }
   await tab('Científico').click();
   for(const label of ['x','y','z'])assert(await key(label).isVisible());
   await input('x+y+z');await page.screenshot({path:`${out}/scientific-xyz-${colorScheme}.png`});
   await tab('ABC').click();await input('');
   for(const label of ['n','+','1','=','2'])await key(label).click();
   assert.equal(await value(),'n+1=2');await calculate('n','{1}');
   await page.screenshot({path:`${out}/qwerty-${colorScheme}.png`});
   await button('Nueva ecuación').click();await frame.waitForFunction(()=>document.getElementById('mf').value==='');
   await key('n').click();await key('+').click();await key('1').click();
   await key('←').click();await key('2').click();assert.equal(await value(),'n+21');
   await key('⌫').click();assert.equal(await value(),'n+1');
   await page.getByRole('button',{name:/Escribir/}).click();await page.getByRole('button',{name:/Teclado/}).click();await key('n').waitFor();assert.equal(await value(),'n+1');
   await input('a^{2}+b');await button('Calcular').click();await page.getByLabel('Derivar',{exact:true}).click();
   await page.getByRole('button',{name:/Variable/}).click();await page.getByLabel('a',{exact:true}).click();
   await calculate('a','2*a');
   await page.screenshot({path:`${out}/qwerty-variable-${colorScheme}.png`});
   await page.setViewportSize({width:1200,height:850});await page.waitForTimeout(300);
   await page.screenshot({path:`${out}/qwerty-desktop-${colorScheme}.png`});
   assert.deepEqual(errors,[]);results.push({colorScheme,checks:['scientific xyz','QWERTY n equation solved','caret editing','mode restoration','select a and differentiate'],errors});
  }catch(error){await page.screenshot({path:`${out}/qwerty-failure.png`});await writeFile(`${out}/qwerty-failure.html`,await page.content());throw error;}
  finally{await context.close();}
 }
 await writeFile(`${out}/qwerty-results.json`,JSON.stringify({base,results},null,2));console.log(JSON.stringify({base,results},null,2));
}finally{await browser.close();}
