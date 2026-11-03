-- Tasks in the hub (ot-client#44): the daily hunt from the taskmaster
-- (ot-server#21). The server sends the status as JSON with extended opcode
-- 106 ({"daily":{...}}) on every kill, at the taskmaster and when asked; the
-- hub's Tasks page (client_mobile/hub.lua) shows it with render().
--
-- More kinds of tasks (hunting tasks, exploration, level rewards) become
-- more tabs: add them to TABS.

local TASKS_OPCODE = 106

TABS = {
    { id = 'daily', text = 'Daily hunt' },
}

local daily -- the last status, and when it came (os.time) for the clocks
local receivedAt = 0
local listeners = {}
local tickEvent

local function plural(n, word)
    return n .. ' ' .. word .. (n == 1 and '' or 's')
end

-- "3 h 20 min", "40 min"
local function duration(seconds)
    local minutes = math.ceil(math.max(0, seconds) / 60)
    local hours = math.floor(minutes / 60)
    minutes = minutes % 60
    if hours > 0 then
        return hours .. ' h ' .. minutes .. ' min'
    end
    return minutes .. ' min'
end

local function capitalize(text)
    return (text:gsub('^%l', string.upper))
end

function getDaily()
    return daily
end

-- Ask the server for the status (the answer comes with opcode 106)
function request()
    local protocol = g_game.getProtocolGame()
    if g_game.isOnline() and protocol then
        protocol:sendExtendedOpcode(TASKS_OPCODE, 'get')
    end
end

-- fn() runs whenever a new status comes
function addListener(fn)
    table.insert(listeners, fn)
end

function removeListener(fn)
    table.removevalue(listeners, fn)
end

local function changed()
    for _, fn in ipairs(listeners) do
        pcall(fn)
    end
end

local function onTasks(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' then
        return
    end
    if type(data.daily) == 'table' then
        daily = data.daily
        receivedAt = os.time()
    end
    changed()
end

-- Seconds left on a clock from the status, counted down since it came
local function remaining(seconds)
    return math.max(0, (seconds or 0) - (os.time() - receivedAt))
end

local function heading(parent, text)
    local widget = g_ui.createWidget('OtHeading', parent)
    widget.text:setText(tr(text))
    return widget
end

local function text(parent, value, style)
    local widget = g_ui.createWidget(style or 'OtText', parent)
    widget:setText(value)
    widget:setMarginBottom(6)
    return widget
end

local function renderDaily(list)
    if not daily then
        text(list, tr('Asking the taskmaster...'), 'OtHint')
        return
    end
    local d = daily
    heading(list, 'Today\'s hunt')
    if d.state == 'locked' then
        text(list, tr('Daily hunts start at level %d. Come back then!', d.minLevel or 8))
    elseif d.state == 'available' then
        text(list, tr('Your daily hunt is ready. Greet a taskmaster and say task.'))
    elseif d.state == 'waiting' then
        text(list, tr('You have had your hunt for today.'))
        text(list, tr('Next hunt in %s.', duration(remaining(d.availableIn))), 'OtHint')
    elseif d.hunt then
        local name = capitalize(d.hunt.name or '')
        text(list, name, 'OtLabel'):setTextAutoResize(true)
        local monsters = {}
        for _, monster in ipairs(d.hunt.monsters or {}) do
            table.insert(monsters, capitalize(monster))
        end
        if #monsters > 1 then
            text(list, tr('Any of these count: %s.', table.concat(monsters, ', ')), 'OtHint')
        end
        local progress = g_ui.createWidget('TasksProgress', list)
        local kills, required = d.kills or 0, math.max(1, d.required or 1)
        progress.bar:setPercent(math.floor(100 * math.min(kills, required) / required))
        progress.bar:setText(kills .. ' / ' .. required)
        if d.state == 'done' then
            text(list, tr('Done! Return to a taskmaster and say reward. %s left.', duration(remaining(d.timeLeft))))
        else
            text(list, tr('%s left. Any blow you land counts.', duration(remaining(d.timeLeft))), 'OtHint')
        end
    end

    -- the streak: a count and what the next hunt pays
    local streak = d.streak or 0
    local multipliers = d.multiplier or {}
    local nextMultiplier = multipliers[math.min(streak + 1, #multipliers)]
    local line = tr('Streak: %s', plural(streak, 'day'))
    if nextMultiplier then
        line = line .. ' - ' .. tr('next hunt %sx experience', tostring(nextMultiplier))
    end
    text(list, line, 'OtLabel'):setTextAutoResize(true)
end

-- Fills `list` with the tab's page
function render(tabId, list)
    if tabId == 'daily' then
        renderDaily(list)
    end
end

-- The open page's clocks count down: a refresh each minute
local function tick()
    if daily and (daily.state == 'active' or daily.state == 'done' or daily.state == 'waiting') then
        changed()
    end
end

local function onGameStart()
    daily = nil
    request()
end

local function onGameEnd()
    daily = nil
end

function init()
    ProtocolGame.registerExtendedOpcode(TASKS_OPCODE, onTasks)
    g_ui.importStyle('tasks')
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    tickEvent = cycleEvent(tick, 60000)
    if g_game.isOnline() then
        request()
    end
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(TASKS_OPCODE)
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    listeners = {}
end
