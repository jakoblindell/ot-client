-- "Add to hotbar": a touch-sized sheet for choosing what an action bar slot
-- does, opened by a long press on the slot (instead of the desktop menu).
-- Tabs: items you carry (with how to use them), 7.92 spells from the server
-- data (Data792), chat text, and the action bar's special actions.

-- Spell list filters: the gap between them, and between a filter's text and
-- its edges
local FILTER_SPACING = 6
local FILTER_PADDING = 10

local TABS = {
    { id = 'items', text = 'Items' },
    { id = 'spells', text = 'Spells' },
    { id = 'text', text = 'Text' },
    { id = 'actions', text = 'Actions' },
}

-- The spell list follows the character's vocation, which the server sends
-- (client_vocation). Without it (a server that does not send it) the player
-- picks the filter (per character).
local VOCATION_FILTERS = {
    { id = 0, text = 'All' },
    { id = 4, text = 'Knight' },
    { id = 3, text = 'Paladin' },
    { id = 1, text = 'Sorc' },
    { id = 2, text = 'Druid' },
}

-- The client's vocation ids (Knight 1, Paladin 2, Sorcerer 3, Druid 4;
-- promoted + 10) -> the spell data's (server ids: Sorcerer 1, Druid 2,
-- Paladin 3, Knight 4)
local SPELL_VOCATIONS = { [1] = 4, [2] = 3, [3] = 1, [4] = 2, [11] = 4, [12] = 3, [13] = 1, [14] = 2 }

local TEXT_EXAMPLES = { 'exura', 'utani hur', 'hi', 'trade' }

local sheet
local slotButton
local showTab -- defined below; the tab lists call it to refresh
local currentTab = 'items'
local skipNextSheet = false

local function actionbar()
    return modules.game_actionbar
end

local function slotIds()
    local barId, buttonId = string.match(slotButton:getId(), '(.*)%.(.*)')
    return tonumber(barId), tonumber(buttonId)
end

local function settingKey(name)
    local player = g_game.getLocalPlayer()
    return 'client_mobile_' .. name .. '_' .. (player and player:getName() or '')
end

local function closeSheet()
    if sheet then
        sheet:destroy()
        sheet = nil
    end
    slotButton = nil
end

-- Refreshes the slot after its mapping changed and saves right away (the
-- action bar otherwise saves on logout, which a closed browser tab skips)
local function slotChanged()
    local bar = actionbar()
    local button = slotButton
    closeSheet()
    bar.updateButton(button)
    bar.ApiJson.saveData()
end

-- A finger dragged over the rows scrolls the list (UIScrollArea, touch
-- mode): once it is a drag, the press on the row is cancelled, so only a tap
-- clicks it
local function addRow(title, subtitle, badge, onTap)
    local row = g_ui.createWidget('HotbarSheetRow', sheet.panel.list)
    row.title:setText(title)
    row.subtitle:setText(subtitle or '')
    row.badge:setText(badge or '')
    if not subtitle or subtitle == '' then
        row.title:setMarginTop(16)
    end
    if onTap then
        row.onClick = function()
            onTap()
        end
    end
    return row
end

local function addHeading(text)
    local heading = g_ui.createWidget('HotbarSheetHeading', sheet.panel.list)
    heading:setText(text:upper())
end

-- Puts the filters in lines across the sheet, onto the next line when one
-- is full (a narrow phone in portrait)
local function layoutFilters()
    local panel = sheet.panel
    local room = panel:getWidth() - panel:getPaddingLeft() - panel:getPaddingRight()
    local x, y, height = 0, 0, 0
    for _, button in ipairs(panel.filters:getChildren()) do
        if x > 0 and x + button:getWidth() > room then
            x, y = 0, height + FILTER_SPACING
        end
        button:setMarginLeft(x)
        button:setMarginTop(y)
        x = x + button:getWidth() + FILTER_SPACING
        height = y + button:getHeight()
    end
    panel.filters:setHeight(height)
end

local function setFilters(buttons)
    local filters = sheet.panel.filters
    filters:destroyChildren()
    filters:setMarginTop(#buttons > 0 and 8 or 0)
    for _, spec in ipairs(buttons) do
        local button = g_ui.createWidget('HotbarSheetFilter', filters)
        button:setText(spec.text)
        -- as wide as its text
        button:setWidth(button:getTextSize().width + 2 * FILTER_PADDING)
        button:setChecked(spec.checked or false)
        button.onClick = spec.onClick
    end
    layoutFilters()
end

local function itemName(itemId)
    return Data792.runes[itemId] or Data792.items[itemId] or tr('Item %d', itemId)
end

-- Items tab --------------------------------------------------------------

local function carriedItems()
    local player = g_game.getLocalPlayer()
    local seen, items = {}, {}
    local function add(item)
        if item and not seen[item:getId()] then
            seen[item:getId()] = true
            table.insert(items, item)
        end
    end
    if player then
        for slot = InventorySlotFirst, InventorySlotLast do
            add(player:getInventoryItem(slot))
        end
    end
    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            add(item)
        end
    end
    return items
end

local function showItemUses(itemId)
    local list = sheet.panel.list
    list:destroyChildren()
    setFilters({})
    -- The action bar stores the use type by name (see UseTypes)
    local thingType = g_things.getThingType(itemId, ThingCategoryItem)
    local uses
    if thingType and thingType:isMultiUse() then
        -- Runes, potions and other items used on something
        uses = {
            { 'UseOnYourself', tr('Use on yourself') },
            { 'UseOnTarget', tr('Use on attack target') },
            { 'SelectUseTarget', tr('Use with crosshair'), tr('Tap the button, then tap a target') },
        }
    else
        uses = {
            { 'Use', tr('Use') },
            { 'Equip', tr('Equip') },
        }
    end
    addHeading(itemName(itemId))
    for _, use in ipairs(uses) do
        local row = addRow(use[2], use[3], nil, function()
            local barId, buttonId = slotIds()
            actionbar().ApiJson.createOrUpdateAction(barId, buttonId, use[1], itemId, 0)
            slotChanged()
        end)
        row.item:setItemId(itemId)
        row.item:setVisible(true)
    end
end

local function showItems()
    setFilters({})
    local items = carriedItems()
    if #items == 0 then
        addRow(tr('Nothing carried'), tr('Open your backpack to list its items'))
        return
    end
    for _, item in ipairs(items) do
        local id = item:getId()
        local row = addRow(itemName(id), Data792.runes[id] and tr('Rune') or nil, nil, function()
            showItemUses(id)
        end)
        row.item:setItemId(id)
        row.item:setVisible(true)
    end
    -- Hotkeys use items from open containers, as in 7.x
    local hint = addRow(tr('Missing something?'), tr('Items in closed backpacks are not listed: open them first'))
    hint:setOpacity(0.7)
end

-- Spells tab -------------------------------------------------------------

-- (a spell without vocations, like the house spells, is for every vocation)
local function spellForVocation(spell, vocation)
    return vocation == 0 or #spell.vocations == 0 or table.contains(spell.vocations, vocation)
end

local function spellUsable(spell, player, vocation)
    if not spellForVocation(spell, vocation) then
        return false
    end
    if not player then
        return true
    end
    return spell.magicLevel <= player:getMagicLevel() and spell.level <= player:getLevel()
end

-- The 7.92 spells by their names in the client's spell data (SpellInfo,
-- from a newer server), where its words and name both differ
local SPELL_ICON_NAMES = {
    ['Poison Strike'] = 'Terra Strike',
    ['Poison Wave'] = 'Terra Wave',
    ['Poison Storm'] = 'Wrath of Nature',
    ['Undead Legion'] = 'Animate Dead Rune',
}
-- For a spell the round icon sheet has nothing for (the house spells)
local SPELL_ICON_NONE = '/images/ui/ot/icons/edit'

-- The spell's round icon, found by its words, else by its name (the newer
-- data renamed some words, and calls the rune spells "... Rune")
local function setSpellIcon(row, spell)
    local spells = SpellInfo and SpellInfo.Default or {}
    local data = Spells.getSpellDataByWords(spell.words) or spells[SPELL_ICON_NAMES[spell.name] or spell.name]
        or spells[spell.name .. ' Rune']
    if data and data.clientId then
        row.icon:setImageSource(Spells.ROUND_ICONS)
        row.icon:setImageClip(Spells.getRoundImageClip(data.clientId))
    else
        row.icon:setImageSource(SPELL_ICON_NONE)
        row.icon:setImageSmooth(true)
    end
    row.icon:setVisible(true)
end

local function showSpells()
    local hideUnusable = g_settings.getBoolean(settingKey('hide_unusable'), true)
    local player = g_game.getLocalPlayer()
    local known = player and SPELL_VOCATIONS[player:getVocation()]
    local vocation = known or g_settings.getNumber(settingKey('vocation'), 0)
    local filters = {
        {
            text = tr('Hide unusable'), checked = hideUnusable,
            onClick = function()
                g_settings.set(settingKey('hide_unusable'), not hideUnusable)
                showTab('spells')
            end
        },
    }
    for _, filter in ipairs(known and {} or VOCATION_FILTERS) do
        table.insert(filters, {
            text = tr(filter.text), checked = vocation == filter.id,
            onClick = function()
                g_settings.set(settingKey('vocation'), filter.id)
                showTab('spells')
            end
        })
    end
    setFilters(filters)

    local shown = 0
    for _, spell in ipairs(Data792.spells) do
        local usable = spellUsable(spell, player, vocation)
        if usable or (not hideUnusable and spellForVocation(spell, vocation)) then
            -- the costs and the magic level, when there are any (the 7.92
            -- spells need no character level)
            local costs = {}
            if spell.mana > 0 then
                table.insert(costs, spell.mana .. ' mana')
            end
            if spell.soul > 0 then
                table.insert(costs, spell.soul .. ' soul')
            end
            local badge = table.concat(costs, ', ')
            local subtitle = spell.words .. (spell.param and ' "..."' or '')
            if spell.magicLevel > 0 then
                subtitle = subtitle .. '  -  ML ' .. spell.magicLevel
            end
            local row = addRow(spell.name, subtitle, badge, function()
                if spell.param then
                    -- Needs a name or direction: finish it in the text tab
                    showTab('text', spell.words .. ' "')
                    return
                end
                local barId, buttonId = slotIds()
                actionbar().ApiJson.createOrUpdateText(barId, buttonId, spell.words, true)
                slotChanged()
            end)
            setSpellIcon(row, spell)
            if not usable then
                row:setOpacity(0.5)
            end
            shown = shown + 1
        end
    end
    if shown == 0 then
        addRow(tr('No spells to show'), known and tr('Turn off "Hide unusable"')
            or tr('Turn off "Hide unusable" or pick another vocation'))
    end
end

-- Text tab ---------------------------------------------------------------

local function showText(prefill)
    local panel = sheet.panel.textPanel
    local input = panel.input
    input:setText(prefill or (slotButton.cache and slotButton.cache.param) or '')
    input:setCursorPos(-1)
    input:focus()
    local examples = panel.examples
    examples:destroyChildren()
    for _, text in ipairs(TEXT_EXAMPLES) do
        local chip = g_ui.createWidget('HotbarSheetButton', examples)
        chip:setText(text)
        chip:setWidth(math.max(50, #text * 8 + 20))
        chip.onClick = function()
            input:setText(text)
            input:setCursorPos(-1)
        end
    end
    panel.confirm.onClick = function()
        local text = input:getText():trim()
        if text == '' then
            return
        end
        local barId, buttonId = slotIds()
        actionbar().ApiJson.createOrUpdateText(barId, buttonId, text, true)
        slotChanged()
    end
end

-- Actions tab ------------------------------------------------------------

local function showActions()
    setFilters({})
    local group = false
    for _, action in ipairs(actionbar().ActionBarSpecialActions) do
        local actionGroup = action.group or tr('Other')
        if actionGroup ~= group then
            group = actionGroup
            addHeading(tr(group))
        end
        local row = addRow(action.text, nil, nil, function()
            local barId, buttonId = slotIds()
            actionbar().ApiJson.createOrUpdateSpecialAction(barId, buttonId, action.id)
            slotChanged()
        end)
        if action.icon then
            row.icon:setImageSource(action.icon)
            row.icon:setVisible(true)
        end
    end
end

-------------------------------------------------------------------------

showTab = function(id, prefill)
    if not sheet then
        return
    end
    currentTab = id
    local panel = sheet.panel
    for _, tab in ipairs(panel.tabs:getChildren()) do
        tab:setChecked(tab:getId() == id)
    end
    local isText = id == 'text'
    panel.textPanel:setVisible(isText)
    panel.list:setVisible(not isText)
    panel.listScroll:setVisible(not isText)
    panel.filters:setVisible(not isText)
    panel.list:destroyChildren()
    panel.listScroll:setValue(0)
    if id == 'items' then
        showItems()
    elseif id == 'spells' then
        showSpells()
    elseif id == 'text' then
        showText(prefill)
    else
        showActions()
    end
end

-- Called by the action bar on a right click (long press) on a slot; returns
-- true when the sheet handles it
function openHotbarSheet(button)
    if skipNextSheet then
        skipNextSheet = false
        return false
    end
    local bar = button:getParent() and button:getParent():getParent()
    if bar and bar.locked then
        return false
    end
    closeSheet()
    slotButton = button
    sheet = g_ui.createWidget('HotbarSheet', rootWidget)
    sheet:raise()
    sheet:focus()
    sheet.onClick = closeSheet
    sheet.onEscape = closeSheet

    local panel = sheet.panel
    local function fit()
        local width = math.min(460, rootWidget:getWidth() - 16)
        local height = math.max(300, math.min(640, rootWidget:getHeight() - 16))
        panel:setSize({ width = width, height = height })
        panel.tabs:getLayout():setCellSize({ width = math.floor((width - 24 - 18) / 4), height = 40 })
        layoutFilters()
    end
    fit()
    -- The screen turned or resized while open: fit it again
    sheet.onGeometryChange = function(widget, oldRect, newRect)
        if oldRect.width > 0 and (oldRect.width ~= newRect.width or oldRect.height ~= newRect.height) then
            addEvent(function()
                if sheet == widget then
                    fit()
                end
            end)
        end
    end
    local _, buttonId = slotIds()
    panel.title:setText(tr('Slot %s', button.hotkeyLabel and button.hotkeyLabel:getText() ~= '' and
        button.hotkeyLabel:getText() or tostring(buttonId)))
    panel.close.onClick = closeSheet

    for _, tab in ipairs(TABS) do
        local tabButton = g_ui.createWidget('HotbarSheetButton', panel.tabs)
        tabButton:setId(tab.id)
        tabButton:setText(tr(tab.text))
        tabButton.onClick = function()
            showTab(tab.id)
        end
    end

    panel.footer.clear.onClick = function()
        local target = slotButton
        closeSheet()
        actionbar().clearButton(target, true)
        actionbar().ApiJson.saveData()
    end
    -- The desktop menu, for multi-actions, hotkeys and the rest
    panel.footer.more.onClick = function()
        local target = slotButton
        closeSheet()
        skipNextSheet = true
        if target.onMouseRelease then
            target:onMouseRelease(g_window.getMousePosition(), MouseRightButton)
        end
        skipNextSheet = false
    end

    showTab(currentTab == 'text' and 'items' or currentTab)
    return true
end

function closeHotbarSheet()
    closeSheet()
end
