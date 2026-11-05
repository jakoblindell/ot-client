-- Hotbar presets and settings for the touch layout (ot-client#18).
--
-- The main hotbar (action bar 1) can hold several presets, P1 to P6, for
-- example hunting runes in P1 and healing and utility in P2. The button next
-- to the hotbar shows the current one; a tap switches to the next. Presets the
-- player is not using are kept in action bars that are never shown (101-106),
-- in the same per-character hotkey set as the rest, so they are saved with it.
--
-- Optional extra hotbars of 3 slots (action bars 2 and 3) sit above the main
-- one and stay the same when the preset changes. The pencil button turns on
-- edit mode: a tap on a slot opens the "Add to hotbar" sheet, dragging one
-- slot onto another swaps them. A long press on either button opens the
-- hotbar settings.

local PRESET_BAR_BASE = 100
local MAX_PRESETS = 6
local PRESET_CHOICES = { 1, 2, 3, 4, 5, 6 }
local SLOT_CHOICES = { 4, 6, 8, 9, 12, 16, 24 }
local DEFAULTS = { presets = 1, current = 1, slots = 12, extra1 = false, extra2 = false, editButton = true }

local presetRow
local editOverlay
local editing = false
local settingsSheet

local function actionbar()
    return modules.game_actionbar
end

local function settingsKey()
    local player = g_game.getLocalPlayer()
    return 'client_mobile_hotbar_' .. (player and player:getName() or '')
end

-- The player's hotbar settings (per character)
function hotbarSettings()
    local saved = g_settings.getNode(settingsKey()) or {}
    local settings = {}
    for key, value in pairs(DEFAULTS) do
        if saved[key] == nil then
            settings[key] = value
        else
            settings[key] = saved[key]
        end
    end
    settings.presets = math.max(1, math.min(MAX_PRESETS, tonumber(settings.presets) or 1))
    settings.current = math.max(1, math.min(settings.presets, tonumber(settings.current) or 1))
    settings.slots = tonumber(settings.slots) or DEFAULTS.slots
    return settings
end

local function saveSettings(settings)
    g_settings.setNode(settingsKey(), settings)
    g_settings.save()
end

local function refreshBar(n)
    local bar = actionbar()
    local actionBar = bar.actionBars and bar.actionBars[n]
    if not actionBar then
        return
    end
    for _, button in ipairs(actionBar.tabBar:getChildren()) do
        if button.item then
            bar.updateButton(button)
        end
    end
    if bar.updateVisibleWidgets then
        bar.updateVisibleWidgets()
    end
end

local function updatePresetButton()
    if not presetRow then
        return
    end
    local settings = hotbarSettings()
    presetRow.preset:setText('P' .. settings.current)
    presetRow.edit:setVisible(settings.editButton)
    presetRow.edit:setOn(editing)
end

-- Shows preset `index` in the main hotbar
function selectHotbarPreset(index)
    local settings = hotbarSettings()
    index = math.max(1, math.min(settings.presets, index))
    if index == settings.current then
        return
    end
    local api = actionbar().ApiJson
    -- The current preset goes back to its storage bar, the new one comes out
    -- of its own
    api.swapBarMappings(1, PRESET_BAR_BASE + settings.current)
    api.swapBarMappings(1, PRESET_BAR_BASE + index)
    api.saveData()
    settings.current = index
    saveSettings(settings)
    refreshBar(1)
    updatePresetButton()
end

local function nextPreset()
    local settings = hotbarSettings()
    if settings.presets <= 1 then
        openHotbarSettings()
        return
    end
    selectHotbarPreset(settings.current % settings.presets + 1)
end

-- Edit mode -------------------------------------------------------------------

local function slotAt(pos)
    local bars = actionbar().actionBars or {}
    for _, n in ipairs({ 1, 2, 3 }) do
        local actionBar = bars[n]
        if actionBar and actionBar:isVisible() then
            for _, button in ipairs(actionBar.tabBar:getChildren()) do
                if button.item and button:isVisible() and button:containsPoint(pos) then
                    return button
                end
            end
        end
    end
end

local function slotIds(button)
    local barId, buttonId = string.match(button:getId(), '(%d+)%.(%d+)')
    return tonumber(barId), tonumber(buttonId)
end

local function swapSlots(a, b)
    local barA, buttonA = slotIds(a)
    local barB, buttonB = slotIds(b)
    local api = actionbar().ApiJson
    api.swapSlotMappings(barA, buttonA, barB, buttonB)
    api.saveData()
    actionbar().updateButton(a)
    actionbar().updateButton(b)
end

function setHotbarEditing(on)
    editing = on and true or false
    if editOverlay then
        editOverlay:setVisible(editing)
        if editing then
            editOverlay:raise()
        end
    end
    updatePresetButton()
end

local function createEditOverlay(actionPanel)
    editOverlay = g_ui.createWidget('MobileHotbarEditOverlay', actionPanel:getParent())
    editOverlay:fill(actionPanel:getId())
    editOverlay:setVisible(false)
    editOverlay.onMousePress = function(widget, pos)
        widget.pressed = slotAt(pos)
        return true
    end
    editOverlay.onMouseRelease = function(widget, pos)
        local from, to = widget.pressed, slotAt(pos)
        widget.pressed = nil
        if not from or not to then
            return true
        end
        if from == to then
            openHotbarSheet(to)
        else
            swapSlots(from, to)
        end
        return true
    end
end

-- Settings sheet --------------------------------------------------------------

-- The sheet scrolls by dragging a finger over it; a drag does not tap
local function dragScroll(widget, onTap)
    local scrollbar = settingsSheet.panel.listScroll
    widget.onMousePress = function(self, mousePos)
        self.dragStart = mousePos
        self.dragOrigin = scrollbar:getValue()
        self.dragged = false
        return onTap == nil
    end
    widget.onMouseMove = function(self, mousePos)
        if not self.dragStart or not g_mouse.isPressed(MouseLeftButton) then
            return false
        end
        local dy = mousePos.y - self.dragStart.y
        if math.abs(dy) > 8 then
            self.dragged = true
        end
        if self.dragged then
            scrollbar:setValue(self.dragOrigin - dy)
        end
        return true
    end
    widget.onMouseRelease = function(self)
        self.dragStart = nil
        return onTap == nil
    end
    if onTap then
        widget.onClick = function(self)
            if not self.dragged then
                onTap()
            end
        end
    end
end

local function closeSettings()
    if settingsSheet then
        settingsSheet:destroy()
        settingsSheet = nil
    end
end

local function addChoices(list, heading, help, choices, current, onPick)
    local title = g_ui.createWidget('HotbarSheetHeading', list)
    title:setText(heading)
    local row = g_ui.createWidget('MobileHotbarChoiceRow', list)
    for _, value in ipairs(choices) do
        local button = g_ui.createWidget('HotbarSheetButton', row)
        button:setText(tostring(value))
        button:setChecked(value == current)
        dragScroll(button, function()
            onPick(value)
        end)
    end
    local note = g_ui.createWidget('MobileHotbarNote', list)
    note:setText(help)
end

local function addToggle(row, text, checked, onChange)
    local button = g_ui.createWidget('HotbarSheetButton', row)
    button:setText(text)
    button:setChecked(checked)
    dragScroll(button, function()
        onChange(not checked)
    end)
end

local function changeSetting(key, value)
    local settings = hotbarSettings()
    if key == 'presets' and settings.current > value then
        -- The preset shown goes back to storage first; presets past the new
        -- count are kept for when it goes up again
        selectHotbarPreset(1)
        settings = hotbarSettings()
    end
    settings[key] = value
    saveSettings(settings)
    if key == 'editButton' and not value then
        setHotbarEditing(false)
    end
    updatePresetButton()
    relayout()
    openHotbarSettings()
end

function openHotbarSettings()
    -- Reopened after a change: keep the place in the list
    local scroll = settingsSheet and settingsSheet.panel.listScroll:getValue() or 0
    closeSettings()
    local settings = hotbarSettings()
    settingsSheet = g_ui.createWidget('HotbarSettingsSheet', rootWidget)
    settingsSheet:raise()
    settingsSheet:focus()
    settingsSheet.onClick = closeSettings
    settingsSheet.onEscape = closeSettings
    local panel = settingsSheet.panel
    panel:setSize({ width = math.min(460, rootWidget:getWidth() - 16),
        height = math.max(280, math.min(560, rootWidget:getHeight() - 16)) })
    panel.close.onClick = closeSettings
    local list = panel.list
    dragScroll(list)

    addChoices(list, tr('Number of presets'),
        tr('Hotbar sets you switch between with the P button (tap it for the next one).'),
        PRESET_CHOICES, settings.presets, function(value) changeSetting('presets', value) end)
    local shown = {}
    for index = 1, settings.presets do
        shown[index] = index
    end
    addChoices(list, tr('Hotbar preset'), tr('The set shown now (the P button also switches).'), shown, settings.current, function(value)
            selectHotbarPreset(value)
            openHotbarSettings()
        end)
    addChoices(list, tr('Slots'), tr('How many slots the main hotbar shows (fewer if they do not fit the screen).'),
        SLOT_CHOICES, settings.slots, function(value) changeSetting('slots', value) end)
    g_ui.createWidget('HotbarSheetHeading', list):setText(tr('Also show'))
    local toggles = g_ui.createWidget('MobileHotbarToggleRow', list)
    local cell = math.floor((list:getWidth() - 12) / 3)
    toggles:getLayout():setCellSize({ width = cell, height = 40 })
    addToggle(toggles, tr('Extra row'), settings.extra1, function(value) changeSetting('extra1', value) end)
    addToggle(toggles, tr('Extra row 2'), settings.extra2, function(value) changeSetting('extra2', value) end)
    addToggle(toggles, tr('Edit button'), settings.editButton, function(value) changeSetting('editButton', value) end)
    g_ui.createWidget('MobileHotbarNote', list):setText(
        tr('Extra rows: 3 slots above the hotbar that stay the same in every preset. Edit: tap a slot to change it, drag one onto another to swap them.'))
    if scroll > 0 then
        local sheet = settingsSheet
        addEvent(function()
            if sheet == settingsSheet then
                sheet.panel.listScroll:setValue(scroll)
            end
        end)
    end
end

-- Layout ----------------------------------------------------------------------

-- Creates the preset and edit buttons next to the hotbar
function createHotbarPresetRow(root, actionPanel)
    presetRow = g_ui.createWidget('MobileHotbarPresetRow', root)
    presetRow:setId('mobileHotbarPresets')
    setRoundFace(presetRow.preset, 'silver')
    setRoundFace(presetRow.edit, 'silver')
    presetRow.preset.onMouseRelease = function(widget, pos, button)
        if not widget:containsPoint(pos) then
            return false
        end
        if button == MouseRightButton then
            openHotbarSettings()
        else
            nextPreset()
        end
        return true
    end
    -- Two quick taps arrive as a double click instead of a second release
    presetRow.preset.onDoubleClick = function()
        nextPreset()
        return true
    end
    presetRow.edit.onMouseRelease = function(widget, pos, button)
        if not widget:containsPoint(pos) then
            return false
        end
        if button == MouseRightButton then
            openHotbarSettings()
        else
            setHotbarEditing(not editing)
        end
        return true
    end
    createEditOverlay(actionPanel)
    updatePresetButton()
    return presetRow
end

-- The P and pencil buttons (the UI setup hides them with the hotbar)
function getHotbarPresetRow()
    return presetRow
end

function destroyHotbarPresetRow()
    closeSettings()
    editing = false
    if editOverlay then
        editOverlay:destroy()
        editOverlay = nil
    end
    if presetRow then
        presetRow:destroy()
        presetRow = nil
    end
end

function refreshHotbarPresetRow()
    updatePresetButton()
end
