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
                help = 'How big buttons, windows and the whole interface are drawn.' },
            { key = 'creatureInformationSize', kind = 'choice', text = 'Map text',
                choices = { { 80, 'Small' }, { 100, 'Normal' }, { 125, 'Large' } },
                help = 'How big names, health bars, speech and damage numbers are drawn over the map, in step with it. In whole steps, so the letters stay sharp.' },
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
            { id = 'turnFromCentre', kind = 'toggle', text = 'Turn from the centre',
                help = 'Touch the middle of the movement control and drag to turn without walking, like Ctrl+arrow. Touch outside the middle to walk.' },
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
                help = 'Drag pieces, panels too, to move them; - and + size them. Save keeps the changes, Cancel undoes them.' },
            { id = 'setupUi', kind = 'button', text = 'Place pieces one by one', buttonText = 'UI setup',
                help = 'Places the movement control, hotbar, backpack and chat one at a time, like on your first login.' },
            { id = 'hotbar', kind = 'button', text = 'Hotbar presets and rows', buttonText = 'Hotbar...',
                help = 'Number of presets (P button) and the extra rows of 3 above the 3x3 hotbar.' },
            { id = 'typing', kind = 'toggle', text = 'Typing suggestions',
                help = 'Words above the chat line while typing: your spells, what the NPC understands, names and words you used before. Gold ones send at once.' },
            { id = 'clearWords', kind = 'button', text = 'Forget the words you typed', buttonText = 'Clear',
                help = 'Typing suggestions learn the words you use. This forgets them.' },
            { id = 'resetUi', kind = 'button', text = 'Back to the default layout', buttonText = 'Reset UI',
                help = 'Puts every piece back in its first place and size and unpins all panels. Your hotbar stays.' },
        },
    },
    {
        id = 'optimization', text = 'Optimization', rows = {
            { id = 'sharpness', kind = 'choice', text = 'Sharpness',
                choices = { { 1, 'Normal' }, { 2, 'High' } },
                help = 'High draws with your screen\'s real pixels (up to 2x): sharper text and icons, but more work for the phone and more battery. Normal is the lightest.' },
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
local tasksTab -- the Tasks tab shown now (nil: another page)
local settingsShown -- Settings is the page shown now
local journalAsked -- the Journal's lists were asked for since the hub opened
local tasksListening

local function options()
    return modules.client_options
end

local function close()
    tasksTab = nil
    journalAsked = false
    settingsShown = false
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

-- The footer under the list (the Journal's filter): emptied for other pages
local function clearFooter()
    if hub then
        hub.panel.footer:destroyChildren()
        hub.panel.footer:setHeight(0)
    end
end

local function applyContrast()
    if hub then
        local on = g_settings.getBoolean(CONTRAST_SETTING)
        hub.panel:setOn(on)
        hub.panel.contrast:setChecked(on)
        hub.panel.contrast.icon:setImageSource(on and '/images/ui/ot/icons/contrast_on' or '/images/ui/ot/icons/contrast')
    end
end

-- Values that are not client options
local function rowValue(row)
    if row.key then
        return options().getOption(row.key)
    elseif row.id == 'movement' then
        return modules.game_joystick and modules.game_joystick.getStyle and modules.game_joystick.getStyle()
    elseif row.id == 'turnFromCentre' then
        return modules.game_joystick.getTurnFromCentre()
    elseif row.id == 'layoutMode' then
        return g_platform.getTouchMode()
    elseif row.id == 'viewSize' then
        return getViewSize()
    elseif row.id == 'typing' then
        return modules.client_typing.isEnabled()
    elseif row.id == 'sharpness' then
        return getSharpness()
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
    elseif row.id == 'turnFromCentre' then
        modules.game_joystick.setTurnFromCentre(value)
    elseif row.id == 'layoutMode' then
        setTouchMode(value)
    elseif row.id == 'viewSize' then
        setViewSize(value)
    elseif row.id == 'typing' then
        modules.client_typing.setEnabled(value)
    elseif row.id == 'sharpness' then
        setSharpness(value)
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
    elseif row.id == 'clearWords' then
        modules.client_typing.clearLearnedWords()
        showHelp('The learned words are forgotten.')
    end
end

local function rowAvailable(row)
    if row.key then
        return options() and options().getOption(row.key) ~= nil
    elseif row.id == 'movement' then
        return modules.game_joystick and modules.game_joystick.STYLES ~= nil
    elseif row.id == 'turnFromCentre' then
        return modules.game_joystick and modules.game_joystick.getTurnFromCentre ~= nil
    elseif row.id == 'controller' then
        return modules.client_gamepad and modules.client_gamepad.openBindWindow ~= nil and g_platform.isBrowser()
    elseif row.id == 'layoutMode' then
        return g_platform.isBrowser()
    elseif row.id == 'typing' or row.id == 'clearWords' then
        return modules.client_typing and modules.client_typing.isEnabled ~= nil
    elseif row.id == 'clientBuild' then
        return modules.client_updates and modules.client_updates.getBuildText and
            modules.client_updates.getBuildText() ~= nil
    end
    return true
end

local showSettings

-- The width rows get in a list (inside its padding)
local function listWidth(list)
    local rect = list:getPaddingRect()
    return rect.width > 0 and rect.width or list:getWidth()
end

-- The width a button needs for its text (font as styled), with room for its edge
local function neededWidth(button)
    return button:getTextSize().width + 20
end

-- A grid of buttons (tabs, the settings actions): as many columns as fit the
-- widest text, sharing the width; the rest wrap to more rows. Returns the
-- number of rows.
function fitButtonGrid(grid, width, spacing, cellHeight, maxCell)
    local children = grid:getChildren()
    local count = #children
    if count == 0 or width <= 0 then
        return 0
    end
    local need = 0
    for _, child in ipairs(children) do
        need = math.max(need, neededWidth(child))
    end
    local columns = count
    while columns > 1 and math.floor((width - spacing * (columns - 1)) / columns) < need do
        columns = columns - 1
    end
    local cell = math.floor((width - spacing * (columns - 1)) / columns)
    if maxCell then
        cell = math.min(cell, math.max(maxCell, need))
    end
    grid:getLayout():setCellSize({ width = cell, height = cellHeight })
    return math.ceil(count / columns)
end

-- The hub's tab row: its tabs share the width, in as many rows as they need
function fitHubTabs(tabs)
    local width = tabs:getWidth()
    if width <= 0 and tabs:getParent() then
        width = tabs:getParent():getWidth() - 20
    end
    local rows = fitButtonGrid(tabs, width, 4, 36, 160)
    tabs:setHeight(math.max(1, rows) * 36 + math.max(0, rows - 1) * 4)
end

-- A setting row whose title and controls don't fit side by side: a short
-- control (a switch, - value +, a button) keeps its place and the title
-- wraps beside it; a wide one (a row of choices) goes under the title, the
-- choices sharing the row's width
local function fitRow(widget, rowWidth, segments)
    local controls = widget.controls
    local title = widget.title
    local titleWidth = title:getTextSize().width
    -- margin, title, gap, ?, gap, controls, margin
    local beside = 4 + titleWidth + 8 + 22 + 12 + controls:getWidth() + 4
    if beside <= rowWidth then
        return
    end
    if not segments and controls:getWidth() <= rowWidth / 2 then
        local room = rowWidth - controls:getWidth() - 4 - 8 - 22 - 12 - 4
        title:setTextAutoResize(false)
        title:setTextWrap(true)
        title:setWidth(room)
        title:setTextVerticalAutoResize(true)
        local lines = math.ceil(titleWidth / room) + 1
        local lineHeight = math.max(14, title:getTextSize().height)
        widget:setHeight(math.max(52, lines * lineHeight + 16))
        return
    end
    -- title (and ?) on top, controls under it, the whole width
    title:breakAnchors()
    title:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    title:addAnchor(AnchorTop, 'parent', AnchorTop)
    title:setMarginTop(10)
    widget.help:breakAnchors()
    widget.help:addAnchor(AnchorLeft, 'title', AnchorRight)
    widget.help:addAnchor(AnchorVerticalCenter, 'title', AnchorVerticalCenter)
    controls:breakAnchors()
    controls:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    controls:addAnchor(AnchorRight, 'parent', AnchorRight)
    controls:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    controls:setMarginBottom(8)
    controls:setMarginLeft(4)
    controls:setMarginRight(4)
    controls:setWidth(rowWidth - 8)
    widget:setHeight(36 + 40 + 16)
    -- the choices share the controls' width as laid out (the segments sit
    -- edge to edge)
    if segments and #segments > 0 then
        local function share()
            if widget:isDestroyed() then
                return
            end
            local cell = math.floor(controls:getWidth() / #segments)
            for _, segment in ipairs(segments) do
                segment:setWidth(cell)
            end
        end
        share()
        addEvent(share)
    end
end

local function addRow(list, row)
    local widget = g_ui.createWidget('OtSettingRow', list)
    widget.title:setText(tr(row.text))
    widget.help.onClick = function()
        showHelp(row.help)
    end
    local controls = widget.controls
    local value = rowValue(row)
    local segments -- the choices of a choice row

    if row.kind == 'toggle' then
        local check = g_ui.createWidget('OtCheck', controls)
        check:setChecked(value and true or false)
        check.onCheckChange = function(widget, checked)
            setRowValue(row, checked)
        end
    elseif row.kind == 'choice' then
        -- a segmented control: every choice as wide as the widest, so the
        -- selected one looks no different in size
        segments = {}
        local width = 44
        for _, choice in ipairs(rowChoices(row)) do
            local button = g_ui.createWidget('OtButton', controls)
            button:setText(tr(choice[2]))
            width = math.max(width, neededWidth(button))
            button:setChecked(choice[1] == value)
            button.onClick = function()
                setRowValue(row, choice[1])
                showSettings(currentPage)
            end
            table.insert(segments, button)
        end
        for _, button in ipairs(segments) do
            button:setWidth(width)
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
        button:setWidth(math.max(110, neededWidth(button)))
        button.onClick = function()
            rowAction(row)
        end
    end
    -- the controls take the room they need; the title wraps beside them, or
    -- they go under it
    local width = 0
    for _, child in ipairs(controls:getChildren()) do
        width = width + child:getWidth() + 4
    end
    controls:setWidth(math.max(40, width - 4))
    fitRow(widget, listWidth(list), segments)
end

-- In Settings, above the tabs' rows: the layout and the rest of the options
local SETTINGS_ACTIONS = {
    { text = 'Hotbar', action = function() close(); openHotbarSettings() end },
    { text = 'Edit layout', action = function() close(); startEditLayout() end },
    { text = 'All options', action = function() close(); showTopMenu() end },
    { text = 'Report a problem', action = function()
        close()
        if modules.client_report then
            modules.client_report.open()
        end
    end },
}

-- One settings tab
showSettings = function(pageId)
    if not hub then
        return
    end
    tasksTab = nil
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
    fitHubTabs(panel.tabs)
    -- keep the place when a setting changed; from another page start at the top
    local scroll = settingsShown and panel.listScroll:getValue() or 0
    settingsShown = true
    panel.list:destroyChildren()
    clearFooter()
    local actions = g_ui.createWidget('HubSettingsActions', panel.list)
    for _, entry in ipairs(SETTINGS_ACTIONS) do
        local button = g_ui.createWidget('OtButton', actions)
        button:setText(tr(entry.text))
        button.onClick = entry.action
    end
    -- three a row where they fit, else fewer (the longest text decides)
    local columnsWidth = listWidth(panel.list)
    fitButtonGrid(actions, columnsWidth, 6, 40, math.floor((columnsWidth - 2 * 6) / 3))
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

-- Tasks (ot-client#44): the daily hunt and, later, other tasks; the pages
-- come from client_tasks and redraw when the server sends news
local function tasks()
    return modules.client_tasks
end

local showTasks
local function refreshTasks()
    if hub and tasksTab then
        showTasks(tasksTab)
    end
end

-- pageId: 'daily' (its own hub button) or 'journal' (tabs), ot-client#58
local tasksPage = 'journal'
showTasks = function(tabId, pageId)
    if not hub or not tasks() then
        return
    end
    pageId = pageId or tasksPage
    tasksPage = pageId
    local page = tasks().PAGES and tasks().PAGES[pageId] or { title = 'Tasks', tabs = tasks().TABS }
    if not tasksListening then
        tasksListening = true
        tasks().addListener(refreshTasks)
    end
    local opening = tasksTab ~= tabId
    tasksTab = tabId
    settingsShown = false
    local panel = hub.panel
    panel.title:setText(tr(page.title))
    panel.back:setText('< ' .. tr('Hub'))
    panel.back:setVisible(true)
    panel.back.onClick = function()
        openHub()
    end
    panel.tabs:destroyChildren()
    -- one tab needs no tab row
    local tabbed = #page.tabs > 1
    panel.tabs:setVisible(tabbed)
    panel.tabs:setHeight(tabbed and 36 or 0)
    if tabbed then
        for _, tab in ipairs(page.tabs) do
            local button = g_ui.createWidget('OtTab', panel.tabs)
            button:setText(tr(tab.text))
            button:setChecked(tab.id == tabId)
            button.onClick = function()
                showTasks(tab.id, pageId)
            end
        end
        -- the tabs share the width (up to 160 each), in more rows if their
        -- names need it
        fitHubTabs(panel.tabs)
    end
    panel.list:destroyChildren()
    clearFooter()
    -- the Journal's filter, in the footer (it stays put while the list
    -- scrolls): region (Quests and Chests) and Show completed
    if page.filter and (tabId == 'quests' or tabId == 'chests') then
        local region, completed = tasks().getFilter()
        local filter = g_ui.createWidget('JournalFilter', panel.footer)
        filter:fill('parent')
        panel.footer:setHeight(46)
        filter.region:setText(region or tr('All regions'))
        filter.region.onClick = function()
            -- cycle: all, then each region
            local list = tasks().getRegions()
            local index = 0
            for i, name in ipairs(list) do
                if name == region then
                    index = i
                end
            end
            local nextRegion = list[index + 1]
            tasks().setFilter(nextRegion, completed)
            showTasks(tabId, pageId)
        end
        filter.completed:setChecked(completed)
        local function toggleCompleted()
            tasks().setFilter(region, not completed)
            showTasks(tabId, pageId)
        end
        filter.completed.onClick = toggleCompleted
        filter.completedLabel.onClick = toggleCompleted
        if tabId == 'quests' then
            -- quests have no region (yet): only Show completed
            filter.label:setVisible(false)
            filter.region:setVisible(false)
            filter.completed:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            filter.completed:setMarginLeft(0)
        end
    end
    tasks().render(tabId, panel.list)
    if opening then
        tasks().request()
        if page.filter and tasks().requestJournal and not journalAsked then
            journalAsked = true
            tasks().requestJournal()
        end
    end
end

-- A page of its own under the hub (the character sheet, character.lua): the
-- title and "< Hub", no tabs, an empty list to fill. nil when the hub is closed.
function hubPage(title)
    if not hub then
        return nil
    end
    tasksTab = nil
    settingsShown = false
    local panel = hub.panel
    panel.title:setText(title)
    panel.back:setText('< ' .. tr('Hub'))
    panel.back:setVisible(true)
    panel.back.onClick = function()
        openHub()
    end
    panel.tabs:destroyChildren()
    panel.tabs:setVisible(false)
    panel.tabs:setHeight(0)
    panel.list:destroyChildren()
    -- (the Journal's filter lives in the footer)
    clearFooter()
    panel.listScroll:setValue(0)
    return panel.list, panel
end

-- The front page (ot-client#60): sections of four icon buttons. icon: a game
-- item shown on the button; character: the player's outfit and level.
-- Without an action the button shows "Soon".

local HUB_SECTIONS = {
    { title = 'ADVENTURE', buttons = {
        { text = 'Character', character = true, action = function() showCharacter() end },
        { text = 'Journal', icon = 2816, action = function() showTasks('quests', 'journal') end },
        -- the full hunt report (stats, monsters, loot, supplies, past hunts)
        { text = 'Hunt', icon = 3264, action = function()
            close()
            if modules.client_hunt and modules.client_hunt.openReport then
                modules.client_hunt.openReport()
            end
        end },
        { text = 'Daily', icon = 3218, action = function() showTasks('daily', 'daily') end },
    } },
    { title = 'SOCIAL', buttons = {
        { text = 'Party', icon = 6578 },
        { text = 'Guild', icon = 3415 },
        { text = 'Channels', icon = 3505, action = function() close(); g_game.requestChannels() end },
    } },
    { title = 'HOME & SETTINGS', buttons = {
        { text = 'House', icon = 5801 },
        { text = 'Automations', icon = 2906, action = function()
            close()
            if modules.client_automations and modules.client_automations.open then
                modules.client_automations.open()
            end
        end },
        { text = 'Ignore List', icon = 3114 },
        { text = 'Settings', icon = 3460, action = function() showSettings(currentPage or 'gameplay') end },
    } },
}

-- "Premium account | Time 13:00"
local function statusText()
    local player = g_game.getLocalPlayer()
    local premium = player and player:isPremium()
    return string.format('{%s, %s}{   |   Time , #a8a8a8}{%s, #e0b84c}',
        premium and tr('Premium account') or tr('Free account'),
        premium and '#70d070' or '#e8e8e8',
        os.date('%H:%M'))
end

-- The sheet sized for the screen as it is now (it may have turned since)
local function fitPanel()
    hub.panel:setSize({ width = math.min(520, rootWidget:getWidth() - 16),
        height = math.max(280, math.min(600, rootWidget:getHeight() - 16)) })
end

-- After a new screen size on a page with tabs: they share the new width
local function fitTabs()
    local tabs = hub.panel.tabs
    if #tabs:getChildren() > 0 then
        fitHubTabs(tabs)
        -- (settings rows are laid out for the width: lay them out again)
        if settingsShown then
            showSettings(currentPage)
        end
    end
end

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
        -- The screen turned or resized while open: fit it again (the front
        -- page is built for its width, so it is built again)
        hub.onGeometryChange = function(widget, oldRect, newRect)
            -- (not its first layout, nor a move)
            if oldRect.width <= 0 or (oldRect.width == newRect.width and oldRect.height == newRect.height) then
                return
            end
            addEvent(function()
                if hub ~= widget then
                    return
                end
                -- (the front page is the one without a way back)
                if not hub.panel.back:isVisible() then
                    openHub()
                else
                    fitPanel()
                    -- (once the tabs row has its new width)
                    addEvent(function()
                        if hub == widget then
                            fitTabs()
                        end
                    end)
                end
            end)
        end
    end
    fitPanel()
    local cell = math.floor((hub.panel:getWidth() - 20 - 12 - 18) / 5)
    hub.panel.tabs:getLayout():setCellSize({ width = cell, height = 36 })
    applyContrast()
    hub:raise()
    hub:focus()
    local panel = hub.panel
    tasksTab = nil
    settingsShown = false
    panel.title:setText(tr('Hub'))
    panel.back:setVisible(false)
    panel.tabs:setVisible(false)
    panel.tabs:setHeight(0)
    panel.tabs:destroyChildren()
    panel.list:destroyChildren()
    clearFooter()
    local status = g_ui.createWidget('HubStatus', panel.list)
    status:setColoredText(statusText())
    local width = panel.list:getWidth()
    -- four a row; two when a name doesn't fit a quarter (a narrow portrait
    -- screen), so the sections stay even
    local cell = math.floor((width - 3 * 8) / 4)
    for _, section in ipairs(HUB_SECTIONS) do
        for _, entry in ipairs(section.buttons) do
            local probe = g_ui.createWidget('HubIconButton', panel.list)
            probe:setText(tr(entry.text))
            if neededWidth(probe) > cell then
                cell = math.floor((width - 8) / 2)
            end
            probe:destroy()
        end
    end
    for _, section in ipairs(HUB_SECTIONS) do
        g_ui.createWidget('HubSection', panel.list).text:setText(tr(section.title))
        local grid = g_ui.createWidget('HubIconGrid', panel.list)
        grid:getLayout():setCellSize({ width = cell, height = 78 })
        for _, entry in ipairs(section.buttons) do
            local button = g_ui.createWidget('HubIconButton', grid)
            button:setText(tr(entry.text))
            if entry.character then
                local player = g_game.getLocalPlayer()
                button.item:setVisible(false)
                if player then
                    button.creature:setOutfit(player:getOutfit())
                    button.creature:setDirection(Directions.South)
                    button.creature:setVisible(true)
                    button.badge:setText('Lv ' .. player:getLevel())
                    button.badge:setVisible(true)
                end
            else
                button.item:setItemId(entry.icon)
            end
            if entry.action then
                button.onClick = entry.action
            else
                button:setEnabled(false)
                button.soon:setVisible(true)
            end
        end
    end
    local logout = g_ui.createWidget('HubLogout', panel.list)
    logout.onClick = function()
        close()
        modules.game_interface.tryLogout()
    end
    -- (the toolbar icons' license asks for this)
    g_ui.createWidget('OtHint', panel.list):setText(tr('Icons by the game-icons.net artists (CC BY 3.0).'))
end

function closeHub()
    close()
end

function isHubOpen()
    return hub ~= nil
end
