#!/usr/bin/env node
/*
 * run-web-test.cjs - the web archive playing and recording in a real browser.
 *
 *   node tests/web/run-web-test.cjs <build-web>
 *
 * <build-web> is the Emscripten build folder holding audioxt_page.js and
 * audioxt_page.wasm (the CMake target audioxt_page, tests/web/page.c over
 * audioxt.a). The page is served from memory on a local port and opened in
 * headless Chromium (Playwright), with Chromium's fake microphone, which
 * needs no hardware and no permission prompt and delivers a beep.
 *
 * What is held, each printed PASS or FAIL, then "audioxt web: N checks, F
 * failed"; the exit status is 1 on any failure:
 *   - the device opens BEFORE any click and a tone is started on it;
 *   - after one click the engine's clock runs in real time and the meter
 *     reads the tone's level (so Web Audio is pulling sound from the mixer);
 *   - the microphone opens, delivers samples and they are not silence;
 *   - shutdown closes it all, and the page raised no error.
 *
 * What this is NOT: OXT-Beyond's web engine. It is the archive that engine
 * will link, called from C as that engine will call it.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const buildDir = process.argv[2];
if (!buildDir || !fs.existsSync(path.join(buildDir, 'audioxt_page.js'))) {
  console.error('usage: run-web-test.cjs <build-web>   (no audioxt_page.js there: build with -DAUDIOXT_BUILD_TESTS=ON)');
  process.exit(2);
}
const FILES = {
  '/': [path.join(__dirname, 'index.html'), 'text/html'],
  '/audioxt_page.js': [path.join(buildDir, 'audioxt_page.js'), 'text/javascript'],
  '/audioxt_page.wasm': [path.join(buildDir, 'audioxt_page.wasm'), 'application/wasm'],
};

let checks = 0, failed = 0;
function check(name, ok, detail) {
  checks += 1;
  if (ok) { console.log('PASS ' + name); return; }
  failed += 1;
  console.log('FAIL ' + name + ' - ' + detail);
}

(async () => {
  const server = http.createServer((req, res) => {
    const entry = FILES[req.url.split('?')[0]];
    if (!entry) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': entry[1] });
    res.end(fs.readFileSync(entry[0]));
  }).listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const origin = 'http://127.0.0.1:' + server.address().port;

  const launch = { args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'] };
  if (process.env.AUDIOXT_CHROMIUM) launch.executablePath = process.env.AUDIOXT_CHROMIUM;
  const browser = await chromium.launch(launch);
  const context = await browser.newContext({ permissions: ['microphone'] });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e.message)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

  const call = (name, type) => page.evaluate(([n, t]) => Module.ccall(n, t, [], []), [name, type || 'number']);

  try {
    await page.goto(origin + '/');
    await page.waitForFunction(() => window.auReady === true, null, { timeout: 30000 });

    check('the archive answers (ABI 1)', (await call('w_abi')) === 1, 'not 1');
    const backend = await call('w_backend', 'string');
    check('the audio system is Web Audio', backend === 'Web Audio', "'" + backend + "' " + (await call('w_error', 'string')));
    const found = await call('w_scan');
    check('a scan finds the browser\'s devices', found >= 1 && (await call('w_playback_count')) >= 1, String(found));

    const rate = await call('w_start');
    check('the device opens before any click', rate >= 8000, rate + ' ' + (await call('w_error', 'string')));
    check('a tone is started on it', (await call('w_playing')) === 1, 'not playing');
    await page.waitForTimeout(300);
    console.log('INFO clock before the click: ' + (await call('w_time')) + ' s (a browser may hold it at 0 until then)');

    await page.click('#go');
    await page.waitForTimeout(1200);
    const time = await call('w_time');
    check('after one click the clock runs in real time', time > 0.5 && time < 5, time + ' s');
    await call('w_peak');
    await page.waitForTimeout(300);
    const peak = await call('w_peak');
    check('the meter reads the tone the browser is pulling', Math.abs(peak - 0.2) < 0.02, String(peak));

    const mic = await call('w_mic_start');
    check('the microphone opens and starts', mic > 0, mic + ' ' + (await call('w_error', 'string')));
    await page.waitForTimeout(1500);
    const waiting = await call('w_mic_available');
    check('it delivers samples', waiting > 3200 && waiting % 2 === 0, waiting + ' bytes');
    const micPeak = await call('w_mic_peak');
    check('and they are not silence (Chromium\'s fake microphone beeps)', micPeak > 0.001 && micPeak <= 1, String(micPeak));
    check('a read takes what was waiting', (await call('w_mic_read')) >= waiting, 'fewer bytes than were waiting');

    check('shutdown closes everything', (await call('w_stop')) === 1, 'the engine is still valid');
    await page.waitForTimeout(200);
    check('the page raised no error', errors.length === 0, errors.join(' | '));
  } catch (e) {
    check('the run finished', false, String(e && e.message ? e.message : e) + ' | ' + errors.join(' | '));
  }
  await browser.close();
  server.close();
  console.log('audioxt web: ' + checks + ' checks, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
