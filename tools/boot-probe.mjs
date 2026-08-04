import { chromium } from 'playwright';
import { createServer } from 'vite';
const q = process.argv[2] ?? 'mobile';
const server = await createServer({ server:{port:5401}, logLevel:'silent' });
await server.listen();
const b = await chromium.launch({ executablePath: process.env.PW_CHROMIUM_PATH, args:['--use-gl=swiftshader','--no-sandbox'] });
const p = await b.newPage();
const t0 = Date.now();
p.on('console', m => { const t = m.text(); if (/init|prewarm|boot|nav|materials|world|ai|weapons/i.test(t)) console.log(String(Date.now()-t0).padStart(6)+'ms  '+t.slice(0,110)); });
await p.goto(`http://127.0.0.1:5401/?q=${q}`, { waitUntil:'domcontentloaded' });
try { await p.waitForFunction('window.__READY__===true', null, { timeout: 300000 });
      console.log('=== READY at ' + (Date.now()-t0) + 'ms ==='); }
catch { console.log('=== NOT READY after ' + (Date.now()-t0) + 'ms ==='); }
await b.close(); await server.close();
