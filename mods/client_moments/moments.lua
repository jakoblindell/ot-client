-- Moments (ot-client#25, ot-server#52): a screenshot of the game view when
-- something happens to the character, kept on the device.
--
-- The server says when (extended opcode 106, {"moment":{"kind","text","at"}},
-- passed on by client_tasks): level ups, skill and magic level advances,
-- deaths, achievements, quest chests and unjustified kills. If the player
-- wants that kind (all are on at first), the game view is captured a moment
-- later (so the game's own message is in the picture) and saved under
-- moments/<character>/ in the write folder (the browser's saved storage).
-- The newest KEEP per character are kept.
--
-- Shown in the hub's character sheet, Screenshots tab (character.lua calls
-- renderTab): what to capture, then the pictures with Save and Delete.

local KEEP = 50
local SETTINGS = 'client_moments'
local INDEX = 'client_moments_index'
-- ms after the moment before the picture: the message is on screen then
local DELAY = 700
-- a death: right away, before the death window covers the game
local DEATH_DELAY = 150

KINDS = {
    { id = 'level', text = 'Level ups' },
    { id = 'skill', text = 'Skill advances' },
    { id = 'death', text = 'Deaths' },
    { id = 'achievement', text = 'Achievements' },
    { id = 'chest', text = 'Quest chests' },
    { id = 'unjustified', text = 'Unjustified kills' },
}

local CAPTIONS = {
    level = 'Level up', skill = 'Skill', death = 'Death', achievement = 'Achievement',
    chest = 'Quest chest', unjustified = 'Unjustified kill',
}

-- Settings ---------------------------------------------------------------------

local function settings()
    return g_settings.getNode(SETTINGS) or {}
end

function isCapturing(kind)
    local value = settings()[kind]
    -- all kinds are on until switched off
    return value == nil or value == true or value == 'true'
end

function setCapturing(kind, on)
    local all = settings()
    all[kind] = on and true or false
    g_settings.setNode(SETTINGS, all)
    g_settings.save()
end

-- The pictures, per character -------------------------------------------------------

-- (a folder name from the character's name)
local function characterFolder()
    local name = g_game.getCharacterName() or ''
    return (name:gsub('[^%w]', '_'))
end

-- The pictures are kept as a map "m<time>" -> entry (the settings file keeps
-- keyed tables, not plain lists); newest first here
function list()
    local all = g_settings.getNode(INDEX) or {}
    local stored = all[characterFolder()]
    local result = {}
    for key, entry in pairs(type(stored) == 'table' and stored or {}) do
        if type(entry) == 'table' and entry.file then
            entry.key = key
            entry.at = tonumber(entry.at) or 0
            table.insert(result, entry)
        end
    end
    table.sort(result, function(a, b) return a.at > b.at end)
    return result
end

local function saveIndex(stored)
    local all = g_settings.getNode(INDEX) or {}
    all[characterFolder()] = stored
    g_settings.setNode(INDEX, all)
    g_settings.save()
end

local function storedIndex()
    local all = g_settings.getNode(INDEX) or {}
    local stored = all[characterFolder()]
    return type(stored) == 'table' and stored or {}
end

function delete(key)
    local stored = storedIndex()
    local entry = stored[key]
    if entry and entry.file then
        pcall(g_resources.deleteFile, entry.file)
    end
    stored[key] = nil
    saveIndex(stored)
end

-- Only the newest KEEP stay
local function prune()
    local entries = list()
    for i = KEEP + 1, #entries do
        delete(entries[i].key)
    end
end

function caption(entry)
    return tr(CAPTIONS[entry.kind] or 'Moment') .. ' - ' .. os.date('%d %b %Y', entry.at)
end

-- The browser saves a copy where the player wants it
function save(entry)
    local name = (CAPTIONS[entry.kind] or 'moment'):lower():gsub('%s+', '-') .. os.date('-%Y%m%d-%H%M%S', entry.at) .. '.png'
    if g_platform.downloadFile then
        g_platform.downloadFile(g_resources.getWriteDir() .. entry.file, name)
    end
end

-- Taking the picture ----------------------------------------------------------------

-- The game view in window pixels (UI coordinates times the display density)
local function gameViewArea()
    local gameInterface = modules.game_interface
    local map = gameInterface and gameInterface.getMapPanel and gameInterface.getMapPanel()
    if not map or not map:isVisible() then
        return nil
    end
    local rect = map:getRect()
    local density = g_window.getDisplayDensity()
    return math.floor(rect.x * density), math.floor(rect.y * density),
        math.floor(rect.width * density), math.floor(rect.height * density)
end

local function capture(kind, text, at)
    if not g_game.isOnline() then
        return
    end
    local folder = 'moments/' .. characterFolder()
    pcall(g_resources.makeDir, 'moments')
    pcall(g_resources.makeDir, folder)
    local file = string.format('%s/%d-%s.png', folder, at, kind)
    local x, y, width, height = gameViewArea()
    if x and g_app.doScreenshotArea then
        g_app.doScreenshotArea(file, x, y, width, height)
    else
        g_app.doScreenshot(file)
    end
    local stored = storedIndex()
    -- (two moments in the same second: the second gets its own key)
    local key = 'm' .. at
    while stored[key] do
        key = key .. 'x'
    end
    stored[key] = { file = file, kind = kind, text = text or '', at = at }
    saveIndex(stored)
    prune()
end

-- From the server (client_tasks passes it on)
function onMoment(moment)
    if type(moment) ~= 'table' or not isCapturing(moment.kind) then
        return
    end
    local kind, text = moment.kind, moment.text
    local at = tonumber(moment.at) or os.time()
    scheduleEvent(function()
        capture(kind, text, at)
    end, kind == 'death' and DEATH_DELAY or DELAY)
end

-- The Screenshots tab (the hub's character sheet) -------------------------------------

function renderTab(listWidget, refresh)
    local toggles = g_ui.createWidget('MomentToggles', listWidget)
    local cell = math.floor((listWidget:getWidth() - 4) / 2)
    toggles:getLayout():setCellSize({ width = cell, height = 40 })
    for _, kind in ipairs(KINDS) do
        local toggle = g_ui.createWidget('MomentToggle', toggles)
        toggle.label:setText(tr(kind.text))
        toggle.check:setChecked(isCapturing(kind.id))
        local function flip()
            local on = not isCapturing(kind.id)
            setCapturing(kind.id, on)
            toggle.check:setChecked(on)
        end
        toggle.check.onClick = flip
        toggle.label.onClick = flip
    end

    local entries = list()
    local hint = g_ui.createWidget('OtHint', listWidget)
    hint:setMarginTop(6)
    if #entries == 0 then
        hint:setText(tr('No pictures yet. They are taken by themselves when one of the above happens, and stay on this device (the newest %d).', KEEP))
        return
    end
    hint:setText(tr('%d of %d pictures, kept on this device.', #entries, KEEP))

    local grid = g_ui.createWidget('MomentGrid', listWidget)
    local width = math.floor((listWidget:getWidth() - 8) / 2)
    grid:getLayout():setCellSize({ width = width, height = 196 })
    for _, entry in ipairs(entries) do
        local card = g_ui.createWidget('MomentCard', grid)
        card.picture:setImageSource('/' .. entry.file)
        card.caption:setText(caption(entry))
        card.detail:setText(entry.text or '')
        card.save.onClick = function()
            save(entry)
        end
        card.delete.onClick = function()
            delete(entry.key)
            if refresh then
                refresh()
            end
        end
    end
end

function init()
    g_ui.importStyle('moments')
end

function terminate()
end
