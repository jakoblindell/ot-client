-- Unopened corpses shine for the player who may loot them. The server says
-- which corpses are the player's (extended opcode 101, "new x y z itemId")
-- and when the player opens a container on the map ("opened x y z"). Marks
-- are kept by position: a corpse becomes a new item as it decays, and tiles
-- are rebuilt when they come back into view, so the shine is put back on
-- the top corpse(s) of each marked tile twice a second.

local CORPSE_OPCODE = 101
local SHINE_COLOR = '#ffe8a0'
local SCAN_INTERVAL = 500
-- a mark whose tile is out of view is dropped after this long (corpses are
-- gone by then)
local MARK_LIFETIME = 30 * 60 * 1000

local marks = {} -- "x,y,z" -> { pos = Position, count = n, at = millis }
local shining = {} -- items currently highlighted
local scanEvent

local function key(pos)
    return pos.x .. ',' .. pos.y .. ',' .. pos.z
end

local function enabled()
    local options = modules.client_options
    return not options or not options.getOption or options.getOption('showUnopenedCorpses') ~= false
end

local function clearShine()
    for item in pairs(shining) do
        item:setHighlight('#ffffff') -- white: no highlight
    end
    shining = {}
end

local function corpsesOn(tile)
    local found = {}
    for _, item in ipairs(tile:getItems()) do
        if item:isContainer() then
            table.insert(found, item)
        end
    end
    return found
end

local function scan()
    clearShine()
    if not g_game.isOnline() or not enabled() then
        return
    end
    local now = g_clock.millis()
    for id, mark in pairs(marks) do
        local tile = g_map.getTile(mark.pos)
        if tile then
            local corpses = corpsesOn(tile)
            if #corpses == 0 then
                -- the corpse decayed away or was moved
                marks[id] = nil
            else
                mark.at = now
                -- the top items come first
                for i = 1, math.min(mark.count, #corpses) do
                    corpses[i]:setHighlight(SHINE_COLOR)
                    shining[corpses[i]] = true
                end
            end
        elseif now - mark.at > MARK_LIFETIME then
            marks[id] = nil
        end
    end
end

local function onCorpseMessage(protocol, opcode, buffer)
    local kind, x, y, z = buffer:match('^(%a+) (%d+) (%d+) (%d+)')
    if not kind then
        return
    end
    local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    local id = key(pos)
    if kind == 'new' then
        local mark = marks[id] or { pos = pos, count = 0 }
        mark.count = mark.count + 1
        mark.at = g_clock.millis()
        marks[id] = mark
    elseif kind == 'opened' and marks[id] then
        marks[id].count = marks[id].count - 1
        if marks[id].count <= 0 then
            marks[id] = nil
        end
    end
    scan()
end

-- Your unopened corpses that are in view: { { pos = Position, item = Item } }
-- (client_automations opens them)
function getMyCorpses()
    local list = {}
    for _, mark in pairs(marks) do
        local tile = g_map.getTile(mark.pos)
        local corpse = tile and corpsesOn(tile)[1]
        if corpse then
            table.insert(list, { pos = mark.pos, item = corpse })
        end
    end
    return list
end

local function onGameEnd()
    clearShine()
    marks = {}
end

function initCorpseShine()
    ProtocolGame.registerExtendedOpcode(CORPSE_OPCODE, onCorpseMessage)
    connect(g_game, { onGameEnd = onGameEnd })
    scanEvent = cycleEvent(scan, SCAN_INTERVAL)
end

function terminateCorpseShine()
    ProtocolGame.unregisterExtendedOpcode(CORPSE_OPCODE)
    disconnect(g_game, { onGameEnd = onGameEnd })
    if scanEvent then
        removeEvent(scanEvent)
        scanEvent = nil
    end
    onGameEnd()
end
