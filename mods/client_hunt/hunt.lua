-- Hunt analyzer (ot-client#29): a compact panel with the session's numbers
-- (a side panel window on desktop, a toolbar panel on touch screens) and a
-- full report with Stats, Monsters, Loot and Supplies. The numbers come from
-- tracker.lua.

local window, report
local reportTab = 'stats'
local updateEvent

local function short(value)
    value = math.floor(value)
    local sign = value < 0 and '-' or ''
    value = math.abs(value)
    if value >= 1000000 then
        return sign .. string.format('%.1fkk', value / 1000000):gsub('%.0kk', 'kk')
    elseif value >= 10000 then
        return sign .. math.floor(value / 1000) .. 'k'
    end
    return sign .. tostring(value)
end

local function duration(seconds)
    seconds = math.floor(seconds)
    local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if h > 0 then
        return string.format('%dh %02dm', h, m)
    end
    return string.format('%dm %02ds', m, seconds % 60)
end

local function timeToLevel(t)
    local player = g_game.getLocalPlayer()
    if not player or t.xpPerHour <= 0 then
        return '-', 0
    end
    local left = experienceForLevel(player:getLevel() + 1) - player:getExperience()
    return duration(left / t.xpPerHour * 3600), left
end

local STATUS = { idle = 'Waiting', tracking = 'Tracking', paused = 'Paused' }

-- Compact panel -----------------------------------------------------------------

local function setRow(id, label, value, color)
    local rows = window.contentsPanel.rows
    local row = rows:getChildById(id)
    if not row then
        row = g_ui.createWidget('HuntRow', rows)
        row:setId(id)
    end
    row.label:setText(tr(label))
    row.value:setText(value)
    row.value:setColor(color or '#e8e8e8')
end

-- The items worth most so far
local function topItems(map, supply, limit)
    local list = {}
    for key, count in pairs(map) do
        table.insert(list, { key = key, count = count, value = itemPrice(key, supply) * count })
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return a.count > b.count
    end)
    while limit and #list > limit do
        table.remove(list)
    end
    return list
end

local function updatePanel()
    if not window or not session then
        return
    end
    local t = totals()
    local level = timeToLevel(t)
    setRow('status', 'Status', tr(STATUS[session.state]), session.state == 'tracking' and '#70d070' or '#a8a8a8')
    setRow('duration', 'Duration', duration(t.seconds))
    setRow('xph', 'XP / h', short(t.xpPerHour))
    setRow('xp', 'XP total', short(t.xp))
    setRow('level', 'Next level', level)
    setRow('kills', 'Kills', t.kills .. ' (' .. t.killsPerHour .. '/h)')
    setRow('loot', 'Loot', short(t.loot) .. ' gp')
    setRow('supplies', 'Supplies', short(t.supplies) .. ' gp', t.supplies > 0 and '#e05050' or nil)
    setRow('profit', 'Profit', (t.profit >= 0 and '+' or '') .. short(t.profit) .. ' gp',
        t.profit >= 0 and '#70d070' or '#e05050')

    local buttons = window.contentsPanel.buttons
    -- three to a row, as wide as the panel lets them
    buttons:getLayout():setCellSize({ width = math.max(40, math.floor((buttons:getWidth() - 6) / 3)), height = 24 })
    buttons.pause:setText(session.state == 'paused' and tr('Resume') or tr('Pause'))
    buttons.pause:setEnabled(session.state ~= 'idle')

    local top = window.contentsPanel.topLoot
    top:destroyChildren()
    for _, entry in ipairs(topItems(session.onlyLooted and session.looted or session.dropped, false, 5)) do
        local row = g_ui.createWidget('HuntRow', top)
        row.label:setText(entry.count .. 'x ' .. itemName(entry.key))
        row.value:setText(short(entry.value))
        row.value:setColor('#e0b84c')
    end
    window.contentsPanel.topTitle:setVisible(#top:getChildren() > 0)
end

-- Report ------------------------------------------------------------------------

local showReport

local function closeReport()
    if report then
        report:destroy()
        report = nil
    end
end

local function itemIdOf(key)
    return tonumber(key:match('^(%d+)'))
end

-- A list of items: name, count and value; a tap opens the price row (and for
-- supplies the count), which stays open while its numbers change
local openKey
local function itemRows(list, map, supply)
    local function render()
        list:destroyChildren()
        for _, entry in ipairs(topItems(map, supply)) do
            local row = g_ui.createWidget('HuntReportRow', list)
            local id = itemIdOf(entry.key)
            if id then
                row.item:setItemId(id)
                if entry.key:find(':') then
                    row.item:setItemSubType(tonumber(entry.key:match(':(%d+)')))
                end
            end
            local each = itemPrice(entry.key, supply)
            row.name:setText(itemName(entry.key) .. (hasCustomPrice(entry.key) and ' *' or ''))
            row.count:setText(tostring(entry.count))
            row.value:setText(short(entry.value) .. ' (' .. short(each) .. ')')
            row.value:setColor(supply and '#e05050' or '#e0b84c')
            row.onClick = function()
                openKey = openKey ~= entry.key and entry.key or nil
                render()
            end
            if openKey == entry.key then
                local edit = g_ui.createWidget('HuntPriceRow', list)
                edit.price:setText(tostring(each))
                edit.set.onClick = function()
                    local value = tonumber(edit.price:getText())
                    if value and value >= 0 then
                        setCustomPrice(entry.key, math.floor(value))
                    end
                    updatePanel()
                    showReport(reportTab)
                end
                edit.default.onClick = function()
                    setCustomPrice(entry.key, nil)
                    openKey = nil
                    updatePanel()
                    showReport(reportTab)
                end
                -- supplies: the count can be corrected (what the tracker missed)
                if supply then
                    local counter = g_ui.createWidget('HuntCountRow', list)
                    counter.count:setText(tostring(entry.count))
                    local function change(by)
                        setSupplyCount(entry.key, entry.count + by)
                        updatePanel()
                        showReport(reportTab)
                    end
                    counter.minus.onClick = function() change(-1) end
                    counter.plus.onClick = function() change(1) end
                end
            end
        end
        if #list:getChildren() == 0 then
            g_ui.createWidget('OtHint', list):setText(tr('Nothing yet.'))
        end
    end
    render()
end

local function textRow(list, name, value, color)
    local row = g_ui.createWidget('HuntReportRow', list)
    row.item:setVisible(false)
    row.name:setMarginLeft(-22)
    row.name:setText(tr(name))
    row.count:setText(value)
    row.count:setColor(color or '#ffffff')
    row.value:setText('')
    return row
end

-- Past hunts (End hunt keeps them): date and time, profit, xp per hour; a tap
-- opens its details
local openHunt
local function historyRows(list, panel)
    local hunts = huntHistory()
    panel.summary:setText(#hunts == 0 and tr('End a hunt to keep it here.') or tr('%d hunts. Tap one for its details.', #hunts))
    for index, hunt in ipairs(hunts) do
        local hours = math.max(hunt.seconds or 0, 1) / 3600
        local row = textRow(list, os.date('%d %b %H:%M', hunt.started or hunt.ended or 0) .. '  ' .. duration(hunt.seconds or 0),
            (hunt.profit >= 0 and '+' or '') .. short(hunt.profit) .. ' gp', hunt.profit >= 0 and '#70d070' or '#e05050')
        row.value:setText(short((hunt.xp or 0) / hours) .. ' xp/h')
        row.value:setColor('#78b4ff')
        row.onClick = function()
            openHunt = openHunt ~= index and index or nil
            showReport('history')
        end
        if openHunt == index then
            textRow(list, '   ' .. tr('Experience'), short(hunt.xp or 0), '#78b4ff')
            textRow(list, '   ' .. tr('Kills'), tostring(hunt.kills or 0), '#ff8080')
            textRow(list, '   ' .. tr('Loot'), short(hunt.loot or 0) .. ' gp', '#e0b84c')
            textRow(list, '   ' .. tr('Supplies'), short(hunt.supplies or 0) .. ' gp', '#e05050')
            local monsters = {}
            for name, count in pairs(type(hunt.monsters) == 'table' and hunt.monsters or {}) do
                table.insert(monsters, { name = name, count = tonumber(count) or 0 })
            end
            table.sort(monsters, function(a, b) return a.count > b.count end)
            for _, monster in ipairs(monsters) do
                textRow(list, '   ' .. monster.name:gsub('^%l', string.upper), tostring(monster.count), '#a8a8a8')
            end
            local actions = g_ui.createWidget('HuntHistoryActions', list)
            local delete = g_ui.createWidget('OtButtonDanger', actions)
            delete:setWidth(110)
            delete:setText(tr('Delete'))
            delete.onClick = function()
                deleteHunt(hunt.key)
                openHunt = nil
                showReport('history')
            end
        end
    end
end

showReport = function(tab)
    reportTab = tab or reportTab
    if not session then
        return
    end
    if not report then
        report = g_ui.createWidget('HuntReport', rootWidget)
        report.onClick = closeReport
        report.onEscape = closeReport
        report.panel.close.onClick = closeReport
        for _, entry in ipairs({ { 'stats', 'Stats' }, { 'monsters', 'Monsters' }, { 'loot', 'Loot' }, { 'supplies', 'Supplies' }, { 'history', 'History' } }) do
            local button = g_ui.createWidget('OtTab', report.panel.tabs)
            button:setId(entry[1])
            button:setText(tr(entry[2]))
            button.onClick = function()
                showReport(entry[1])
            end
        end
        report.panel.onlyLooted.onCheckChange = function(widget, checked)
            session.onlyLooted = checked
            updatePanel()
            showReport('loot')
        end
    end
    local panel = report.panel
    panel:setSize({ width = math.min(520, rootWidget:getWidth() - 16), height = math.min(420, rootWidget:getHeight() - 16) })
    panel.tabs:getLayout():setCellSize({ width = math.floor((panel:getWidth() - 24 - 16) / 5), height = 36 })
    for _, button in ipairs(panel.tabs:getChildren()) do
        button:setChecked(button:getId() == reportTab)
    end
    local t = totals()
    panel.title:setText(tr('Hunt') .. ' - ' .. duration(t.seconds))
    panel.onlyLooted:setVisible(reportTab == 'loot')
    panel.onlyLootedText:setVisible(reportTab == 'loot')
    panel.onlyLooted:setChecked(session.onlyLooted or false)

    local list = panel.listFrame.list
    list:destroyChildren()
    if reportTab == 'stats' then
        local actions = g_ui.createWidget('HuntActionRow', list)
        local pause = g_ui.createWidget('OtButton', actions)
        pause:setWidth(110)
        pause:setText(session.state == 'paused' and tr('Resume') or tr('Pause'))
        pause:setEnabled(session.state ~= 'idle')
        pause.onClick = function()
            pauseSession()
            updatePanel()
            showReport('stats')
        end
        local finish = g_ui.createWidget('OtButtonPrimary', actions)
        finish:setWidth(120)
        finish:setText(tr('End hunt'))
        finish.onClick = function()
            endHunt()
            updatePanel()
            showReport('history')
        end
        local panelButton = g_ui.createWidget('OtButton', actions)
        panelButton:setWidth(120)
        panelButton:setText(window and window:isVisible() and tr('Hide panel') or tr('Show panel'))
        panelButton.onClick = function()
            toggle()
            showReport('stats')
        end
        local level, left = timeToLevel(t)
        panel.summary:setText(session.started and tr('Started %s', os.date('%H:%M', session.started)) or tr('Starts with your first kill.'))
        textRow(list, 'Experience', short(t.xp) .. '  (' .. short(t.xpPerHour) .. '/h)', '#78b4ff')
        textRow(list, 'Gold', short(t.gold) .. ' gp', '#e0b84c')
        textRow(list, 'Loot', short(t.loot) .. ' gp  (' .. short(t.lootPerHour) .. '/h)', '#e0b84c')
        textRow(list, 'Supplies', short(t.supplies) .. ' gp', '#e05050')
        textRow(list, 'Profit', (t.profit >= 0 and '+' or '') .. short(t.profit) .. ' gp', t.profit >= 0 and '#70d070' or '#e05050')
        textRow(list, 'Kills', t.kills .. '  (' .. t.killsPerHour .. '/h)', '#ff8080')
        textRow(list, 'Time to level', level .. (left > 0 and ('  (' .. short(left) .. ' xp)') or ''))
    elseif reportTab == 'monsters' then
        local monsters, species = {}, 0
        for name, count in pairs(session.kills) do
            table.insert(monsters, { name = name, count = count })
            species = species + 1
        end
        table.sort(monsters, function(a, b) return a.count > b.count end)
        panel.summary:setText(tr('%d kills, %d kinds', t.kills, species))
        for _, monster in ipairs(monsters) do
            local name = monster.name:gsub('^%l', string.upper)
            local row = textRow(list, name, tostring(monster.count), '#78b4ff')
            local loot = monsterLootValue(monster.name)
            if loot > 0 then
                row.value:setText(short(loot) .. ' (' .. short(loot / monster.count) .. ')')
                row.value:setColor('#e0b84c')
            end
        end
        if #monsters > 0 then
            g_ui.createWidget('OtHint', list):setText(tr('Kills, then loot: total (per kill), from the loot messages.'))
        end
    elseif reportTab == 'loot' then
        panel.summary:setText(tr('%s gp. Tap an item to set its price.', short(t.loot)))
        itemRows(list, session.onlyLooted and session.looted or session.dropped, false)
    elseif reportTab == 'supplies' then
        panel.summary:setText(tr('%s gp used. Tap an item to set its price or count.', short(t.supplies)))
        itemRows(list, session.supplies, true)
    else
        historyRows(list, panel)
    end
    report:raise()
end

function openReport()
    showReport(reportTab)
end

-- Module ------------------------------------------------------------------------

function onTrackerChange()
    updatePanel()
end

function toggle()
    if not window then
        return
    end
    if window:isVisible() then
        window:close()
    else
        window:open()
    end
end

function getWindow()
    return window
end

local function onGameStart()
    trackerGameStart()
    updatePanel()
    if updateEvent then
        removeEvent(updateEvent)
    end
    -- the clock and the per-hour numbers move on their own
    updateEvent = cycleEvent(function()
        if session and session.state == 'tracking' then
            updatePanel()
        end
    end, 1000)
end

local function onGameEnd()
    closeReport()
    if updateEvent then
        removeEvent(updateEvent)
        updateEvent = nil
    end
    trackerGameEnd()
end

function init()
    g_ui.importStyle('hunt_styles')
    window = g_ui.loadUI('hunt', modules.game_interface.getRightPanel())
    window:setup()
    local buttons = window.contentsPanel.buttons
    buttons.pause.onClick = function()
        pauseSession()
        updatePanel()
    end
    buttons.reset.onClick = function()
        resetSession()
        updatePanel()
    end
    buttons.report.onClick = openReport
    initTracker()
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    onGameEnd()
    terminateTracker()
    if window then
        window:destroy()
        window = nil
    end
end
