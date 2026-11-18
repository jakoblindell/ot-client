-- The outfit screen for touch screens (ot-client#101).
--
-- The desktop outfit window (game_outfit) is 735x575 and does not fit a
-- phone: its OK and Cancel were off the screen. On touch screens game_outfit
-- opens this instead: a preview, the previous and next outfit, the addons
-- when the outfit has them, the four colour parts with the colour grid, and
-- Cancel and OK, always on the screen. It lays itself out for the screen's
-- shape (landscape: preview on the left, colours on the right; portrait:
-- stacked) and again when the screen turns.
--
-- It never opens on top of the "Build your UI" setup (setup.lua), and the
-- setup waits for it: one at a time.

local PARTS = {
    { id = 'head', text = 'Head' },
    { id = 'body', text = 'Primary' },
    { id = 'legs', text = 'Secondary' },
    { id = 'feet', text = 'Detail' },
}
local COLUMNS, ROWS = 19, 7
local GAP = 8

local sheet
local state -- outfit, list, index, part
local pending -- an outfit screen waiting for the setup to finish
local onClosedCallbacks = {}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Places a widget at x, y (relative to the panel's inner area) with a size
local function place(widget, area, x, y, width, height)
    widget:breakAnchors()
    widget:setRect({ x = area.x + x, y = area.y + y, width = math.max(0, width), height = math.max(0, height) })
end

local function updatePreview()
    if not sheet then
        return
    end
    local panel = sheet.panel
    panel.preview.creature:setOutfit(state.outfit)
    panel.preview.creature:setDirection(Directions.South)
    local entry = state.list[state.index]
    panel.name:setText(entry and entry[2] or '')
    local available = entry and tonumber(entry[3]) or 0
    local addons = state.outfit.addons or 0
    panel.addons.addon1:setEnabled(available % 2 == 1)
    panel.addons.addon2:setEnabled(available >= 2)
    panel.addons.addon1:setChecked(addons % 2 == 1)
    panel.addons.addon2:setChecked(addons >= 2)
    panel.addons:setVisible(available > 0)
    local multiple = #state.list > 1
    panel.prev:setEnabled(multiple)
    panel.next:setEnabled(multiple)
    for _, child in ipairs(panel.parts:getChildren()) do
        child:setChecked(child.part == state.part)
    end
    local chosen = state.outfit[state.part] or 0
    for _, child in ipairs(panel.colors:getChildren()) do
        child:setChecked(child.colorId == chosen)
    end
end

-- Lays the sheet out for the screen: everything fits, Cancel and OK at the
-- bottom
local function layout()
    if not sheet then
        return
    end
    local root = g_ui.getRootWidget()
    local screenWidth, screenHeight = root:getWidth(), root:getHeight()
    local landscape = screenWidth >= screenHeight
    local panel = sheet.panel
    local padding = 12
    local width = math.min(screenWidth - 8, landscape and 720 or 520)
    local inner = width - 2 * padding
    local hasAddons = panel.addons:isVisible()
    local tabs, buttons, title = 36, 40, 40

    local cell, height, previewSize
    if landscape then
        -- the colours on the right; the preview, name and addons on the left
        local left = clamp(math.floor(inner * 0.34), 150, 230)
        local right = inner - left - GAP
        local maxHeight = screenHeight - 8
        local middleRoom = maxHeight - 2 * padding - title - buttons - 2 * GAP
        cell = clamp(math.min(math.floor(right / COLUMNS), math.floor((middleRoom - tabs - 6) / ROWS)), 10, 28)
        local gridHeight = cell * ROWS
        local leftNeed = 96 + GAP + 40 + (hasAddons and (GAP + 40) or 0)
        local middle = math.max(tabs + 6 + gridHeight, math.min(leftNeed, middleRoom))
        height = 2 * padding + title + GAP + middle + GAP + buttons
        local area = { x = 0, y = 0 }
        panel:breakAnchors()
        panel:setRect({ x = root:getX() + math.floor((screenWidth - width) / 2),
            y = root:getY() + math.floor((screenHeight - height) / 2), width = width, height = height })
        area.x, area.y = panel:getX() + padding, panel:getY() + padding
        local top = title + GAP
        previewSize = middle - 40 - GAP - (hasAddons and (40 + GAP) or 0)
        place(panel.preview, area, 0, top, left, previewSize)
        place(panel.prev, area, 0, top + previewSize + GAP, 40, 40)
        place(panel.name, area, 44, top + previewSize + GAP, left - 88, 40)
        place(panel.next, area, left - 40, top + previewSize + GAP, 40, 40)
        place(panel.addons, area, 0, top + previewSize + GAP + 40 + GAP, left, 40)
        place(panel.parts, area, left + GAP, top, right, tabs)
        place(panel.colors, area, left + GAP + math.floor((right - cell * COLUMNS) / 2), top + tabs + 6, cell * COLUMNS, gridHeight)
        panel.parts:getLayout():setCellSize({ width = math.floor((right - 3 * 4) / 4), height = tabs })
        place(panel.title, area, 0, 8, inner - 48, 24)
        place(panel.close, area, inner - 40, 0, 40, 40)
        place(panel.cancel, area, 0, height - 2 * padding - buttons, math.floor((inner - GAP) / 2), buttons)
        place(panel.ok, area, math.floor((inner + GAP) / 2), height - 2 * padding - buttons, math.floor((inner - GAP) / 2), buttons)
    else
        -- stacked: the preview beside the name and addons, then the colours
        cell = clamp(math.floor(inner / COLUMNS), 10, 28)
        -- (narrow phones: a smaller preview leaves room for the addons)
        previewSize = clamp(inner - 210 - GAP, 64, 96)
        local beside = inner - previewSize - GAP
        local topBlock = math.max(previewSize, 40 + (hasAddons and (GAP + 40) or 0))
        local middle = topBlock + GAP + tabs + 6 + cell * ROWS
        height = math.min(screenHeight - 8, 2 * padding + title + GAP + middle + GAP + buttons)
        panel:breakAnchors()
        panel:setRect({ x = root:getX() + math.floor((screenWidth - width) / 2),
            y = root:getY() + math.floor((screenHeight - height) / 2), width = width, height = height })
        local area = { x = panel:getX() + padding, y = panel:getY() + padding }
        local top = title + GAP
        place(panel.preview, area, 0, top, previewSize, previewSize)
        place(panel.prev, area, previewSize + GAP, top, 40, 40)
        place(panel.name, area, previewSize + GAP + 44, top, beside - 88, 40)
        place(panel.next, area, inner - 40, top, 40, 40)
        place(panel.addons, area, previewSize + GAP, top + 40 + GAP, beside, 40)
        local gridTop = top + topBlock + GAP
        place(panel.parts, area, 0, gridTop, inner, tabs)
        panel.parts:getLayout():setCellSize({ width = math.floor((inner - 3 * 4) / 4), height = tabs })
        place(panel.colors, area, math.floor((inner - cell * COLUMNS) / 2), gridTop + tabs + 6, cell * COLUMNS, cell * ROWS)
        place(panel.title, area, 0, 8, inner - 48, 24)
        place(panel.close, area, inner - 40, 0, 40, 40)
        place(panel.cancel, area, 0, height - 2 * padding - buttons, math.floor((inner - GAP) / 2), buttons)
        place(panel.ok, area, math.floor((inner + GAP) / 2), height - 2 * padding - buttons, math.floor((inner - GAP) / 2), buttons)
    end
    panel.colors:getLayout():setCellSize({ width = cell, height = cell })
    -- the outfit as big as the preview allows
    local box = math.min(panel.preview:getWidth(), panel.preview:getHeight()) - 12
    panel.preview.creature:setSize({ width = box, height = box })
    panel.preview.creature:setCreatureSize(box)
end

local function closeSheet()
    if not sheet then
        return
    end
    disconnect(g_ui.getRootWidget(), { onGeometryChange = layout })
    sheet:destroy()
    sheet = nil
    state = nil
    for _, callback in ipairs(onClosedCallbacks) do
        callback()
    end
end

local function step(delta)
    local count = #state.list
    if count == 0 then
        return
    end
    state.index = (state.index - 1 + delta) % count + 1
    local entry = state.list[state.index]
    state.outfit.type = entry[1]
    -- keep only the addons this outfit has
    local available = tonumber(entry[3]) or 0
    local addons = state.outfit.addons or 0
    local keep = 0
    if addons % 2 == 1 and available % 2 == 1 then
        keep = keep + 1
    end
    if addons >= 2 and available >= 2 then
        keep = keep + 2
    end
    state.outfit.addons = keep
    updatePreview()
    layout()
end

local function setAddon(bit, on)
    local addons = state.outfit.addons or 0
    local has = bit == 1 and addons % 2 == 1 or bit == 2 and addons >= 2
    if on and not has then
        addons = addons + bit
    elseif not on and has then
        addons = addons - bit
    end
    state.outfit.addons = addons
    updatePreview()
end

local function build(onAccept)
    sheet = g_ui.createWidget('MobileOutfitSheet', g_ui.getRootWidget())
    sheet:setId('mobileOutfitSheet')
    local panel = sheet.panel
    for _, part in ipairs(PARTS) do
        local tab = g_ui.createWidget('OtTab', panel.parts)
        tab:setText(tr(part.text))
        tab.part = part.id
        tab.onClick = function()
            state.part = part.id
            updatePreview()
        end
    end
    for row = 0, ROWS - 1 do
        for column = 0, COLUMNS - 1 do
            local id = row * COLUMNS + column
            local box = g_ui.createWidget('MobileOutfitColor', panel.colors)
            box:setBackgroundColor(getOutfitColor(id))
            box.colorId = id
            box.onCheckChange = function(widget, checked)
                if not state then
                    return
                end
                if checked and state.outfit[state.part] ~= widget.colorId then
                    state.outfit[state.part] = widget.colorId
                    updatePreview()
                elseif not checked and state.outfit[state.part] == widget.colorId then
                    -- a tap on the chosen colour keeps it chosen
                    widget:setChecked(true)
                end
            end
        end
    end
    panel.prev.onClick = function() step(-1) end
    panel.next.onClick = function() step(1) end
    panel.addons.addon1.onCheckChange = function(_, checked) setAddon(1, checked) end
    panel.addons.addon2.onCheckChange = function(_, checked) setAddon(2, checked) end
    panel.close.onClick = closeSheet
    panel.cancel.onClick = closeSheet
    panel.ok.onClick = function()
        local outfit = state.outfit
        closeSheet()
        onAccept(outfit)
    end
    -- a tap beside the panel closes it, as on every sheet
    sheet.onClick = closeSheet
    sheet.onEscape = closeSheet
    sheet.onEnter = panel.ok.onClick
    connect(g_ui.getRootWidget(), { onGeometryChange = layout })
end

-- Opens the outfit screen: the current outfit, and the server's list of
-- outfits ({ lookType, name, addons } each). onAccept(outfit) is called with
-- the chosen outfit (by default it is sent to the server).
function openOutfitSheet(current, list, onAccept)
    onAccept = onAccept or function(outfit) g_game.changeOutfit(outfit) end
    if isUiSetupBusy and isUiSetupBusy() then
        -- after the setup (setup.lua calls outfitSheetAfterSetup)
        pending = { current, list, onAccept }
        return
    end
    pending = nil
    closeSheet()
    local outfit = table.copy(current)
    state = { outfit = outfit, list = list or {}, index = 1, part = 'head' }
    for index, entry in ipairs(state.list) do
        if entry[1] == outfit.type then
            state.index = index
        end
    end
    build(onAccept)
    updatePreview()
    layout()
    sheet:raise()
    sheet:focus()
end

function isOutfitSheetOpen()
    return sheet ~= nil or pending ~= nil
end

-- The setup has finished: an outfit screen that waited for it opens now
function outfitSheetAfterSetup()
    if pending then
        local waiting = pending
        pending = nil
        openOutfitSheet(waiting[1], waiting[2], waiting[3])
    end
end

-- Called when the outfit screen closes (the setup waits for it)
function onOutfitSheetClosed(callback)
    table.insert(onClosedCallbacks, callback)
end

function closeOutfitSheet()
    pending = nil
    closeSheet()
end
