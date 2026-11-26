-- UI gallery for screenshot tests (ot-client#70).
--
-- Opened with window.otclientConfig.gallery = '<page>' (the screenshot
-- script sets it; tools/ui-gallery). Shows one page of our components over
-- the login screen and logs "[gallery] ready <page>" when it is drawn, so
-- the script knows when to take the picture. Nothing happens without it.
-- With gallery = '@list' it logs the pages instead ("[gallery] page {...}",
-- then "[gallery] pages done <count>"), so gallery.js needs no list of its own.
--
-- The pages are in pages/*.lua, loaded in file name order (that order is
-- the report's). Each file returns function(G) and registers its pages with
-- G.page(name, { about = 'what it shows', keyboard = true }, build); a new
-- page is a new file, so pages added at the same time don't touch the same
-- lines. keyboard: shown with the on-screen keyboard open, on touch devices
-- only. build(page) fills the page; it may return windows of its own that
-- existed before it, and true to skip the fit checks on them. Styles of a
-- page's own go in pages/<file>.otui, imported with gallery.otui.
--
-- Optional: window.otclientConfig.galleryHudScale (a number) sets the
-- interface scale first, for the in-between scales.

local root
local PAGES = {}
local PAGE_ORDER = {}

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

local function openHub()
    local mobile = modules.client_mobile
    if mobile and mobile.openHub then
        mobile.openHub()
    end
end

-- The pages ---------------------------------------------------------------------

-- What a page file gets: the helpers above and G.page to add a page
local G = {
    widget = widget, section = section, button = button, holder = holder, centered = centered,
    column = column, roundFace = roundFace, FIXED_TIME = FIXED_TIME, receive = receive,
    findByText = findByText, tap = tap, openHub = openHub,
}

function G.page(name, options, build)
    if PAGES[name] then
        g_logger.error('[gallery] page "' .. name .. '" is defined twice')
        return
    end
    options = options or {}
    PAGES[name] = { build = build, about = options.about, keyboard = options.keyboard or nil }
    table.insert(PAGE_ORDER, name)
end

local PAGES_DIR = '/mods/client_gallery/pages'

local function pageFiles(extension)
    local files = {}
    for _, file in ipairs(g_resources.listDirectoryFiles(PAGES_DIR)) do
        if file:sub(-#extension) == extension then
            table.insert(files, file)
        end
    end
    table.sort(files)
    return files
end

local function loadPages()
    for _, file in ipairs(pageFiles('.lua')) do
        -- (a broken file loses its own pages, which gallery.js then reports
        -- as missing, not the others)
        local ok, err = pcall(function() dofile(PAGES_DIR .. '/' .. file)(G) end)
        if not ok then
            g_logger.error('[gallery] pages/' .. file .. ': ' .. tostring(err))
        end
    end
end

-- One line per page, for gallery.js
local function listPages()
    for _, name in ipairs(PAGE_ORDER) do
        local p = PAGES[name]
        g_logger.info('[gallery] page ' .. json.encode({ name = name, about = p.about, keyboard = p.keyboard }))
    end
    g_logger.info('[gallery] pages done ' .. #PAGE_ORDER)
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
-- fails the check (unless the baseline has it already: doesnt-fit.txt).
-- Text that wraps or sizes its widget always fits.
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
-- (order: the order widgets are drawn in, a widget before its children and
-- before the widgets after it: a control drawn under a text does not cover it,
-- such as the game view under a panel laid over it)
local function collectTexts(widget, texts, controls, order)
    order = order or { n = 0 }
    if not widget:isVisible() or widget:getWidth() <= 0 then
        return
    end
    order.n = order.n + 1
    local drawn = order.n
    -- (every widget has UIWidget's own onClick: only one set on it counts)
    local clickable = widget.onClick and widget.onClick ~= UIWidget.onClick
    local switch = widget.onCheckChange and widget.onCheckChange ~= UIWidget.onCheckChange
    local shown = shownRect(widget)
    if not shown then
        -- (scrolled out of sight: nothing of it, or its children, shows)
        return
    end
    if (clickable or switch) and not widget:isPhantom() then
        table.insert(controls, { widget = widget, rect = shown, drawn = drawn })
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
            table.insert(texts, { widget = widget, x = x, y = rect.y, width = width, height = rect.height,
                drawn = drawn })
        end
    end
    for _, child in ipairs(widget:getChildren()) do
        collectTexts(child, texts, controls, order)
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
            if overlapX > 2 and overlapY > 2 and entry.drawn > text.drawn and not isInside(text.widget, control)
                and not isInside(control, text.widget) then
                table.insert(found, string.format('%s#%s "%s" covered by %s#%s "%s"', text.widget:getStyleName(),
                    text.widget:getId(), text.widget:getText(), control:getStyleName(), control:getId(),
                    control.getText and control:getText() or ''))
                break
            end
        end
    end
end

-- A widget that sticks out of its parent, or off the screen (a row of
-- buttons wider than its sheet): logged like clipped text. The rows of a
-- scrolled list (a clipping parent) are left out: the list cuts them off on
-- purpose, and they scroll off the screen.
local function describe(widget)
    return widget:getStyleName() .. '#' .. widget:getId()
end

local function sticksOut(r, outer)
    -- (1 pixel of rounding at in-between scales)
    return r.x < outer.x - 1 or r.y < outer.y - 1 or r.x + r.width > outer.x + outer.width + 1
        or r.y + r.height > outer.y + outer.height + 1
end

local function checkOutside(widget, found, inList)
    if not widget:isVisible() or widget:getWidth() <= 0 or widget:getHeight() <= 0 then
        return
    end
    local r = widget:getRect()
    if not inList and sticksOut(r, g_ui.getRootWidget():getRect()) then
        table.insert(found, string.format('%s at %d,%d %dx%d is off the screen', describe(widget), r.x, r.y, r.width,
            r.height))
    end
    local parent = widget:getParent()
    if parent and parent:isVisible() and not parent:isClipping() and parent:getWidth() > 0 and parent:getHeight() > 0
        and sticksOut(r, parent:getRect()) then
        local p = parent:getRect()
        table.insert(found, string.format('%s at %d,%d %dx%d is outside its parent %s at %d,%d %dx%d', describe(widget),
            r.x, r.y, r.width, r.height, describe(parent), p.x, p.y, p.width, p.height))
    end
    for _, child in ipairs(widget:getChildren()) do
        checkOutside(child, found, inList or widget:isClipping())
    end
end

-- Showing a page ----------------------------------------------------------------

local function show(name)
    local build = PAGES[name] and PAGES[name].build
    if not build then
        g_logger.error('[gallery] no page "' .. name .. '"; pages: ' .. table.concat(PAGE_ORDER, ', '))
        return
    end
    fixClock()
    local rootWidget = g_ui.getRootWidget()
    root = g_ui.createWidget('GalleryRoot', rootWidget)
    -- the component pages are a 560 px column: a narrow phone shows the part
    -- that fits (cut off on purpose, like a list, not checked as outside)
    root:setClipping(true)
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
    -- NPC dialog; and skip the text checks on them: a whole game screen)
    local opened, uncheckedOpened = build(root)
    opened = opened or {}
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
            -- the checks (text that doesn't fit, widgets outside their
            -- parent or the screen), once everything is laid out (a scale
            -- or a list may still settle after "ready"): twice, a second
            -- apart, and only what both passes find counts
            local function check()
                local clipped, outside = {}, {}
                local widgets = { root }
                if not uncheckedOpened then
                    for _, widget in ipairs(opened) do
                        table.insert(widgets, widget)
                    end
                end
                for _, widget in ipairs(widgets) do
                    if not widget:isDestroyed() then
                        checkClipped(widget, clipped)
                        checkCovered(widget, clipped)
                        checkOutside(widget, outside)
                    end
                end
                local found = {}
                for _, line in ipairs(clipped) do
                    table.insert(found, 'clipped ' .. line)
                end
                for _, line in ipairs(outside) do
                    table.insert(found, 'outside ' .. line)
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
                            g_logger.info('[gallery] ' .. line)
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
    -- (here, while the module loads: the page files see the module's
    -- sandbox, as this file does)
    loadPages()
    if name == '@list' then
        listPages()
        return
    end
    -- the touch pieces, also on desktop
    g_ui.importStyle('/mods/client_mobile/mobile')
    g_ui.importStyle('/mods/client_mobile/hotbar_sheet')
    g_ui.importStyle('/mods/client_mobile/hub')
    g_ui.importStyle('/mods/client_mobile/outfit')
    g_ui.importStyle('/modules/game_joystick/joystick_styles')
    g_ui.importStyle('gallery')
    for _, file in ipairs(pageFiles('.otui')) do
        g_ui.importStyle(PAGES_DIR .. '/' .. file)
    end
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
