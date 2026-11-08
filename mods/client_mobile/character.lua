-- The hub's character sheet (ot-client#60): outfit, level and vocation,
-- premium, skills, blessings, frags and the skull, later screenshots
-- ("Moments", #25).
--
-- Level and skills come from the game. Vocation, blessings, frags and the
-- skull's time are not in the 7.92 protocol: the server sends them when asked
-- (extended opcode 106, "character", ot-server#50); the answer arrives through
-- client_tasks (onCharacterData).

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

local data -- the server's answer, nil until it comes
local header -- the page's first widget: the page is open while it is

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

local function row(list, style, name, value)
    local widget = g_ui.createWidget(style, list)
    widget.name:setText(name)
    widget.value:setText(value or '')
    return widget
end

local function skillRow(list, name, level, percent)
    local widget = row(list, 'CharacterSkillRow', name, tostring(level))
    -- (the row is laid out a moment later: size the line then)
    addEvent(function()
        if not widget:isDestroyed() then
            widget.fill:setWidth(math.floor(widget:getWidth() * math.max(0, math.min(100, percent or 0)) / 100))
        end
    end)
end

local function section(list, title)
    g_ui.createWidget('HubSection', list).text:setText(tr(title))
end

local function render()
    local player = g_game.getLocalPlayer()
    local list = hubPage(tr('Character'))
    if not list or not player then
        header = nil
        return
    end

    header = g_ui.createWidget('CharacterHeader', list)
    header.outfit:setOutfit(player:getOutfit())
    header.outfit:setDirection(Directions.South)
    header.name:setText(player:getName())
    local vocation = data and data.vocation or ''
    if vocation == 'None' then
        vocation = ''
    end
    -- (the fonts are not UTF-8: no middle dot)
    header.vocation:setText(tr('Level') .. ' ' .. player:getLevel() .. (vocation ~= '' and (', ' .. vocation) or ''))
    if player:isPremium() then
        local days = data and tonumber(data.premiumDays) or nil
        header.premium:setText(tr('Premium account') .. (days and days > 0 and days < 65535 and (', ' .. days .. ' ' .. tr('days left')) or ''))
        header.premium:setColor('#70d070')
    else
        header.premium:setText(tr('Free account'))
        header.premium:setColor('#a8a8a8')
    end
    header.outfitButton.onClick = function()
        closeHub()
        g_game.requestOutfit()
    end

    section(list, 'SKILLS')
    skillRow(list, tr('Experience level'), player:getLevel(), player:getLevelPercent())
    skillRow(list, tr('Magic level'), player:getMagicLevel(), player:getMagicLevelPercent())
    for _, skill in ipairs(SKILLS) do
        skillRow(list, tr(skill[1]), player:getSkillLevel(skill[2]), player:getSkillLevelPercent(skill[2]))
    end

    section(list, 'BLESSINGS')
    for i, name in ipairs(BLESSINGS) do
        local has = data and data.blessings and data.blessings[i] == true
        local widget = row(list, 'CharacterCheckRow', tr(name), data and (has and tr('Yes') or tr('No')) or '...')
        widget.dot:setOn(has)
        widget.name:setMarginLeft(24)
    end

    section(list, 'FRAGS')
    local frags = data and data.frags
    if frags then
        local red, ban = frags.red or {}, frags.ban or {}
        local function frag(label, count, redAt, banAt)
            local widget = row(list, 'CharacterRow', label,
                string.format('%d   (%s %s, %s %s)', count or 0, tr('red skull at'), tostring(redAt or '-'), tr('ban at'), tostring(banAt or '-')))
            if redAt and count and count >= redAt - 1 and count > 0 then
                widget.value:setColor('#e05050')
            end
        end
        frag(tr('Last 24 hours'), frags.day, red.day, ban.day)
        frag(tr('Last 7 days'), frags.week, red.week, ban.week)
        frag(tr('Last 30 days'), frags.month, red.month, ban.month)
        local skull = tonumber(data.skull) or 0
        local text = tr('None')
        if skull == SkullWhite then
            text = tr('White') .. (data.skullLeft and data.skullLeft > 0 and (', ' .. tr('ends in') .. ' ' .. duration(data.skullLeft)) or '')
        elseif skull == SkullRed then
            text = tr('Red') .. (data.skullLeft and data.skullLeft > 0 and (', ' .. tr('ends in') .. ' ' .. duration(data.skullLeft)) or '')
        elseif skull ~= 0 then
            text = tr('Yes')
        end
        local skullRow = row(list, 'CharacterRow', tr('Skull'), text)
        if skull == SkullRed then
            skullRow.value:setColor('#e05050')
        end
    else
        g_ui.createWidget('OtHint', list):setText(tr('Loading...'))
    end

    section(list, 'SCREENSHOTS')
    g_ui.createWidget('OtHint', list):setText(tr('Coming later: pictures of your level-ups, deaths and quest rewards.'))
end

local function isOpen()
    return header ~= nil and not header:isDestroyed()
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
