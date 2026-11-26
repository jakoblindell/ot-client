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
//   --out      where screenshots, diffs, report.html and summary.md go
//              (default: out)
//   --update   save this run as the baseline: changed and new screenshots,
//              the doesn't-fit findings as the known ones, and (a full run)
//              baselines of pages that are gone removed
//
// The pages come from the client (mods/client_gallery/pages), not a list here.
//
// Exit code 1 for real problems only: a page that failed to load, a page
// with a baseline that is no longer in the run, or a doesn't-fit finding
// that is not in baseline/doesnt-fit.txt (the findings the baseline already
// has). Changed and new images are reported (report.html, summary.md) but
// do not fail. Baselines live in ./baseline; CI makes them on web-client-792
// (software rendering differs slightly between machines).
'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const { chromium } = require(process.env.PW_MODULE || 'playwright');

// Pages with keyboard: true (G.page in the client) are shown with the
// on-screen keyboard open, on touch devices only: the page tells the game
// the part of the canvas above the keyboard, as shell.html does from
// visualViewport (keyboardVisibleTop/Bottom). Assumed keyboard heights:
// 300 px in portrait, 210 px in landscape (iPhone).

// Mostly landscape, as the game is played, plus an iPhone in portrait and one
// turned to landscape after the page loaded (the screen resized under a
// running client). mobile: the touch layout (chosen from the user agent).
// config: extra window.otclientConfig settings. rotateTo: the screen size
// the page is resized to once it is ready, before the screenshot.
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';
const IPAD = 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const DEVICES = [
    { name: 'phone-small', width: 667, height: 375, ratio: 2, mobile: true, ua: ANDROID },
    { name: 'phone-big', width: 932, height: 430, ratio: 3, mobile: true, ua: ANDROID },
    { name: 'phone-big-sharp', width: 932, height: 430, ratio: 3, mobile: true, ua: ANDROID, config: { sharpness: 2 } },
    { name: 'tablet', width: 1180, height: 820, ratio: 2, mobile: true, ua: IPAD },
    // iPhone 15 Pro, the page area under Safari's toolbars
    { name: 'iphone-portrait', width: 393, height: 660, ratio: 3, mobile: true, ua: IPHONE },
    { name: 'iphone-rotated', width: 393, height: 660, ratio: 3, mobile: true, ua: IPHONE, rotateTo: { width: 852, height: 375 } },
    { name: 'desktop', width: 1366, height: 768, ratio: 1, mobile: false },
    { name: 'desktop-scale-1.5', width: 1366, height: 768, ratio: 1, mobile: false, config: { galleryHudScale: 1.5 } },
];

// The doesn't-fit findings the baseline already has, one "device/page: finding"
// per line, in baseline/ next to the images
const KNOWN_FILE = 'doesnt-fit.txt';

// Pixels whose colour differs by more than this (0-255, any channel) count
const PIXEL_TOLERANCE = 24;
// A page differs when more than this share of its pixels do
const PAGE_TOLERANCE = 0.001;

function parseArgs(argv) {
    const args = { out: 'out', update: false, known: path.join(__dirname, 'baseline', KNOWN_FILE) };
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

// The client's pages: the gallery opened with '@list' logs them
async function listPages(browser, base) {
    const context = await browser.newContext({ viewport: { width: 1366, height: 768 } });
    const tab = await context.newPage();
    const pages = [], problems = [], log = [];
    try {
        await tab.addInitScript(() => { window.otclientConfig = Object.assign(window.otclientConfig || {}, { gallery: '@list' }); });
        const done = new Promise((resolve) => {
            tab.on('console', (msg) => {
                const text = msg.text();
                log.push(text);
                const page = text.match(/\[gallery\] page (\{.*\})/);
                if (page) pages.push(JSON.parse(page[1]));
                // a page file that failed to load, a name used twice
                const problem = text.match(/\[gallery\] (pages\/.*|page ".*" is defined twice)/);
                if (problem) problems.push(problem[1]);
                if (text.includes('[gallery] pages done')) resolve();
            });
        });
        await tab.goto(base + '/otclient.html', { waitUntil: 'load' });
        await Promise.race([done, new Promise((_, reject) => setTimeout(() => reject(new Error('no "[gallery] pages done" within 120 s')), 120000))]);
    } catch (e) {
        throw new Error(e.message + '\n' + log.filter((l) => /error|gallery/i.test(l)).slice(-15).join('\n'));
    } finally {
        await context.close();
    }
    return { pages, problems };
}

// A finding as it is compared with the known ones: without numbers (widget
// ids, positions and sizes move when anything else on the page does)
function findingKey(key, line) {
    return key + ': ' + line.replace(/\d+/g, 'N');
}

function readKnown(file) {
    if (!fs.existsSync(file)) return null;
    return new Set(fs.readFileSync(file, 'utf8').split('\n').filter((l) => l && !l.startsWith('#')));
}

// One page on one device: the screenshot, or an error
async function capture(context, base, device, page, file, clipped) {
    const tab = await context.newPage();
    const log = [];
    try {
        const config = Object.assign({ gallery: page.name }, device.config || {});
        await tab.addInitScript((c) => { window.otclientConfig = Object.assign(window.otclientConfig || {}, c); }, config);
        if (page.keyboard) {
            // (again and again: the page clears them when its own text input
            // loses focus, and the screen may turn)
            await tab.addInitScript(() => {
                const set = () => {
                    const c = (window.otclientConfig = window.otclientConfig || {});
                    const w = window.innerWidth, h = window.innerHeight;
                    c.keyboardVisibleTop = '0';
                    c.keyboardVisibleBottom = ((h - (h > w ? 300 : 210)) / h).toFixed(4);
                };
                set();
                setInterval(set, 100);
            });
        }
        let markChecked;
        const checked = new Promise((resolve) => { markChecked = resolve; });
        const ready = new Promise((resolve, reject) => {
            tab.on('console', (msg) => {
                const text = msg.text();
                log.push(text);
                // text that doesn't fit, a widget outside its parent or the screen
                const found = text.match(/\[gallery\] (clipped|outside) (.*)/);
                if (found) clipped.push((found[1] === 'outside' ? 'outside: ' : '') + found[2]);
                if (text.includes('[gallery] checked ' + page.name)) markChecked();
                if (text.includes('[gallery] ready ' + page.name)) resolve();
                if (text.includes('[gallery] no page')) reject(new Error(text));
            });
            tab.on('pageerror', (e) => log.push('pageerror: ' + e.message));
        });
        await tab.goto(base + '/otclient.html', { waitUntil: 'load' });
        // the page's loading text sits over the canvas
        await tab.addStyleTag({ content: '#title-text, #start { display: none !important; }' });
        await Promise.race([ready, new Promise((_, reject) => setTimeout(() => reject(new Error('no "[gallery] ready" within 120 s')), 120000))]);
        if (device.rotateTo) {
            await tab.setViewportSize(device.rotateTo);
            await tab.waitForTimeout(1500);
        }
        await tab.waitForTimeout(300);
        await tab.screenshot({ path: file });
        // the checks (cut off or covered text, widgets outside their parent
        // or the screen) run after "ready"
        await Promise.race([checked, tab.waitForTimeout(10000)]);
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

const escape = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

function report(outDir, results, devices, pages) {
    const cell = (r) => {
        const rel = (f) => path.relative(outDir, f).split(path.sep).join('/');
        if (!r || r.status === 'skipped') {
            return '<td>-</td>';
        }
        if (r.error) {
            return `<td class="bad"><b>failed</b><pre>${escape(r.error)}</pre></td>`;
        }
        const fits = (title, lines) => lines.length ? `<b>${title}</b><pre>${escape(lines.join('\n'))}</pre>` : '';
        const cut = fits("doesn't fit (new)", r.newFindings || []) + fits("doesn't fit (already on the baseline)", r.knownFindings || []);
        const status = cut + (r.status === 'same' ? '' : `<b>${r.status}</b>${r.share !== undefined ? ` (${(r.share * 100).toFixed(2)}% of pixels)` : ''}${r.size ? ' ' + r.size : ''}`);
        const images = [`<a href="${rel(r.file)}"><img src="${rel(r.file)}" title="new"></a>`];
        if (r.status === 'changed') {
            images.push(`<a href="${rel(r.baselineCopy)}"><img src="${rel(r.baselineCopy)}" title="baseline"></a>`);
            if (r.diffFile) images.push(`<a href="${rel(r.diffFile)}"><img src="${rel(r.diffFile)}" title="diff"></a>`);
        }
        const cls = r.newFindings && r.newFindings.length ? 'bad' : r.status === 'changed' ? 'changed' : r.status === 'new' ? 'new' : '';
        return `<td class="${cls}">${status}${images.join('')}</td>`;
    };
    const rows = pages.map((p) => `<tr><th>${p.name}${p.about ? `<br><small>${escape(p.about)}</small>` : ''}</th>${devices.map((d) => cell(results[d.name + '/' + p.name])).join('')}</tr>`).join('\n');
    const head = devices.map((d) => `<th>${d.name}<br><small>${d.width}×${d.height}${d.rotateTo ? ' → ' + d.rotateTo.width + '×' + d.rotateTo.height : ''} @${d.ratio}x${d.config ? ' ' + JSON.stringify(d.config) : ''}</small></th>`).join('');
    fs.writeFileSync(path.join(outDir, 'report.html'), `<!doctype html><meta charset="utf-8"><title>UI gallery</title>
<style>body{font:14px system-ui;background:#111;color:#ddd;margin:16px}table{border-collapse:collapse}td,th{border:1px solid #333;padding:6px;vertical-align:top}
th small{font-weight:normal;display:block;max-width:200px}
img{max-width:360px;display:block;margin-top:4px;image-rendering:pixelated}td.bad{background:#401818}td.changed{background:#403418}td.new{background:#183018}pre{white-space:pre-wrap;max-width:360px;font-size:11px}</style>
<h1>UI gallery</h1><p>Changed pages show the new image, the baseline and the difference (red). Red cells fail the check.</p>
<table><tr><th></th>${head}</tr>\n${rows}</table>`);
}

// summary.md: what the check found, for the job summary
function summary(outDir, s, update) {
    const md = [];
    const list = (title, lines) => {
        if (!lines.length) return;
        md.push(`#### ${title}`, '', ...lines.map((l) => '- ' + l), '');
    };
    md.push(update ? '### UI screenshots: baseline updated' : '### UI screenshots', '');
    md.push(`${s.pages} pages on ${s.devices} devices: ${s.same.length} same, ${s.changed.length} changed, ${s.added.length} new, ` +
        `${s.errors.length} failed, ${s.missing.length} missing.`, '');
    if (s.failures) {
        md.push(`**The check fails:** ${s.failures} problem(s) below (a page that failed or is missing, or something that doesn't fit and is not on the baseline yet).`, '');
    } else if (!update) {
        md.push('No problems. Changed images do not fail the check; look at them in the report.', '');
    }
    list('Failed to load', s.errors.map((e) => `\`${e.key}\`: ${e.error.split('\n')[0]}`));
    list(update ? 'Removed (no longer a page)' : 'Missing (a baseline image, no page in this run)', s.missing.map((k) => `\`${k}\``));
    list(update ? "Doesn't fit (recorded as known)" : "Doesn't fit (new, not on the baseline)", s.newFindings.map((l) => '`' + l + '`'));
    list(update ? 'Updated images' : 'Changed images (compared with the baseline)', s.changed.map((c) => `\`${c.key}\` (${(c.share * 100).toFixed(2)}% of pixels${c.size ? ', ' + c.size : ''})`));
    list(update ? 'New images' : 'New pages or devices (no baseline yet)', s.added.map((k) => `\`${k}\``));
    if (s.knownFindings.length && !update) {
        md.push(`<details><summary>${s.knownFindings.length} doesn't-fit finding(s) already on the baseline (not failing)</summary>`, '',
            ...s.knownFindings.map((l) => '- `' + l + '`'), '', '</details>', '');
    }
    md.push(`Images: the \`ui-gallery-*\` artifact of this run, \`report.html\` (new, baseline and diff images); \`summary.md\` is this text.`);
    fs.writeFileSync(path.join(outDir, 'summary.md'), md.join('\n') + '\n');
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const devices = args.devices ? DEVICES.filter((d) => args.devices.split(',').includes(d.name)) : DEVICES;
    // (a subset run checks and updates only what it ran)
    const full = !args.pages && !args.devices;
    const outDir = path.resolve(args.out);
    const baselineDir = path.join(__dirname, 'baseline');
    const knownFile = path.resolve(args.known);
    fs.mkdirSync(path.join(outDir, 'new'), { recursive: true });
    fs.mkdirSync(path.join(outDir, 'baseline'), { recursive: true });
    fs.mkdirSync(path.join(outDir, 'diff'), { recursive: true });
    fs.mkdirSync(baselineDir, { recursive: true });
    const known = readKnown(knownFile);

    const server = await serve(path.resolve(args.bundle));
    const base = `http://127.0.0.1:${server.address().port}`;
    const browser = await chromium.launch({
        args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
    });
    const results = {};
    const s = { pages: 0, devices: devices.length, same: [], changed: [], added: [], errors: [], missing: [], newFindings: [], knownFindings: [], failures: 0 };
    const findings = [];
    let pages = [];
    try {
        const listed = await listPages(browser, base);
        for (const problem of listed.problems) {
            s.errors.push({ key: 'pages', error: problem });
        }
        pages = listed.pages;
        if (args.pages) {
            const wanted = args.pages.split(',');
            for (const name of wanted.filter((n) => !pages.some((p) => p.name === n))) {
                s.errors.push({ key: name, error: 'no such page' });
            }
            pages = pages.filter((p) => wanted.includes(p.name));
        }
        if (!listed.pages.length) {
            s.errors.push({ key: 'pages', error: 'the client listed no pages' });
        }
        s.pages = pages.length;
        console.log(`pages: ${pages.map((p) => p.name).join(', ')}`);
        for (const device of devices) {
            const context = await browser.newContext({
                viewport: { width: device.width, height: device.height },
                deviceScaleFactor: device.ratio,
                isMobile: device.mobile,
                hasTouch: device.mobile,
                userAgent: device.ua,
            });
            for (const page of pages) {
                const key = device.name + '/' + page.name;
                if (page.keyboard && !device.mobile) {
                    results[key] = { status: 'skipped' };
                    continue;
                }
                const name = `${device.name}--${page.name}.png`;
                const file = path.join(outDir, 'new', name);
                const clipped = [];
                const error = await capture(context, base, device, page, file, clipped);
                const baseline = path.join(baselineDir, name);
                let r;
                if (error) {
                    r = { error };
                    s.errors.push({ key, error });
                } else if (!fs.existsSync(baseline)) {
                    r = { status: 'new', file };
                    s.added.push(key);
                } else {
                    const baselineCopy = path.join(outDir, 'baseline', name);
                    fs.copyFileSync(baseline, baselineCopy);
                    const diffFile = path.join(outDir, 'diff', name);
                    const c = await compare(browser, file, baseline, diffFile);
                    r = { status: c.share > PAGE_TOLERANCE ? 'changed' : 'same', share: c.share, size: c.size, file, baselineCopy, diffFile: c.diff ? diffFile : null };
                    (r.status === 'changed' ? s.changed : s.same).push(r.status === 'changed' ? { key, share: c.share, size: c.size } : key);
                }
                // text cut off by its widget, or a widget outside its parent
                // or the screen: fails the page unless the baseline has it
                // already (known), baseline image or not
                if (!r.error) {
                    r.newFindings = [];
                    r.knownFindings = [];
                    for (const line of clipped) {
                        const k = findingKey(key, line);
                        findings.push(k);
                        if (!args.update && known && known.has(k)) {
                            r.knownFindings.push(line);
                            s.knownFindings.push(k);
                        } else {
                            r.newFindings.push(line);
                            s.newFindings.push(k);
                        }
                    }
                }
                // (only what changed: a "same" image saved again would be a
                // new file for every pixel of rounding)
                if (args.update && !r.error && r.status !== 'same') fs.copyFileSync(file, baseline);
                results[key] = r;
                console.log(`${key}: ${r.error ? 'FAILED ' + r.error.split('\n')[0] : r.status + (r.share ? ` (${(r.share * 100).toFixed(2)}%)` : '')}`);
                for (const line of r.newFindings || []) console.log(`  doesn't fit: ${line}`);
                for (const line of r.knownFindings || []) console.log(`  doesn't fit (known): ${line}`);
            }
            await context.close();
        }
    } catch (e) {
        s.errors.push({ key: 'run', error: e.message });
        console.error(e);
    } finally {
        await browser.close();
        server.close();
    }

    // Baseline images of pages that are not in this run: a page that is
    // gone, or failed to register (a full run only, and only when the page
    // list came; an intended removal goes away with --update)
    const ran = new Set();
    for (const device of devices) {
        for (const page of pages) ran.add(`${device.name}--${page.name}.png`);
    }
    if (full && pages.length) {
        for (const file of fs.readdirSync(baselineDir).filter((f) => f.endsWith('.png')).sort()) {
            if (ran.has(file)) continue;
            s.missing.push(file.replace(/\.png$/, '').replace('--', '/'));
            if (args.update) fs.unlinkSync(path.join(baselineDir, file));
        }
    }

    // This run's findings, as a known-findings file (the baseline's, with --update)
    const header = "# Doesn't-fit findings the baseline already has (tools/ui-gallery/gallery.js --update).\n" +
        '# A pull request fails only on findings that are not listed here.\n';
    const findingsText = (lines) => header + [...new Set(lines)].sort().join('\n') + (lines.length ? '\n' : '');
    fs.writeFileSync(path.join(outDir, KNOWN_FILE), findingsText(findings));
    if (args.update) {
        let lines = findings;
        if (!full && known) {
            // keep the findings of the pages this run did not see again
            const seen = new Set(Object.keys(results).filter((k) => results[k].status && results[k].status !== 'skipped'));
            lines = [...known].filter((l) => !seen.has(l.split(': ')[0])).concat(findings);
        }
        fs.writeFileSync(knownFile, findingsText(lines));
    }

    s.failures = s.errors.length + (args.update ? 0 : s.missing.length + s.newFindings.length);
    if (pages.length) report(outDir, results, devices, pages);
    summary(outDir, s, args.update);
    console.log(fs.readFileSync(path.join(outDir, 'summary.md'), 'utf8'));
    console.log(`report: ${path.join(outDir, 'report.html')}`);
    if (args.update) console.log('baseline updated');
    process.exit(s.failures ? 1 : 0);
}

main().catch((e) => {
    console.error(e);
    process.exit(2);
});
