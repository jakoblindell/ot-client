-- Tap-to-talk NPC dialog. The server (extended opcode 103, JSON) describes
-- the NPC the player talks to after each answer: what it said, the keywords
-- in it, whether it asked a yes/no question, and its shop and travel offers
-- as this player gets them. Buttons say the words for the player (the NPC's
-- own rules do the trading); after a shop or travel choice the NPC's
-- "Do you want...?" is answered "yes" automatically. Typing still works.

local NPC_DIALOG_OPCODE = 103
local TEXT_COLOR = '#e8e8e8'
local KEYWORD_COLOR = '#e0b84c' -- $ot-gold
local AUTO_YES_TIMEOUT = 4000
local AFFORD_COLOR = '#70d070'
local SHORT_COLOR = '#e05050'
-- Buy without asking when the goods weigh more than the free capacity
local SKIP_CAPACITY_SETTING = 'npcDialogSkipCapacityCheck'

local window
local dialog -- the last message from the server
local view = 'talk' -- 'talk', 'trade' or 'travel'
local tradeTab = 'buy'
local selected -- the chosen offer (shop or travel)
local autoYesUntil = 0
local askingCapacity = false -- Confirm asked whether to buy what cannot be carried

local function say(text)
    if g_game.isOnline() then
        g_game.talk(text)
    end
end

local function shortGold(value)
    if value >= 10000 and value % 1000 == 0 then
        return (value / 1000) .. 'k'
    end
    return tostring(value)
end

-- "{text, #color}" segments with the keywords in gold
local function coloredAnswer(text, keywords)
    text = text:gsub('[{}]', '')
    local lower = text:lower()
    local marks = {}
    for _, keyword in ipairs(keywords) do
        -- the first time it stands as a whole word
        local from, to = 0, 0
        repeat
            from, to = lower:find(keyword:lower(), to + 1, true)
        until not from or ((from == 1 or not lower:sub(from - 1, from - 1):match('%a')) and not lower:sub(to + 1, to + 1):match('%a'))
        if from then
            table.insert(marks, { from = from, to = to })
        end
    end
    table.sort(marks, function(a, b) return a.from < b.from end)
    local out, at = '', 1
    for _, mark in ipairs(marks) do
        if mark.from >= at then
            if mark.from > at then
                out = out .. '{' .. text:sub(at, mark.from - 1) .. ', ' .. TEXT_COLOR .. '}'
            end
            out = out .. '{' .. text:sub(mark.from, mark.to) .. ', ' .. KEYWORD_COLOR .. '}'
            at = mark.to + 1
        end
    end
    if at <= #text then
        out = out .. '{' .. text:sub(at) .. ', ' .. TEXT_COLOR .. '}'
    end
    return out
end

local function fitWindow()
    addEvent(function()
        if window then
            local content = window:getChildById('content')
            -- children may have changed size since the last layout pass
            window:recursiveGetChildById('trade'):getLayout():update()
            content:getLayout():update()
            window:setHeight(content:getHeight() + window:getPaddingTop() + window:getPaddingBottom() + 4)
        end
    end)
end

local function addButton(parent, text, onClick, on)
    local button = g_ui.createWidget('NpcDialogButton', parent)
    button:setText(text)
    button:setOn(on == true)
    button.onClick = onClick
    return button
end

local render

local function setView(name)
    view = name
    selected = nil
    askingCapacity = false
    render()
end

local function offerAmount()
    local chosen = window:recursiveGetChildById('chosen')
    local scroll = chosen:getChildById('amount')
    return scroll:isVisible() and scroll:getValue() or 1
end

-- Weight of the chosen amount (oz) and the player's free capacity, when it
-- does not fit
local function overweight()
    local player = g_game.getLocalPlayer()
    if view ~= 'trade' or tradeTab ~= 'buy' or not selected or not player or not selected.weight or selected.weight <= 0 then
        return nil
    end
    local weight = selected.weight * offerAmount() / 100
    local free = player:getFreeCapacity()
    if weight > free then
        return weight, free
    end
    return nil
end

local function updateChosen()
    local chosen = window:recursiveGetChildById('chosen')
    chosen:setVisible(selected ~= nil and view == 'trade')
    if not selected or view ~= 'trade' then
        return
    end
    chosen:getChildById('item'):setItemId(selected.item)
    chosen:getChildById('name'):setText(selected.name)
    local weight = selected.weight and selected.weight > 0 and string.format(', %.2f oz', selected.weight / 100) or ''
    chosen:getChildById('each'):setText(string.format('%d gold each%s', selected.price, weight))
    local amount = offerAmount()
    local cost = selected.price * amount
    local total = chosen:getChildById('total')
    if chosen:getChildById('amount'):isVisible() then
        total:setText(string.format('%d for %d gold', amount, cost))
    else
        total:setText(string.format('%s: %d gold', tr('Total'), cost))
    end
    -- Green when the gold the player carries pays for it, red when not
    if tradeTab == 'buy' and dialog.money then
        total:setColor(cost <= dialog.money and AFFORD_COLOR or SHORT_COLOR)
    else
        total:setColor(KEYWORD_COLOR)
    end

    -- What does not fit the player's capacity lands at their feet
    local warningLabel = chosen:getChildById('warning')
    local skip = chosen:getChildById('skipCapacity')
    local weight, free = overweight()
    if weight then
        local text = string.format('Weighs %.2f oz, you can carry %d oz. The rest will be put at your feet.', weight, free)
        if askingCapacity then
            text = 'Not enough capacity: what you cannot carry will land under you. Buy anyway?'
        end
        warningLabel:setText(text)
        skip:setChecked(g_settings.getBoolean(SKIP_CAPACITY_SETTING))
    else
        askingCapacity = false
    end
    warningLabel:setVisible(weight ~= nil)
    skip:setVisible(weight ~= nil)
    chosen:setHeight(weight and 112 or 58)

    local confirmButton = window:recursiveGetChildById('confirm')
    confirmButton:setText(askingCapacity and tr('Proceed') or tr('Confirm'))
    window:recursiveGetChildById('back'):setText(askingCapacity and tr('Cancel') or tr('Back'))
    fitWindow()
end

local function confirm()
    if not selected then
        return
    end
    -- Too heavy: ask once before buying (unless the player said not to)
    if not askingCapacity and overweight() and not g_settings.getBoolean(SKIP_CAPACITY_SETTING) then
        askingCapacity = true
        updateChosen()
        return
    end
    askingCapacity = false
    local words = selected.words
    if view == 'trade' then
        local amount = offerAmount()
        if amount > 1 then
            -- the NPC's amount rules: "5 torch", "sell 5 rope"
            if tradeTab == 'sell' then
                words = 'sell ' .. amount .. ' ' .. words:gsub('^sell ', '')
            else
                words = amount .. ' ' .. words
            end
        end
    end
    autoYesUntil = g_clock.millis() + AUTO_YES_TIMEOUT
    say(words)
end

local function renderTrade()
    local trade = window:recursiveGetChildById('trade')
    local offers = trade:getChildById('offers')
    offers:destroyChildren()
    local list = (dialog[tradeTab] or {})
    trade:recursiveGetChildById('buyTab'):setOn(tradeTab == 'buy')
    trade:recursiveGetChildById('buyTab'):setEnabled(#(dialog.buy or {}) > 0)
    trade:recursiveGetChildById('sellTab'):setOn(tradeTab == 'sell')
    trade:recursiveGetChildById('sellTab'):setEnabled(#(dialog.sell or {}) > 0)
    trade:getChildById('money'):setText(dialog.money and string.format('%s: %d gold', tr('You carry'), dialog.money) or '')
    trade:getChildById('money'):setVisible(dialog.money ~= nil)
    for _, offer in ipairs(list) do
        local cell = g_ui.createWidget('NpcOfferCell', offers)
        cell:getChildById('item'):setItemId(offer.item)
        cell:getChildById('price'):setText(shortGold(offer.price))
        cell:setTooltip(string.format('%s: %d gold', offer.name, offer.price))
        cell:setOn(selected == offer)
        cell.onClick = function()
            askingCapacity = false
            selected = offer
            local scroll = window:recursiveGetChildById('chosen'):getChildById('amount')
            scroll:setVisible(offer.amounts == true)
            scroll:setValue(1)
            render()
        end
    end
    updateChosen()
end

local function renderTravel()
    local travel = window:recursiveGetChildById('travel')
    travel:destroyChildren()
    for _, offer in ipairs(dialog.travel or {}) do
        local row = g_ui.createWidget('NpcTravelRow', travel)
        row:getChildById('name'):setText(offer.name)
        row:getChildById('price'):setText(string.format('%d gold', offer.price))
        row:setOn(selected == offer)
        row.onClick = function()
            selected = offer
            render()
        end
    end
end

render = function()
    if not window or not dialog then
        return
    end
    window:setText(dialog.npc)
    local answer = window:recursiveGetChildById('answer')
    answer:setColoredText(coloredAnswer(dialog.text or '', dialog.keywords or {}))

    local buttons = window:recursiveGetChildById('buttons')
    buttons:destroyChildren()
    if view == 'talk' then
        if dialog.question then
            addButton(buttons, tr('Yes'), function() say('yes') end, true)
            addButton(buttons, tr('No'), function() say('no') end)
        end
        for _, keyword in ipairs(dialog.keywords or {}) do
            addButton(buttons, keyword, function() say(keyword) end)
        end
        if #(dialog.buy or {}) + #(dialog.sell or {}) > 0 then
            addButton(buttons, tr('Trade'), function()
                tradeTab = #(dialog.buy or {}) > 0 and 'buy' or 'sell'
                setView('trade')
            end, true)
        end
        if #(dialog.travel or {}) > 0 then
            addButton(buttons, tr('Travel'), function() setView('travel') end, true)
        end
        addButton(buttons, tr('Bye'), function() say('bye') end)
    end
    buttons:setVisible(#buttons:getChildren() > 0)

    window:recursiveGetChildById('trade'):setVisible(view == 'trade')
    window:recursiveGetChildById('travel'):setVisible(view == 'travel')
    if view == 'trade' then
        renderTrade()
    elseif view == 'travel' then
        renderTravel()
    end
    local confirmButton = window:recursiveGetChildById('confirm')
    confirmButton:setText(askingCapacity and tr('Proceed') or tr('Confirm'))
    window:recursiveGetChildById('back'):setText(askingCapacity and tr('Cancel') or tr('Back'))
    confirmButton:setVisible(view ~= 'talk')
    confirmButton:setEnabled(selected ~= nil)
    window:recursiveGetChildById('back'):setVisible(view ~= 'talk')
    window:recursiveGetChildById('actions'):setVisible(view ~= 'talk')
    fitWindow()
end

local function onDialog(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' then
        return
    end
    if data.close then
        if dialog and dialog.id == data.id then
            close()
        end
        return
    end
    -- A shop or travel choice was just made: answer the NPC's question
    if data.question and autoYesUntil > g_clock.millis() then
        autoYesUntil = 0
        say('yes')
        return
    end
    autoYesUntil = 0
    local sameNpc = dialog and dialog.id == data.id
    dialog = data
    if not sameNpc then
        -- Captains and other travel NPCs open on their destinations, unless
        -- they asked something or also run a shop
        local travelOnly = #(data.travel or {}) > 0 and #(data.buy or {}) + #(data.sell or {}) == 0
        view = (travelOnly and not data.question) and 'travel' or 'talk'
        selected = nil
    elseif data.question then
        -- a question the automatic "yes" did not answer (slow reply, or typed
        -- words): Yes and No are in the talk view
        view = 'talk'
        selected = nil
    elseif view == 'trade' or view == 'travel' then
        -- after a purchase, the shop stays open with the same choice
        local list = view == 'travel' and (data.travel or {}) or (data[tradeTab] or {})
        local still
        for _, offer in ipairs(list) do
            if selected and offer.words == selected.words then
                still = offer
            end
        end
        selected = still
    end
    render()
    window:show()
    window:raise()
end

-- What the player can say to the NPC now (client_typing's suggestions), or
-- nil when no NPC is talking to the player
function getWords()
    if not dialog then
        return nil
    end
    local words = {}
    if dialog.question then
        table.insert(words, 'yes')
        table.insert(words, 'no')
    end
    for _, keyword in ipairs(dialog.keywords or {}) do
        table.insert(words, keyword)
    end
    if #(dialog.buy or {}) + #(dialog.sell or {}) > 0 then
        table.insert(words, 'trade')
    end
    table.insert(words, 'bye')
    return words
end

-- The player closed the window: say goodbye so the NPC is free again
function dismiss()
    if dialog then
        say('bye')
    end
    close()
end

function close()
    if window then
        window:hide()
    end
    askingCapacity = false
    dialog = nil
    view = 'talk'
    selected = nil
end

function init()
    g_ui.importStyle('npcdialog')
    window = g_ui.createWidget('NpcDialogWindow', rootWidget)
    window:hide()

    local trade = window:recursiveGetChildById('trade')
    trade:recursiveGetChildById('buyTab').onClick = function() tradeTab = 'buy'; selected = nil; render() end
    trade:recursiveGetChildById('sellTab').onClick = function() tradeTab = 'sell'; selected = nil; render() end
    trade:recursiveGetChildById('amount').onValueChange = function() askingCapacity = false; updateChosen() end
    trade:recursiveGetChildById('skipCapacity').onCheckChange = function(widget, checked)
        g_settings.set(SKIP_CAPACITY_SETTING, checked)
    end
    window:recursiveGetChildById('confirm').onClick = confirm
    window:recursiveGetChildById('back').onClick = function()
        if askingCapacity then
            askingCapacity = false
            updateChosen()
        else
            setView('talk')
        end
    end

    ProtocolGame.registerExtendedOpcode(NPC_DIALOG_OPCODE, onDialog)
    connect(g_game, { onGameEnd = close })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(NPC_DIALOG_OPCODE)
    disconnect(g_game, { onGameEnd = close })
    if window then
        window:destroy()
        window = nil
    end
end
