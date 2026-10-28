-- Typing suggestions (ot-client#20): on a touch screen a row of words just
-- above the chat line, so phones type less and autocorrect less.
--
-- With nothing typed: the words the NPC you talk to understands (from the
-- NPC dialog, client_npcdialog), or what you said last. While typing: the
-- spells that start with it, then names (VIP list, people who spoke near
-- you) and words you used before that start with the word being typed.
-- Gold chips send at once; plain ones complete the word.
--
-- Settings > Layout: on or off, and Clear learned words (hub.lua).
-- Commands (/ and !) have their own list (client_commands).

local ENABLED_SETTING = 'typingSuggestions'
local LEARNED_SETTING = 'typingLearnedWords'
local MAX_LEARNED = 400
local MAX_RECENT = 6
local MAX_SPEAKERS = 30

-- The client's vocation ids (player:getVocation) -> the server's, which the
-- 7.72 spell list uses (client_classic, client_vocation)
local SERVER_VOCATIONS = { [3] = 1, [4] = 2, [2] = 3, [1] = 4, [13] = 5, [14] = 6, [12] = 7, [11] = 8 }
-- Said to players and channels (names are learned from these)
local PLAYER_MODES = {}

local bar, textEdit, placeEvent
local learned = {} -- word -> times used
local recent = {} -- what you said, newest first
local speakers = {} -- names, newest first
local shown -- the suggestions on the bar now (to skip rebuilding)

function isEnabled()
    return g_settings.getString(ENABLED_SETTING) ~= 'false'
end

function setEnabled(enabled)
    g_settings.set(ENABLED_SETTING, enabled and 'true' or 'false')
    g_settings.save()
    update()
end

-- Learned words ----------------------------------------------------------------

local function loadLearned()
    local ok, words = pcall(json.decode, g_settings.getString(LEARNED_SETTING))
    learned = ok and type(words) == 'table' and words or {}
end

local function saveLearned()
    -- the most used ones only
    local list = {}
    for word, count in pairs(learned) do
        table.insert(list, { word, count })
    end
    if #list > MAX_LEARNED then
        table.sort(list, function(a, b) return a[2] > b[2] end)
        learned = {}
        for i = 1, MAX_LEARNED do
            learned[list[i][1]] = list[i][2]
        end
    end
    g_settings.set(LEARNED_SETTING, json.encode(learned))
    g_settings.save()
end

function clearLearnedWords()
    learned = {}
    recent = {}
    g_settings.set(LEARNED_SETTING, '{}')
    g_settings.save()
    update()
end

local function pushFront(list, value, max)
    for i, existing in ipairs(list) do
        if existing:lower() == value:lower() then
            table.remove(list, i)
            break
        end
    end
    table.insert(list, 1, value)
    while #list > max do
        table.remove(list)
    end
end

-- Every message the player sends (a console filter; never blocks it)
local function onSend(message)
    if message:find('^[/!]') then
        return false
    end
    pushFront(recent, message, MAX_RECENT)
    for word in message:gmatch('[%a\'%-]+') do
        if #word >= 3 then
            word = word:lower()
            learned[word] = (learned[word] or 0) + 1
        end
    end
    saveLearned()
    return false
end

local function onTalk(name, level, mode, message)
    local player = g_game.getLocalPlayer()
    if PLAYER_MODES[mode] and name and name ~= '' and not (player and player:getName() == name) then
        pushFront(speakers, name, MAX_SPEAKERS)
    end
end

-- Suggestions --------------------------------------------------------------------

local function spellWords(prefix)
    local player = g_game.getLocalPlayer()
    local vocation = player and SERVER_VOCATIONS[player:getVocation()]
    local list = {}
    for _, spell in pairs(SpellInfo and SpellInfo.Default or {}) do
        local words = spell.words and spell.words:lower()
        if words and words:sub(1, #prefix) == prefix and words ~= prefix and
            (not vocation or table.contains(spell.vocations or {}, vocation)) then
            table.insert(list, spell.words)
        end
    end
    table.sort(list, function(a, b) return #a < #b or (#a == #b and a < b) end)
    return list
end

local function names()
    local list = {}
    for _, vip in pairs(g_game.getVips and g_game.getVips() or {}) do
        if type(vip[1]) == 'string' then
            table.insert(list, vip[1])
        end
    end
    for _, name in ipairs(speakers) do
        table.insert(list, name)
    end
    return list
end

local function learnedWords(prefix)
    local list = {}
    for word, count in pairs(learned) do
        if word:sub(1, #prefix) == prefix and word ~= prefix then
            table.insert(list, { word, count })
        end
    end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local words = {}
    for _, entry in ipairs(list) do
        table.insert(words, entry[1])
    end
    return words
end

-- { text = 'exura gran', send = true } or { text = 'Gandalf', word = true }
local function suggestions(text)
    local list, seen = {}, {}
    local function add(entry)
        local key = entry.text:lower()
        if not seen[key] then
            seen[key] = true
            table.insert(list, entry)
        end
    end
    local npcWords = modules.client_npcdialog and modules.client_npcdialog.getWords and
        modules.client_npcdialog.getWords()

    if text:match('^%s*$') then
        for _, word in ipairs(npcWords or recent) do
            add({ text = word, send = true })
        end
        return list
    end

    local lower = text:lower()
    local last = lower:match('([%a\'%-]+)$')
    for _, words in ipairs(spellWords(lower)) do
        add({ text = words, send = true })
    end
    if last then
        for _, word in ipairs(npcWords or {}) do
            if word:lower():sub(1, #last) == last and word:lower() ~= last and lower == last then
                add({ text = word, send = true })
            end
        end
        for _, name in ipairs(names()) do
            if name:lower():sub(1, #last) == last and name:lower() ~= last then
                add({ text = name, word = true })
            end
        end
        for _, word in ipairs(learnedWords(last)) do
            add({ text = word, word = true })
        end
    end
    return list
end

local function choose(entry)
    if not textEdit then
        return
    end
    if entry.send then
        textEdit:setText(entry.text)
        modules.game_console.sendCurrentMessage()
    else
        -- the word being typed becomes the suggestion, then a space
        local text = textEdit:getText()
        local stem = text:gsub('[%a\'%-]+$', '')
        textEdit:setText(stem .. entry.text .. ' ')
        textEdit:setCursorPos(-1)
    end
    textEdit:focus()
    update()
end

local function place()
    local pos = textEdit:getPosition()
    bar:setWidth(math.max(300, textEdit:getWidth()))
    bar:setPosition({ x = pos.x, y = math.max(0, pos.y - bar:getHeight() - 4) })
    bar:raise()
end

local function render(list)
    bar:destroyChildren()
    local room = math.max(300, textEdit:getWidth())
    local used = 0
    for _, entry in ipairs(list) do
        local chip = g_ui.createWidget('TypingChip', bar)
        chip:setText(entry.text)
        chip:setOn(entry.send or false)
        local width = math.max(48, chip:getTextSize().width + 24)
        chip:setWidth(width)
        used = used + width + chip:getMarginRight()
        if used > room then
            -- what does not fit is left out
            chip:destroy()
            break
        end
        chip.onClick = function()
            choose(entry)
        end
    end
end

-- The chat's messages move up while the bar is shown, so it covers none
local function makeRoom(room)
    local parent = textEdit and textEdit:getParent()
    for _, id in ipairs({ 'consoleContentPanel', 'readOnlyPanel' }) do
        local panel = parent and parent:getChildById(id)
        if panel and panel:getMarginBottom() ~= 4 + room then
            panel:setMarginBottom(4 + room)
        end
    end
end

function update()
    if not bar then
        return
    end
    if not isEnabled() or not textEdit or not textEdit:isVisible() or not g_game.isOnline() or
        textEdit:getText():find('^[/!]') then
        bar:hide()
        makeRoom(0)
        shown = nil
        return
    end
    local list = suggestions(textEdit:getText())
    local key = {}
    for _, entry in ipairs(list) do
        table.insert(key, (entry.send and '!' or '') .. entry.text)
    end
    key = table.concat(key, '\n')
    if key ~= shown then
        shown = key
        render(list)
    end
    bar:setVisible(#bar:getChildren() > 0)
    if bar:isVisible() then
        place()
    end
    makeRoom(bar:isVisible() and bar:getHeight() + 4 or 0)
end

local function onTextChange()
    update()
end

local function attach()
    local console = modules.game_console
    textEdit = console and console.getConsole and console.getConsole()
    if not textEdit or textEdit.typingAttached then
        return
    end
    textEdit.typingAttached = true
    connect(textEdit, { onTextChange = onTextChange })
end

local function onGameStart()
    attach()
    -- the chat opens, closes and moves with the layout
    if placeEvent then
        removeEvent(placeEvent)
    end
    placeEvent = cycleEvent(update, 300)
end

local function onGameEnd()
    if placeEvent then
        removeEvent(placeEvent)
        placeEvent = nil
    end
    speakers = {}
    if bar then
        bar:hide()
    end
    makeRoom(0)
    shown = nil
end

function init()
    if not g_platform.isMobile() then
        return
    end
    for _, mode in ipairs({ 'Say', 'Whisper', 'Yell', 'PrivateFrom', 'Channel', 'ChannelHighlight' }) do
        if MessageModes[mode] then
            PLAYER_MODES[MessageModes[mode]] = true
        end
    end
    g_ui.importStyle('typing')
    bar = g_ui.createWidget('TypingBar', rootWidget)
    bar:hide()
    loadLearned()
    modules.game_console.addFilter(onSend)
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onTalk = onTalk })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    if not bar then
        return
    end
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onTalk = onTalk })
    modules.game_console.removeFilter(onSend)
    onGameEnd()
    if textEdit and textEdit.typingAttached then
        disconnect(textEdit, { onTextChange = onTextChange })
        textEdit.typingAttached = nil
    end
    bar:destroy()
    bar = nil
end
