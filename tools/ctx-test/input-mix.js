#!/usr/bin/env node
// ot-client#143: touch and mouse take turns in one session.
// On the login screen (desktop layout, 1280x720) the "Remember password"
// check box is clicked with the mouse and tapped with a finger (CDP touch
// events), in turns; every click and every tap must toggle it (its pixels
// change from one step to the next).
'use strict';
const path = require('path');
const { chromium } = require(process.env.PW_MODULE || 'playwright');
const serve = require('./serve');

const BOX = { x: 522, y: 330 };
const CLIP = { x: BOX.x - 12, y: BOX.y - 10, width: 24, height: 20 };

(async () => {
    const server = await serve(path.resolve(process.argv[2]));
    const base = `http://127.0.0.1:${server.address().port}`;
    const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
    const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
    const page = await context.newPage();
    const log = [];
    page.on('console', (m) => log.push(m.text()));
    await page.goto(base + '/otclient.html');
    for (let i = 0; i < 90 && !log.some((l) => l.includes('Startup done')); i++) await page.waitForTimeout(1000);
    await page.addStyleTag({ content: '#title-text, #start { display: none !important; }' });
    await page.waitForTimeout(3000);
    const cdp = await context.newCDPSession(page);
    // touch events from here on (the layout stays the desktop one)
    await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });

    const tap = async () => {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: BOX.x, y: BOX.y, id: 1 }] });
        await page.waitForTimeout(80);
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    };
    const click = async () => {
        await page.mouse.move(BOX.x + 40, BOX.y + 60);
        await page.mouse.move(BOX.x, BOX.y, { steps: 4 });
        await page.mouse.down();
        await page.waitForTimeout(60);
        await page.mouse.up();
        await page.waitForTimeout(300);
        // (away again: the hover look is not the toggle)
        await page.mouse.move(BOX.x + 40, BOX.y + 60, { steps: 4 });
    };
    const shot = async () => (await page.screenshot({ clip: CLIP })).toString('base64');

    const steps = ['mouse', 'mouse', 'touch', 'mouse', 'touch', 'mouse', 'mouse', 'touch', 'touch', 'mouse'];
    let failed = 0;
    let before = await shot();
    for (const how of steps) {
        await (how === 'touch' ? tap() : click());
        await page.waitForTimeout(900);
        const after = await shot();
        const toggled = after !== before;
        if (!toggled) failed++;
        console.log(`${toggled ? 'ok  ' : 'FAIL'} ${how}: the check box ${toggled ? 'toggled' : 'did not toggle'}`);
        before = after;
    }
    console.log(failed ? `FAILED: ${failed} of ${steps.length} steps` : `PASSED: ${steps.length} steps`);
    await browser.close();
    server.close();
    process.exit(failed ? 1 : 0);
})();
