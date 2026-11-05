#!/usr/bin/env node
// UI screenshot tests (ot-client#70).
//
// Opens the browser build's UI gallery (mods/client_gallery) on a set of
// devices, saves a screenshot of every page, compares them with the
// baseline images and writes an HTML report.
//
//   node gallery.js --bundle <browser build folder> [--out <folder>]
//                   [--update] [--pages buttons,touch] [--devices phone-big]
//
//   --bundle   folder with otclient.html, .js, .wasm and .data
//   --out      where screenshots, diffs and report.html go (default: out)
//   --update   copy the new screenshots over the baseline (an intended change)
//
// Exit code 1 when a page differs from its baseline or failed to load.
// Baselines live in ./baseline; make them in CI (software rendering differs
// slightly between machines).
'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const { chromium } = require(process.env.PW_MODULE || 'playwright');

const PAGES = ['buttons', 'controls', 'text', 'touch'];

// Landscape, as the game is played. mobile: the touch layout (chosen from the
// user agent). config: extra window.otclientConfig settings.
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';
const IPAD = 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
const DEVICES = [
    { name: 'phone-small', width: 667, height: 375, ratio: 2, mobile: true, ua: ANDROID },
    { name: 'phone-big', width: 932, height: 430, ratio: 3, mobile: true, ua: ANDROID },
    { name: 'phone-big-sharp', width: 932, height: 430, ratio: 3, mobile: true, ua: ANDROID, config: { sharpness: 2 } },
    { name: 'tablet', width: 1180, height: 820, ratio: 2, mobile: true, ua: IPAD },
    { name: 'desktop', width: 1366, height: 768, ratio: 1, mobile: false },
    { name: 'desktop-scale-1.5', width: 1366, height: 768, ratio: 1, mobile: false, config: { galleryHudScale: 1.5 } },
];

// Pixels whose colour differs by more than this (0-255, any channel) count
const PIXEL_TOLERANCE = 24;
// A page differs when more than this share of its pixels do
const PAGE_TOLERANCE = 0.001;

function parseArgs(argv) {
    const args = { out: 'out', update: false };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--update') args.update = true;
        else if (a.startsWith('--')) args[a.slice(2)] = argv[++i];
    }
    if (!args.bundle) {
        console.error('usage: node gallery.js --bundle <browser build folder> [--out out] [--update] [--pages a,b] [--devices a,b]');
        process.exit(2);
    }
    return args;
}

// A static server for the bundle, with the headers threads need
// (SharedArrayBuffer: cross-origin isolation)
function serve(dir) {
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.data': 'application/octet-stream' };
    const server = http.createServer((req, res) => {
        const url = decodeURIComponent(req.url.split('?')[0]);
        const file = path.join(dir, url === '/' ? 'otclient.html' : url);
        if (!file.startsWith(path.resolve(dir)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
            res.writeHead(404);
            return res.end();
        }
        res.writeHead(200, {
            'Content-Type': types[path.extname(file)] || 'application/octet-stream',
            'Cross-Origin-Opener-Policy': 'same-origin',
            'Cross-Origin-Embedder-Policy': 'require-corp',
            'Cache-Control': 'max-age=3600',
        });
        fs.createReadStream(file).pipe(res);
    });
    return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// One page on one device: the screenshot, or an error
async function capture(context, base, device, page, file) {
    const tab = await context.newPage();
    const log = [];
    try {
        const config = Object.assign({ gallery: page }, device.config || {});
        await tab.addInitScript((c) => { window.otclientConfig = Object.assign(window.otclientConfig || {}, c); }, config);
        const ready = new Promise((resolve, reject) => {
            tab.on('console', (msg) => {
                const text = msg.text();
                log.push(text);
                if (text.includes('[gallery] ready ' + page)) resolve();
                if (text.includes('[gallery] no page')) reject(new Error(text));
            });
            tab.on('pageerror', (e) => log.push('pageerror: ' + e.message));
        });
        await tab.goto(base + '/otclient.html', { waitUntil: 'load' });
        // the page's loading text sits over the canvas
        await tab.addStyleTag({ content: '#title-text, #start { display: none !important; }' });
        await Promise.race([ready, new Promise((_, reject) => setTimeout(() => reject(new Error('no "[gallery] ready" within 120 s')), 120000))]);
        await tab.waitForTimeout(300);
        await tab.screenshot({ path: file });
        return null;
    } catch (e) {
        return e.message + '\n' + log.filter((l) => /error|gallery/i.test(l)).slice(-15).join('\n');
    } finally {
        await tab.close();
    }
}

// Compares two PNGs in the browser (no image libraries needed): the share of
// differing pixels, and a diff image (red where they differ)
async function compare(browser, a, b, diffFile) {
    const tab = await browser.newPage();
    try {
        const result = await tab.evaluate(async ({ a, b, tolerance }) => {
            const load = (src) => new Promise((resolve, reject) => {
                const img = new Image();
                img.onload = () => resolve(img);
                img.onerror = reject;
                img.src = src;
            });
            const [ia, ib] = await Promise.all([load(a), load(b)]);
            if (ia.width !== ib.width || ia.height !== ib.height) {
                return { share: 1, size: `${ia.width}x${ia.height} vs ${ib.width}x${ib.height}` };
            }
            const pixels = (img) => {
                const c = document.createElement('canvas');
                c.width = img.width;
                c.height = img.height;
                const g = c.getContext('2d');
                g.drawImage(img, 0, 0);
                return g.getImageData(0, 0, img.width, img.height);
            };
            const pa = pixels(ia), pb = pixels(ib);
            const out = document.createElement('canvas');
            out.width = ia.width;
            out.height = ia.height;
            const g = out.getContext('2d');
            const diff = g.createImageData(ia.width, ia.height);
            let count = 0;
            for (let i = 0; i < pa.data.length; i += 4) {
                const d = Math.max(Math.abs(pa.data[i] - pb.data[i]), Math.abs(pa.data[i + 1] - pb.data[i + 1]),
                    Math.abs(pa.data[i + 2] - pb.data[i + 2]), Math.abs(pa.data[i + 3] - pb.data[i + 3]));
                if (d > tolerance) {
                    count++;
                    diff.data.set([255, 0, 0, 255], i);
                } else {
                    // the image, faded
                    const v = (pa.data[i] + pa.data[i + 1] + pa.data[i + 2]) / 3;
                    diff.data.set([v / 3, v / 3, v / 3, 255], i);
                }
            }
            g.putImageData(diff, 0, 0);
            return { share: count / (pa.data.length / 4), diff: count ? out.toDataURL('image/png') : null };
        }, {
            a: 'data:image/png;base64,' + fs.readFileSync(a).toString('base64'),
            b: 'data:image/png;base64,' + fs.readFileSync(b).toString('base64'),
            tolerance: PIXEL_TOLERANCE,
        });
        if (result.diff) {
            fs.writeFileSync(diffFile, Buffer.from(result.diff.split(',')[1], 'base64'));
        }
        return result;
    } finally {
        await tab.close();
    }
}

function report(outDir, results, devices, pages) {
    const cell = (r) => {
        const rel = (f) => path.relative(outDir, f).split(path.sep).join('/');
        if (r.error) {
            return `<td class="bad"><b>failed</b><pre>${r.error.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</pre></td>`;
        }
        const status = r.status === 'same' ? '' : `<b>${r.status}</b>${r.share !== undefined ? ` (${(r.share * 100).toFixed(2)}% of pixels)` : ''}${r.size ? ' ' + r.size : ''}`;
        const images = [`<a href="${rel(r.file)}"><img src="${rel(r.file)}" title="new"></a>`];
        if (r.status === 'changed') {
            images.push(`<a href="${rel(r.baselineCopy)}"><img src="${rel(r.baselineCopy)}" title="baseline"></a>`);
            if (r.diffFile) images.push(`<a href="${rel(r.diffFile)}"><img src="${rel(r.diffFile)}" title="diff"></a>`);
        }
        return `<td class="${r.status === 'changed' ? 'bad' : r.status === 'new' ? 'new' : ''}">${status}${images.join('')}</td>`;
    };
    const rows = pages.map((p) => `<tr><th>${p}</th>${devices.map((d) => cell(results[d.name + '/' + p])).join('')}</tr>`).join('\n');
    const head = devices.map((d) => `<th>${d.name}<br><small>${d.width}×${d.height} @${d.ratio}x${d.config ? ' ' + JSON.stringify(d.config) : ''}</small></th>`).join('');
    fs.writeFileSync(path.join(outDir, 'report.html'), `<!doctype html><meta charset="utf-8"><title>UI gallery</title>
<style>body{font:14px system-ui;background:#111;color:#ddd;margin:16px}table{border-collapse:collapse}td,th{border:1px solid #333;padding:6px;vertical-align:top}
img{max-width:360px;display:block;margin-top:4px;image-rendering:pixelated}td.bad{background:#401818}td.new{background:#183018}pre{white-space:pre-wrap;max-width:360px;font-size:11px}</style>
<h1>UI gallery</h1><p>Changed pages show the new image, the baseline and the difference (red).</p>
<table><tr><th></th>${head}</tr>\n${rows}</table>`);
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const pages = args.pages ? args.pages.split(',') : PAGES;
    const devices = args.devices ? DEVICES.filter((d) => args.devices.split(',').includes(d.name)) : DEVICES;
    const outDir = path.resolve(args.out);
    const baselineDir = path.join(__dirname, 'baseline');
    fs.mkdirSync(path.join(outDir, 'new'), { recursive: true });
    fs.mkdirSync(path.join(outDir, 'baseline'), { recursive: true });
    fs.mkdirSync(path.join(outDir, 'diff'), { recursive: true });
    fs.mkdirSync(baselineDir, { recursive: true });

    const server = await serve(path.resolve(args.bundle));
    const base = `http://127.0.0.1:${server.address().port}`;
    const browser = await chromium.launch({
        args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
    });
    const results = {};
    let failed = 0;
    try {
        for (const device of devices) {
            const context = await browser.newContext({
                viewport: { width: device.width, height: device.height },
                deviceScaleFactor: device.ratio,
                isMobile: device.mobile,
                hasTouch: device.mobile,
                userAgent: device.ua,
            });
            for (const page of pages) {
                const key = device.name + '/' + page;
                const name = `${device.name}--${page}.png`;
                const file = path.join(outDir, 'new', name);
                const error = await capture(context, base, device, page, file);
                const baseline = path.join(baselineDir, name);
                let r;
                if (error) {
                    r = { error };
                } else if (!fs.existsSync(baseline)) {
                    r = { status: 'new', file };
                } else {
                    const baselineCopy = path.join(outDir, 'baseline', name);
                    fs.copyFileSync(baseline, baselineCopy);
                    const diffFile = path.join(outDir, 'diff', name);
                    const c = await compare(browser, file, baseline, diffFile);
                    r = { status: c.share > PAGE_TOLERANCE ? 'changed' : 'same', share: c.share, size: c.size, file, baselineCopy, diffFile: c.diff ? diffFile : null };
                }
                if (r.error || r.status === 'changed') failed++;
                if (args.update && !r.error) fs.copyFileSync(file, baseline);
                results[key] = r;
                console.log(`${key}: ${r.error ? 'FAILED ' + r.error.split('\n')[0] : r.status + (r.share ? ` (${(r.share * 100).toFixed(2)}%)` : '')}`);
            }
            await context.close();
        }
    } finally {
        await browser.close();
        server.close();
    }
    report(outDir, results, devices, pages);
    console.log(`report: ${path.join(outDir, 'report.html')}`);
    if (args.update) {
        console.log('baseline updated');
        return;
    }
    process.exit(failed ? 1 : 0);
}

main().catch((e) => {
    console.error(e);
    process.exit(2);
});
