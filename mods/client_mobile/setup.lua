-- "Build your UI" (ot-client#27): on the first login on a device, and the
-- first time in the other orientation, the player places the touch layout's
-- pieces one at a time: each appears in the middle with what it is, the
-- player drags it (and sizes it with - and +) and taps the tick for the
-- next. Back goes to the previous piece, Skip keeps its default place.
-- Nothing is fixed: Edit layout changes it all later, and Settings > Layout
-- runs this again. Places are saved like the layout editor's (edit.lua).

local SETUP_SETTING = 'client_mobile_setup'

-- Most important first; pieces not on the screen are left out
local STEPS = {
    { key = 'joystick', name = 'Movement', text = 'Walks your character. Put it where your thumb rests.' },
    { key = 'grid', name = 'Hotbar', text = 'Spells, potions and runes: tap a slot to use it.' },
    { key = 'stats', name = 'Health and mana', text = 'Your health and mana bars.' },
    { key = 'containers', name = 'Backpack', text = 'Your bags and loot. The bag button below shows or hides it.' },
    { key = 'chat', name = 'Chat', text = 'Opens the chat over the game.' },
}

local sheet, bar
local steps -- the steps of the setup running (nil: not running)
local current

local function root()
    return modules.game_interface.getRootPanel()
end

local function orientation()
    local r = root()
    return r:getHeight() > r:getWidth() and 'portrait' or 'landscape'
end

local function setupDone()
    local name = g_game.getCharacterName()
    local all = g_settings.getNode(SETUP_SETTING) or {}
    return all[name] and all[name][orientation()]
end

local function markDone()
    local name = g_game.getCharacterName()
    if not name or name == '' then
        return
    end
    local all = g_settings.getNode(SETUP_SETTING) or {}
    all[name] = all[name] or {}
    all[name][orientation()] = true
    g_settings.setNode(SETUP_SETTING, all)
    g_settings.save()
end

local function closeSheet()
    if sheet then
        sheet:destroy()
        sheet = nil
    end
end

-- A sheet with a title, a text and two buttons
local function showSheet(title, text, skipText, skipAction, startText, startAction)
    closeSheet()
    sheet = g_ui.createWidget('MobileSetupSheet', rootWidget)
    local panel = sheet.panel
    panel:setWidth(math.min(380, rootWidget:getWidth() - 16))
    panel.title:setText(tr(title))
    panel.text:setText(tr(text))
    panel.skip:setVisible(skipText ~= nil)
    if skipText then
        panel.skip:setText(tr(skipText))
        panel.skip.onClick = function()
            closeSheet()
            skipAction()
            -- an outfit screen that waited for the setup (outfit.lua)
            outfitSheetAfterSetup()
        end
    else
        panel.start:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        panel.start:setMarginLeft(0)
    end
    panel.start:setText(tr(startText))
    panel.start.onClick = function()
        closeSheet()
        startAction()
        if not steps then
            outfitSheetAfterSetup()
        end
    end
    sheet:raise()
end

-- Pieces still to come are hidden; the ones placed (and the current one)
-- are shown. Also called after each layout (it shows them all again).
function applySetupVisibility()
    if not steps then
        return
    end
    local widgets = getMovableWidgets()
    for index, step in ipairs(steps) do
        local widget = widgets[step.key]
        if widget then
            widget:setVisible(index <= current)
        end
        -- P and the pencil go with the hotbar
        local presets = getHotbarPresetRow()
        if step.key == 'grid' and presets then
            presets:setVisible(index <= current)
        end
    end
end

local function showStep()
    local step = steps[current]
    applySetupVisibility()
    local widget = getMovableWidgets()[step.key]
    -- in the middle of the game view (above the bar), where it cannot be
    -- missed
    local game = modules.game_interface.getMapPanel():getRect()
    widget:breakAnchors()
    widget:setPosition({ x = game.x + math.floor((game.width - widget:getWidth()) / 2),
        y = game.y + math.max(0, math.floor((game.height - bar:getHeight() - widget:getHeight()) / 2)) })
    step.shownAt = widget:getPosition()
    widget:raise()
    startPlacingPiece(step.key)

    bar.title:setText(tr('Place: %s', tr(step.name)) .. '   ' .. current .. '/' .. #steps)
    bar.text:setText(tr(step.text))
    bar.back:setEnabled(current > 1)
    bar:raise()
end

local function finish()
    stopPlacingPiece()
    if bar then
        bar:destroy()
        bar = nil
    end
    steps = nil
    markDone()
    -- the backpack window was shown to be placed: hidden again when empty
    local containers = modules.client_containers
    if containers and containers.getWindow() and #g_game.getContainers() == 0 then
        containers.getWindow():hide()
    end
    relayout()
    showSheet('Your UI is ready', 'Change it any time: Menu > Edit layout. Settings > Layout runs this setup again.',
        nil, nil, 'Play', function() end)
end

local function nextStep()
    if current < #steps then
        current = current + 1
        showStep()
    else
        finish()
    end
end

local function startSteps()
    if isEditingLayout() then
        stopEditLayout()
    end
    steps = {}
    local widgets = getMovableWidgets()
    -- (the backpack window shows even with nothing open, to be placed)
    local containers = modules.client_containers and modules.client_containers.getWindow()
    if containers then
        containers:setVisible(true)
        widgets.containers = containers
    end
    for _, step in ipairs(STEPS) do
        if widgets[step.key] then
            table.insert(steps, step)
        end
    end
    if #steps == 0 then
        steps = nil
        return
    end
    current = 1
    bar = g_ui.createWidget('MobileSetupBar', rootWidget)
    -- along the bottom of the game view: the one place no piece goes
    local game = modules.game_interface.getMapPanel():getRect()
    bar:setWidth(math.min(420, game.width - 8))
    bar:setPosition({ x = game.x + math.floor((game.width - bar:getWidth()) / 2),
        y = game.y + game.height - bar:getHeight() - 4 })
    -- its default place (the layout puts it there; the pieces already
    -- placed keep theirs, they are saved)
    local function keepDefault()
        forgetPiece(steps[current].key)
        stopPlacingPiece()
        relayout()
        nextStep()
    end
    bar.ok.onClick = function()
        local step = steps[current]
        local widget = getMovableWidgets()[step.key]
        local at = widget and widget:getPosition()
        -- not moved: the tick keeps the default place
        if at and step.shownAt and at.x == step.shownAt.x and at.y == step.shownAt.y then
            keepDefault()
        else
            confirmPlacedPiece(step.key)
            nextStep()
        end
    end
    bar.skip.onClick = keepDefault
    bar.back.onClick = function()
        if current > 1 then
            stopPlacingPiece()
            current = current - 1
            showStep()
        end
    end
    showStep()
end

-- Runs the setup (Settings > Layout, or offered on login)
function startUiSetup()
    if steps or not g_game.isOnline() then
        return
    end
    startSteps()
end

function isUiSetupRunning()
    return steps ~= nil
end

-- The setup's sheet or its steps are on the screen (the outfit screen waits)
function isUiSetupBusy()
    return steps ~= nil or sheet ~= nil
end

-- The outfit screen (outfit.lua) is open on the first login: the offer
-- waits until it closes, so the two never overlap
local waitingForOutfit = false
onOutfitSheetClosed(function()
    if waitingForOutfit then
        waitingForOutfit = false
        addEvent(offerUiSetup)
    end
end)

-- On login and after turning the screen: offered once per character and
-- orientation, unless the player already arranged this orientation
function offerUiSetup()
    if steps or sheet or not g_game.isOnline() or setupDone() then
        return
    end
    if isOutfitSheetOpen() then
        waitingForOutfit = true
        return
    end
    if hasSavedLayout() then
        markDone()
        return
    end
    local other = orientation() == 'portrait' and 'landscape' or 'portrait'
    local name = g_game.getCharacterName()
    local all = g_settings.getNode(SETUP_SETTING) or {}
    local again = all[name] and all[name][other]
    local title = again and tr('Set up %s too?', tr(orientation())) or tr("Let's build your UI")
    showSheet(title, 'Place the movement control, hotbar, bars, backpack and chat where they suit your hands and screen, one at a time. You can change everything later.',
        'Use the default', markDone, 'Start', startSteps)
end

-- Logged out in the middle of it
function stopUiSetup()
    waitingForOutfit = false
    closeSheet()
    if steps then
        stopPlacingPiece()
        if bar then
            bar:destroy()
            bar = nil
        end
        steps = nil
    end
end

