-- Automations (ot-client#21): optional helpers that save the repetitive
-- work, per character, all off until switched on:
--
--   Loot gold / Loot food: what is in a corpse you open goes to your backpack
--   Change gold: a stack that looting fills to 100 coins becomes the next
--     coin (coins you carry or change down yourself are left alone)
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
-- Arrows and bolts (items with the Ammo flag in the game server's
-- items.srv; 7.x item files give the client no such flag)
local AMMO = { [3446] = true, [3447] = true, [3448] = true, [3449] = true, [3450] = true, [6528] = true }

local AUTOMATIONS = {
    { id = 'openCorpse', text = 'Open corpse' },
    { id = 'lootGold', text = 'Loot gold' },
    { id = 'lootFood', text = 'Loot food' },
    { id = 'changeGold', text = 'Change gold' },
    { id = 'eatFood', text = 'Eat food' },
    { id = 'refillAmmo', text = 'Refill ammo' },
    { id = 'stakeSkin', text = 'Stake/skin' },
    { id = 'autoTurn', text = 'Auto-turn' },
    { id = 'manaSound', text = 'Mana sound' },
}

-- Auto stake/skin: tool -> the corpses it works on (the game server's
-- data/actions/scripts/misc/skinning_dusting.lua)
local OBSIDIAN_KNIFE, BLESSED_STAKE = 5908, 5942
local SKINNING = {
    [OBSIDIAN_KNIFE] = { [4011] = true, [4047] = true, [4057] = true, [4052] = true, -- minotaurs
        [4321] = true, [4327] = true, [4324] = true, -- lizards
        [4025] = true, [4062] = true, [4112] = true, [4212] = true }, -- dragons, dragon lords, behemoths, bone beasts
    [BLESSED_STAKE] = { [4097] = true, [4137] = true }, -- demons, vampires
}
-- Auto-turn: spells that hit what is in front of you
local DIRECTIONAL = { 'Strike', 'Wave', 'Beam' }
local MANA_SOUND = '/mods/client_automations/sounds/mana_full'

local options = {} -- this character's switches
local ticker, eatEvent
local lastUseAt, lastEatAt = 0, 0
-- Coins just looted: { container = id, coin = id, until = millis }. Change
-- gold only changes a stack that looting filled, never coins you carry or
-- changed down yourself
local lootedCoins
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

-- Loot filters: named loot lists kept for every character on this device
-- ({ name -> { item id (text) -> a container name, or false: as "Put loot
-- in" } }); each character picks one (options.lootFilter) or none
local FILTERS_SETTING = 'automations_lootFilters'
local filters = {}

local function loadFilters()
    local ok, saved = pcall(json.decode, g_settings.getString(FILTERS_SETTING))
    filters = ok and type(saved) == 'table' and saved or {}
    -- a character's list from before filters becomes a filter of its own
    if type(options.lootList) == 'table' and next(options.lootList) then
        local player = g_game.getLocalPlayer()
        local name = (player and player:getName() or 'My') .. '\'s loot'
        filters[name] = filters[name] or options.lootList
        options.lootFilter = options.lootFilter or name
    end
    options.lootList = nil
end

local function saveFilters()
    g_settings.set(FILTERS_SETTING, json.encode(filters))
    g_settings.save()
end

-- A ready-made filter: every item some monster drops Rare or rarer (from
-- the item data's rarity words; read-only)
local PRESET_RARE = 'Everything rare'
local MAX_ITEMS = 500
local rareList

local function presetRare()
    if not rareList then
        local itemdata = modules.client_itemdata
        local list = {}
        for _, entry in ipairs(itemdata and itemdata.lootItems and itemdata.lootItems() or {}) do
            if entry.tier >= itemdata.RARE_TIER then
                list[tostring(entry.id)] = false
            end
        end
        -- (the item data may not be loaded yet: try again next time)
        if next(list) then
            rareList = list
        end
        return list
    end
    return rareList
end

local function isPreset(name)
    return name == PRESET_RARE
end

-- The active filter's items, or nil
local function activeList()
    if isPreset(options.lootFilter) then
        return presetRare()
    end
    return options.lootFilter and filters[options.lootFilter] or nil
end

local function countOf(list)
    local n = 0
    for _ in pairs(list or {}) do
        n = n + 1
    end
    return n
end

-- Helpers ----------------------------------------------------------------------

-- Opened from the map (a corpse, a bag on the floor): not inside another
-- container and not one of your equipped items (small corpses count as
-- pickupable in 7.x, so that says nothing)
local function isGround(container)
    -- the containers window knows where each was opened from
    local containers = modules.client_containers
    local known = containers and containers.isGroundContainer and containers.isGroundContainer(container)
    if known ~= nil then
        return known
    end
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

-- Your main backpack, when it is open
local function openBackpack()
    local player = g_game.getLocalPlayer()
    local backpack = player and player:getInventoryItem(InventorySlotBack)
    if not backpack then
        return nil
    end
    for _, container in pairs(g_game.getContainers()) do
        local item = container:getContainerItem()
        if not container:hasParent() and item and item:getId() == backpack:getId() and not isGround(container) then
            return container
        end
    end
end

-- An open container you named (client_containers), or nil
local function namedContainer(name)
    local containers = modules.client_containers
    if name and containers and containers.getNamedContainers then
        for _, entry in ipairs(containers.getNamedContainers()) do
            if entry.name == name then
                return entry.container
            end
        end
    end
end

-- Where an item goes: its own container from the loot list, else the one
-- in "Put loot in", else the main backpack (each when it is open)
local function lootContainer(item)
    local list = activeList()
    local listed = list and list[tostring(item:getId())]
    if listed == 'Backpack' then
        return openBackpack()
    end
    return (type(listed) == 'string' and namedContainer(listed)) or namedContainer(options.lootTo) or openBackpack()
end

-- Where to move an item so it joins a stack of the same kind (coins on
-- coins), else the container's first free slot. (A move to the container's
-- slot 0 could land inside a bag kept there.)
local function lootTarget(item)
    local container = lootContainer(item)
    if not container then
        local player = g_game.getLocalPlayer()
        local backpack = player and player:getInventoryItem(InventorySlotBack)
        if backpack and backpack:isContainer() then
            return { x = 65535, y = InventorySlotBack, z = 0 }, item:getCount()
        end
        return nil
    end
    if item:isStackable() then
        for slot, carried in ipairs(container:getItems()) do
            if carried:getId() == item:getId() and carried:getCount() < 100 then
                return { x = 65535, y = 64 + container:getId(), z = slot - 1 },
                    math.min(item:getCount(), 100 - carried:getCount())
            end
        end
    end
    if container:getItemsCount() >= container:getCapacity() then
        return nil
    end
    return { x = 65535, y = 64 + container:getId(), z = container:getItemsCount() }, item:getCount()
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
    return (isOn('lootGold') and COINS[id]) or (isOn('lootFood') and FOODS[id]) or
        (activeList() ~= nil and activeList()[tostring(id)] ~= nil) or false
end

-- The loot list ---------------------------------------------------------------

local function lootListActive()
    local list = activeList()
    return list ~= nil and next(list) ~= nil
end

function isListed(id)
    local list = activeList()
    return list ~= nil and list[tostring(id)] ~= nil
end

-- (with no filter chosen, one named "Loot" is made and chosen). Returns
-- false when it cannot: a ready-made filter, or the filter is full
function setListed(id, listed)
    if isPreset(options.lootFilter) then
        return false
    end
    if not activeList() then
        options.lootFilter = options.lootFilter or 'Loot'
        filters[options.lootFilter] = filters[options.lootFilter] or {}
        saveOptions()
    end
    local list = activeList()
    if listed then
        if list[tostring(id)] == nil then
            if countOf(list) >= MAX_ITEMS then
                return false
            end
            list[tostring(id)] = false
        end
    else
        list[tostring(id)] = nil
    end
    saveFilters()
    return true
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

-- Everything wanted in a container you opened, sent at once. From the last
-- slot to the first: taking one item out moves the ones after it up, so
-- the others keep their places.
local function lootAll(container)
    if container:isClosed() then
        return
    end
    local items = container:getItems()
    local planned = {} -- container id -> items being added
    for i = #items, 1, -1 do
        local item = items[i]
        if wanted(item) then
            local target, count = lootTarget(item)
            if target and target.y >= 64 then
                -- a new slot: count what is on its way there
                local id = target.y - 64
                local into = g_game.getContainer(id)
                local stacking = item:isStackable() and target.z < (into and into:getItemsCount() or 0)
                if not stacking then
                    planned[id] = (planned[id] or 0) + 1
                    if into and into:getItemsCount() + planned[id] > into:getCapacity() then
                        target = nil
                    end
                end
            end
            if not target then
                -- nowhere to put it
                return
            end
            g_game.move(item, target, count)
            if COINS[item:getId()] and target.y >= 64 then
                lootedCoins = { container = target.y - 64, coin = item:getId(), untilAt = g_clock.millis() + 3000 }
            end
        end
    end
end

local function changeStep()
    -- (wait for the server's answer before using another stack)
    if not isOn('changeGold') or not lootedCoins or g_clock.millis() - lastUseAt < 1000 then
        return false
    end
    if g_clock.millis() > lootedCoins.untilAt then
        lootedCoins = nil
        return false
    end
    local container = g_game.getContainer(lootedCoins.container)
    local coin = lootedCoins.coin
    for _, item in ipairs(container and container:getItems() or {}) do
        if item:getId() == coin and coin ~= CRYSTAL_COIN and item:getCount() == 100 then
            lastUseAt = g_clock.millis()
            lootedCoins = nil
            g_game.use(item)
            return true
        end
    end
    -- (the loot move may not have arrived yet: try again next tick)
    return true
end

tick = function()
    if not g_game.isOnline() then
        stopTicking()
        return
    end
    if changeStep() then
        return
    end
    stopTicking()
end

-- Open corpse: one of your corpses next to you (never walks to it)
local CORPSE_EVERY = 500
local corpseEvent
local triedAt = {} -- "x,y,z" -> millis of the last try

local skinned = {} -- "x,y,z" -> true once the knife or stake was used

-- A tool in a hand, the ammo slot or your open bags
local function findTool(id)
    local player = g_game.getLocalPlayer()
    for slot = InventorySlotFirst, InventorySlotLast do
        local item = player and player:getInventoryItem(slot)
        if item and item:getId() == id then
            return item
        end
    end
    return findCarried(function(item) return item:getId() == id end)
end

local function openCorpseStep()
    if not (isOn('openCorpse') or isOn('stakeSkin')) or not g_game.isOnline() then
        return
    end
    local classic = modules.client_classic
    local player = g_game.getLocalPlayer()
    if not (classic and classic.getMyCorpses and player) then
        return
    end
    local here = player:getPosition()
    local now = g_clock.millis()
    for _, corpse in ipairs(classic.getMyCorpses()) do
        local pos = corpse.pos
        local key = pos.x .. ',' .. pos.y .. ',' .. pos.z
        local near = pos.z == here.z and math.abs(pos.x - here.x) <= 1 and math.abs(pos.y - here.y) <= 1
        if near and isOn('stakeSkin') and not skinned[key] then
            -- first the knife or stake (it changes the corpse), then open
            for tool, corpses in pairs(SKINNING) do
                if corpses[corpse.item:getId()] then
                    local carried = findTool(tool)
                    if carried then
                        skinned[key] = true
                        g_game.useWith(carried, corpse.item)
                        return
                    end
                end
            end
        end
        if near and isOn('openCorpse') and now - (triedAt[key] or 0) > 3000 then
            triedAt[key] = now
            g_game.open(corpse.item)
            return
        end
    end
end

-- Events -----------------------------------------------------------------------

local function onContainerOpen(container)
    if (isOn('lootGold') or isOn('lootFood') or lootListActive()) and isGround(container) then
        lootAll(container)
        -- (a coin stack that reached 100 is changed once the moves arrive)
        if lootedCoins and isOn('changeGold') then
            startTicking()
        end
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

-- (the client reports no old item when a slot empties, so the arrows in
-- the slot are remembered while they are there)
local ammoInSlot

local function onInventoryChange(player, slot, item)
    if slot ~= InventorySlotAmmo then
        return
    end
    if item then
        ammoInSlot = AMMO[item:getId()] and item:getId() or nil
        return
    end
    local id = ammoInSlot
    ammoInSlot = nil
    if not id or not isOn('refillAmmo') then
        return
    end
    scheduleEvent(function()
        local refill = g_game.isOnline() and findCarried(function(candidate) return candidate:getId() == id end)
        if refill then
            g_game.move(refill, { x = 65535, y = InventorySlotAmmo, z = 0 }, refill:getCount())
        end
    end, MOVE_DELAY)
end

local function onTextMessage(mode, text)
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
    helpBox.box:setWidth(math.min(520, rootWidget:getWidth() - 16))
    helpBox.box:setHeight(math.min(rootWidget:getHeight() - 16, helpBox.box.text:getHeight() + 50))
    helpBox.onClick = closeHelp
    helpBox:raise()
end

local prompt

local function closePrompt()
    if prompt then
        prompt:destroy()
        prompt = nil
    end
end

local chooser

local function closeChooser()
    if chooser then
        chooser:destroy()
        chooser = nil
    end
end

local picker

local function closePicker()
    if picker then
        picker:destroy()
        picker = nil
    end
end

function close()
    closeHelp()
    closePrompt()
    closeChooser()
    closePicker()
    if sheet then
        sheet:destroy()
        sheet = nil
    end
end

local HELP = 'Open corpse: a corpse of a monster you killed opens when you stand next to it.\n' ..
    'Stake/skin: with an obsidian knife or blessed stake in your bags, a minotaur, lizard, dragon, behemoth, bone beast, vampire or demon corpse of yours is skinned or staked when you stand next to it.\n' ..
    'Auto-turn: a strike, wave or beam (hotbar or typed) first turns you to your target.\n' ..
    'Mana sound: a chime when your mana is full.\n' ..
    'Loot gold / food: coins or food from a corpse you open go to your loot container, onto a stack of the same kind when there is one.\n' ..
    'Change gold: when looting makes a stack of 100 gold or platinum coins, it becomes the next coin. Coins you carry or change yourself are never touched.\n' ..
    'Eat food: eats after you log in and every two minutes.\n' ..
    'Refill ammo: arrows or bolts from your bags fill an empty ammo slot.\n' ..
    'Loot list: loot filters, each a list of items to take from corpses you open, into their own container or the one in Put loot in. Filters are kept for every character on this device; each character uses one. Copy code and Import move a filter to another device.\n' ..
    'They work at a player\'s speed, only on what you open yourself. Saved for this character.'

-- The containers loot can go to: Backpack (nil) and the ones you named
local function lootChoices(current)
    local choices = { { value = nil, text = tr('Backpack') } }
    local containers = modules.client_containers
    local seen = {}
    for _, entry in ipairs(containers and containers.getNamedContainers and containers.getNamedContainers() or {}) do
        if not seen[entry.name] then
            seen[entry.name] = true
            table.insert(choices, { value = entry.name, text = entry.name })
        end
    end
    -- a chosen container that is closed now still shows
    if current and not seen[current] then
        table.insert(choices, { value = current, text = current })
    end
    return choices
end

local function renderLootTo()
    local row = sheet.panel.general.lootTo
    row:destroyChildren()
    for _, choice in ipairs(lootChoices(options.lootTo)) do
        local button = g_ui.createWidget('OtButton', row)
        button:setText(choice.text)
        button:setWidth(math.max(80, button:getTextSize().width + 24))
        button:setChecked(options.lootTo == choice.value)
        button.onClick = function()
            options.lootTo = choice.value
            saveOptions()
            renderLootTo()
        end
    end
end

local function itemName(id)
    local itemdata = modules.client_itemdata
    local entry = itemdata and itemdata.getItem and itemdata.getItem(id)
    return entry and entry.n:gsub('^%l', string.upper) or tostring(id)
end

local renderLootPage

local function renderLootList()
    local page = sheet.panel.lootPage
    local list = page.list
    list:destroyChildren()
    local readOnly = isPreset(options.lootFilter)
    local entries = {}
    for id, target in pairs(activeList() or {}) do
        table.insert(entries, { id = tonumber(id), target = target, name = itemName(id) })
    end
    table.sort(entries, function(a, b) return a.name < b.name end)
    for _, entry in ipairs(entries) do
        local row = g_ui.createWidget('LootListRow', list)
        row.item:setItemId(entry.id)
        row.name:setText(entry.name)
        row.target:setVisible(not readOnly)
        row.remove:setVisible(not readOnly)
        -- the item's own container, or the one in "Put loot in"
        row.target:setText(entry.target or tr('Default'))
        row.target:setChecked(entry.target ~= false)
        row.target.onClick = function()
            -- Default (as in "Put loot in"), Backpack, then your named containers
            local choices = { false, 'Backpack' }
            local named = entry.target ~= 'Backpack' and entry.target or nil
            for _, choice in ipairs(lootChoices(named)) do
                if choice.value and choice.value ~= 'Backpack' then
                    table.insert(choices, choice.value)
                end
            end
            local at = 1
            for i, value in ipairs(choices) do
                if value == entry.target then
                    at = i
                    break
                end
            end
            activeList()[tostring(entry.id)] = choices[at % #choices + 1]
            saveFilters()
            renderLootList()
        end
        row.remove.onClick = function()
            setListed(entry.id, false)
            renderLootPage()
        end
    end
    page.empty:setVisible(#entries == 0)
    page.empty:setText(activeList() and
        tr('Nothing in this filter yet. Tap Add loot, or long press an item in a container and choose Loot this.') or
        tr('No loot filter in use. Tap the filter above to choose or make one. Filters are kept for every character on this device.'))
end

-- Filter codes: "LOOT1:" and the filter as JSON (copied to share it with
-- another device, pasted to import)
local CODE_PREFIX = 'LOOT1:'
local function askText(title, text, done)
    closePrompt()
    prompt = g_ui.createWidget('LootFilterPrompt', rootWidget)
    prompt.box.title:setText(tr(title))
    prompt.box.text:setText(text or '')
    prompt.box.text:setCursorPos(-1)
    prompt.box.cancel.onClick = closePrompt
    prompt.box.ok.onClick = function()
        local value = prompt.box.text:getText():gsub('^%s+', ''):gsub('%s+$', '')
        closePrompt()
        if value ~= '' then
            done(value)
        end
    end
    prompt.onEscape = closePrompt
    prompt:raise()
    prompt.box.text:focus()
end

-- A name not taken yet: "Name", "Name 2", ...
local function freeName(name)
    local candidate, n = name, 1
    while filters[candidate] or isPreset(candidate) do
        n = n + 1
        candidate = name .. ' ' .. n
    end
    return candidate
end

local function useFilter(name)
    options.lootFilter = name
    saveOptions()
    renderLootPage()
end

-- A list to choose from (LootChooser): rows of { text, checked, onClick };
-- the search narrows them when there are many
local function openChooser(title, rows)
    closeChooser()
    chooser = g_ui.createWidget('LootChooser', rootWidget)
    local panel = chooser.panel
    panel:setSize({ width = math.min(420, rootWidget:getWidth() - 16), height = math.min(420, rootWidget:getHeight() - 16) })
    panel.title:setText(tr(title))
    panel.close.onClick = closeChooser
    chooser.onClick = closeChooser
    chooser.onEscape = closeChooser
    local many = #rows > 8
    panel.search:setVisible(many)
    panel.search:setHeight(many and 36 or 0)
    local function render()
        panel.list:destroyChildren()
        local text = panel.search:getText():lower()
        local shown = 0
        for _, row in ipairs(rows) do
            if text == '' or row.fixed or row.text:lower():find(text, 1, true) then
                shown = shown + 1
                if shown > 100 then
                    break
                end
                local button = g_ui.createWidget(row.style or 'OtButton', panel.list)
                button:setText(row.text)
                button:setChecked(row.checked or false)
                button.onClick = function()
                    closeChooser()
                    row.onClick()
                end
            end
        end
    end
    panel.search.onTextChange = render
    render()
    chooser:raise()
end

local function openFilterMenu()
    local rows = {
        { text = tr('None'), checked = options.lootFilter == nil, fixed = true, onClick = function() useFilter(nil) end },
        { text = tr(PRESET_RARE) .. '  (' .. tr('ready-made') .. ')', checked = isPreset(options.lootFilter), fixed = true,
            onClick = function() useFilter(PRESET_RARE) end },
    }
    local names = {}
    for name in pairs(filters) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        table.insert(rows, { text = name .. '  (' .. countOf(filters[name]) .. ')', checked = options.lootFilter == name,
            onClick = function() useFilter(name) end })
    end
    table.insert(rows, { text = '+ ' .. tr('New filter'), style = 'OtButtonPrimary', fixed = true, onClick = function()
        askText('Name the new loot filter', '', function(name)
            name = freeName(name:sub(1, 20))
            filters[name] = {}
            saveFilters()
            useFilter(name)
        end)
    end })
    table.insert(rows, { text = tr('Import a code'), fixed = true, onClick = function()
        askText('Paste a loot filter code', '', function(code)
            local ok, data = pcall(json.decode, code:gsub('^' .. CODE_PREFIX, ''))
            if not ok or type(data) ~= 'table' or type(data.items) ~= 'table' then
                showHelp('That is not a loot filter code.')
                return
            end
            local items, count, dropped = {}, 0, 0
            for id, target in pairs(data.items) do
                if tonumber(id) and (target == false or type(target) == 'string') then
                    if count < MAX_ITEMS then
                        items[tostring(id)] = target
                        count = count + 1
                    else
                        dropped = dropped + 1
                    end
                end
            end
            local name = freeName(type(data.name) == 'string' and data.name:sub(1, 20) or 'Imported')
            filters[name] = items
            saveFilters()
            useFilter(name)
            if dropped > 0 then
                showHelp(string.format('A filter holds at most %d items: %d were left out.', MAX_ITEMS, dropped))
            end
        end)
    end })
    openChooser('Loot filter', rows)
end

-- Add loot: everything monsters drop (or one monster's loot), a-z, with a
-- tick for what is in the filter
local function openPicker(creature)
    closePicker()
    local itemdata = modules.client_itemdata
    if not (itemdata and itemdata.lootItems) then
        return
    end
    picker = g_ui.createWidget('LootPicker', rootWidget)
    local panel = picker.panel
    panel:setSize({ width = math.min(560, rootWidget:getWidth() - 16), height = math.min(460, rootWidget:getHeight() - 16) })
    panel.title:setText(tr('Add loot to') .. ' ' .. options.lootFilter)
    panel.close.onClick = function()
        closePicker()
        renderLootPage()
    end
    picker.onEscape = panel.close.onClick
    panel.creature:setText((creature or tr('All monsters')) .. '  v')
    panel.creature.onClick = function()
        local rows = { { text = tr('All monsters'), checked = creature == nil, fixed = true, onClick = function() openPicker(nil) end } }
        for _, name in ipairs(itemdata.creaturesWithLoot()) do
            table.insert(rows, { text = name, checked = creature == name, onClick = function() openPicker(name) end })
        end
        openChooser('Monster', rows)
    end
    local items = itemdata.lootItems(creature)
    local function render()
        panel.list:destroyChildren()
        local text = panel.search:getText():lower()
        local matching = {}
        for _, entry in ipairs(items) do
            if text == '' or entry.name:lower():find(text, 1, true) then
                table.insert(matching, entry)
            end
        end
        local LIMIT = 120
        for i = 1, math.min(#matching, LIMIT) do
            local entry = matching[i]
            local row = g_ui.createWidget('LootPickRow', panel.list)
            row.item:setItemId(entry.id)
            row.name:setText(entry.name:gsub('^%l', string.upper))
            -- the monster's rarity word, or from the most common to the rarest
            if creature or entry.minTier == entry.tier then
                row.rarity:setText(itemdata.rarityName(entry.tier))
            else
                row.rarity:setText(itemdata.rarityName(entry.minTier) .. ' - ' .. itemdata.rarityName(entry.tier))
            end
            row.rarity:setColor(itemdata.RARITY_COLORS[entry.tier] or '#e8e8e8')
            row.check:setChecked(isListed(entry.id))
            row.onClick = function()
                local want = not isListed(entry.id)
                if not setListed(entry.id, want) then
                    showHelp(string.format('A filter holds at most %d items.', MAX_ITEMS))
                end
                row.check:setChecked(isListed(entry.id))
                panel.count:setText(tr('%d in this filter', countOf(activeList())))
            end
        end
        panel.count:setText(tr('%d in this filter', countOf(activeList())) ..
            (#matching > LIMIT and ('  -  ' .. tr('showing %d of %d: search to narrow', LIMIT, #matching)) or ''))
    end
    panel.search.onTextChange = render
    render()
    picker:raise()
end

local function renderActions()
    local page = sheet.panel.lootPage
    page.actions:destroyChildren()
    local current = options.lootFilter
    local list = activeList()
    page.filter:setText(tr('Loot filter') .. ':  ' .. (current or tr('None')) ..
        (list and ('  (' .. countOf(list) .. ')') or '') .. '   v')
    page.filter.onClick = openFilterMenu
    local function addButton(text, onClick, style)
        local button = g_ui.createWidget(style or 'OtButton', page.actions)
        button:setText(text)
        button:setWidth(math.max(64, button:getTextSize().width + 24))
        button.onClick = onClick
        return button
    end
    if not current then
        return
    end
    if isPreset(current) then
        -- (ready-made: copy it to change it)
        addButton(tr('Make a copy'), function()
            local name = freeName(PRESET_RARE)
            filters[name] = {}
            for id in pairs(presetRare()) do
                filters[name][id] = false
            end
            saveFilters()
            useFilter(name)
        end)
        return
    end
    addButton(tr('Add loot'), function() openPicker(nil) end, 'OtButtonPrimary')
    addButton(tr('Rename'), function()
        askText('Rename the loot filter', current, function(name)
            name = name:sub(1, 20)
            if name ~= current then
                name = freeName(name)
                filters[name] = filters[current]
                filters[current] = nil
                saveFilters()
                useFilter(name)
            end
        end)
    end)
    addButton(tr('Copy code'), function()
        g_window.setClipboardText(CODE_PREFIX .. json.encode({ name = current, items = filters[current] }))
        showHelp('The code of "' .. current .. '" is copied. Paste it with Import a code on another device.')
    end)
    addButton(tr('Delete'), function()
        filters[current] = nil
        saveFilters()
        -- other characters that used it fall back to none
        useFilter(nil)
    end, 'OtButtonDanger')
end

renderLootPage = function()
    renderActions()
    renderLootList()
end

local function showTab(id)
    local panel = sheet.panel
    panel.general:setVisible(id == 'general')
    panel.lootPage:setVisible(id == 'loot')
    for _, tab in ipairs(panel.tabs:getChildren()) do
        tab:setChecked(tab:getId() == id)
    end
    if id == 'loot' then
        renderLootPage()
    end
end

function open(tab)
    close()
    sheet = g_ui.createWidget('AutomationsSheet', rootWidget)
    local panel = sheet.panel
    local width = math.min(600, rootWidget:getWidth() - 16)
    panel:setWidth(width)
    sheet.onClick = close
    sheet.onEscape = close
    panel.close.onClick = close
    panel.help.onClick = function() showHelp(HELP) end
    for _, entry in ipairs({ { 'general', 'General' }, { 'loot', 'Loot list' } }) do
        local button = g_ui.createWidget('OtTab', panel.tabs)
        button:setId(entry[1])
        button:setText(tr(entry[2]))
        button.onClick = function() showTab(entry[1]) end
    end
    panel.tabs:getLayout():setCellSize({ width = 130, height = 36 })
    local toggles = panel.general.toggles
    -- as many columns as fit (4 on a tablet or desktop, 3 on a phone)
    local columns = math.max(2, math.min(4, math.floor((width - 24) / 140)))
    toggles:getLayout():setCellSize({ width = math.floor((width - 24 - 2 * (columns - 1)) / columns), height = 40 })
    for _, automation in ipairs(AUTOMATIONS) do
        local toggle = g_ui.createWidget('AutomationToggle', toggles)
        toggle.text:setText(tr(automation.text))
        toggle.check:setChecked(isOn(automation.id))
        toggle.check.onCheckChange = function(widget, checked)
            options[automation.id] = checked
            saveOptions()
        end
        toggle.onClick = function()
            toggle.check:setChecked(not toggle.check:isChecked())
        end
    end
    renderLootTo()
    -- as tall as the switches need, and room for a list
    local rows = math.ceil(#AUTOMATIONS / columns)
    local general = 12 + 40 + 6 + 36 + 6 + rows * 42 + 12 + 16 + 4 + 40 + 12
    panel:setHeight(math.min(rootWidget:getHeight() - 16, math.max(general, 380)))
    showTab(tab or 'general')
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

-- Auto-turn: before a strike, wave or beam from the hotbar, face the target
local directional = {} -- spell words -> true
local originalTalk

local function buildDirectional()
    directional = {}
    for _, spell in pairs(SpellInfo and SpellInfo.Default or {}) do
        for _, word in ipairs(DIRECTIONAL) do
            if spell.words and spell.name and spell.name:find(word) then
                directional[spell.words:lower()] = true
            end
        end
    end
end

local function faceTarget()
    local player = g_game.getLocalPlayer()
    local target = g_game.getAttackingCreature()
    if not player or not target then
        return
    end
    local from, to = player:getPosition(), target:getPosition()
    if from.z ~= to.z then
        return
    end
    local dx, dy = to.x - from.x, to.y - from.y
    if dx == 0 and dy == 0 then
        return
    end
    local direction
    if math.abs(dx) >= math.abs(dy) then
        direction = dx > 0 and East or West
    else
        direction = dy > 0 and South or North
    end
    if player:getDirection() ~= direction then
        g_game.turn(direction)
    end
end

local function beforeSpell(words)
    if isOn('autoTurn') and type(words) == 'string' then
        if not next(directional) then
            buildDirectional()
        end
        if directional[words:lower():gsub('^%s+', ''):gsub('%s+$', '')] then
            faceTarget()
        end
    end
end

local originalTalkChannel

local function onTalk(words, ...)
    beforeSpell(words)
    return originalTalk(words, ...)
end

-- (typed in the chat: said in the default channel)
local function onTalkChannel(mode, channel, words, ...)
    if mode == MessageModes.Say then
        beforeSpell(words)
    end
    return originalTalkChannel(mode, channel, words, ...)
end

-- Mana full sound
local function onManaChange(player, mana, maxMana, oldMana)
    -- (not at login: mana comes from 0 then)
    if not isOn('manaSound') or not g_sounds or maxMana <= 0 or mana < maxMana or
        not oldMana or oldMana <= 0 or oldMana >= maxMana then
        return
    end
    -- (the client's own sounds stay off: this channel only)
    if g_sounds.setAudioEnabled and not g_sounds.isAudioEnabled() then
        g_sounds.setAudioEnabled(true)
    end
    local channel = g_sounds.getChannel(SoundChannels.Bot)
    if channel then
        channel:setEnabled(true)
        channel:setGain(1)
        channel:play(MANA_SOUND, 0, 1.0)
    end
end

-- Module ------------------------------------------------------------------------

local function onGameStart()
    rareList = nil
    loadOptions()
    loadFilters()
    saveOptions()
    if eatEvent then
        removeEvent(eatEvent)
    end
    eatEvent = cycleEvent(eat, EAT_EVERY)
    if corpseEvent then
        removeEvent(corpseEvent)
    end
    triedAt = {}
    skinned = {}
    corpseEvent = cycleEvent(openCorpseStep, CORPSE_EVERY)
    scheduleEvent(eat, 5000)
end

local function onGameEnd()
    close()
    stopTicking()
    if eatEvent then
        removeEvent(eatEvent)
        eatEvent = nil
    end
    if corpseEvent then
        removeEvent(corpseEvent)
        corpseEvent = nil
    end
end

function init()
    g_ui.importStyle('automations')
    -- first: a handler that returns true ends the others' turn
    connect(Container, { onOpen = onContainerOpen }, true)
    -- first: a handler that returns true ends the others' turn
    connect(LocalPlayer, { onInventoryChange = onInventoryChange, onManaChange = onManaChange }, true)
    originalTalk = g_game.talk
    g_game.talk = onTalk
    originalTalkChannel = g_game.talkChannel
    g_game.talkChannel = onTalkChannel
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
    disconnect(Container, { onOpen = onContainerOpen })
    disconnect(LocalPlayer, { onInventoryChange = onInventoryChange, onManaChange = onManaChange })
    if g_game.talk == onTalk then
        g_game.talk = originalTalk
    end
    if g_game.talkChannel == onTalkChannel then
        g_game.talkChannel = originalTalkChannel
    end
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onTextMessage = onTextMessage })
    onGameEnd()
    if topButton then
        topButton:destroy()
        topButton = nil
    end
end
