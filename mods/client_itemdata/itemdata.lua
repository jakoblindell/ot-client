-- Item data (ot-client#31): every item that can be picked up, with its
-- stats, the NPCs that buy and sell it and the creatures that drop it. The
-- website builds it from the game server's files (/data/items/version and
-- /data/items/<version>.json); it is downloaded only when its version
-- changes and kept on this device.
--
-- Other modules: modules.client_itemdata.getItem(id), .getFluid(id, fluid),
-- .findByName(name), .npcName(i), .creatureName(i), .isReady(), and the
-- onItemDataReady callback (connect(modules.client_itemdata, ...) style is
-- not available for a module table, so they register with onReady(fn)).

local FILE = '/settings/itemdata.json'

local data -- the decoded file
local byName = {}
local listeners = {}
local checking = false

-- Where the website is: the page's own (the browser build), or Services.website
local function baseUrl()
    if g_platform.isBrowser and g_platform.isBrowser() then
        return ''
    end
    local website = Services and Services.website
    return website and website:gsub('/$', '') or nil
end

local function plural(name)
    if name:find('s$') or name:find('x$') or name:find('ch$') then
        return name .. 'es'
    end
    return name .. 's'
end

local function use(decoded)
    data = decoded
    creatureIndex = nil
    byName = {}
    for id, item in pairs(data.items or {}) do
        local name = item.n:lower()
        byName[name] = byName[name] or tonumber(id)
        byName[plural(name)] = byName[plural(name)] or tonumber(id)
    end
    for _, fn in ipairs(listeners) do
        pcall(fn)
    end
end

local function loadSaved()
    if not g_resources.fileExists(FILE) then
        return
    end
    local ok, decoded = pcall(function()
        return json.decode(g_resources.readFileContents(FILE))
    end)
    if ok and type(decoded) == 'table' and decoded.items then
        use(decoded)
    end
end

-- Asks the website for the current version; downloads the file if it is new
function check()
    local base = baseUrl()
    if checking or not base or not HTTP then
        return
    end
    checking = true
    -- (the file is bigger than the default 2 s allows on a slow phone)
    local timeout = HTTP.timeout
    HTTP.timeout = 30
    HTTP.getJSON(base .. '/data/items/version', function(info, err)
        if err or type(info) ~= 'table' or not info.version then
            checking = false
            return
        end
        if data and data.version == info.version then
            checking = false
            return
        end
        HTTP.get(base .. info.url, function(body, err2)
            checking = false
            if err2 or not body then
                return
            end
            local ok, decoded = pcall(json.decode, body)
            if not ok or type(decoded) ~= 'table' or not decoded.items then
                return
            end
            if not g_resources.directoryExists('/settings/') then
                g_resources.makeDir('/settings/')
            end
            g_resources.writeFileContents(FILE, body)
            use(decoded)
        end)
    end)
    HTTP.timeout = timeout
end

function isReady()
    return data ~= nil
end

function getItem(id)
    return data and data.items[tostring(id)]
end

-- A vial's prices depend on what is in it
function getFluid(id, fluid)
    return data and data.fluids and data.fluids[id .. ':' .. fluid]
end

-- An item id from a name as the game writes it ("a serpent sword",
-- "3 gold coins", "worms")
function findByName(name)
    name = name:lower():gsub('^an? ', ''):gsub('^the ', '')
    return byName[name] or byName[name:gsub('es$', '')] or byName[name:gsub('s$', '')]
end

-- Items whose name holds the text, those starting with it first, as
-- { { id = 3297, name = 'serpent sword' } } (at most limit)
function search(text, limit)
    text = text:lower():gsub('^%s+', ''):gsub('%s+$', '')
    if not data or #text < 2 then
        return {}
    end
    local seen, found = {}, {}
    for id, item in pairs(data.items) do
        local name = item.n:lower()
        local at = name:find(text, 1, true)
        if at and not seen[name] then
            seen[name] = true
            table.insert(found, { id = tonumber(id), name = item.n, first = at == 1 })
        end
    end
    table.sort(found, function(a, b)
        if a.first ~= b.first then
            return a.first
        end
        return a.name < b.name
    end)
    while limit and #found > limit do
        table.remove(found)
    end
    return found
end

function npcName(index)
    return data and data.npcs[index + 1]
end

function creatureName(index)
    return data and data.creatures[index + 1]
end

-- Rarity tiers (an index into data.rarities: 0 Always ... 6 Extremely rare)
-- and the colour each is shown in (loot messages, loot lists)
RARITY_COLORS = { [0] = '#c8c8c8', [1] = '#e8e8e8', [2] = '#5fd35f', [3] = '#4aa3ff',
    [4] = '#c06cff', [5] = '#ff9f2e', [6] = '#ff5050' }
RARE_TIER = 4

function rarityName(tier)
    return data and data.rarities and data.rarities[tier + 1] or ''
end

local creatureIndex -- lower-case name -> index

local function findCreature(name)
    if not data then
        return nil
    end
    if not creatureIndex then
        creatureIndex = {}
        for i, creature in ipairs(data.creatures or {}) do
            creatureIndex[creature:lower()] = i - 1
        end
    end
    name = name:lower():gsub('^an? ', ''):gsub('^the ', '')
    return creatureIndex[name]
end

-- The creatures that drop something players may see, a-z
function creaturesWithLoot()
    local seen, list = {}, {}
    for _, item in pairs(data and data.items or {}) do
        for _, drop in ipairs(item.drop or {}) do
            if not seen[drop[1]] then
                seen[drop[1]] = true
                table.insert(list, data.creatures[drop[1] + 1])
            end
        end
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

-- Items creatures drop, a-z: { id, name, tier (the creature's, or the
-- rarest when no creature is given), minTier (the most common),
-- creatures (how many drop it) }
function lootItems(creatureName)
    local index = creatureName and findCreature(creatureName)
    if creatureName and not index then
        return {}
    end
    local list, seenName = {}, {}
    for id, item in pairs(data and data.items or {}) do
        local tier, minTier, count
        for _, drop in ipairs(item.drop or {}) do
            if not index or drop[1] == index then
                tier = math.max(tier or 0, drop[2])
                minTier = math.min(minTier or 99, drop[2])
                count = (count or 0) + 1
            end
        end
        local name = item.n:lower()
        if tier and not seenName[name] then
            seenName[name] = true
            table.insert(list, { id = tonumber(id), name = item.n, tier = tier, minTier = minTier, creatures = count })
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

-- "Loot of a dragon: 37 gold coins, a dragon shield." with each item in the
-- colour of its rarity from that creature (as "{text, #colour}" parts for
-- setColoredText); items the data does not know keep the plain colour
function lootColoredText(text)
    local creature, items = text:match('^(Loot of [^:]+: )(.+)$')
    if not creature or not data then
        return nil
    end
    local index = findCreature(creature:match('^Loot of (.-): $'))
    local parts = {}
    for part in items:gmatch('[^,]+') do
        local word = part:gsub('^%s+', ''):gsub('%.$', '')
        local id = findByName((word:gsub('^%d+ ', '')))
        local tier
        for _, drop in ipairs(id and getItem(id) and getItem(id).drop or {}) do
            if drop[1] == index then
                tier = drop[2]
            end
        end
        local color = tier and RARITY_COLORS[tier]
        local lead = part:match('^%s*')
        local tail = part:match('%.$') and '.' or ''
        if color then
            table.insert(parts, lead .. '{' .. word:gsub(',', '') .. ', ' .. color .. '}' .. tail)
        else
            table.insert(parts, part)
        end
    end
    return creature .. table.concat(parts, ',')
end

-- fn() runs whenever the data is (re)loaded
function onReady(fn)
    table.insert(listeners, fn)
    if data then
        pcall(fn)
    end
end

-- The item card ------------------------------------------------------------------

local ICONS = '/images/ui/ot/icons/'
local hoverCard

local function short(value)
    if value >= 10000 then
        return math.floor(value / 1000) .. 'k'
    end
    return tostring(value)
end

local function names(list, nameOf, format, limit)
    local parts = {}
    for index, entry in ipairs(list or {}) do
        if index > limit then
            table.insert(parts, tr('+%d more', #list - limit))
            break
        end
        table.insert(parts, format(nameOf(entry[1]) or '?', entry[2]))
    end
    return table.concat(parts, ', ')
end

-- Fills a card (an ItemCard widget) for an item id (and fluid); false when
-- there is nothing to say about it
function fillCard(card, id, fluid)
    local entry = getItem(id)
    if not entry then
        return false
    end
    card.item:setItemId(id)
    if fluid then
        card.item:setItemSubType(fluid)
    end
    card.name:setText((entry.n:gsub('^%l', string.upper)))
    card.weight:setText(entry.w and tr('Weight: %.2f oz', entry.w) or '')
    card.lines:destroyChildren()
    local function line(icon, text, color)
        local row = g_ui.createWidget('ItemCardLine', card.lines)
        row.icon:setImageSource(ICONS .. icon)
        row.text:setText(text)
        if color then
            row.text:setColor(color)
        end
    end
    if entry.atk then
        line('fightOffensive', tr('Attack: %d', entry.atk))
    end
    if entry.def then
        line('fightDefensive', tr('Defense: %d', entry.def))
    end
    if entry.arm then
        line('fightDefensive', tr('Armor: %d', entry.arm))
    end
    if entry.t then
        line('battle', (entry.t:gsub('^%l', string.upper)))
    end
    local trades = fluid and getFluid(id, fluid) or entry
    if trades.sell then
        line('coins', tr('Sell to: %s', names(trades.sell, npcName, function(name, price)
            return name .. ' (' .. short(price) .. ' gp)'
        end, 2)), '#e0b84c')
    end
    if trades.buy then
        line('containers', tr('Buy from: %s', names(trades.buy, npcName, function(name, price)
            return name .. ' (' .. short(price) .. ' gp)'
        end, 2)))
    end
    if entry.drop then
        -- (the data gives a rarity, never the drop chance)
        line('drops', tr('Dropped by: %s', names(entry.drop, creatureName, function(name, tier)
            local rarity = data.rarities and data.rarities[tier + 1]
            return rarity and (name .. ' (' .. rarity:lower() .. ')') or name
        end, 3)), '#a8a8a8')
    end
    -- the lines wrap at the card's width: their height once laid out
    local function fitHeight()
        local height = 0
        for _, row in ipairs(card.lines:getChildren()) do
            row:setHeight(math.max(18, row.text:getHeight() + 2))
            height = height + row:getHeight()
        end
        card:setHeight(8 + 34 + 6 + height + 8)
    end
    fitHeight()
    addEvent(function()
        if not card:isDestroyed() then
            fitHeight()
        end
    end)
    return true
end

local function itemOf(widget)
    local item = widget.getItem and widget:getItem()
    if not item then
        return nil
    end
    local fluid = item:isFluidContainer() and item:getSubType() > 0 and item:getSubType() or nil
    return item:getId(), fluid
end

local function hideCard()
    if hoverCard then
        hoverCard:hide()
    end
end

-- Desktop: the card next to the item under the mouse
local function showCardFor(widget)
    local id, fluid = itemOf(widget)
    if not id or not data then
        return hideCard()
    end
    hoverCard = hoverCard or g_ui.createWidget('ItemCard', rootWidget)
    if not fillCard(hoverCard, id, fluid) then
        return hideCard()
    end
    local rect = widget:getRect()
    local x = rect.x + rect.width + 6
    if x + hoverCard:getWidth() > rootWidget:getWidth() then
        x = rect.x - hoverCard:getWidth() - 6
    end
    local y = math.max(0, math.min(rect.y, rootWidget:getHeight() - hoverCard:getHeight()))
    hoverCard:setPosition({ x = math.max(0, x), y = y })
    hoverCard:show()
    hoverCard:raise()
end

local savedHover
local function onItemHover(self, hovered)
    savedHover(self, hovered)
    if g_platform.isMobile() or g_ui.getDraggingWidget() then
        return hideCard()
    end
    if hovered then
        showCardFor(self)
    else
        hideCard()
    end
end

function init()
    g_ui.importStyle('itemdata')
    if UIItem and UIItem.onHoverChange then
        savedHover = UIItem.onHoverChange
        UIItem.onHoverChange = onItemHover
    end
    loadSaved()
    connect(g_game, { onGameStart = check })
    if g_game.isOnline() then
        check()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = check })
    listeners = {}
    if savedHover then
        UIItem.onHoverChange = savedHover
        savedHover = nil
    end
    if hoverCard then
        hoverCard:destroy()
        hoverCard = nil
    end
end
