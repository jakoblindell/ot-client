#!/usr/bin/env node
// ot-client#142: the GL context is lost and comes back (WEBGL_lose_context
// on the game thread's context), and the game draws again as before,
// without reloading the page.
//
//   node context-loss.js <bundle> [gallery page] [--print]
//
// The page is drawn at two sizes before the loss (references), then the
// context is lost and restored (twice: also while the first restore may
// still be busy), and the page is drawn at both sizes again: each must
// match its reference. The canvas must not be lost after the restore, and
// the page must not have reloaded.
'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PW_MODULE || 'playwright');
const serve = require('./serve');

const SIZE_A = { width: 1280, height: 720 };
const SIZE_B = { width: 1000, height: 650 };

(async () => {
    const bundle = path.resolve(process.argv[2]);
    const gallery = process.argv[3] && !process.argv[3].startsWith('--') ? process.argv[3] : null;
    const print = process.argv.includes('--print');
    const outDir = process.env.OUT || '.';
    const name = gallery || 'login';
    const server = await serve(bundle);
    const base = `http://127.0.0.1:${server.address().port}`;
    const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
    const page = await browser.newPage({ viewport: SIZE_A });
    const log = [];
    let loads = 0;
    page.on('console', (m) => log.push(m.text()));
    page.on('load', () => loads++);
    page.on('pageerror', (e) => log.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(0, 4).join(' | ')));
    if (gallery)
        await page.addInitScript((g) => { window.otclientConfig = Object.assign(window.otclientConfig || {}, { gallery: g }); }, gallery);
    await page.goto(base + '/otclient.html');
    const ready = gallery ? `[gallery] ready ${gallery}` : 'Startup done';
    for (let i = 0; i < 120 && !log.some((l) => l.includes(ready)); i++) await page.waitForTimeout(1000);
    if (!log.some((l) => l.includes(ready))) {
        console.log(`FAIL ${name}: not ready`, log.filter((l) => /error|gallery/i.test(l)).slice(-10).join('\n'));
        process.exit(1);
    }
    await page.addStyleTag({ content: '#title-text, #start { display: none !important; }' });
    await page.waitForTimeout(3000);

    const shot = async (label) => {
        const buf = await page.screenshot();
        fs.writeFileSync(path.join(outDir, `${name}-${label}.png`), buf);
        return buf;
    };
    const atSize = async (size, label) => {
        await page.setViewportSize(size);
        await page.waitForTimeout(2500);
        return shot(label);
    };

    // the GL context lives on one of the pthreads (an OffscreenCanvas)
    let glWorker = null;
    for (const w of page.workers()) {
        const has = await Promise.race([
            w.evaluate(() => typeof GL !== 'undefined' && !!(GL.currentContext && GL.currentContext.GLctx)).catch(() => false),
            new Promise((r) => setTimeout(() => r(false), 2000)),
        ]);
        if (has) glWorker = w;
    }
    if (!glWorker) {
        console.log(`FAIL ${name}: no worker with the GL context`);
        process.exit(1);
    }
    const isLost = () => glWorker.evaluate(() => GL.currentContext.GLctx.isContextLost());

    const refA = await atSize(SIZE_A, 'before-a');
    const refB = await atSize(SIZE_B, 'before-b');
    await page.setViewportSize(SIZE_A);
    await page.waitForTimeout(2000);

    const lose = () => glWorker.evaluate(() => { self.__loseExt = self.__loseExt || GL.currentContext.GLctx.getExtension('WEBGL_lose_context'); self.__loseExt.loseContext(); });
    const restore = () => glWorker.evaluate(() => self.__loseExt.restoreContext());

    // 1. lost; the screen turns (resized) while it is away; back
    await lose();
    await page.waitForTimeout(1000);
    const lost1 = await isLost();
    await page.setViewportSize(SIZE_B);
    await page.waitForTimeout(1500);
    await restore();
    await page.waitForTimeout(4000);
    const afterB = await shot('after-b');
    const afterA = await atSize(SIZE_A, 'after-a');

    // 2. lost again, and back right away; then lost and back once more
    // while that restore may still be busy
    await lose();
    await page.waitForTimeout(300);
    const lost2 = await isLost();
    await restore();
    await page.waitForTimeout(30);
    await lose();
    await page.waitForTimeout(300);
    await restore();
    await page.waitForTimeout(4000);
    const lostAfter = await isLost();
    const afterA2 = await shot('after-a2');
    const afterB2 = await atSize(SIZE_B, 'after-b2');

    // compare in the browser (no image libraries): share of pixels that differ
    const cmp = await browser.newPage();
    const diff = (a, b) => cmp.evaluate(async ({ a, b }) => {
        const load = (src) => new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
        const [ia, ib] = await Promise.all([load(a), load(b)]);
        if (ia.width !== ib.width || ia.height !== ib.height) return 1;
        const px = (img) => { const c = document.createElement('canvas'); c.width = img.width; c.height = img.height; const g = c.getContext('2d'); g.drawImage(img, 0, 0); return g.getImageData(0, 0, img.width, img.height).data; };
        const pa = px(ia), pb = px(ib);
        let n = 0;
        for (let i = 0; i < pa.length; i += 4) {
            if (Math.max(Math.abs(pa[i] - pb[i]), Math.abs(pa[i + 1] - pb[i + 1]), Math.abs(pa[i + 2] - pb[i + 2])) > 24) n++;
        }
        return n / (pa.length / 4);
    }, { a: 'data:image/png;base64,' + a.toString('base64'), b: 'data:image/png;base64,' + b.toString('base64') });

    const results = [
        ['lost after loseContext (1)', lost1 === true],
        ['lost after loseContext (2)', lost2 === true],
        ['context back after restoreContext', lostAfter === false],
        ['game saw the loss', log.some((l) => l.includes('GL context was lost'))],
        ['game made the graphics again', log.some((l) => l.includes('GL context is back'))],
        ['page not reloaded', loads === 1],
    ];
    for (const [label, a, b] of [['1000x650 (resized while lost) after restore', afterB, refB], ['1280x720 after that', afterA, refA],
        ['1280x720 after two more restores', afterA2, refA], ['1000x650 after that', afterB2, refB]]) {
        const share = await diff(a, b);
        results.push([`${label} matches the one before (${(share * 100).toFixed(2)}% of pixels differ)`, share < 0.002]);
    }
    const errors = log.filter((l) => /\berror\b|pageerror|Unable|Failed to/i.test(l) && !/config\.ini|option_control_buttons|option_healthcircle|stack traceback|\[C\]|\.lua:|\.otmod:/.test(l));
    results.push(['no errors in the log', errors.length === 0]);
    let failed = 0;
    for (const [label, ok] of results) {
        if (!ok) failed++;
        console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${label}`);
    }
    if (errors.length) console.log(`${name}: errors in the log:\n  ` + errors.slice(-15).join('\n  '));
    console.log(log.filter((l) => /GL context/.test(l)).join('\n'));
    if (print) {
        for (const label of ['after-a', 'after-b']) {
            const img = fs.readFileSync(path.join(outDir, `${name}-${label}.png`));
            const jpg = await cmp.evaluate(async (src) => {
                const i = new Image(); await new Promise((r) => { i.onload = r; i.src = src; });
                const c = document.createElement('canvas'); c.width = i.width / 2; c.height = i.height / 2;
                c.getContext('2d').drawImage(i, 0, 0, c.width, c.height);
                return c.toDataURL('image/jpeg', 0.5);
            }, 'data:image/png;base64,' + img.toString('base64'));
            console.log(`IMAGE ${name}-${label} ${jpg}`);
        }
    }
    console.log(failed ? `FAILED ${name}: ${failed} of ${results.length}` : `PASSED ${name}: ${results.length} checks`);
    await browser.close();
    server.close();
    process.exit(failed ? 1 : 0);
})();
