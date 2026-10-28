-- The hub (ot-client#19): what the toolbar's menu button opens on a touch
-- screen, instead of the desktop top menu. Large buttons for the settings,
-- the layout editor, the hotbar and controller settings, outfit, quest log
-- and logout; "All options" still opens the desktop menu with everything.
--
-- Settings shows what matters on a phone in five tabs, touch-sized: a
-- switch, a row of choices or - value +. Every setting is the client's own
-- option (client_options), so desktop and phone stay the same. "?" next to a
-- setting explains it (touch screens have no hover tooltips).

local CONTRAST_SETTING = 'client_mobile_hubContrast'

-- kind: toggle | choice (choices = { { value, text } }) | step (min, max, step, unit)
-- get / set: for values that are not client options
local SETTINGS = {
    {
        id = 'gameplay', text = 'Gameplay', rows = {
            { key = 'autoChaseOverride', kind = 'toggle', text = 'Stop chasing when walking',
                help = 'Walking by hand stops following the creature you attack.' },
            { key = 'smartWalk', kind = 'toggle', text = 'Smart walking',
                help = 'When the way is blocked, walk around the obstacle instead of stopping.' },
            { key = 'moveStack', kind = 'toggle', text = 'Move whole stacks',
                help = 'Dragging a stack of items moves all of it without asking how many.' },
            { key = 'showUnopenedCorpses', kind = 'toggle', text = 'Shine on my unopened corpses',
                help = 'Corpses of monsters you killed shine until you open them.' },
            { key = 'hideSpellWordsInChat', kind = 'toggle', text = 'Hide spell words in chat',
                help = 'Spell words (exura, utani hur...) are not shown in the chat.' },
            { key = 'blueNpcNames', kind = 'toggle', text = 'Blue NPC names',
                help = 'NPC names are drawn in blue so they stand out from players.' },
            { key = 'walkFirstStepDelay', kind = 'step', text = 'Walk delay after first step', min = 50, max = 500,
                step = 25, unit = 'ms',
                help = 'How long you stand after the first step before walking on, when the D-pad or stick is held.' },
            { id = 'clientBuild', kind = 'build', text = 'Client version',
                help = 'The build of the game client you are running. Check asks the website for a newer one; an update loads when you log out.' },
        },
    },
    {
        id = 'display', text = 'Display', rows = {
            { key = 'hudScale', kind = 'choice', text = 'Interface size',
                choices = { { 1, '1x' }, { 2, '1.5x' }, { 3, '2x' }, { 4, '2.5x' } },
                help = 'How big names, bars and the whole interface are drawn.' },
            { key = 'displayNames', kind = 'toggle', text = 'Names above creatures',
                help = 'Show names over creatures and players.' },
            { key = 'displayHealth', kind = 'toggle', text = 'Health bars above creatures',
                help = 'Show health bars over creatures and players.' },
            { key = 'displayMana', kind = 'toggle', text = 'Your mana bar', help = 'Show a mana bar over your character.' },
            { key = 'enableLights', kind = 'toggle', text = 'Lights', help = 'Draw darkness and light sources.' },
            { key = 'ambientLight', kind = 'step', text = 'Minimum brightness', min = 0, max = 100, step = 10, unit = '%',
                help = 'How bright dark places are at least. 0% is the classic darkness.' },
            { key = 'showFps', kind = 'toggle', text = 'Show frame rate',
                help = 'Frames per second and the client build, in the top left corner of the game view.' },
            { key = 'showPing', kind = 'toggle', text = 'Show ping',
                help = 'Your connection delay to the server in milliseconds, in the top left corner of the game view.' },
            { key = 'soundMaster', kind = 'step', text = 'Volume', min = 0, max = 100, step = 10, unit = '%',
                help = 'Volume of all game sounds. 0% is muted.' },
        },
    },
    {
        id = 'controls', text = 'Controls', rows = {
            { id = 'movement', kind = 'choice', text = 'Movement',
                help = 'D-Pad: four arrows. D-Pad (8-way): with diagonals. Analog stick: follows your thumb.' },
            { id = 'controller', kind = 'button', text = 'Game controller', buttonText = 'Bind...',
                help = 'Choose which hotbar slot each controller button uses. Walk with the stick or D-pad.' },
            { id = 'layoutMode', kind = 'choice', text = 'Layout',
                help = 'Touch or desktop layout. Automatic picks one for this device. Changing it reloads the client.' },
        },
    },
    {
        id = 'layout', text = 'Layout', rows = {
            { id = 'viewSize', kind = 'choice', text = 'Game view size',
                help = 'How much of the screen the game takes. Medium and Small leave room beside it for your bag, panels and hotbar. Large makes the game bigger; on small screens panels may then cover its edges.' },
            { id = 'editLayout', kind = 'button', text = 'Move and size pieces', buttonText = 'Edit layout',
                help = 'Drag pieces to move them. Tap one, then - and + to size it. Long press a toolbar button to pin its panel.' },
            { id = 'setupUi', kind = 'button', text = 'Place pieces one by one', buttonText = 'UI setup',
                help = 'Places the movement control, hotbar, bars, backpack and chat one at a time, like on your first login.' },
            { id = 'hotbar', kind = 'button', text = 'Hotbar presets, rows and slots', buttonText = 'Hotbar...',
                help = 'Number of presets (P button), extra rows and how many slots the hotbar shows.' },
            { id = 'resetUi', kind = 'button', text = 'Back to the default layout', buttonText = 'Reset UI',
                help = 'Puts every piece back in its first place and size and unpins all panels. Your hotbar stays.' },
        },
    },
    {
        id = 'optimization', text = 'Optimization', rows = {
            { key = 'lowPowerMode', kind = 'toggle', text = 'Battery saver',
                help = 'Draws fewer frames while nothing moves, to save battery.' },
            { key = 'backgroundFrameRate', kind = 'choice', text = 'Frame rate limit',
                choices = { { 30, '30' }, { 60, '60' }, { 501, 'Max' } },
                help = 'Fewer frames per second use less battery and keep the phone cooler.' },
            { key = 'optimizeFps', kind = 'toggle', text = 'Optimize frame rate',
                help = 'Skips drawing work that is not seen.' },
            { key = 'forceEffectOptimization', kind = 'toggle', text = 'Simpler effects',
                help = 'Draws spell and item effects more simply when many are on screen.' },
        },
    },
}

local hub
local currentPage
local helpBox

local function options()
    return modules.client_options
end

local function close()
    if helpBox then
        helpBox:destroy()
        helpBox = nil
    end
    if hub then
        hub:destroy()
        hub = nil
    end
end

local function showHelp(text)
    if helpBox then
        helpBox:destroy()
    end
    helpBox = g_ui.createWidget('HubHelp', rootWidget)
    helpBox.box.text:setText(tr(text))
    helpBox.box:setOn(g_settings.getBoolean(CONTRAST_SETTING))
    helpBox:raise()
    helpBox.onClick = function()
        helpBox:destroy()
        helpBox = nil
    end
end

local function applyContrast()
    if hub then
        local on = g_settings.getBoolean(CONTRAST_SETTING)
        hub.panel:setOn(on)
        hub.panel.contrast:setChecked(on)
    end
end

-- Values that are not client options
local function rowValue(row)
    if row.key then
        return options().getOption(row.key)
    elseif row.id == 'movement' then
        return modules.game_joystick and modules.game_joystick.getStyle and modules.game_joystick.getStyle()
    elseif row.id == 'layoutMode' then
        return g_platform.getTouchMode()
    elseif row.id == 'viewSize' then
        return getViewSize()
    end
end

local function rowChoices(row)
    if row.id == 'movement' then
        local list = {}
        for _, style in ipairs(modules.game_joystick.STYLES or {}) do
            table.insert(list, { style.id, style.name })
        end
        return list
    elseif row.id == 'layoutMode' then
        return { { 0, 'Automatic' }, { 1, 'Touch' }, { 2, 'Desktop' } }
    elseif row.id == 'viewSize' then
        local list = {}
        for _, size in ipairs(VIEW_SIZES) do
            table.insert(list, { size.id, size.text })
        end
        return list
    end
    return row.choices
end

local function setRowValue(row, value)
    if row.key then
        options().setOption(row.key, value)
    elseif row.id == 'movement' then
        modules.game_joystick.setStyle(value)
    elseif row.id == 'layoutMode' then
        setTouchMode(value)
    elseif row.id == 'viewSize' then
        setViewSize(value)
    end
end

local function rowAction(row)
    if row.id == 'controller' then
        close()
        modules.client_gamepad.openBindWindow()
    elseif row.id == 'editLayout' then
        close()
        startEditLayout()
    elseif row.id == 'hotbar' then
        close()
        openHotbarSettings()
    elseif row.id == 'setupUi' then
        close()
        startUiSetup()
    elseif row.id == 'resetUi' then
        close()
        confirmResetLayout()
    end
end

local function rowAvailable(row)
    if row.key then
        return options() and options().getOption(row.key) ~= nil
    elseif row.id == 'movement' then
        return modules.game_joystick and modules.game_joystick.STYLES ~= nil
    elseif row.id == 'controller' then
        return modules.client_gamepad and modules.client_gamepad.openBindWindow ~= nil and g_platform.isBrowser()
    elseif row.id == 'layoutMode' then
        return g_platform.isBrowser()
    elseif row.id == 'clientBuild' then
        return modules.client_updates and modules.client_updates.getBuildText and
            modules.client_updates.getBuildText() ~= nil
    end
    return true
end

local showSettings

local function addRow(list, row)
    local widget = g_ui.createWidget('OtSettingRow', list)
    widget.title:setText(tr(row.text))
    widget.help.onClick = function()
        showHelp(row.help)
    end
    local controls = widget.controls
    local value = rowValue(row)

    if row.kind == 'toggle' then
        local check = g_ui.createWidget('OtCheck', controls)
        check:setChecked(value and true or false)
        check.onCheckChange = function(widget, checked)
            setRowValue(row, checked)
        end
    elseif row.kind == 'choice' then
        for _, choice in ipairs(rowChoices(row)) do
            local button = g_ui.createWidget('OtButton', controls)
            button:setText(tr(choice[2]))
            button:setWidth(math.max(44, 16 + #choice[2] * 9))
            button:setChecked(choice[1] == value)
            button.onClick = function()
                setRowValue(row, choice[1])
                showSettings(currentPage)
            end
        end
    elseif row.kind == 'step' then
        local function step(delta)
            local current = tonumber(rowValue(row)) or row.min
            local new = math.max(row.min, math.min(row.max, current + delta))
            setRowValue(row, new)
            showSettings(currentPage)
        end
        local minus = g_ui.createWidget('OtIconButton', controls)
        minus:setText('-')
        minus.onClick = function() step(-row.step) end
        local label = g_ui.createWidget('OtValue', controls)
        label:setText(tostring(value) .. (row.unit or ''))
        local plus = g_ui.createWidget('OtIconButton', controls)
        plus:setText('+')
        plus.onClick = function() step(row.step) end
    elseif row.kind == 'build' then
        -- the build, and Check (client_updates)
        local updates = modules.client_updates
        local label = g_ui.createWidget('OtValue', controls)
        label:setText(updates.getBuildText())
        label:setWidth(140)
        local button = g_ui.createWidget('OtButton', controls)
        button:setText(updates.isUpdatePending() and tr('Update') or tr('Check'))
        button:setWidth(90)
        button.onClick = function()
            if updates.isUpdatePending() then
                close()
                updates.openSheet()
                return
            end
            button:setEnabled(false)
            updates.check(function(found)
                if not hub then
                    return
                end
                button:setEnabled(true)
                if found then
                    close()
                    updates.openSheet()
                elseif found == false then
                    showHelp('You have the newest build.')
                else
                    showHelp('The website did not answer. Try again later.')
                end
            end)
        end
    elseif row.kind == 'button' then
        local button = g_ui.createWidget('OtButton', controls)
        button:setText(tr(row.buttonText))
        button:setWidth(110)
        button.onClick = function()
            rowAction(row)
        end
    end
    -- the controls take the room they need; the title wraps beside them
    local width = 0
    for _, child in ipairs(controls:getChildren()) do
        width = width + child:getWidth() + 4
    end
    controls:setWidth(math.max(40, width - 4))
end

-- One settings tab
showSettings = function(pageId)
    if not hub then
        return
    end
    currentPage = pageId
    local panel = hub.panel
    panel.title:setText(tr('Settings'))
    panel.back:setText('< ' .. tr('Hub'))
    panel.back:setVisible(true)
    panel.back.onClick = function()
        openHub()
    end
    panel.tabs:destroyChildren()
    panel.tabs:setVisible(true)
    panel.tabs:setHeight(36)
    for _, page in ipairs(SETTINGS) do
        local tab = g_ui.createWidget('OtTab', panel.tabs)
        tab:setText(tr(page.text))
        tab:setChecked(page.id == pageId)
        tab.onClick = function()
            showSettings(page.id)
        end
    end
    local scroll = panel.listScroll:getValue()
    panel.list:destroyChildren()
    for _, page in ipairs(SETTINGS) do
        if page.id == pageId then
            for _, row in ipairs(page.rows) do
                if rowAvailable(row) then
                    addRow(panel.list, row)
                end
            end
        end
    end
    local logout = g_ui.createWidget('HubLogout', panel.list)
    logout.onClick = function()
        close()
        modules.game_interface.tryLogout()
    end
    -- keep the place in the list when a setting changed
    addEvent(function()
        if hub then
            hub.panel.listScroll:setValue(scroll)
        end
    end)
end

local HUB_BUTTONS = {
    { text = 'Settings', action = function() showSettings(currentPage or 'gameplay') end },
    { text = 'Edit layout', action = function() close(); startEditLayout() end },
    { text = 'Hotbar', action = function() close(); openHotbarSettings() end },
    { text = 'Outfit', action = function() close(); g_game.requestOutfit() end },
    { text = 'Quest log', action = function()
        close()
        if modules.game_questlog and modules.game_questlog.show then
            modules.game_questlog.show()
        end
    end },
    { text = 'All options', action = function() close(); showTopMenu() end },
    { text = 'Logout', danger = true, action = function() close(); modules.game_interface.tryLogout() end },
}

-- The hub's front page
function openHub()
    if not hub then
        hub = g_ui.createWidget('HubSheet', rootWidget)
        hub.onClick = close
        hub.onEscape = close
        local panel = hub.panel
        panel.close.onClick = close
        panel.contrast.onClick = function()
            g_settings.set(CONTRAST_SETTING, not g_settings.getBoolean(CONTRAST_SETTING))
            applyContrast()
        end
    end
    -- sized for the screen as it is now (it may have turned since)
    local panel = hub.panel
    panel:setSize({ width = math.min(520, rootWidget:getWidth() - 16),
        height = math.max(280, math.min(600, rootWidget:getHeight() - 16)) })
    local cell = math.floor((panel:getWidth() - 20 - 12 - 18) / 5)
    panel.tabs:getLayout():setCellSize({ width = cell, height = 36 })
    applyContrast()
    hub:raise()
    hub:focus()
    local panel = hub.panel
    panel.title:setText(tr('Menu'))
    panel.back:setVisible(false)
    panel.tabs:setVisible(false)
    panel.tabs:setHeight(0)
    panel.tabs:destroyChildren()
    panel.list:destroyChildren()
    local grid = g_ui.createWidget('HubGrid', panel.list)
    local cell = math.floor((panel.list:getWidth() - 8) / 2)
    grid:getLayout():setCellSize({ width = cell, height = 56 })
    for _, entry in ipairs(HUB_BUTTONS) do
        if entry.danger then
            local button = g_ui.createWidget('HubLogout', panel.list)
            button.onClick = entry.action
        else
            local button = g_ui.createWidget('HubBigButton', grid)
            button:setText(tr(entry.text))
            button.onClick = entry.action
        end
    end
    -- (the icons' license asks for this)
    g_ui.createWidget('OtHint', panel.list):setText(tr('Icons by the game-icons.net artists (CC BY 3.0).'))
end

function closeHub()
    close()
end

function isHubOpen()
    return hub ~= nil
end
