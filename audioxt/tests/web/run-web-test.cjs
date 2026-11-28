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
 *   - shutdown closes it all, and the page raised no error;
 *   - on a page with no microphone API (as one served over plain http
 *     has none) a capture is refused with a reason and playback still
 *     opens; on a page whose AudioContext cannot be made, a device of
 *     either kind is refused with a reason. miniaudio's own JavaScript
 *     would throw on both, through every WebAssembly frame above it (the
 *     web engine's main loop included); neither page may raise an error;
 *   - a device the page opens at load, before any gesture, is held silent
 *     (its clock stands at 0) until the visitor's first key press, mouse
 *     button or click, and Escape, which is no gesture, leaves it held.
 *     In Playwright a page.evaluate counts as a gesture, so the first
 *     page, which the test drives through evaluate, cannot show the hold
 *     (its INFO line prints the clock before the click); these pages
 *     open the device themselves (index.html?atload) and print their
 *     clock to the console, and the test never calls into them;
 *   - a page that sets window.audioxtWebBuffer (milliseconds) before it
 *     opens an engine gets a ScriptProcessorNode buffer that long or
 *     longer, a power of two; one that sets nonsense, or nothing, keeps
 *     miniaudio's own.
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
    const buffer = await call('w_buffer');
    check('with no buffer asked for, the device keeps miniaudio\'s own (under 4096 frames)', buffer >= 256 && buffer < 4096, String(buffer));
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

    // Pages that cannot have what miniaudio's JavaScript takes for granted.
    // Each is a fresh page with one thing taken away before the archive
    // loads; a throw would show as a page error or a failed call.
    const hobbled = async (init, body) => {
      const p = await context.newPage();
      const errs = [];
      p.on('pageerror', (e) => errs.push(String(e.message)));
      await p.addInitScript(init);
      await p.goto(origin + '/');
      await p.waitForFunction(() => window.auReady === true, null, { timeout: 30000 });
      await body((n, t) => p.evaluate(([n2, t2]) => Module.ccall(n2, t2, [], []), [n, t || 'number']), errs);
      await p.close();
    };
    await hobbled(() => { Object.defineProperty(navigator, 'mediaDevices', { value: undefined, configurable: true }); },
      async (c, errs) => {
        const mic = await c('w_try_mic');
        const why = await c('w_error', 'string');
        check('no microphone API (plain http): a capture is refused, with the reason', mic === 0 && why.includes('https'), mic + " '" + why + "'");
        check('and playback still opens there', (await c('w_start')) >= 8000, await c('w_error', 'string'));
        check('and closes', (await c('w_stop')) === 1, 'the engine is still valid');
        check('that page raised no error', errs.length === 0, errs.join(' | '));
      });
    await hobbled(() => { window.AudioContext = function () { throw new Error('no audio for this page'); }; window.webkitAudioContext = undefined; },
      async (c, errs) => {
        const eng = await c('w_try_engine');
        const why = await c('w_error', 'string');
        check('no AudioContext for the page: a playback device is refused, with the reason', eng === 0 && why.includes('Web Audio'), eng + " '" + why + "'");
        const mic = await c('w_try_mic');
        check('and so is a microphone', mic === 0 && (await c('w_error', 'string')).includes('Web Audio'), String(mic));
        check('that page raised no error', errs.length === 0, errs.join(' | '));
      });

    // A page that asks for a longer buffer (window.audioxtWebBuffer, in
    // milliseconds) before it opens an engine gets one; nonsense is ignored.
    await hobbled(() => { window.audioxtWebBuffer = 80; },
      async (c, errs) => {
        const rate = await c('w_start');
        const buf = await c('w_buffer');
        check('a page that asks for 80 ms gets a buffer of 80 ms or more, a power of two', rate >= 8000 && buf >= rate * 0.08 && (buf & (buf - 1)) === 0,
          rate + ' Hz ' + buf + ' frames ' + (await c('w_error', 'string')));
        check('and its tone plays', (await c('w_playing')) === 1, 'not playing');
        check('and closes', (await c('w_stop')) === 1, 'the engine is still valid');
        check('that page raised no error', errs.length === 0, errs.join(' | '));
      });
    await hobbled(() => { window.audioxtWebBuffer = 'lots'; },
      async (c, errs) => {
        await c('w_start');
        const buf = await c('w_buffer');
        check('a page that asks with nonsense keeps miniaudio\'s own', buf >= 256 && buf < 4096, String(buf));
        check('and closes', (await c('w_stop')) === 1, 'the engine is still valid');
        check('that page raised no error', errs.length === 0, errs.join(' | '));
      });

    // A device opened at load, before any gesture, and the gesture that
    // lets it start. Each page prints its clock; nothing calls into it.
    const atLoad = async (gesture) => {
      const p = await context.newPage();
      const errs = [];
      let clock = null, refused = null;
      p.on('pageerror', (e) => errs.push(String(e.message)));
      p.on('console', (m) => {
        const t = m.text();
        if (t.startsWith('auclock refused')) refused = t;
        else if (t.startsWith('auclock ')) clock = Number(t.slice(8));
      });
      await p.goto(origin + '/?atload=1');
      for (let i = 0; i < 300 && clock === null && refused === null; ++i) await p.waitForTimeout(100);
      if (refused !== null || clock === null) throw new Error('the page opened no device: ' + refused);
      await p.waitForTimeout(800);
      await gesture(p, () => clock);
      check('that page raised no error', errs.length === 0, errs.join(' | '));
      await p.close();
    };
    await atLoad(async (p, clock) => {
      check('a device opened before any gesture is held silent', clock() === 0, clock() + ' s');
      await p.keyboard.press('Escape');
      await p.waitForTimeout(600);
      check('Escape, which is no gesture, leaves it held', clock() === 0, clock() + ' s');
      await p.keyboard.press('a');
      await p.waitForTimeout(1200);
      check('a key press starts it (miniaudio itself waits for a click)', clock() > 0.5 && clock() < 5, clock() + ' s');
    });
    await atLoad(async (p, clock) => {
      check('held silent on a second page', clock() === 0, clock() + ' s');
      await p.mouse.move(400, 300);
      await p.mouse.down();
      await p.waitForTimeout(1200);
      check('a mouse button held down starts it, before any click', clock() > 0.5 && clock() < 5, clock() + ' s');
      await p.mouse.up();
    });
    await atLoad(async (p, clock) => {
      check('held silent on a third page', clock() === 0, clock() + ' s');
      await p.click('#go');
      await p.waitForTimeout(1200);
      check('a click starts it', clock() > 0.5 && clock() < 5, clock() + ' s');
    });
  } catch (e) {
    check('the run finished', false, String(e && e.message ? e.message : e) + ' | ' + errors.join(' | '));
  }
  await browser.close();
  server.close();
  console.log('audioxt web: ' + checks + ' checks, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
