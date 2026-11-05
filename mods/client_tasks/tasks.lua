-- Tasks in the hub (ot-client#44, #47): the daily hunt (ot-server#21) and
-- the hunting tasks with the hunter rank (ot-server#29) from the
-- taskmaster. The server sends the status as JSON with extended opcode 106
-- ({"daily":{...},"hunting":{...}}) on every kill, at the taskmaster and
-- when asked; the hub's Tasks page (client_mobile/hub.lua) shows it with
-- render().
--
-- More kinds of tasks (hunting tasks, exploration, level rewards) become
-- more tabs: add them to TABS.

local TASKS_OPCODE = 106

-- The hub's pages (ot-client#58): Daily on its own button, the Journal with
-- tabs (Quests and Chests come later, ot-server#44)
PAGES = {
    daily = { title = 'Daily hunt', tabs = { { id = 'daily', text = 'Daily hunt' } } },
    journal = { title = 'Journal', tabs = {
        { id = 'hunting', text = 'Tasks' },
        { id = 'achievements', text = 'Achievements' },
    } },
}
TABS = PAGES.journal.tabs

local daily -- the last status, and when it came (os.time) for the clocks
local hunting
local achievements
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
    if type(data.hunting) == 'table' then
        hunting = data.hunting
    end
    if type(data.achievements) == 'table' then
        achievements = data.achievements
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

-- "4000 experience, 500 gold and 1 item"
local function rewardLine(reward)
    local parts = {}
    if (reward.exp or 0) > 0 then
        table.insert(parts, reward.exp .. ' experience')
    end
    if (reward.gold or 0) > 0 then
        table.insert(parts, reward.gold .. ' gold')
    end
    local items = #(reward.items or {})
    if items > 0 then
        table.insert(parts, plural(items, 'item'))
    end
    if #parts == 0 then
        return nil
    end
    if #parts == 1 then
        return parts[1]
    end
    return table.concat(parts, ', ', 1, #parts - 1) .. ' and ' .. parts[#parts]
end

local function monsterList(monsters)
    local names = {}
    for _, monster in ipairs(monsters or {}) do
        table.insert(names, capitalize(monster))
    end
    return table.concat(names, ', ')
end

local function renderHunting(list)
    if not hunting then
        text(list, tr('Asking the taskmaster...'), 'OtHint')
        return
    end
    local h = hunting

    heading(list, 'Hunter rank')
    text(list, tr('%s - %s', h.rank or '', plural(h.points or 0, 'point')), 'OtLabel'):setTextAutoResize(true)
    if h.nextRank then
        text(list, tr('%s more for %s.', plural((h.nextPoints or 0) - (h.points or 0), 'point'), h.nextRank), 'OtHint')
    end
    if (h.bonus or 0) > 0 then
        text(list, tr('Your rank adds %d%% to the experience and gold of task rewards.', math.floor(h.bonus * 100 + 0.5)), 'OtHint')
    end

    if h.task then
        local task = h.task
        heading(list, 'Your task')
        text(list, capitalize(task.name or ''), 'OtLabel'):setTextAutoResize(true)
        if #(task.monsters or {}) > 1 then
            text(list, tr('Any of these count: %s.', monsterList(task.monsters)), 'OtHint')
        end
        local progress = g_ui.createWidget('TasksProgress', list)
        local kills, required = task.kills or 0, math.max(1, task.required or 1)
        progress.bar:setPercent(math.floor(100 * math.min(kills, required) / required))
        progress.bar:setText(kills .. ' / ' .. required)
        if kills >= required then
            text(list, tr('Done! Report to a taskmaster for your reward.'))
        else
            text(list, tr('No time limit. Any blow you land counts.'), 'OtHint')
        end
        local reward = rewardLine(task.reward or {})
        if reward then
            text(list, tr('Reward: %s.', reward), 'OtHint')
        end
        return
    end

    heading(list, 'Tasks for you')
    if #(h.available or {}) == 0 then
        text(list, tr('No hunting task for you right now.'))
    else
        for _, task in ipairs(h.available) do
            text(list, tr('%s: %d kills', capitalize(task.name or ''), task.kills or 0), 'OtLabel'):setTextAutoResize(true)
            if #(task.monsters or {}) > 1 then
                text(list, monsterList(task.monsters), 'OtHint')
            end
        end
        text(list, tr('Ask a taskmaster: say "start" and the task\'s name.'), 'OtHint')
    end
    if (h.locked or 0) > 0 then
        text(list, tr('A higher hunter rank unlocks %s.', plural(h.locked, 'more task')), 'OtHint')
    end
end

-- Done so far (also under an active task)
local function renderFinished(list)
    local finished = hunting and hunting.finished or {}
    heading(list, 'Finished tasks')
    if #finished == 0 then
        text(list, tr('None yet.'), 'OtHint')
        return
    end
    for _, entry in ipairs(finished) do
        local line = capitalize(entry.name or '')
        if (entry.times or 1) > 1 then
            line = line .. ' x' .. entry.times
        end
        text(list, tr('%s - %s', line, plural(entry.points or 0, 'point')))
    end
end

local function renderAchievements(list)
    if not achievements then
        text(list, tr('Asking the server...'), 'OtHint')
        return
    end
    local a = achievements
    heading(list, 'Achievements')
    text(list, tr('%d of %d unlocked - %d of %d points', a.unlocked or 0, a.count or 0, a.points or 0, a.totalPoints or 0),
        'OtLabel'):setTextAutoResize(true)
    for _, category in ipairs(a.categories or {}) do
        local entries = {}
        for _, entry in ipairs(a.list or {}) do
            if entry.category == category.id then
                table.insert(entries, entry)
            end
        end
        if #entries > 0 then
            heading(list, category.name)
            -- unlocked first, then the rest in list order
            table.sort(entries, function(x, y)
                if (x.unlockedAt ~= nil) ~= (y.unlockedAt ~= nil) then
                    return x.unlockedAt ~= nil
                end
                return x.id < y.id
            end)
            for _, entry in ipairs(entries) do
                local points = plural(entry.points or 0, 'point')
                if entry.hidden then
                    text(list, tr('??? - %s', points), 'OtHint')
                else
                    local row = text(list, tr('%s - %s', entry.name or '', points),
                        entry.unlockedAt and 'TasksAchievementDone' or 'OtLabel')
                    row:setTextAutoResize(true)
                    local detail = entry.text or ''
                    if entry.unlockedAt then
                        detail = detail .. '  ' .. os.date('%Y-%m-%d', entry.unlockedAt)
                    end
                    text(list, detail, 'OtHint')
                    if entry.target and not entry.unlockedAt then
                        local progress = g_ui.createWidget('TasksProgress', list)
                        local value, goal = entry.progress or 0, math.max(1, entry.target)
                        progress.bar:setPercent(math.floor(100 * math.min(value, goal) / goal))
                        progress.bar:setText(value .. ' / ' .. goal)
                    end
                end
            end
        end
    end
end

-- Fills `list` with the tab's page
function render(tabId, list)
    if tabId == 'daily' then
        renderDaily(list)
    elseif tabId == 'hunting' then
        renderHunting(list)
        renderFinished(list)
    elseif tabId == 'achievements' then
        renderAchievements(list)
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
    hunting = nil
    achievements = nil
    request()
end

local function onGameEnd()
    daily = nil
    hunting = nil
    achievements = nil
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
