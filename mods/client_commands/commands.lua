-- Chat command suggestions (ot-client#24). At login the server sends the
-- commands this character may use (extended opcode 104, JSON: words,
-- parameters, what it does; data/lib/core/commands.lua on the server).
-- Typing / or ! in the chat shows the matching ones above the chat line;
-- once a command is typed, its row stays with the parameter being typed
-- shown white. Tab or a tap completes the chosen one, Up/Down choose,
-- Escape closes. The server still checks every command when it runs.

local COMMANDS_OPCODE = 104
local MAX_ROWS = 6
local ROW_HEIGHT = 46

local commands = {}
local list
local textEdit
local matches = {}
local selected = 1
local dismissedText -- Escape hides the list until the text changes

local function hide()
    if list then
        list:hide()
    end
    matches = {}
end

-- "<x>  <y>  <z>" with the one being typed (index) white (no commas: they
-- separate colours in coloured text)
local function paramsText(command, index)
    if #command.params == 0 then
        return ''
    end
    local parts = {}
    for i, param in ipairs(command.params) do
        local color = (i == index) and '#ffffff' or '#a8a8a8'
        table.insert(parts, '{<' .. param:gsub(',', ';') .. '>' .. (i < #command.params and '  ' or '') .. ', ' .. color .. '}')
    end
    return table.concat(parts)
end

local function place()
    local rows = math.min(MAX_ROWS, #matches)
    list:setHeight(rows * ROW_HEIGHT + 18 + list:getPaddingTop() + list:getPaddingBottom())
    list:setWidth(math.min(460, math.max(300, textEdit:getWidth())))
    local pos = textEdit:getPosition()
    list:setPosition({ x = pos.x, y = math.max(0, pos.y - list:getHeight() - 4) })
    list:raise()
end

local complete

local function render(currentParam)
    local rows = list:getChildById('rows')
    rows:destroyChildren()
    for i, command in ipairs(matches) do
        local row = g_ui.createWidget('CommandRow', rows)
        row:getChildById('words'):setText(command.words)
        local params = row:getChildById('params')
        if #command.params > 0 then
            params:setColoredText(paramsText(command, currentParam))
        else
            params:setText('')
        end
        row:getChildById('text'):setText(command.text)
        row:setOn(i == selected and currentParam == nil and #matches > 1)
        row.onClick = function()
            selected = i
            complete()
        end
    end
    place()
    list:show()
    -- the chosen row in view
    local scroll = list:getChildById('rowsScroll')
    local top = (selected - 1) * ROW_HEIGHT
    if top < scroll:getValue() then
        scroll:setValue(top)
    elseif top + ROW_HEIGHT > scroll:getValue() + MAX_ROWS * ROW_HEIGHT then
        scroll:setValue(top + ROW_HEIGHT - MAX_ROWS * ROW_HEIGHT)
    end
end

local function update(text)
    if not textEdit or #commands == 0 then
        return
    end
    if text ~= dismissedText then
        dismissedText = nil
    end
    local first = text:sub(1, 1)
    if dismissedText or (first ~= '/' and first ~= '!') then
        hide()
        return
    end
    local typed, rest = text:match('^(%S+)(.*)$')
    typed = typed or text
    local lower = typed:lower()

    if rest and rest ~= '' then
        -- a command and its parameters: show its row, the current one white
        for _, command in ipairs(commands) do
            if command.words:lower() == lower then
                matches = { command }
                selected = 1
                local _, commas = rest:gsub(',', '')
                render(math.min(#command.params, commas + 1))
                return
            end
        end
        hide()
        return
    end

    -- still typing the command: every one that starts with it
    local previous = matches[selected]
    matches = {}
    for _, command in ipairs(commands) do
        if command.words:lower():sub(1, #lower) == lower then
            table.insert(matches, command)
        end
    end
    if #matches == 0 then
        hide()
        return
    end
    selected = 1
    for i, command in ipairs(matches) do
        if command == previous then
            selected = i
        end
    end
    render(nil)
end

complete = function()
    local command = matches[selected]
    if not command or not textEdit then
        return
    end
    local text = command.words .. (#command.params > 0 and ' ' or '')
    textEdit:setText(text)
    textEdit:setCursorPos(-1)
    textEdit:focus()
    update(text)
end

local function onKey(key)
    return function()
        if not list or not list:isVisible() then
            return false
        end
        if key == 'Escape' then
            dismissedText = textEdit:getText()
            hide()
            return true
        end
        if key == 'Tab' then
            local command = matches[selected]
            -- a command already typed out: Tab is the console's again
            if #matches == 1 and textEdit:getText():lower():sub(1, #command.words) == command.words:lower()
                and textEdit:getText():find(' ') then
                return false
            end
            complete()
            return true
        end
        if #matches < 2 then
            return false
        end
        if key == 'Up' then
            selected = selected > 1 and selected - 1 or #matches
        else
            selected = selected < #matches and selected + 1 or 1
        end
        render(nil)
        return true
    end
end

-- JSON, joined from parts when the server splits a long one (ot-server#66)
local function onCommands(protocol, opcode, data)
    if type(data) ~= 'table' or type(data.commands) ~= 'table' then
        return
    end
    commands = {}
    for _, command in ipairs(data.commands) do
        if type(command.words) == 'string' then
            table.insert(commands, {
                words = command.words,
                params = type(command.params) == 'table' and command.params or {},
                text = command.text or '',
            })
        end
    end
end

local function onTextChange(widget, text)
    update(text)
end

local function attach()
    local console = modules.game_console
    textEdit = console and console.getConsole and console.getConsole()
    if not textEdit or textEdit.commandsAttached then
        return
    end
    textEdit.commandsAttached = true
    connect(textEdit, { onTextChange = onTextChange })
    for _, key in ipairs({ 'Tab', 'Up', 'Down', 'Escape' }) do
        g_keyboard.bindKeyPress(key, onKey(key), textEdit)
    end
end

local function onGameEnd()
    commands = {}
    hide()
end

function init()
    g_ui.importStyle('commands')
    list = g_ui.createWidget('CommandList', rootWidget)
    list:hide()
    ProtocolGame.registerExtendedJSONOpcode(COMMANDS_OPCODE, onCommands)
    connect(g_game, { onGameStart = attach, onGameEnd = onGameEnd })
    attach()
end

function terminate()
    ProtocolGame.unregisterExtendedJSONOpcode(COMMANDS_OPCODE)
    disconnect(g_game, { onGameStart = attach, onGameEnd = onGameEnd })
    if textEdit and textEdit.commandsAttached then
        disconnect(textEdit, { onTextChange = onTextChange })
        for _, key in ipairs({ 'Tab', 'Up', 'Down', 'Escape' }) do
            g_keyboard.unbindKeyPress(key, nil, textEdit)
        end
        textEdit.commandsAttached = nil
    end
    if list then
        list:destroy()
        list = nil
    end
end
