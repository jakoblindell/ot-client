-- UI gallery for screenshot tests (ot-client#70).
--
-- Opened with window.otclientConfig.gallery = '<page>' (the screenshot
-- script sets it; tools/ui-gallery). Shows one page of our components over
-- the login screen and logs "[gallery] ready <page>" when it is drawn, so
-- the script knows when to take the picture. Nothing happens without it.
--
-- Optional: window.otclientConfig.galleryHudScale (a number) sets the
-- interface scale first, for the in-between scales.

local root
local PAGES = {}
local PAGE_ORDER = { 'buttons', 'controls', 'text', 'touch', 'hub', 'journal', 'achievements', 'npc', 'hotbar', 'outfit',
    'settings-gameplay', 'settings-display', 'settings-controls', 'settings-layout', 'settings-optimization',
    'letter', 'letter-keyboard', 'letter-read', 'house-list', 'house-list-keyboard', 'messages' }

-- Helpers -------------------------------------------------------------------

local function widget(style, parent, setup)
    local w = g_ui.createWidget(style, parent)
    if setup then
        setup(w)
    end
    return w
end

-- A caption and a row of components, the row as high as given
local function section(parent, caption, height)
    local s = g_ui.createWidget('GallerySection', parent)
    s:setHeight(14 + 4 + height)
    s:getChildById('caption'):setText(caption)
    return s:getChildById('items')
end

local function button(style, parent, text, width, state)
    return widget(style, parent, function(w)
        w:setText(text)
        if width then
            w:setWidth(width)
        end
        if state == 'checked' then
            w:setChecked(true)
        elseif state == 'on' then
            w:setOn(true)
        elseif state == 'disabled' then
            w:setEnabled(false)
        end
    end)
end

-- A holder as high as the row, so a smaller component (the ? button, a
-- check box) keeps its own size, centred
local function holder(parent, width)
    local h = g_ui.createWidget('UIWidget', parent)
    h:setWidth(width)
    h:setPhantom(true)
    return h
end

local function centered(style, parent, width, setup)
    local w = widget(style, holder(parent, width), setup)
    w:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    w:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    return w
end

local function column(parent, width)
    local c = g_ui.createWidget('GalleryColumn', parent)
    c:setWidth(width)
    return c
end

-- Round buttons: the face client_mobile gives them (setRoundFace, ot-client#66)
-- when it has one, else the style's image
local function roundFace(w, kind)
    local mobile = modules.client_mobile
    if mobile and mobile.setRoundFace then
        mobile.setRoundFace(w, kind)
    end
end

-- Pages -----------------------------------------------------------------------

PAGES.buttons = function(page)
    local c = column(page, 560)
    local row = section(c, 'OtButton: normal, checked, on, disabled', 40)
    button('OtButton', row, 'Normal', 110)
    button('OtButton', row, 'Checked', 110, 'checked')
    button('OtButton', row, 'On', 110, 'on')
    button('OtButton', row, 'Disabled', 110, 'disabled')

    row = section(c, 'OtButtonPrimary, OtButtonDanger, OtIconButton, OtHelpButton', 40)
    button('OtButtonPrimary', row, 'Confirm', 110)
    button('OtButtonDanger', row, 'Delete', 110)
    button('OtIconButton', row, 'X')
    button('OtIconButton', row, '-')
    button('OtIconButton', row, '+')
    centered('OtHelpButton', row, 30)

    row = section(c, 'OtTabRow with OtTab (first checked)', 36)
    local tabs = widget('OtTabRow', row, function(w) w:setWidth(400) end)
    button('OtTab', tabs, 'Quests', nil, 'checked')
    button('OtTab', tabs, 'Tasks')
    button('OtTab', tabs, 'Achievements')
    button('OtTab', tabs, 'Chests')
end

PAGES.controls = function(page)
    local c = column(page, 560)
    local row = section(c, 'OtCheck: off, on, disabled on', 40)
    widget('OtCheck', row)
    widget('OtCheck', row, function(w) w:setChecked(true) end)
    widget('OtCheck', row, function(w) w:setChecked(true); w:setEnabled(false) end)

    row = section(c, 'OtProgress: 0, 45 and 100 percent', 24)
    for _, percent in ipairs({ 0, 45, 100 }) do
        widget('OtProgress', row, function(w)
            w:setWidth(150)
            w:setPercent(percent)
            w:setText(percent .. ' / 100')
        end)
    end

    row = section(c, 'Stepper: OtIconButton, OtValue, OtIconButton', 40)
    button('OtIconButton', row, '-')
    widget('OtValue', row, function(w) w:setText('5') end)
    button('OtIconButton', row, '+')

    row = section(c, 'OtSettingRow in an OtPanel; an OtPanel on (contrast)', 136)
    local panel = widget('OtPanel', row, function(w)
        w:setSize({ width = 380, height = 136 })
        w:setLayout(UIVerticalLayout.create(w))
    end)
    local setting = widget('OtSettingRow', panel)
    setting:getChildById('title'):setText('Sharpness')
    local controls = setting:getChildById('controls')
    button('OtButton', controls, 'Normal', 90, 'checked')
    button('OtButton', controls, 'High', 90)
    setting = widget('OtSettingRow', panel)
    setting:getChildById('title'):setText('Vibration')
    widget('OtCheck', setting:getChildById('controls'), function(w) w:setChecked(true) end)

    local contrast = widget('OtPanel', row, function(w)
        w:setSize({ width = 160, height = 136 })
        w:setOn(true)
    end)
    widget('OtLabel', contrast, function(w)
        w:setText('Contrast on')
        w:addAnchor(AnchorTop, 'parent', AnchorTop)
        w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        w:resizeToText()
    end)
end

PAGES.text = function(page)
    local c = column(page, 560)
    local row = section(c, 'OtTitle', 20)
    widget('OtTitle', row, function(w) w:setText('Journal') end)

    row = section(c, 'OtHeading', 28)
    widget('OtHeading', row, function(w)
        w:setWidth(400)
        w:getChildById('text'):setText('QUESTS')
    end)

    row = section(c, 'OtLabel, small font', 16)
    widget('OtLabel', row, function(w) w:setText('Hunter rank: Skilled Hunter'); w:resizeToText() end)
    widget('GalleryFontSmall', row, function(w) w:setText('Small text: 12 of 21 unlocked') end)

    row = section(c, 'OtText (wraps), OtHint', 60)
    widget('OtText', row, function(w)
        w:setWidth(260)
        w:setText('Kill 100 rotworms in the sewers under Thais and report back to the Taskmaster.')
    end)
    widget('OtHint', row, function(w)
        w:setWidth(260)
        w:setText('Hidden achievements show their name once you have them.')
    end)

    row = section(c, 'Colours: gold, gold dark, positive, negative, muted', 28)
    widget('GallerySwatchGold', row, function(w) w:setText('gold') end)
    widget('GallerySwatchGoldDark', row, function(w) w:setText('dark') end)
    widget('GallerySwatchPositive', row, function(w) w:setText('positive') end)
    widget('GallerySwatchNegative', row, function(w) w:setText('negative') end)
    widget('GallerySwatchMuted', row, function(w) w:setText('muted') end)
end

PAGES.touch = function(page)
    local c = column(page, 560)
    -- (no items in them: the game's sprites are not part of the client build)
    local row = section(c, 'Hotbar slot: 32, 40, 48 and 64 px', 64)
    for _, size in ipairs({ 32, 40, 48, 64 }) do
        centered('MobileHotbarRoundButton', row, size, function(w)
            w:setSize({ width = size, height = size })
            roundFace(w, 'gold')
        end)
    end

    row = section(c, 'Chat button: closed, open; preset and edit: off, on', 48)
    centered('MobileChatButton', row, 48, function(w) roundFace(w, 'gold') end)
    centered('MobileChatButton', row, 48, function(w)
        roundFace(w, 'gold')
        w:setChecked(true)
        w:getChildById('icon'):setImageSource('/images/ui/ot/icons/chat_on')
    end)
    for _, on in ipairs({ false, true }) do
        centered('MobileHotbarPresetRow', row, 84, function(w)
            for _, id in ipairs({ 'preset', 'edit' }) do
                local b = w:getChildById(id)
                roundFace(b, 'silver')
                b:setOn(on)
            end
            if on then
                w:getChildById('edit'):getChildById('icon'):setImageSource('/images/ui/ot/icons/edit_on')
            end
        end)
    end

    row = section(c, 'Health and mana bars: full, 30 percent', 22)
    for _, part in ipairs({ 1, 0.3 }) do
        widget('MobileStats', row, function(w)
            w:setWidth(260)
            for _, id in ipairs({ 'health', 'mana' }) do
                local bar = w:getChildById(id)
                local fill = bar:getChildById('fill')
                if id == 'mana' then
                    fill:setImageSource('/mods/client_mobile/images/bar_mana')
                end
                fill:setWidth(math.floor((130 - 3 - 2) * part))
                bar:getChildById('text'):setText(math.floor(345 * part) .. ' / 345')
            end
        end)
    end

    row = section(c, 'Toolbar: normal, checked (open), on (pinned)', 44)
    widget('MobileToolbar', row, function(w)
        w:setWidth(320)
        local buttons = w:getChildById('buttons')
        for i, icon in ipairs({ 'menu', 'equipment', 'map', 'battle', 'containers' }) do
            widget('MobileToolbarButton', buttons, function(b)
                b:setIcon('/images/ui/ot/icons/' .. icon .. (i == 3 and '_on' or ''))
                b:setChecked(i == 3)
                b:setOn(i == 4)
            end)
        end
    end)
end

-- Whole screens, with sample data (no server) ------------------------------------

-- A fixed clock: the hub shows the time, and a screenshot must not change
-- from one run to the next (gallery mode only)
local FIXED_TIME = 1767268800 -- 2026-01-01 12:00 UTC
local realDate = os.date
local function fixClock()
    os.date = function(format, time)
        return realDate(format, time or FIXED_TIME)
    end
end

-- What the server would send on an extended opcode
local function receive(opcode, data)
    ProtocolGame.onExtendedOpcode(nil, opcode, json.encode(data))
end

-- The first widget under root showing the text (a hub button, a tab);
-- visibleOnly: only widgets shown now (a hidden desktop window may have a
-- button with the same text)
local function findByText(root, text, visibleOnly)
    for _, child in ipairs(root:getChildren()) do
        if not visibleOnly or child:isVisible() then
            if child.getText and child:getText() == text then
                return child
            end
            local found = findByText(child, text, visibleOnly)
            if found then
                return found
            end
        end
    end
end

local function tap(text)
    local widget = findByText(g_ui.getRootWidget(), text, true)
    if widget and widget.onClick then
        widget:onClick()
    end
end

local SAMPLE_ACHIEVEMENTS = {
    unlocked = 1, count = 4, points = 1, totalPoints = 9,
    categories = { { id = 'milestones', name = 'Milestones' }, { id = 'hunting', name = 'Hunting' }, { id = 'luck', name = 'Luck' } },
    list = {
        { id = 1, category = 'milestones', points = 1, name = 'First Steps', text = 'Reach level 20.', unlockedAt = FIXED_TIME },
        { id = 2, category = 'milestones', points = 2, name = 'Seasoned', text = 'Reach level 50.' },
        { id = 20, category = 'hunting', points = 1, name = 'Rat Catcher', text = 'Kill 100 rats.', progress = 45, target = 100 },
        { category = 'luck', points = 5, hidden = true },
    },
}

local SAMPLE_QUESTS = {
    part = 'quests', regions = { 'Mainland', 'Rookgaard' },
    quests = {
        { name = 'The Ancient Tombs', started = true, complete = false, done = 2, missions = 7, text = 'Find the third tomb under the desert.' },
        { name = 'Factions', started = false, done = 0, missions = 3 },
        { name = "Sam's Old Backpack", started = true, complete = true, done = 2, missions = 2, text = 'Sam has his backpack back.' },
    },
}

local SAMPLE_CHESTS = {
    part = 'chests', first = true, more = false,
    chests = {
        { name = 'Boots Of Haste Quest', reward = 'Boots Of Haste', region = 'Mainland', opened = true },
        { name = '100x Gold Coin Quest', reward = '100x Gold Coin', region = 'Rookgaard', opened = false },
    },
}

local function journalData()
    receive(106, { achievements = SAMPLE_ACHIEVEMENTS })
    receive(106, { journal = SAMPLE_QUESTS })
    receive(106, { journal = SAMPLE_CHESTS })
end

local function openHub()
    local mobile = modules.client_mobile
    if mobile and mobile.openHub then
        mobile.openHub()
    end
end

PAGES.hub = function()
    openHub()
end

PAGES.journal = function()
    journalData()
    openHub()
    tap(tr('Journal'))
end

PAGES.achievements = function()
    journalData()
    openHub()
    tap(tr('Journal'))
    tap(tr('Achievements'))
end

PAGES.npc = function()
    receive(103, {
        id = 1, npc = 'Benjamin', money = 1500,
        text = 'Hello, traveller. I sell runes and fluids. Ask me for a trade, or about the news.',
        -- every word the NPC takes (ot-server#88): more than four rows scroll
        keywords = { 'trade', 'news', 'job', 'name', 'time', 'king', 'thais', 'carlin', 'venore', 'magic',
            'fluids', 'runes', 'blessings', 'rumours', 'tibia', 'excalibug', 'ferumbras', 'library' },
        buy = {
            { item = 3160, name = 'ultimate healing rune', price = 175, words = 'buy ultimate healing rune' },
            { item = 3155, name = 'sudden death rune', price = 325, words = 'buy sudden death rune' },
            { item = 3152, name = 'intense healing rune', price = 95, words = 'buy intense healing rune' },
        },
        sell = { { item = 3147, name = 'blank rune', price = 5, words = 'sell blank rune' } },
    })
    for _, child in ipairs(g_ui.getRootWidget():getChildren()) do
        if child:getStyleName() == 'NpcDialogWindow' then
            return { child }
        end
    end
end

PAGES.hotbar = function()
    local mobile = modules.client_mobile
    if mobile and mobile.openHotbarSettings then
        mobile.openHotbarSettings()
    end
end

-- The outfit screen for touch screens (ot-client#101), with sample outfits
PAGES.outfit = function()
    local mobile = modules.client_mobile
    if mobile and mobile.openOutfitSheet then
        mobile.openOutfitSheet({ type = 128, head = 78, body = 69, legs = 58, feet = 76, addons = 1 }, {
            { 128, 'Citizen', 3 }, { 129, 'Hunter', 3 }, { 130, 'Mage', 0 }, { 131, 'Knight', 1 },
        }, function() end)
    end
end

-- The hub's Settings, one page per tab
for _, tab in ipairs({ 'Gameplay', 'Display', 'Controls', 'Layout', 'Optimization' }) do
    PAGES['settings-' .. tab:lower()] = function()
        openHub()
        tap(tr('Settings'))
        tap(tr(tab))
    end
end

-- Text windows (ot-client#124): a letter as the server opens it (Edit Text),
-- the same letter only to read, and a house list (Edit List). The -keyboard
-- pages are the same windows with the on-screen keyboard open: gallery.js
-- sets keyboardVisibleTop/Bottom as the page would (shell.html).
local SAMPLE_LETTER = 'Dear Aren,\n\nthe ferry leaves at dawn. Bring the map, two ropes and something to eat; ' ..
    'the island has nothing but rats.\n\nIf the weather turns, wait for me at the lighthouse.\n\n- Mira'

local function textWindows()
    return modules.game_textwindow
end

PAGES.letter = function()
    textWindows().onGameEditText(1, 0, 1000, SAMPLE_LETTER, 'Mira', '18 Nov 2026')
end
PAGES['letter-keyboard'] = PAGES.letter

PAGES['letter-read'] = function()
    textWindows().onGameEditText(2, 0, #SAMPLE_LETTER, SAMPLE_LETTER, 'Mira', '18 Nov 2026')
end

PAGES['house-list'] = function()
    textWindows().onGameEditList(3, 1, 'Mira\nToren\nLune\nKasimir\nOld Bess')
end
PAGES['house-list-keyboard'] = PAGES['house-list']

-- BEFORE screenshots for ot-client#173 (temporary branch, not for merging):
-- the old textmessage.otui, its labels set the way the old displayMessage did
local BLACKBOARD = 'You see a blackboard.\nYou read: The room of the Oracle\n\nIf you are wise enough you may ' ..
    'leave this isle and explore the great continent of Tibia. Once you are at level eight you may talk to the ' ..
    'Oracle who will send you to the continent.'

PAGES.messages = function(page)
    local screen = g_ui.getRootWidget():getSize()
    local width = math.min(480, screen.width - 16)
    local height = math.min(240, math.floor((screen.height - 16 - 10) / 2))
    local column = widget('GalleryColumn', page, function(w) w:setWidth(width) end)
    local shown = {
        { { 'highCenterLabel', TextColors.green, BLACKBOARD }, { 'statusLabel', TextColors.white, 'Sorry, not possible.' } },
        { { 'highCenterLabel', TextColors.green, 'Loot of a rat: 3 gold coins, cheese, a mace.' },
          { 'middleCenterLabel', TextColors.white, 'You advanced from Level 7 to Level 8.' },
          { 'lowCenterLabel', TextColors.red, 'Warning! The murder of Bob was not justified.' } },
    }
    for _, list in ipairs(shown) do
        local view = widget('GalleryGameView', column, function(w)
            w:setSize({ width = width, height = height })
            w:setImageClip({ x = 960 - width, y = 420 - height, width = width * 2, height = height * 2 })
        end)
        local panel = g_ui.loadUI('/modules/game_textmessage/textmessage', view)
        panel:fill('parent')
        for _, entry in ipairs(list) do
            local label = panel:recursiveGetChildById(entry[1])
            local text = entry[3]
            label:setText(text)
            label:setColor(entry[2])
            local isLoot = text:find('^Loot of ') ~= nil
            local colored = isLoot and modules.game_textmessage.lootColors(text, entry[2])
            if colored then
                label:setColoredText(colored)
            end
            label:setFont(isLoot and 'Verdana Bold-11px-outline' or 'verdana-11px-rounded')
            label:setBackgroundColor(isLoot and '#000000a0' or 'alpha')
            label:setPadding(isLoot and 3 or 0)
            local sideMargin = 0
            if isLoot then
                sideMargin = math.max(0, math.floor((label:getParent():getWidth() - label:getTextSize().width - 6) / 2))
            end
            label:setMarginLeft(sideMargin)
            label:setMarginRight(sideMargin)
            label:setVisible(true)
        end
    end
end

-- The part of a widget's rect that shows: inside every clipping ancestor (a
-- scrolled list). nil when none of it shows.
local function shownRect(widget)
    local r = widget:getRect()
    local x1, y1, x2, y2 = r.x, r.y, r.x + r.width, r.y + r.height
    local parent = widget:getParent()
    while parent do
        if parent:isClipping() then
            local p = parent:getRect()
            x1, y1 = math.max(x1, p.x), math.max(y1, p.y)
            x2, y2 = math.min(x2, p.x + p.width), math.min(y2, p.y + p.height)
        end
        parent = parent:getParent()
    end
    if x2 - x1 <= 0 or y2 - y1 <= 0 then
        return nil
    end
    return { x = x1, y = y1, width = x2 - x1, height = y2 - y1 }
end

-- Text that doesn't fit its widget (cut off, or spilling over its
-- neighbours): logged for every visible widget on the page, and gallery.js
-- fails the page. Text that wraps or sizes its widget always fits.
local function checkClipped(widget, found)
    if not widget:isVisible() or widget:getWidth() <= 0 then
        return
    end
    local text = widget.getText and widget:getText() or ''
    if text ~= '' and not widget:isTextWrap() and shownRect(widget) then
        local room = widget:getWidth() - widget:getPaddingLeft() - widget:getPaddingRight()
        local width = widget:getTextSize().width
        if width > room + 1 then
            table.insert(found, string.format('%s#%s "%s" text %d > room %d', widget:getStyleName(), widget:getId(),
                text, width, room))
        end
    end
    for _, child in ipairs(widget:getChildren()) do
        checkClipped(child, found)
    end
end

-- Text covered by a button or switch it doesn't belong to (a setting's name
-- under its row of choices): logged like clipped text
local function collectTexts(widget, texts, controls)
    if not widget:isVisible() or widget:getWidth() <= 0 then
        return
    end
    -- (every widget has UIWidget's own onClick: only one set on it counts)
    local clickable = widget.onClick and widget.onClick ~= UIWidget.onClick
    local switch = widget.onCheckChange and widget.onCheckChange ~= UIWidget.onCheckChange
    local shown = shownRect(widget)
    if not shown then
        -- (scrolled out of sight: nothing of it, or its children, shows)
        return
    end
    if (clickable or switch) and not widget:isPhantom() then
        table.insert(controls, { widget = widget, rect = shown })
    else
        local text = widget.getText and widget:getText() or ''
        if text ~= '' and not widget:isTextWrap() then
            -- the part of the widget the text is drawn in
            local rect = shown
            local width = math.min(rect.width, widget:getTextSize().width)
            local align = widget:getTextAlign()
            local x = rect.x
            if bit.band(align, AlignHorizontalCenter) ~= 0 then
                x = rect.x + math.floor((rect.width - width) / 2)
            elseif bit.band(align, AlignRight) ~= 0 then
                x = rect.x + rect.width - width
            end
            table.insert(texts, { widget = widget, x = x, y = rect.y, width = width, height = rect.height })
        end
    end
    for _, child in ipairs(widget:getChildren()) do
        collectTexts(child, texts, controls)
    end
end

local function isInside(widget, ancestor)
    while widget do
        if widget == ancestor then
            return true
        end
        widget = widget:getParent()
    end
    return false
end

local function checkCovered(top, found)
    local texts, controls = {}, {}
    collectTexts(top, texts, controls)
    for _, text in ipairs(texts) do
        for _, entry in ipairs(controls) do
            local control, r = entry.widget, entry.rect
            local overlapX = math.min(text.x + text.width, r.x + r.width) - math.max(text.x, r.x)
            local overlapY = math.min(text.y + text.height, r.y + r.height) - math.max(text.y, r.y)
            -- (a button's own label, or a label laid over a whole panel, is fine)
            if overlapX > 2 and overlapY > 2 and not isInside(text.widget, control) and not isInside(control, text.widget) then
                table.insert(found, string.format('%s#%s "%s" covered by %s#%s "%s"', text.widget:getStyleName(),
                    text.widget:getId(), text.widget:getText(), control:getStyleName(), control:getId(),
                    control.getText and control:getText() or ''))
                break
            end
        end
    end
end

-- Showing a page ----------------------------------------------------------------

local function show(name)
    local build = PAGES[name]
    if not build then
        g_logger.error('[gallery] no page "' .. name .. '"; pages: ' .. table.concat(PAGE_ORDER, ', '))
        return
    end
    fixClock()
    local rootWidget = g_ui.getRootWidget()
    root = g_ui.createWidget('GalleryRoot', rootWidget)
    -- the background over everything else; a screen page's own windows
    -- (opened by build, after it) over the background
    -- everything already there (the login screen, its locked Enter Game
    -- window, which nothing can be raised over) is hidden: only the page shows
    -- (by id: getChildren gives new Lua handles each time, so widgets cannot
    -- be table keys)
    local before = {}
    for _, child in ipairs(rootWidget:getChildren()) do
        before[child:getId()] = true
        if child:getId() ~= root:getId() then
            rootWidget:unlockChild(child)
            child:hide()
        end
    end
    root:raise()
    -- (a page can name windows of its own that existed before it, like the
    -- NPC dialog)
    local opened = build(root) or {}
    for _, child in ipairs(rootWidget:getChildren()) do
        if child:getId() ~= root:getId() and not before[child:getId()] then
            table.insert(opened, child)
        end
    end
    local keep = { [root:getId()] = true }
    for _, widget in ipairs(opened) do
        keep[widget:getId()] = true
    end
    local function raiseAll()
        -- (the login screen may show itself again a moment after start)
        for _, child in ipairs(rootWidget:getChildren()) do
            if not keep[child:getId()] and child:isVisible() then
                rootWidget:unlockChild(child)
                child:hide()
            end
        end
        root:raise()
        for _, widget in ipairs(opened) do
            if not widget:isDestroyed() then
                widget:raise()
            end
        end
    end
    raiseAll()
    -- a few frames later: everything laid out, images loaded and drawn
    scheduleEvent(function()
        if root then
            raiseAll()
            g_logger.info('[gallery] ready ' .. name)
            -- the text checks, once everything is laid out (a scale or a
            -- list may still settle after "ready"): twice, a second apart,
            -- and only what both passes find counts
            local function check()
                local found = {}
                checkClipped(root, found)
                checkCovered(root, found)
                for _, widget in ipairs(opened) do
                    if not widget:isDestroyed() then
                        checkClipped(widget, found)
                        checkCovered(widget, found)
                    end
                end
                return found
            end
            scheduleEvent(function()
                local first = {}
                for _, line in ipairs(check()) do
                    first[line] = true
                end
                scheduleEvent(function()
                    for _, line in ipairs(check()) do
                        if first[line] then
                            g_logger.info('[gallery] clipped ' .. line)
                        end
                    end
                    g_logger.info('[gallery] checked ' .. name)
                end, 1000)
            end, 1000)
        end
    end, 1000)
end

function init()
    local name = g_platform.getBrowserConfigString and g_platform.getBrowserConfigString('gallery') or ''
    if name == '' then
        return
    end
    -- the touch pieces, also on desktop
    g_ui.importStyle('/mods/client_mobile/mobile')
    g_ui.importStyle('/mods/client_mobile/hotbar_sheet')
    g_ui.importStyle('/mods/client_mobile/hub')
    g_ui.importStyle('/mods/client_mobile/outfit')
    g_ui.importStyle('gallery')
    -- through the options (they apply their own scale shortly after start,
    -- over a direct g_app.setHUDScale); option value v is a scale of v / 2 + 0.5
    local scale = tonumber(g_platform.getBrowserConfigString('galleryHudScale'))
    local options = modules.client_options
    if scale and options and options.setOption then
        options.setOption('hudScale', math.floor((scale - 0.5) * 2 + 0.5), true)
    end
    -- once the window has its size (laying out pages in a window that is
    -- not sized yet never finished) and the login screen has opened
    local tries = 0
    local function waitForWindow()
        tries = tries + 1
        local rootWidget = g_ui.getRootWidget()
        if rootWidget:getWidth() >= 320 and rootWidget:getHeight() >= 200 or tries > 100 then
            scheduleEvent(function() show(name) end, 500)
        else
            scheduleEvent(waitForWindow, 100)
        end
    end
    waitForWindow()
end

function terminate()
    if root then
        root:destroy()
        root = nil
    end
end
