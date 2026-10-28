-- Automations (ot-client#21): optional helpers that save the repetitive
-- work, per character, all off until switched on:
--
--   Loot gold / Loot food: what is in a corpse you open goes to your backpack
--   Change gold: a full stack of 100 coins (in your bags or equipment)
--     becomes the next coin
--   Eat food: eats from your open bags now and then ("You are full." is
--     not shown when it comes from this)
--   Refill ammo: an empty ammo slot is filled from the same arrows or bolts
--     in your open bags
--
-- Only what a player could do by hand, at a player's speed: one move or use
-- every MOVE_DELAY, only on containers you opened, never walking,
-- targeting or casting. The server checks every move as usual.

local MOVE_DELAY = 300
local EAT_EVERY = 2 * 60 * 1000
local SETTING_PREFIX = 'automations_'

local GOLD_COIN, PLATINUM_COIN, CRYSTAL_COIN = 3031, 3035, 3043
local COINS = { [GOLD_COIN] = true, [PLATINUM_COIN] = true, [CRYSTAL_COIN] = true }
-- (the game server's data/actions/scripts/misc/food.lua)
local FOODS = {}
for _, id in ipairs({ 3250, 3577, 3578, 3579, 3580, 3581, 3582, 3583, 3584, 3585, 3586, 3587, 3588, 3589,
    3590, 3591, 3592, 3593, 3594, 3595, 3596, 3597, 3598, 3599, 3600, 3601, 3602, 3606, 3607, 3723, 3724,
    3725, 3726, 3727, 3728, 3729, 3730, 3731, 3732, 5096, 5678, 6125, 6277, 6278, 6392, 6393, 6500, 6541,
    6542, 6543, 6544, 6545, 6569, 6574 }) do
    FOODS[id] = true
end
-- Server answers that end a looting run
local STOP_MESSAGES = {
    'You cannot put more objects in this container.',
    'This object is too heavy for you to carry.',
    'You do not have enough room.',
    'There is not enough room.',
}

local AUTOMATIONS = {
    { id = 'lootGold', text = 'Loot gold',
        help = 'Coins in a corpse you open go to your backpack.' },
    { id = 'lootFood', text = 'Loot food',
        help = 'Food in a corpse you open goes to your backpack.' },
    { id = 'changeGold', text = 'Change gold',
        help = 'A full stack of 100 gold or platinum coins in your open bags becomes the next coin.' },
    { id = 'eatFood', text = 'Eat food',
        help = 'Eats food from your open bags after you log in and every two minutes, so you keep regenerating.' },
    { id = 'refillAmmo', text = 'Refill ammo',
        help = 'When your arrows or bolts run out, the same kind from your open bags goes to the ammo slot.' },
}

local options = {} -- this character's switches
local lootQueue = {} -- containers (corpses) to take things from
local ticker, eatEvent
local lastUseAt, lastEatAt = 0, 0
local sheet, helpBox, topButton

-- Settings ---------------------------------------------------------------------

local function settingKey()
    local player = g_game.getLocalPlayer()
    return player and (SETTING_PREFIX .. player:getName()) or nil
end

local function loadOptions()
    local key = settingKey()
    local ok, saved = pcall(json.decode, key and g_settings.getString(key) or '')
    options = ok and type(saved) == 'table' and saved or {}
end

local function saveOptions()
    local key = settingKey()
    if key then
        g_settings.set(key, json.encode(options))
        g_settings.save()
    end
end

function isOn(id)
    return options[id] == true
end

-- Helpers ----------------------------------------------------------------------

-- Opened from the map (a corpse, a bag on the floor): not inside another
-- container and not one of your equipped items (small corpses count as
-- pickupable in 7.x, so that says nothing)
local function isGround(container)
    if container:hasParent() then
        return false
    end
    local item = container:getContainerItem()
    local player = g_game.getLocalPlayer()
    for slot = InventorySlotFirst, InventorySlotLast do
        local equipped = player and player:getInventoryItem(slot)
        if equipped and item and equipped:getId() == item:getId() then
            return false
        end
    end
    return true
end

local function backpackPosition()
    local player = g_game.getLocalPlayer()
    local backpack = player and player:getInventoryItem(InventorySlotBack)
    if backpack and backpack:isContainer() then
        return { x = 65535, y = InventorySlotBack, z = 0 }
    end
end

-- The first item in your own open bags (not corpses) that matches
local function findCarried(match)
    for _, container in pairs(g_game.getContainers()) do
        if not isGround(container) then
            for _, item in ipairs(container:getItems()) do
                if match(item) then
                    return item
                end
            end
        end
    end
end

local function wanted(item)
    local id = item:getId()
    return (isOn('lootGold') and COINS[id]) or (isOn('lootFood') and FOODS[id]) or false
end

-- The work loop: one move or use per tick ------------------------------------------

local tick

local function startTicking()
    if not ticker then
        ticker = cycleEvent(tick, MOVE_DELAY)
    end
end

local function stopTicking()
    if ticker then
        removeEvent(ticker)
        ticker = nil
    end
end

local function lootStep()
    while #lootQueue > 0 do
        local container = lootQueue[1]
        local target = backpackPosition()
        if container:isClosed() or not target then
            table.remove(lootQueue, 1)
        else
            for _, item in ipairs(container:getItems()) do
                if wanted(item) then
                    g_game.move(item, target, item:getCount())
                    return true
                end
            end
            table.remove(lootQueue, 1)
        end
    end
    return false
end

local function changeStep()
    -- (wait for the server's answer before using another stack)
    if not isOn('changeGold') or g_clock.millis() - lastUseAt < 1000 then
        return false
    end
    local function full(item)
        local id = item and item:getId()
        return (id == GOLD_COIN or id == PLATINUM_COIN) and item:getCount() == 100
    end
    -- (coins are often held in a hand or the ammo slot in 7.x)
    local player = g_game.getLocalPlayer()
    local stack
    for slot = InventorySlotFirst, InventorySlotLast do
        local item = player and player:getInventoryItem(slot)
        if full(item) then
            stack = item
            break
        end
    end
    stack = stack or findCarried(full)
    if stack then
        lastUseAt = g_clock.millis()
        g_game.use(stack)
        return true
    end
    return false
end

tick = function()
    if not g_game.isOnline() then
        stopTicking()
        return
    end
    if lootStep() or changeStep() then
        return
    end
    stopTicking()
end

-- Events -----------------------------------------------------------------------

local function onContainerOpen(container)
    if (isOn('lootGold') or isOn('lootFood')) and isGround(container) then
        table.insert(lootQueue, container)
        startTicking()
    end
end

local function onContainerChange()
    if isOn('changeGold') then
        startTicking()
    end
end

local function eat()
    if not isOn('eatFood') or not g_game.isOnline() then
        return
    end
    local food = findCarried(function(item) return FOODS[item:getId()] end)
    if food then
        lastEatAt = g_clock.millis()
        g_game.use(food)
    end
end

local function onInventoryChange(player, slot, item, oldItem)
    if item and isOn('changeGold') then
        startTicking()
    end
    if slot ~= InventorySlotAmmo then
        return
    end
    -- arrows and bolts only (coins live there too)
    if item or not oldItem or not oldItem:isAmmo() or not isOn('refillAmmo') then
        return
    end
    local id = oldItem:getId()
    scheduleEvent(function()
        local refill = g_game.isOnline() and findCarried(function(candidate) return candidate:getId() == id end)
        if refill then
            g_game.move(refill, { x = 65535, y = InventorySlotAmmo, z = 0 }, refill:getCount())
        end
    end, MOVE_DELAY)
end

local function onTextMessage(mode, text)
    for _, message in ipairs(STOP_MESSAGES) do
        if text == message then
            lootQueue = {}
        end
    end
    -- our own meal: no need to say so
    if text == 'You are full.' and g_clock.millis() - lastEatAt < 2000 then
        return true
    end
end

-- The window ---------------------------------------------------------------------

local function closeHelp()
    if helpBox then
        helpBox:destroy()
        helpBox = nil
    end
end

local function showHelp(text)
    closeHelp()
    helpBox = g_ui.createWidget('AutomationsHelp', rootWidget)
    helpBox.box.text:setText(tr(text))
    helpBox.onClick = closeHelp
    helpBox:raise()
end

function close()
    closeHelp()
    if sheet then
        sheet:destroy()
        sheet = nil
    end
end

function open()
    close()
    sheet = g_ui.createWidget('AutomationsSheet', rootWidget)
    local panel = sheet.panel
    panel:setSize({ width = math.min(480, rootWidget:getWidth() - 16),
        height = math.min(420, rootWidget:getHeight() - 16) })
    sheet.onClick = close
    sheet.onEscape = close
    panel.close.onClick = close
    for _, automation in ipairs(AUTOMATIONS) do
        local row = g_ui.createWidget('OtSettingRow', panel.list)
        row.title:setText(tr(automation.text))
        row.help.onClick = function() showHelp(automation.help) end
        local check = g_ui.createWidget('OtCheck', row.controls)
        check:setChecked(isOn(automation.id))
        check.onCheckChange = function(widget, checked)
            options[automation.id] = checked
            saveOptions()
            if automation.id == 'changeGold' and checked then
                startTicking()
            end
        end
        row.controls:setWidth(40)
    end
    sheet:raise()
    sheet:focus()
end

function toggle()
    if sheet then
        close()
    else
        open()
    end
end

-- Module ------------------------------------------------------------------------

local function onGameStart()
    loadOptions()
    lootQueue = {}
    if eatEvent then
        removeEvent(eatEvent)
    end
    eatEvent = cycleEvent(eat, EAT_EVERY)
    scheduleEvent(eat, 5000)
    -- (a full stack may be waiting from last time)
    if isOn('changeGold') then
        scheduleEvent(startTicking, 2000)
    end
end

local function onGameEnd()
    close()
    stopTicking()
    lootQueue = {}
    if eatEvent then
        removeEvent(eatEvent)
        eatEvent = nil
    end
end

function init()
    g_ui.importStyle('automations')
    -- first: a handler that returns true ends the others' turn
    connect(Container, { onOpen = onContainerOpen, onAddItem = onContainerChange, onUpdateItem = onContainerChange }, true)
    connect(LocalPlayer, { onInventoryChange = onInventoryChange })
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    -- first, to keep our own "You are full." out of the messages
    connect(g_game, { onTextMessage = onTextMessage }, true)
    -- the touch layout opens it from the hub; the desktop from the top menu
    if not g_platform.isMobile() and modules.client_topmenu then
        topButton = modules.client_topmenu.addRightGameButton('automationsButton', tr('Automations'),
            '/images/ui/ot/icons/check_on', toggle)
    end
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(Container, { onOpen = onContainerOpen, onAddItem = onContainerChange, onUpdateItem = onContainerChange })
    disconnect(LocalPlayer, { onInventoryChange = onInventoryChange })
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onTextMessage = onTextMessage })
    onGameEnd()
    if topButton then
        topButton:destroy()
        topButton = nil
    end
end
