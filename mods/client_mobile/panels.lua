-- The bottom bar's panels as pieces of the touch layout (design:
-- ot-client#124). Every panel the bottom bar opens (equipment, map, skills,
-- battle, VIP, hunt analyzer, containers) is a piece with its own place and
-- size, kept per orientation like the other pieces (edit.lua).
--   - A panel is a small window sized to its contents, with a title bar
--     holding - (minimise) and x (close). The mini windows (skills,
--     battle...) bring their own title bar; equipment and the map get one.
--   - A bottom bar button shows or hides its panel. Panels the player has
--     not placed go to the free areas off the game view: the strip above
--     it in portrait; the tops of the side columns, above the joystick and
--     the hotbar, in landscape. They fill these left to right in the order
--     they were opened; one that does not fit replaces the oldest panel
--     still in its default place (a panel the player placed stays).
--   - Lists (skills, battle, VIP, hunt, containers) are as high as the free
--     area and scroll; - and + in Edit layout make them smaller or bigger.
--     Equipment and the map keep the size of their contents.
--   - Other windows that open in the side panel (party list...) are one
--     more piece, "Windows", shown while one is open.
-- The panels are the existing windows, moved into the pieces, so their
-- modules keep working as usual.

local OPEN_SETTING = 'client_mobile_open_panels'
local GAP = 4
local LIST_WIDTH = 176
local LIST_MIN_HEIGHT = 80
local LIST_MIN_WIDTH = 140

-- Bottom bar order. key: the piece's name in the saved layout (edit.lua)
PANELS = {
    { id = 'equipment', key = 'equipment', name = 'Equipment', kind = 'fixed',
        ids = { 'maininventorypanel' } },
    { id = 'map', key = 'map', name = 'Map', kind = 'fixed', ids = { 'mainmappanel' } },
    -- (the skills window has no parent until the game places it)
    { id = 'skills', key = 'skills', name = 'Skills', kind = 'list', ids = { 'skillWindow' },
        find = function() return modules.game_skills and modules.game_skills.skillsWindow end },
    { id = 'battle', key = 'battle', name = 'Battle', kind = 'list', prefixes = { 'battleWindow' } },
    { id = 'vip', key = 'vip', name = 'VIP', kind = 'list', ids = { 'vipWindow' } },
    -- (as wide as its row of buttons)
    { id = 'hunt', key = 'hunt', name = 'Hunt analyzer', kind = 'list', ids = { 'huntAnalyzer' },
        width = 204 },
    -- the containers window (client_containers) is its own piece
    { id = 'bag', key = 'containers', name = 'Containers', kind = 'list', containers = true },
    -- the side panel itself, while a window no button owns is open in it
    { id = 'windows', key = 'windows', name = 'Windows', kind = 'list', others = true },
}

-- The desktop side panels windows may sit in (containers remember theirs)
local SIDE_PANELS = { 'gameLeftPanel', 'gameLeftExtraPanel', 'gameRightExtraPanel', 'gameMainRightPanel',
    'gameRightPanel' }

local holders = {} -- panel id -> its piece (equipment, map and the lists)
local opened = {} -- ids of the panels on the screen, oldest first
local minimized = {} -- panel id -> true
local evictPending = false -- (a panel was just opened)
local settling = false -- (the screen is still being laid out: game start)

local function gameInterface()
    return modules.game_interface
end

function findPanel(id)
    for _, def in ipairs(PANELS) do
        if def.id == id then
            return def
        end
    end
end

local function panelOfKey(key)
    for _, def in ipairs(PANELS) do
        if def.key == key then
            return def
        end
    end
end

local function owns(def, widget)
    local id = widget:getId()
    for _, wanted in ipairs(def.ids or {}) do
        if id == wanted then
            return true
        end
    end
    for _, prefix in ipairs(def.prefixes or {}) do
        if id:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function ownerOf(widget)
    for _, def in ipairs(PANELS) do
        if (def.ids or def.prefixes) and owns(def, widget) then
            return def
        end
    end
end

local function containersWindow()
    return modules.client_containers and modules.client_containers.getWindow and modules.client_containers.getWindow()
end

-- Opened panels, kept per character ------------------------------------------

local function characterName()
    local name = g_game.getCharacterName()
    if (not name or name == '') and isLayoutPreview() then
        return '-'
    end
    return name
end

local function saveOpened()
    local name = characterName()
    if not name or name == '' or isLayoutPreview() then
        return
    end
    local folded = {}
    for id in pairs(minimized) do
        table.insert(folded, id)
    end
    local all = g_settings.getNode(OPEN_SETTING) or {}
    all[name] = { opened = table.concat(opened, ','), minimized = table.concat(folded, ',') }
    g_settings.setNode(OPEN_SETTING, all)
    g_settings.save()
end

-- On game start: the panels open when the character last played
function loadOpenedPanels()
    opened, minimized = {}, {}
    local name = characterName()
    local all = g_settings.getNode(OPEN_SETTING) or {}
    local entry = name and all[name]
    if type(entry) ~= 'table' then
        return
    end
    for id in tostring(entry.opened or ''):gmatch('[^,]+') do
        local def = findPanel(id)
        if def and not def.others then
            table.insert(opened, id)
        end
    end
    for id in tostring(entry.minimized or ''):gmatch('[^,]+') do
        minimized[id] = true
    end
end

-- The panels on the screen, as a list of ids (the layout preview)
function setOpenedPanels(ids)
    opened, minimized = {}, {}
    for _, id in ipairs(ids or {}) do
        local def = findPanel(id)
        if def and not def.others then
            table.insert(opened, id)
        end
    end
end

local function indexOf(id)
    for index, value in ipairs(opened) do
        if value == id then
            return index
        end
    end
end

function isPanelShown(id)
    local def = findPanel(id)
    if def and def.others then
        local widget = gameInterface().getRightPanel()
        return widget:isVisible()
    end
    return indexOf(id) ~= nil
end

-- The pieces ------------------------------------------------------------------

local function setMinimized(def, value)
    minimized[def.id] = value or nil
    saveOpened()
    relayout()
end

-- - on a panel: folds it to its title bar, or opens it again
function setPanelMinimized(id, value)
    local def = findPanel(id)
    if def then
        setMinimized(def, value)
    end
end

-- A piece for equipment or the map: their own title bar over the contents
local function createHolder(def)
    local root = gameInterface().getRootPanel()
    local holder = g_ui.createWidget('MobilePanelPiece', root)
    holder:setId('mobilePanel_' .. def.id)
    holder.ignoreFillAll = true
    holder.mobilePanel = def.id
    if def.kind == 'fixed' then
        local header = g_ui.createWidget('MobilePanelHeader', holder)
        header:setId('mobilePanelHeader')
        header:getChildById('title'):setText(tr(def.name))
        header:getChildById('minimize').onClick = function()
            setMinimized(def, not minimized[def.id])
        end
        header:getChildById('close').onClick = function()
            hidePanel(def.id)
        end
        holder.header = header
    end
    holders[def.id] = holder
    return holder
end

local function holderFor(def)
    local holder = holders[def.id]
    if holder and not holder:isDestroyed() then
        return holder
    end
    return createHolder(def)
end

-- The widget that is the panel's piece
function getPanelWidget(id)
    local def = findPanel(id)
    if not def then
        return nil
    end
    if def.containers then
        return containersWindow()
    elseif def.others then
        return gameInterface().getRightPanel()
    end
    return holderFor(def)
end

-- A mini window in a piece: its own - and x hide the piece or fold it
local function adoptWindow(def, window)
    if window.mobilePanelHooked == def.id then
        return
    end
    window.mobilePanelHooked = def.id
    if window.setDraggable then
        window:setDraggable(false)
    end
    connect(window, {
        onClose = function()
            if window.mobilePanelHooked == def.id and isPanelShown(def.id) then
                hidePanel(def.id)
            end
        end,
        onMinimize = function()
            if window.mobilePanelHooked == def.id and not minimized[def.id] then
                setMinimized(def, true)
            end
        end,
        onMaximize = function()
            if window.mobilePanelHooked == def.id and minimized[def.id] then
                setMinimized(def, false)
            end
        end,
    })
end

-- Moves every panel's widgets into its piece, and windows no button owns
-- into the side panel
local function adoptWindows()
    local gi = gameInterface()
    local root = gi.getRootPanel()
    local rightPanel = gi.getRightPanel()
    local candidates = {} -- { widget, the panel it is in }
    local function addChildren(panel)
        for _, child in ipairs(panel:getChildren()) do
            table.insert(candidates, { child, panel })
        end
    end
    for _, id in ipairs(SIDE_PANELS) do
        local panel = root:recursiveGetChildById(id)
        if panel then
            addChildren(panel)
        end
    end
    for _, holder in pairs(holders) do
        if not holder:isDestroyed() then
            addChildren(holder)
        end
    end
    -- (a window not in a side panel yet: the skills window until the game
    -- starts)
    for _, def in ipairs(PANELS) do
        for _, id in ipairs(def.ids or {}) do
            local window = rootWidget:getChildById(id)
            if window then
                table.insert(candidates, { window, rootWidget })
            end
        end
        local window = def.find and def.find()
        if window and not window:isDestroyed() and not window:getParent() then
            table.insert(candidates, { window, rootWidget })
        end
    end
    for _, entry in ipairs(candidates) do
        local child, source = entry[1], entry[2]
        local def = child:getId() ~= 'mobilePanelHeader' and ownerOf(child)
        local isMiniWindow = child:getClassName() == 'UIMiniWindow'
        if def then
            local holder = holderFor(def)
            if child:getParent() ~= holder then
                -- (its own width, before the piece's layout sets it)
                child.mobileWidth = child.mobileWidth or child:getWidth()
                if isMiniWindow then
                    child:setParent(holder, true)
                else
                    child:setParent(holder)
                end
            end
            if isMiniWindow and child:getChildById('closeButton') and not child.panelHeight then
                adoptWindow(def, child)
            end
        elseif source ~= rightPanel and source ~= rootWidget and isMiniWindow
            and source:getId() ~= 'gameMainRightPanel' then
            -- (a container window, the party list... opened in a left panel)
            child:setParent(rightPanel, true)
        end
    end
end

-- Its size when it has its default size: lists as high as `height`
local function naturalSize(def, widget, height)
    local scale = getPieceScale(def.key)
    if def.containers then
        modules.client_containers.setPieceHeight(minimized[def.id] and nil or math.floor(height * scale))
        return widget:getWidth(), widget:getHeight()
    end
    if def.kind == 'fixed' then
        local width = 0
        local total = widget:getPaddingTop() + widget:getPaddingBottom()
        for _, child in ipairs(widget:getChildren()) do
            if child:isVisible() then
                -- (the title bar is as wide as the piece)
                if child ~= widget.header then
                    width = math.max(width, child.mobileWidth or child:getWidth())
                end
                total = total + child:getHeight() + child:getMarginTop() + child:getMarginBottom()
            end
        end
        return width + widget:getPaddingLeft() + widget:getPaddingRight(), total
    end
    local width = math.floor((def.width or LIST_WIDTH) * scale)
    if minimized[def.id] then
        local total = widget:getPaddingTop() + widget:getPaddingBottom()
        for _, child in ipairs(widget:getChildren()) do
            if child:isVisible() then
                total = total + child:getHeight()
            end
        end
        return width, math.max(total, 20)
    end
    return width, math.floor(height * scale)
end

-- The windows in a list piece share its height
local function fillHeight(def, widget)
    if def.kind ~= 'list' or def.containers or minimized[def.id] then
        return
    end
    local windows = {}
    local free = widget:getHeight() - widget:getPaddingTop() - widget:getPaddingBottom()
    for _, child in ipairs(widget:getChildren()) do
        if child:isVisible() then
            local minimize = child:getChildById('minimizeButton')
            if child:getClassName() == 'UIMiniWindow' and not (minimize and minimize:isOn()) then
                table.insert(windows, child)
            else
                free = free - child:getHeight()
            end
        end
    end
    for _, window in ipairs(windows) do
        window:setHeight(math.max(20, math.floor(free / #windows)))
    end
end

-- Shows the contents of a piece as it should be (open, minimised)
local function applyContents(def, widget, shown)
    if def.containers then
        modules.client_containers.setPieceShown(shown, minimized[def.id] == true)
        return
    end
    if def.others then
        return
    end
    widget:setVisible(shown)
    if not shown then
        return
    end
    for _, child in ipairs(widget:getChildren()) do
        if child == widget.header then
            child:setVisible(true)
            child:getChildById('minimize'):setOn(minimized[def.id] == true)
        elseif child:getClassName() == 'UIMiniWindow' and not child.panelHeight then
            -- (opened, not just shown: a window saved as closed would be
            -- closed again, and its panel with it, on the next login)
            if not child:isExplicitlyVisible() then
                child:open()
            end
            local minimize = child:getChildById('minimizeButton')
            local folded = minimize and minimize:isOn()
            if minimized[def.id] and not folded then
                child:minimize(true)
            elseif not minimized[def.id] and folded then
                child:maximize(true)
            end
        else
            -- equipment and the map: hidden while minimised
            child:setVisible(not minimized[def.id])
            if child.panelHeight then
                child:setHeight(child.panelHeight)
            end
        end
    end
end

-- Placing ---------------------------------------------------------------------

local function overlaps(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

local function inside(rect, region)
    return rect.x >= region.x and rect.y >= region.y and rect.x + rect.width <= region.x + region.width
        and rect.y + rect.height <= region.y + region.height
end

-- The first free spot for a piece in the areas: left to right, then below
-- what is already there. A list is as high as the room under its spot.
-- size(region) gives the piece's width and height for an area.
local function findSpot(regions, size, taken, list)
    for _, region in ipairs(regions) do
        local width, height = size(region)
        local candidates = { { x = region.x, y = region.y } }
        for _, rect in ipairs(taken) do
            table.insert(candidates, { x = rect.x + rect.width + GAP, y = rect.y })
            table.insert(candidates, { x = rect.x, y = rect.y + rect.height + GAP })
            table.insert(candidates, { x = region.x, y = rect.y + rect.height + GAP })
        end
        table.sort(candidates, function(a, b)
            if a.y ~= b.y then
                return a.y < b.y
            end
            return a.x < b.x
        end)
        for _, spot in ipairs(candidates) do
            local h = height
            if list then
                h = math.min(height, region.y + region.height - spot.y)
            end
            local rect = { x = spot.x, y = spot.y, width = width, height = h }
            if (not list or h >= math.min(height, LIST_MIN_HEIGHT)) and inside(rect, region) then
                local free = true
                for _, other in ipairs(taken) do
                    if overlaps(rect, other) then
                        free = false
                        break
                    end
                end
                if free then
                    return rect
                end
            end
        end
    end
end

-- Lays out the shown panels. regions: the free areas off the game view
-- ({ x, y, width, height } on the screen), best first. The places the
-- player chose are applied after this (applySavedLayout).
function placePanels(regions)
    adoptWindows()
    local gi = gameInterface()
    local rightPanel = gi.getRightPanel()
    local mainPanel = gi.getMainRightPanel()
    mainPanel:setVisible(false)
    mainPanel:setHeight(0)
    -- other windows in the side panel make it a piece of its own
    local othersOpen = false
    for _, child in ipairs(rightPanel:getChildren()) do
        if child:isVisible() then
            othersOpen = true
        end
    end
    rightPanel:setVisible(othersOpen)
    rightPanel:setOn(othersOpen)
    rightPanel.ignoreFillAll = true

    local list = {}
    for _, def in ipairs(PANELS) do
        local widget = getPanelWidget(def.id)
        local shown = def.others and othersOpen or indexOf(def.id) ~= nil
        if widget then
            applyContents(def, widget, shown)
            if shown then
                widget:breakAnchors()
                widget:setMargin(0)
                table.insert(list, def)
            end
        end
    end

    -- the placed ones keep their place; the others go in order of opening
    local taken = {}
    local defaults = {}
    for _, def in ipairs(list) do
        local saved = getSavedPiece(def.key)
        if saved and saved.x then
            local widget = getPanelWidget(def.id)
            local first = regions[1] or { height = 200 }
            local width, height = naturalSize(def, widget, first.height)
            local r = gi.getRootPanel():getRect()
            table.insert(taken, { x = r.x + math.floor(saved.x * r.width), y = r.y + math.floor(saved.y * r.height),
                width = width, height = height })
            widget:setSize({ width = width, height = height })
        else
            table.insert(defaults, def)
        end
    end
    table.sort(defaults, function(a, b)
        return (indexOf(a.id) or 1000) < (indexOf(b.id) or 1000)
    end)

    -- A panel that does not fit replaces the oldest panel still in its
    -- default place (the newest stays, even when it is too big for every
    -- area). Not while the screen is still settling at game start: its
    -- first layouts may be smaller than the screen.
    local evict = evictPending or not settling
    evictPending = false
    local function sizeFor(def, widget)
        return function(region)
            local width, height = naturalSize(def, widget, region.height)
            -- (a list is narrower in a narrow column)
            if def.kind == 'list' and not def.containers then
                width = math.max(LIST_MIN_WIDTH, math.min(width, region.width))
            end
            return width, height
        end
    end
    -- (only when the new one has room once the others are gone: next to
    -- panels the player placed there may be none)
    local newest = defaults[#defaults]
    if evict and newest and not findSpot(regions, sizeFor(newest, getPanelWidget(newest.id)), taken,
        newest.kind == 'list' and not minimized[newest.id]) then
        evict = false
    end
    local placed, occupied
    while true do
        placed = {}
        occupied = {}
        for _, rect in ipairs(taken) do
            table.insert(occupied, rect)
        end
        local failing = false
        for _, def in ipairs(defaults) do
            local fills = def.kind == 'list' and not minimized[def.id]
            local rect = findSpot(regions, sizeFor(def, getPanelWidget(def.id)), occupied, fills)
            if rect then
                placed[def.id] = rect
                table.insert(occupied, rect)
            else
                failing = true
            end
        end
        local evictable = {}
        for _, def in ipairs(defaults) do
            if not def.others then
                table.insert(evictable, def)
            end
        end
        if not failing or not evict or #evictable <= 1 then
            break
        end
        local oldest = evictable[1]
        for index, def in ipairs(defaults) do
            if def == oldest then
                table.remove(defaults, index)
                break
            end
        end
        local index = indexOf(oldest.id)
        if index then
            table.remove(opened, index)
        end
        applyContents(oldest, getPanelWidget(oldest.id), false)
        saveOpened()
    end

    -- What still does not fit (a screen still settling, a panel too big for
    -- every area): anywhere free above the bottom bar, over the game view
    -- rather than over another panel
    local r = gi.getRootPanel():getRect()
    local toolbar = gi.getRootPanel():getChildById('mobileToolbar')
    local bottom = toolbar and toolbar:isVisible() and toolbar:getY() or r.y + r.height
    local screen = { x = r.x, y = r.y, width = r.width, height = bottom - r.y }
    for _, def in ipairs(defaults) do
        local widget = getPanelWidget(def.id)
        local rect = placed[def.id]
        if not rect then
            local region = regions[1] or screen
            local width, height = naturalSize(def, widget, region.height)
            rect = findSpot({ screen }, function() return width, height end, occupied, false)
                or { x = region.x, y = region.y, width = width, height = height }
            table.insert(occupied, rect)
        end
        widget:setSize({ width = rect.width, height = rect.height })
        widget:setPosition({ x = rect.x, y = rect.y })
    end
    for _, def in ipairs(list) do
        local widget = getPanelWidget(def.id)
        if def.containers then
            modules.client_containers.setPieceHeight(not minimized[def.id] and widget:getHeight() or nil)
        end
        fillHeight(def, widget)
        widget:raise()
    end
end

-- Showing and hiding ----------------------------------------------------------

-- Game start: for a moment, panels that do not fit are not closed (the
-- screen may not have its size yet); then laid out again
function settlePanels(delay)
    settling = true
    scheduleEvent(function()
        settling = false
        relayout()
    end, delay)
end

function showPanel(id)
    local def = findPanel(id)
    if not def or def.others or indexOf(id) then
        return
    end
    table.insert(opened, id)
    minimized[id] = nil
    saveOpened()
    evictPending = true
    relayout()
end

function hidePanel(id)
    local def = findPanel(id)
    if not def then
        return
    end
    if def.others then
        -- closes the windows in it
        for _, child in ipairs(gameInterface().getRightPanel():getChildren()) do
            if child:isVisible() and child.close then
                child:close()
            end
        end
        relayout()
        return
    end
    local index = indexOf(id)
    if not index then
        return
    end
    table.remove(opened, index)
    saveOpened()
    relayout()
end

function togglePanel(id)
    if isPanelShown(id) then
        hidePanel(id)
    else
        showPanel(id)
    end
end

-- The panels as layout pieces (edit.lua): { key, name, kind } of those on
-- the screen
function getPanelPieces()
    local pieces = {}
    for _, def in ipairs(PANELS) do
        if isPanelShown(def.id) then
            table.insert(pieces, { key = def.key, name = def.name, panel = def.id, kind = def.kind,
                scalable = def.kind == 'list' })
        end
    end
    return pieces
end

function getPanelOfKey(key)
    return panelOfKey(key)
end

-- Logged out: the pieces stay (a reconnect keeps the screen), the next game
-- loads its own opened panels
function terminatePanels()
    for _, holder in pairs(holders) do
        if not holder:isDestroyed() then
            -- (the windows go back to the side panel before the piece goes)
            local rightPanel = gameInterface().getRightPanel()
            local mainPanel = gameInterface().getMainRightPanel()
            for _, child in ipairs(holder:getChildren()) do
                if child ~= holder.header then
                    if child.panelHeight then
                        child:setParent(mainPanel)
                    elseif child:getClassName() == 'UIMiniWindow' then
                        child:setParent(rightPanel, true)
                    end
                end
            end
            holder:destroy()
        end
    end
    holders = {}
end
