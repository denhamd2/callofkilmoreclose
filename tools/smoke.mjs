#!/usr/bin/env node
/**
 * Pre-deploy smoke test: does the game actually DRAW?
 *
 * This exists because a build shipped to a player with the HUD rendering
 * correctly and the entire 3D scene black. Nothing in the existing toolchain
 * caught it: `npm run build` was green, the selftests passed, and every
 * derivation check was correct — they verify data and geometry, not pixels.
 * `capture.mjs` would have caught it, but on a software rasteriser it takes
 * long enough to routinely time out, so in practice it was never run.
 *
 * So this is deliberately the CHEAPEST possible check that can still fail on a
 * black screen. It does not settle TAA, does not apply a shot, does not write a
 * PNG. It boots, waits for ready, pumps a handful of frames and asserts three
 * things:
 *
 *   1  no page errors
 *   2  the renderer issued draw calls
 *   3  the frame is not uniformly one colour
 *
 * (3) is the one that matters. A black screen with a working HUD passes every
 * other check in the repo.
 *
 *   node tools/smoke.mjs                     # the dev server
 *   node tools/smoke.mjs --file=out.html     # a built single-file artifact
 *
 * Honours PW_CHROMIUM_PATH like the rest of the harness.
 */
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import net from 'node:net';

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] ?? true] : [a, true];
  })
);
const PORT = Number(args.port ?? 5399);
const TIMEOUT = Number(args.timeout ?? 420000);
const FILE = args.file ?? null;

const portOpen = (p) =>
  new Promise((r) => {
    const s = net.connect({ port: p, host: '127.0.0.1' }, () => (s.destroy(), r(true)));
    s.on('error', () => r(false));
    s.setTimeout(400, () => (s.destroy(), r(false)));
  });

let server = null;
let httpServer = null;

if (FILE) {
  // Serve a single-file build the way the artifact host does: the document
  // body wrapped in the doctype/head/body skeleton it gets at publish time.
  const body = readFileSync(resolve(FILE), 'utf8');
  const page =
    '<!doctype html><html><head><meta charset="utf-8">' +
    '<style>*{margin:0;padding:0;box-sizing:border-box}html,body{width:100%;height:100%}</style>' +
    `</head><body>${body}</body></html>`;
  httpServer = createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(page);
  });
  await new Promise((r) => httpServer.listen(PORT, r));
} else if (!(await portOpen(PORT))) {
  const root = resolve(import.meta.dirname, '..');
  server = spawn(resolve(root, 'node_modules/.bin/vite'), ['--port', String(PORT), '--strictPort'], {
    cwd: root,
    stdio: 'ignore',
  });
  for (let i = 0; i < 80; i++) {
    await new Promise((r) => setTimeout(r, 500));
    if (await portOpen(PORT)) break;
  }
}

const browser = await chromium.launch({
  headless: true,
  ...(process.env.PW_CHROMIUM_PATH ? { executablePath: process.env.PW_CHROMIUM_PATH } : {}),
  args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--mute-audio'],
});
const page = await browser.newPage({ viewport: { width: 480, height: 270 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message.split('\n')[0]));
page.on('console', (m) => {
  if (m.type() === 'error' && !/favicon/i.test(m.text())) errors.push(`[console] ${m.text().slice(0, 200)}`);
});

const fail = [];
let info = null;
try {
  await page.goto(`http://127.0.0.1:${PORT}/${args.q ? '?q=' + args.q : ''}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction('window.__READY__ === true', null, { timeout: TIMEOUT });
  // A few frames so the first-frame state is not what gets judged.
  await page.waitForTimeout(3000);

  info = await page.evaluate(() => {
    const e = window.__ENGINE__;
    const canvas = document.getElementById('game');
    const out = {
      calls: e?.ctx?.peek('render')?.renderer?.info?.render?.calls ?? 0,
      tris: e?.ctx?.peek('render')?.renderer?.info?.render?.triangles ?? 0,
      canvas: canvas ? `${canvas.width}x${canvas.height}` : 'missing',
    };
    return out;
  });

  /**
   * Judge the PIXELS from a real page screenshot, not from the canvas.
   *
   * Reading the canvas back with drawImage/getImageData looks like the obvious
   * check and is a trap: the renderer runs with `preserveDrawingBuffer` off, so
   * the drawing buffer is released once the frame is composited and a later
   * read returns transparent black even when the frame was perfect. The first
   * version of this file did exactly that and reported a black screen on a
   * build that renders correctly.
   *
   * page.screenshot() composites the same way the display does, so what it
   * returns is what a player sees.
   */
  const png = await page.screenshot({ type: 'png', timeout: 120000 });
  const { PNG } = await import('pngjs');
  const img = PNG.sync.read(png);
  let min = 255;
  let max = 0;
  let sum = 0;
  let n = 0;
  // Sample the middle band only — the HUD lives at the edges, and a black scene
  // behind a working HUD is precisely the case this has to catch.
  const y0 = (img.height * 0.25) | 0;
  const y1 = (img.height * 0.75) | 0;
  const x0 = (img.width * 0.2) | 0;
  const x1 = (img.width * 0.8) | 0;
  for (let y = y0; y < y1; y += 2) {
    for (let x = x0; x < x1; x += 2) {
      const i = (img.width * y + x) << 2;
      const l = (img.data[i] * 0.2126 + img.data[i + 1] * 0.7152 + img.data[i + 2] * 0.0722) | 0;
      if (l < min) min = l;
      if (l > max) max = l;
      sum += l;
      n++;
    }
  }
  info.lumMin = min;
  info.lumMax = max;
  info.lumMean = Math.round(sum / Math.max(1, n));

  if (errors.length) fail.push(`page errors: ${errors.slice(0, 3).join(' ; ')}`);
  if (!info.calls) fail.push('renderer issued ZERO draw calls');
  // The real test. A black screen has max luminance ~0 and no spread.
  if (info.lumMax !== undefined && info.lumMax < 8) fail.push(`frame is black (max luminance ${info.lumMax})`);
  if (info.lumMax !== undefined && info.lumMax - info.lumMin < 6) {
    fail.push(`frame is a flat fill (luminance spread ${info.lumMax - info.lumMin})`);
  }
} catch (e) {
  fail.push(`did not reach ready: ${e.message.split('\n')[0]}`);
}

await browser.close();
server?.kill();
httpServer?.close();

console.log(JSON.stringify({ ok: fail.length === 0, info, fail }, null, 2));
process.exit(fail.length ? 1 : 0);
