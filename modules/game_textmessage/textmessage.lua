MessageSettings = {
    none = {},
    consoleYellow = {
        color = TextColors.yellow,
        consoleTab = 'Local Chat'
    },
    consoleRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat'
    },
    consoleOrange = {
        color = TextColors.orange,
        consoleTab = 'Local Chat'
    },
    consoleBlue = {
        color = TextColors.blue,
        consoleTab = 'Local Chat'
    },
    centerRed = {
        color = TextColors.red,
        consoleTab = 'Server Log',
        screenTarget = 'lowCenterLabel'
    },
    centerGreen = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole'
    },
    centerHKGreen = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showHotkeyMessagesInConsole'
    },
    centerWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'middleCenterLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    bottomWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    status = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusOwn = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusBoosted = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showBoostedMessagesInConsole'
    },
    othersStatus = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        consoleOption = 'showOthersStatusMessagesInConsole'
    },
    statusSmall = {
        color = TextColors.white,
        screenTarget = 'statusLabel'
    },
    private = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        screenTarget = 'privateLabel'
    },
    privateRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToPlayer = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToNpc = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    privateNpcToPlayer = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    channelYellow = {
        color = TextColors.yellow
    },
    channelWhite = {
        color = TextColors.white
    },
    channelRed = {
        color = TextColors.red
    },
    channelOrange = {
        color = TextColors.orange
    },
    monsterSay = {
        color = TextColors.orange,
        hideInConsole = true
    },
    monsterYell = {
        color = TextColors.orange,
        hideInConsole = true
    },
    potion = {
        color = TextColors.orange,
        hideInConsole = true
    },
    loot = {
        color = TextColors.white,
        consoleTab = 'Loot',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    },
    valuableLoot = {
        color = TextColors.white,
        consoleTab = 'Loot',
        screenTarget = 'statusLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    }
}

MessageTypes = {
    [MessageModes.Say] = MessageSettings.consoleYellow,
    [MessageModes.Whisper] = MessageSettings.consoleYellow,
    [MessageModes.Yell] = MessageSettings.consoleYellow,
    [MessageModes.MonsterSay] = MessageSettings.monsterSay,
    [MessageModes.MonsterYell] = MessageSettings.monsterYell,
    [MessageModes.BarkLow] = MessageSettings.consoleOrange,
    [MessageModes.BarkLoud] = MessageSettings.consoleOrange,
    [MessageModes.Failure] = MessageSettings.statusSmall,
    [MessageModes.Login] = MessageSettings.bottomWhite,
    [MessageModes.Game] = MessageSettings.centerWhite,
    [MessageModes.Status] = MessageSettings.status,
    [MessageModes.Warning] = MessageSettings.centerRed,
    [MessageModes.Look] = MessageSettings.centerGreen,
    [MessageModes.Loot] = MessageSettings.loot,
    [MessageModes.Red] = MessageSettings.consoleRed,
    [MessageModes.Blue] = MessageSettings.consoleBlue,
    [MessageModes.PrivateFrom] = MessageSettings.private,
    [MessageModes.PrivateTo] = MessageSettings.privatePlayerToPlayer,
    [MessageModes.GamemasterPrivateFrom] = MessageSettings.privateRed,
    [MessageModes.NpcTo] = MessageSettings.privatePlayerToNpc,
    [MessageModes.NpcFrom] = MessageSettings.privateNpcToPlayer,
    [MessageModes.NpcFromStartBlock] = MessageSettings.privateNpcToPlayer,
    [MessageModes.Channel] = MessageSettings.channelYellow,
    [MessageModes.ChannelManagement] = MessageSettings.channelWhite,
    [MessageModes.GamemasterChannel] = MessageSettings.channelRed,
    [MessageModes.ChannelHighlight] = MessageSettings.channelOrange,
    [MessageModes.Spell] = MessageSettings.consoleYellow,
    [MessageModes.RVRChannel] = MessageSettings.channelWhite,
    [MessageModes.RVRContinue] = MessageSettings.consoleYellow,

    [MessageModes.GamemasterBroadcast] = MessageSettings.consoleRed,

    [MessageModes.DamageDealed] = MessageSettings.statusOwn,
    [MessageModes.DamageReceived] = MessageSettings.statusOwn,
    [MessageModes.Heal] = MessageSettings.statusOwn,
    [MessageModes.Exp] = MessageSettings.statusOwn,

    [MessageModes.DamageOthers] = MessageSettings.othersStatus,
    [MessageModes.HealOthers] = MessageSettings.othersStatus,
    [MessageModes.ExpOthers] = MessageSettings.othersStatus,
    [MessageModes.Potion] = MessageSettings.potion,

    [MessageModes.TradeNpc] = MessageSettings.centerGreen,
    [MessageModes.Guild] = MessageSettings.statusOwn,
    [MessageModes.Party] = MessageSettings.statusOwn,
    [MessageModes.PartyManagement] = MessageSettings.centerGreen,
    [MessageModes.TutorialHint] = MessageSettings.statusSmall,
    [MessageModes.BeyondLast] = MessageSettings.centerWhite,
    [MessageModes.Report] = MessageSettings.centerWhite,
    [MessageModes.GameHighlight] = MessageSettings.centerRed,
    [MessageModes.HotkeyUse] = MessageSettings.centerGreen,
    [MessageModes.Attention] = MessageSettings.bottomWhite,
    [MessageModes.BoostedCreature] = MessageSettings.centerWhite,
    [MessageModes.OfflineTrainning] = MessageSettings.centerWhite,
    [MessageModes.Transaction] = MessageSettings.centerWhite,
    [MessageModes.ValuableLoot] = MessageSettings.valuableLoot,

    [254] = MessageSettings.private
}

messagesPanel = nil

-- The message boxes on the game view
local BOXES = { 'highCenterLabel', 'middleCenterLabel', 'lowCenterLabel', 'privateLabel', 'statusLabel' }
-- A message's box is at most this wide (with its padding), and keeps this far
-- from the sides of the game view: long text (a blackboard) wraps inside it
local MAX_BOX_WIDTH = 300
local VIEW_MARGIN = 16
local WRAP_SLACK = 2

-- The message boxes (textmessage.otui) in parent: the game view's, or the
-- UI gallery's
function createMessagesPanel(parent)
    local panel = g_ui.loadUI('textmessage', parent)
    -- a smaller game view (a phone turned): the shown messages wrap again
    panel.onGeometryChange = function()
        for _, id in ipairs(BOXES) do
            local box = panel:recursiveGetChildById(id)
            if box and box:isVisible() and box.message then
                fitBox(panel, box)
            end
        end
    end
    return panel
end

function init()
    for messageMode, _ in pairs(MessageTypes) do
        registerMessageMode(messageMode, displayMessage)
    end

    connect(g_game, 'onGameEnd', clearMessages)
    messagesPanel = createMessagesPanel(modules.game_interface.getRootPanel())
    messagesPanel:fill('gameMapPanel')
end

function terminate()
    for messageMode, _ in pairs(MessageTypes) do
        unregisterMessageMode(messageMode, displayMessage)
    end

    disconnect(g_game, 'onGameEnd', clearMessages)
    clearMessages()
    messagesPanel:destroy()
    messagesPanel = nil
end

function calculateVisibleTime(text)
    return math.max(#text * 50, 4000)
end

-- A 7.x loot message with each item coloured by its rarity, or nil; the
-- rest in baseColor ("{text, #colour}" parts, for setColoredText)
function lootColors(text, baseColor)
    local itemdata = modules.client_itemdata
    if not (itemdata and itemdata.lootColoredText and text:find('^Loot of ')) then
        return nil
    end
    local ok, colored = pcall(itemdata.lootColoredText, text)
    if not ok or not colored then
        return nil
    end
    local parts, at = {}, 1
    while true do
        local open, close = colored:find('%b{}', at)
        local plain = colored:sub(at, (open or #colored + 1) - 1)
        if plain ~= '' then
            table.insert(parts, '{' .. plain .. ', ' .. baseColor .. '}')
        end
        if not open then
            break
        end
        table.insert(parts, colored:sub(open, close))
        at = close + 1
    end
    return table.concat(parts)
end

function displayMessage(mode, text)

    if not g_game.isOnline() then
        return
    end
    if g_game.getClientVersion() >= 1300 then
        MessageTypes[MessageModes.Loot] = MessageSettings.loot
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.valuableLoot
        MessageTypes[MessageModes.Guild] = MessageSettings.statusOwn
        MessageTypes[MessageModes.Party] = MessageSettings.statusOwn
    else
        MessageTypes[MessageModes.PrivateFrom] = MessageSettings.privateNpcToPlayer
        MessageTypes[MessageModes.Loot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Guild] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Party] = MessageSettings.centerGreen
        MessageTypes[MessageModes.MonsterSay] = MessageSettings.consoleOrange
        MessageTypes[MessageModes.MonsterYell] = MessageSettings.consoleOrange
    end
    local msgtype = MessageTypes[mode]
    if not msgtype then
        return
    end

    if msgtype == MessageSettings.none then
        return
    end

    if msgtype.consoleTab ~= nil and
        (msgtype.consoleOption == nil or modules.client_options.getOption(msgtype.consoleOption)) then
        if msgtype == MessageSettings.loot or msgtype == MessageSettings.valuableLoot then
            local lootColoredText = ItemsDatabase.setColorLootMessage(text)
            local lootTabName = tr(msgtype.consoleTab)
            local targetTab = modules.game_console.getTab(lootTabName) and lootTabName or tr("Server Log")
            modules.game_console.addText(lootColoredText, msgtype, targetTab)
        else
            local colored = lootColors(text, msgtype.color)
            if colored then
                modules.game_console.addText(colored, setmetatable({ colored = true }, { __index = msgtype }),
                    tr(msgtype.consoleTab))
            else
                modules.game_console.addText(text, msgtype, tr(msgtype.consoleTab))
            end
        end
    end

    if msgtype.screenTarget then
        if msgtype == MessageSettings.loot and not modules.client_options.getOption('showLootMessagesOnScreen') then
            return
        end
        showOnScreen(messagesPanel, msgtype, text)
    end
end

-- Wraps a box's text at the widest a box may be in this game view, then
-- sizes the label to its widest line and the box to the label plus its
-- padding.
function fitBox(panel, box)
    local label = box:getChildById('text')
    local message = box.message
    local padWidth = box:getPaddingLeft() + box:getPaddingRight()
    local limit = math.max(60, math.min(MAX_BOX_WIDTH, panel:getWidth() - 2 * VIEW_MARGIN))
    label:setWidth(limit - padWidth)
    label.baseFont = label.baseFont or label:getFont()
    label:setFont(message.font or label.baseFont)
    -- (setText wraps at the label's width now; '' first, or the same text
    -- would keep its old wrap)
    label:setText('')
    if message.colored then
        label:setColoredText(message.colored)
    else
        label:setText(message.text)
        label:setColor(message.color)
    end
    -- the label as wide as its widest line (the wrap measures a line with
    -- the spacing after its last letter, the text size without it: a few
    -- pixels more, never past the wrap width, so the lines stay as they are)
    local textSize = label:getTextSize()
    local labelWidth = math.min(textSize.width + WRAP_SLACK, limit - padWidth)
    label:setWidth(labelWidth)
    local width = labelWidth + padWidth
    box:setSize({ width = width, height = textSize.height + box:getPaddingTop() + box:getPaddingBottom() })
    local parent = box:getParent()
    if parent:getId() == 'centerTextMessagePanel' then
        -- the column's layout stretches its boxes to its width: margins
        -- centre each box at the width of its text
        parent:setWidth(limit)
        local side = math.max(0, math.floor((limit - width) / 2))
        box:setMarginLeft(side)
        box:setMarginRight(side)
    end
end

-- Shows text in its box on panel (msgtype.screenTarget), on the see-through
-- backdrop, until it times out. Returns the box.
function showOnScreen(panel, msgtype, text)
    local box = panel:recursiveGetChildById(msgtype.screenTarget)
    if not box then
        return nil
    end
    local message = { text = text, color = msgtype.color }
    if msgtype == MessageSettings.loot or msgtype == MessageSettings.valuableLoot then
        message.colored = ItemsDatabase.setColorLootMessage(text)
    end
    -- Loot messages ("Loot of a rat: cheese", 7.x sends them as plain info
    -- messages) stand out in bold, each item in the colour of its rarity
    -- (client_itemdata)
    if text:find('^Loot of ') then
        message.colored = lootColors(text, msgtype.color) or message.colored
        message.font = 'Verdana Bold-11px-outline'
    end
    box.message = message
    fitBox(panel, box)
    box:setVisible(true)
    removeEvent(box.hideEvent)
    box.hideEvent = scheduleEvent(function()
        box:setVisible(false)
    end, calculateVisibleTime(text))
    return box
end

function displayPrivateMessage(text)
    if not g_game.isOnline() then
        return
    end
    showOnScreen(messagesPanel, MessageSettings.private, text)
end

function displayStatusMessage(text)
    displayMessage(MessageModes.Status, text)
end

function displayFailureMessage(text)
    displayMessage(MessageModes.Failure, text)
end

function displayGameMessage(text)
    displayMessage(MessageModes.Game, text)
end

function displayBroadcastMessage(text)
    displayMessage(MessageModes.Warning, text)
end

function clearMessages()
    for _i, child in pairs(messagesPanel:recursiveGetChildren()) do
        if child:getId():match('Label') then
            child:hide()
            removeEvent(child.hideEvent)
        end
    end
end

function LocalPlayer:onAutoWalkFail(player)
    modules.game_textmessage.displayFailureMessage(tr('There is no way.'))
end
