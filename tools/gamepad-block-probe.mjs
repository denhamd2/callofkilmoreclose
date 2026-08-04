/**
 * Reproduces a sandboxed-iframe permissions policy: getGamepads() EXISTS but
 * throws SecurityError. That is what a published artifact does, and it black-
 * screened the game on a Mali-G57 phone at ~1 exception per frame.
 */
import { chromium } from 'playwright';
import { createServer } from 'vite';
import { PNG } from 'pngjs';
const server = await createServer({ server: { port: 5402 }, logLevel: 'silent' });
await server.listen();
const b = await chromium.launch({ executablePath: process.env.PW_CHROMIUM_PATH, args: ['--use-gl=swiftshader', '--no-sandbox'] });
const p = await b.newPage({ viewport: { width: 480, height: 270 } });
const errs = [];
p.on('pageerror', (e) => errs.push(String(e).slice(0, 90)));
await p.addInitScript(() => {
  Object.defineProperty(navigator, 'getGamepads', {
    value: () => { throw new DOMException('disallowed by permissions policy', 'SecurityError'); },
    configurable: true,
  });
});
await p.goto('http://127.0.0.1:5402/?q=mobile', { waitUntil: 'domcontentloaded' });
let ready = false;
try { await p.waitForFunction('window.__READY__===true', null, { timeout: 300000 }); ready = true; } catch {}
const png = PNG.sync.read(await p.screenshot({ type: 'png' }));
let sum = 0, max = 0;
for (let i = 0; i < png.data.length; i += 4) {
  const l = 0.2126 * png.data[i] + 0.7152 * png.data[i + 1] + 0.0722 * png.data[i + 2];
  sum += l; if (l > max) max = l;
}
const mean = sum / (png.data.length / 4);
console.log(JSON.stringify({ ready, lumMean: +mean.toFixed(1), lumMax: +max.toFixed(0),
  pageErrors: errs.length, sample: errs.slice(0, 2),
  verdict: ready && mean > 5 ? 'SCENE RENDERS under a blocked gamepad API' : 'STILL BLACK' }, null, 2));
await b.close(); await server.close();
