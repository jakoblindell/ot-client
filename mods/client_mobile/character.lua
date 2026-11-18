-- The hub's character sheet (ot-client#60): "Name - Level N", then tabs:
-- Skills, Frags, Blessings, Outfit, Screenshots (later: Moments, #25).
--
-- Level, experience, soul, magic level, speed and the skills come from the
-- game. Vocation, food time, blessings, frags, the skull's time and what a
-- death would cost are not in the 7.92 protocol: the server sends them when
-- asked (extended opcode 106, "character", ot-server#50); the answer arrives
-- through client_tasks (onCharacterData).

local OPCODE = 106

local BLESSINGS = { 'Spiritual Shielding', 'Embrace of Tibia', 'Fire of the Suns', 'Wisdom of Solitude', 'Spark of the Phoenix' }

local SKILLS = {
    { 'Fist fighting', Skill.Fist },
    { 'Club fighting', Skill.Club },
    { 'Sword fighting', Skill.Sword },
    { 'Axe fighting', Skill.Axe },
    { 'Distance fighting', Skill.Distance },
    { 'Shielding', Skill.Shielding },
    { 'Fishing', Skill.Fishing },
}

local TABS = {
    { id = 'skills', text = 'Skills' },
    { id = 'frags', text = 'Frags' },
    { id = 'blessings', text = 'Blessings' },
    { id = 'outfit', text = 'Outfit' },
    { id = 'screenshots', text = 'Screenshots' },
}

local MUTED = '#a8a8a8'
local GOOD = '#70d070'
local BAD = '#e05050'
local SOUL = '#78b4ff'
local WARN = '#e8a050'

local data -- the server's answer, nil until it comes
local currentTab = 'skills'
local title -- the page's first widget: the page is open while it is

-- 64611933 -> "64,611,933"
local function thousands(value)
    local text = tostring(math.floor(value))
    local sign, digits = text:match('^(-?)(%d+)$')
    if not digits then
        return text
    end
    return sign .. digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

-- "1 day 3 h", "12 min"
local function duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.ceil(seconds % 3600 / 60)
    if days > 0 then
        return days .. (days == 1 and ' day ' or ' days ') .. hours .. ' h'
    elseif hours > 0 then
        return hours .. ' h ' .. minutes .. ' min'
    end
    return math.max(1, minutes) .. ' min'
end

-- A row: the name, and the value as {text, colour} parts
local function row(list, name, ...)
    local widget = g_ui.createWidget('CharacterRow', list)
    widget.name:setText(name)
    -- "{text, colour}" for each part (the colour after the last comma)
    local parts = {}
    for _, part in ipairs({ ... }) do
        table.insert(parts, '{' .. part[1] .. ', ' .. (part[2] or '#ffffff') .. '}')
    end
    widget.value:setColoredText(table.concat(parts))
    return widget
end

local function hint(list, text)
    local widget = g_ui.createWidget('OtHint', list)
    widget:setText(text)
    widget:setMarginTop(8)
    return widget
end

local function loading(list)
    hint(list, tr('Loading...'))
end

-- Tabs ----------------------------------------------------------------------------

local function renderSkills(list, player)
    local level = player:getLevel()
    row(list, tr('Level'), { tostring(level) },
        { string.format('   %.1f%% %s %d', player:getLevelPercent(), tr('towards'), level + 1), MUTED })
    local experience = player:getExperience()
    local nextLevel = math.floor((50 * level * level * level - 150 * level * level + 400 * level) / 3)
    row(list, tr('Experience'), { thousands(experience) },
        { '   ' .. thousands(math.max(0, nextLevel - experience)) .. ' ' .. tr('to go'), MUTED })
    row(list, tr('Soul points'), { tostring(player:getSoul()), SOUL })
    row(list, tr('Magic level'), { tostring(player:getMagicLevel()) },
        { string.format('   %d%%', player:getMagicLevelPercent()), MUTED })
    if data and data.food then
        local food = tonumber(data.food) or 0
        row(list, tr('Food'), { string.format('%d:%02d', math.floor(food / 60), food % 60), food > 0 and GOOD or BAD })
    end
    row(list, tr('Speed'), { tostring(player:getSpeed()) })
    for _, skill in ipairs(SKILLS) do
        row(list, tr(skill[1]), { tostring(player:getSkillLevel(skill[2])) },
            { string.format('   %d%%', player:getSkillLevelPercent(skill[2])), MUTED })
    end
end

local function renderFrags(list)
    local frags = data and data.frags
    if not frags then
        return loading(list)
    end
    local red = frags.red or {}
    local function frag(label, count, limit)
        count = tonumber(count) or 0
        -- red when one more would mean a red skull
        local color = limit and count >= limit - 1 and count > 0 and BAD or '#ffffff'
        row(list, label, { count .. ' / ' .. tostring(limit or '-'), color })
    end
    frag(tr('Daily'), frags.day, red.day)
    frag(tr('Weekly'), frags.week, red.week)
    frag(tr('Monthly'), frags.month, red.month)
    local skull = tonumber(data.skull) or 0
    local left = tonumber(data.skullLeft) or 0
    local ends = left > 0 and ('   ' .. tr('ends in') .. ' ' .. duration(left)) or ''
    if skull == SkullWhite then
        row(list, tr('Skull'), { tr('White') }, { ends, MUTED })
    elseif skull == SkullRed then
        row(list, tr('Skull'), { tr('Red'), BAD }, { ends, MUTED })
    else
        row(list, tr('Skull'), { tr('None'), GOOD })
    end
    local ban = frags.ban or {}
    hint(list, tr('A red skull comes at the numbers above; a banishment at %s, %s and %s.',
        tostring(ban.day or '-'), tostring(ban.week or '-'), tostring(ban.month or '-')))
end

local function renderBlessings(list)
    if not data or not data.blessings then
        return loading(list)
    end
    local count = 0
    for i = 1, #BLESSINGS do
        if data.blessings[i] == true then
            count = count + 1
        end
    end
    row(list, tr('Pilgrimage'), { count .. ' / ' .. #BLESSINGS, count == #BLESSINGS and GOOD or (count > 0 and WARN or MUTED) })
    for i, name in ipairs(BLESSINGS) do
        local widget = g_ui.createWidget('CharacterBlessing', list)
        widget:setText('+  ' .. tr(name))
        widget:setOn(data.blessings[i] == true)
    end
    local death = data.death
    if death then
        local items
        if death.redSkull then
            items = { tr('all items drop (red skull)'), BAD }
        elseif death.amulet then
            items = { tr('items protected (amulet of loss)'), GOOD }
        else
            items = { tr('%d%% chance per item', tonumber(death.itemChance) or 10), WARN }
        end
        local deathRow = row(list, tr('On death'), { string.format('%.1f%% %s', tonumber(death.loss) or 0, tr('experience')), WARN },
            { '   ', MUTED }, items)
        deathRow:setMarginTop(6)
    end
    if count > 0 then
        hint(list, tr('Your next death takes the blessings you have.'))
    else
        hint(list, tr('Each blessing lowers what a death costs. Ask the monks in the temples about the pilgrimage.'))
    end
end

local function renderOutfit(list, player)
    local outfit = g_ui.createWidget('CharacterOutfit', list)
    outfit.outfit:setOutfit(player:getOutfit())
    outfit.outfit:setDirection(Directions.South)
    outfit.change.onClick = function()
        closeHub()
        g_game.requestOutfit()
    end
end

-- Moments (client_moments, ot-client#25): what to capture and the pictures
local render
local function renderScreenshots(list)
    local moments = modules.client_moments
    if moments and moments.renderTab then
        moments.renderTab(list, function() render() end)
    else
        hint(list, tr('Screenshots are not available.'))
    end
end

-- The page ------------------------------------------------------------------------

render = function()
    local player = g_game.getLocalPlayer()
    local list, panel = hubPage(tr('Character'))
    if not list or not player then
        title = nil
        return
    end

    -- the tabs, in the hub's tab row
    panel.tabs:setVisible(true)
    panel.tabs:setHeight(36)
    local width = math.min(160, math.floor((panel.tabs:getWidth() - 4 * (#TABS - 1)) / #TABS))
    panel.tabs:getLayout():setCellSize({ width = width, height = 36 })
    for _, tab in ipairs(TABS) do
        local button = g_ui.createWidget('OtTab', panel.tabs)
        button:setText(tr(tab.text))
        button:setChecked(tab.id == currentTab)
        button.onClick = function()
            currentTab = tab.id
            render()
        end
    end

    -- (the fonts are not UTF-8: a plain hyphen, no dash)
    title = g_ui.createWidget('CharacterTitle', list)
    local vocation = data and data.vocation or ''
    title:setText(player:getName() .. ' - ' .. tr('Level') .. ' ' .. player:getLevel()
        .. ((vocation ~= '' and vocation ~= 'None') and (', ' .. vocation) or ''))

    if currentTab == 'skills' then
        renderSkills(list, player)
    elseif currentTab == 'frags' then
        renderFrags(list)
    elseif currentTab == 'blessings' then
        renderBlessings(list)
    elseif currentTab == 'outfit' then
        renderOutfit(list, player)
    else
        renderScreenshots(list)
    end
end

local function isOpen()
    return title ~= nil and not title:isDestroyed()
end

-- The server's answer (client_tasks passes it on)
function onCharacterData(answer)
    data = answer
    if isOpen() then
        render()
    end
end

-- From the hub's Character button
function showCharacter()
    render()
    local protocol = g_game.getProtocolGame()
    if protocol and g_game.isOnline() then
        protocol:sendExtendedOpcode(OPCODE, 'character')
    end
end
