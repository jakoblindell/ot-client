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
    { key = 'containers', name = 'Backpack', text = 'Your bags and loot. The bag button below shows or hides it.' },
    { key = 'chat', name = 'Chat', text = 'Opens the chat over the game.' },
}

local sheet, bar
local shownForSetup = false -- (the backpack panel, shown to be placed)
local steps -- the steps of the setup running (nil: not running)
local current
local resumeAt -- a setup cut short by a reconnect: character, orientation, step

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

-- The prompt: along the bottom of the game view, where it is now
local function placeBar()
    local game = modules.game_interface.getMapPanel():getRect()
    bar:setWidth(math.min(420, game.width - 8))
    bar:setPosition({ x = game.x + math.floor((game.width - bar:getWidth()) / 2),
        y = game.y + game.height - bar:getHeight() - 4 })
end

-- Pieces still to come are hidden; the ones placed (and the current one)
-- are shown. Also called after each layout (it shows them all again).
function applySetupVisibility()
    if not steps then
        return
    end
    if bar then
        placeBar()
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
    -- (over the game view and the other pieces)
    startPlacingPiece(step.key)

    bar.title:setText(tr('Place: %s', tr(step.name)) .. '   ' .. current .. '/' .. #steps)
    bar.text:setText(tr(step.text))
    bar.back:setEnabled(current > 1)
    onPlacingPieceHeld(false)
    bar:raise()
end

-- A finger on the piece being placed (edit.lua): the prompt fades out of
-- its way, and takes no touches while hidden; back when the finger lifts
local PROMPT_FADE = 120

function onPlacingPieceHeld(down)
    if not bar then
        return
    end
    g_effects.cancelFade(bar)
    removeEvent(bar.hideEvent)
    bar.hideEvent = nil
    if down then
        g_effects.fadeOut(bar, PROMPT_FADE)
        bar.hideEvent = scheduleEvent(function()
            if bar then
                bar.hideEvent = nil
                bar:setVisible(false)
            end
        end, PROMPT_FADE)
    elseif not bar:isVisible() or bar:getOpacity() < 1 then
        bar:setVisible(true)
        bar:raise()
        g_effects.fadeIn(bar, PROMPT_FADE)
    end
end

local function destroyBar()
    if bar then
        g_effects.cancelFade(bar)
        removeEvent(bar.hideEvent)
        bar:destroy()
        bar = nil
    end
end

local function finish()
    stopPlacingPiece()
    destroyBar()
    steps = nil
    markDone()
    -- the backpack window was shown to be placed: hidden again when empty
    if shownForSetup and #g_game.getContainers() == 0 then
        hidePanel('bag')
    end
    shownForSetup = false
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

-- (from the step with key fromKey, when given: a setup taken up again)
local function startSteps(fromKey)
    if isEditingLayout() then
        stopEditLayout()
    end
    steps = {}
    -- (the backpack window shows even with nothing open, to be placed)
    shownForSetup = not isPanelShown('bag')
    showPanel('bag')
    local widgets = getMovableWidgets()
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
    for index, step in ipairs(steps) do
        if step.key == fromKey then
            current = index
        end
    end
    bar = g_ui.createWidget('MobileSetupBar', rootWidget)
    placeBar()
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

-- The UI gallery (client_mobile startLayoutPreview): the setup's first
-- step over the touch layout without a game, its piece placed partly over
-- the game view; held: with a finger on the piece (the prompt hidden)
function startUiSetupPreview(held)
    if steps or not isLayoutPreview() then
        return
    end
    startSteps()
    if not steps then
        return
    end
    -- once the preview's screen has settled (the game view in its place)
    scheduleEvent(function()
        local widget = steps and getMovableWidgets()[steps[current].key]
        if not widget then
            return
        end
        local game = modules.game_interface.getMapPanel():getRect()
        if orientation() == 'portrait' then
            -- (over the game view's top edge: the bars are under it)
            movePlacingPiece(game.x + 8, game.y - math.floor(widget:getHeight() / 3))
        else
            movePlacingPiece(game.x - math.floor(widget:getWidth() / 2),
                game.y + math.floor((game.height - widget:getHeight()) / 3))
        end
        if held then
            onPlacingPieceHeld(true)
        end
    end, 750)
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
    -- cut short by a reconnect: carries on at the same piece
    local resume = resumeAt
    resumeAt = nil
    if resume and resume.name == g_game.getCharacterName() and resume.orientation == orientation() then
        startSteps(resume.step)
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
    showSheet(title, 'Place the movement control, hotbar, backpack and chat where they suit your hands and screen, one at a time. You can change everything later.',
        'Use the default', markDone, 'Start', startSteps)
end

-- Logged out in the middle of it: the pieces still to come are shown again.
-- reconnecting: the same character is coming back (client_reconnect), and
-- the setup carries on at the same piece then (offerUiSetup).
function stopUiSetup(reconnecting)
    waitingForOutfit = false
    closeSheet()
    resumeAt = nil
    if steps then
        stopPlacingPiece()
        destroyBar()
        if reconnecting then
            resumeAt = { name = g_game.getCharacterName(), orientation = orientation(), step = steps[current].key }
        end
        local widgets = getMovableWidgets()
        for index = current + 1, #steps do
            local key = steps[index].key
            if key == 'grid' and getHotbarPresetRow() then
                getHotbarPresetRow():setVisible(true)
            end
            -- (the backpack window shows when a container is open)
            if widgets[key] and key ~= 'containers' then
                widgets[key]:setVisible(true)
            end
        end
        steps = nil
        -- the backpack window was shown to be placed: hidden again when empty
        local containers = modules.client_containers
        if containers and containers.getWindow() and #g_game.getContainers() == 0 then
            containers.getWindow():hide()
        end
    end
end

