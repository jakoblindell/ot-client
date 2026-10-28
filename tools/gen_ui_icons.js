// Renders the touch UI's icons (ot-client#28) from game-icons.net SVGs
// (CC BY 3.0, https://game-icons.net) to PNGs at 2x: a single-colour glyph
// on a transparent background, one file per icon and colour.
//
//   node tools/gen_ui_icons.js <game-icons checkout> <output dir>
//
// Also writes the round spell sheet: spell-icons-32x32.png with a circular
// mask, at 64 px per icon, 16 to a row.
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PW_MODULE || 'playwright');

const SIZE = 64;
const WHITE = '#e8e8e8', GOLD = '#e0b84c', YELLOW = '#f0d040', RED = '#e05050';
// output name -> game-icons file; written in white and gold (name_on)
const ICONS = {
    menu: 'delapouite/hamburger-menu', equipment: 'delapouite/chest-armor', map: 'lorc/treasure-map',
    skills: 'delapouite/histogram', battle: 'lorc/crossed-swords', vip: 'delapouite/star-formation',
    containers: 'delapouite/backpack', chat: 'skoll/talk', edit: 'delapouite/pencil',
    fullscreen: 'delapouite/expand', settings: 'lorc/cog',
    // equipment panel: fight mode, chase and secure mode
    fightOffensive: 'delapouite/sword-brandish', fightBalanced: 'lorc/scales', fightDefensive: 'lorc/checked-shield',
    stand: 'delapouite/person', chase: 'lorc/run', secure: 'lorc/dove',
    // UI setup (setup.lua)
    check: 'delapouite/check-mark', hunt: 'lorc/hunting-horn',
    // item card (client_itemdata)
    coins: 'delapouite/two-coins', drops: 'lorc/skull-crossed-bones',
    // a new client build is ready (client_updates)
    update: 'delapouite/upgrade',
};
// Hotbar special actions (modules/game_actionbar, by id): a glyph, and a
// small badge in the bottom right corner for the variant (nearest, lowest
// HP...) where the old icons had a letter
const MONSTER = 'delapouite/goblin-head', PLAYER = 'delapouite/person', TARGET = 'delapouite/crosshair';
const NEAREST = 'delapouite/contract', FURTHEST = 'delapouite/expand', HIGH = 'skoll/hearts';
const LOW = 'lorc/broken-heart', CYCLE = 'lorc/cycle';
const ACTIONS = {
    attackNearestMonster: [MONSTER, NEAREST], attackFurthestMonster: [MONSTER, FURTHEST],
    attackHighestHpMonster: [MONSTER, HIGH], attackLowestHpMonster: [MONSTER, LOW], cycleMonster: [MONSTER, CYCLE],
    attackNearestPlayer: [PLAYER, NEAREST], attackFurthestPlayer: [PLAYER, FURTHEST],
    attackHighestHpPlayer: [PLAYER, HIGH], attackLowestHpPlayer: [PLAYER, LOW], cyclePlayer: [PLAYER, CYCLE],
    followNearestPlayer: ['lorc/footprint', NEAREST],
    attackSkulled: ['lorc/skull-crossed-bones', CYCLE, RED], attackYellowSkull: ['lorc/skull-crossed-bones', CYCLE, YELLOW],
    attackNonParty: [PLAYER, 'delapouite/exit-door'],
    stopAttack: ['lorc/broadsword', 'sbed/cancel', WHITE, RED],
    convertCurrency: ['delapouite/two-coins', CYCLE, GOLD],
    useAtCrosshair: ['lorc/grab', TARGET], lookAtCrosshair: ['delapouite/eye-target'],
    contextMenuAtCrosshair: ['delapouite/hamburger-menu', TARGET],
    attackNext: [TARGET, 'delapouite/plain-arrow', WHITE, GOLD, -90], attackPrevious: [TARGET, 'delapouite/plain-arrow', WHITE, GOLD, 90],
    toggleChase: ['lorc/run'], toggleWasdChatMode: ['delapouite/keyboard'],
    // touch: arm a mode, then tap the game
    tapAttack: [TARGET], tapFollow: ['lorc/footprint'], tapLook: ['delapouite/eye-target'], tapUse: ['lorc/grab'],
};

(async () => {
    const [source, out] = process.argv.slice(2);
    fs.mkdirSync(path.join(out, 'actions'), { recursive: true });
    const browser = await chromium.launch();
    const page = await browser.newPage();
    const svg = (file) => fs.readFileSync(path.join(source, file + '.svg'), 'utf8');
    // glyph: [svg, colour]; badge: [svg, colour, degrees turned] or null
    const render = (glyph, badge) => page.evaluate(async ({ glyph, badge, size }) => {
        const load = async (svg, colour) => {
            // the icon path only (drop the black square behind it), in our colour
            svg = svg.replace(/<path d="M0 0h512v512H0z"\/>/, '').replace(/fill="#fff"/g, `fill="${colour}"`);
            const img = new Image();
            img.src = 'data:image/svg+xml;base64,' + btoa(svg);
            await img.decode();
            return img;
        };
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = size;
        const ctx = canvas.getContext('2d');
        const main = await load(...glyph);
        if (!badge) {
            ctx.drawImage(main, 0, 0, size, size);
        } else {
            // the glyph a little smaller and up left, the badge on a dark disc
            ctx.drawImage(main, 0, 0, size * 0.78, size * 0.78);
            const b = size * 0.56, x = size - b, y = size - b;
            ctx.fillStyle = '#141414';
            ctx.beginPath();
            ctx.arc(x + b / 2, y + b / 2, b / 2, 0, Math.PI * 2);
            ctx.fill();
            const img = await load(badge[0], badge[1]);
            ctx.save();
            ctx.translate(x + b / 2, y + b / 2);
            ctx.rotate((badge[2] || 0) * Math.PI / 180);
            ctx.drawImage(img, -b * 0.36, -b * 0.36, b * 0.72, b * 0.72);
            ctx.restore();
        }
        return canvas.toDataURL('image/png').split(',')[1];
    }, { glyph, badge, size: SIZE });
    const write = (file, data) => fs.writeFileSync(path.join(out, file), Buffer.from(data, 'base64'));
    for (const [name, file] of Object.entries(ICONS)) {
        write(name + '.png', await render([svg(file), WHITE], null));
        write(name + '_on.png', await render([svg(file), GOLD], null));
    }
    for (const [id, [glyph, badge, colour, badgeColour, turn]] of Object.entries(ACTIONS)) {
        write('actions/' + id + '.png', await render([svg(glyph), colour || WHITE],
            badge ? [svg(badge), badgeColour || GOLD, turn] : null));
    }

    // round spells: every 32 px tile scaled to 64 and cut to a circle
    const sheet = fs.readFileSync(path.join(__dirname, '../data/images/game/spells/spell-icons-32x32.png')).toString('base64');
    const round = await page.evaluate(async (sheet) => {
        const img = new Image();
        img.src = 'data:image/png;base64,' + sheet;
        await img.decode();
        // in rows of 16 (textures may be at most 8192 px wide)
        const count = img.width / 32, size = 64, columns = 16;
        const canvas = document.createElement('canvas');
        canvas.width = columns * size;
        canvas.height = Math.ceil(count / columns) * size;
        const ctx = canvas.getContext('2d');
        ctx.imageSmoothingEnabled = false;
        for (let i = 0; i < count; i++) {
            const x = (i % columns) * size, y = Math.floor(i / columns) * size;
            ctx.save();
            ctx.beginPath();
            ctx.arc(x + size / 2, y + size / 2, size / 2 - 1, 0, Math.PI * 2);
            ctx.clip();
            ctx.drawImage(img, i * 32, 0, 32, 32, x, y, size, size);
            ctx.restore();
        }
        return canvas.toDataURL('image/png').split(',')[1];
    }, sheet);
    fs.writeFileSync(path.join(out, 'spell-icons-round-64x64.png'), Buffer.from(round, 'base64'));
    await browser.close();
})();
