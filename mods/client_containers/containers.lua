-- Containers on touch screens (ot-client#22): one small window holds every
-- open container as a tab, instead of a window per container.
--   - The shown container is a 4-wide grid in portrait, 5-wide in landscape
--     (a backpack 4x5 / 5x4, a bag 4x2).
--   - Tapping a container in it opens that one as a new tab, so both stay
--     open. x on a tab closes it; the tabs scroll sideways (>, or the list).
--   - Containers on the ground (corpses, chests) open as a red tab in the
--     background, with the number of items, so nothing pops up over the game.
--   - Tap an item: use it (eat, drink); runes, ropes and the like then ask for
--     a target. Long press: the item menu. Drag: onto a slot to move, reorder
--     or stack, onto a tab to put it in that container. Moving a stack asks
--     how many (the move sheet), with < name > to pick another container.
--   - Long press a tab: name it (kept on this device for the character),
--     close it, or close the others.
-- The classic container windows (game_containers) still exist but are kept
-- out of sight.

local NAMES_SETTING = 'client_containers_names'
local SLOT = 34
local SPACING = 0

local window
local holder -- the classic container windows, hidden
local tabs = {} -- { container = c, key = 'inv3/7' or nil, ground = bool, seen = n }
local shown -- container id
local firstTab = 1
local menu, moveSheet, renameSheet
local savedMoveStackable, savedUse, savedOpen

local function root()
    return modules.game_interface.getRootPanel()
end

local function portrait()
    local r = root()
    return r:getHeight() > r:getWidth()
end

-- Names -----------------------------------------------------------------------

local function namesNode()
    local name = g_game.getCharacterName()
    if not name or name == '' then
        return nil
    end
    local all = g_settings.getNode(NAMES_SETTING) or {}
    all[name] = all[name] or {}
    return all, all[name]
end

local function tabFor(id)
    for index, tab in ipairs(tabs) do
        if tab.container:getId() == id then
            return tab, index
        end
    end
end

-- Where an opened container came from: the client is not told, so the
-- position of the last container item used or opened is kept (g_game.use and
-- g_game.open are wrapped in init)
local pendingPosition

local function rememberOpening(item)
    if item and item.isContainer and item:isContainer() then
        pendingPosition = item:getPosition()
    end
end

-- A key for a container's name from where it sits: "inv3" (inventory slot 3)
-- or the parent's key and the slot ("inv3/7"). Nil for one on the ground.
local function locationKey(pos)
    if not pos or pos.x ~= 65535 then
        return nil
    end
    if pos.y < 64 then
        return 'inv' .. pos.y
    end
    local parent = tabFor(pos.y - 64)
    if parent and parent.key then
        return parent.key .. '/' .. pos.z
    end
    return nil
end

-- Where to move an item to put it in a container: its first free slot.
-- (Slot 0 may hold a bag, and a move onto a bag puts the item inside it.)
local function intoPosition(container)
    local slot = math.min(container:getItemsCount(), math.max(0, container:getCapacity() - 1))
    return { x = 65535, y = 64 + container:getId(), z = slot }
end

local function displayName(tab)
    local _, names = namesNode()
    local custom = names and tab.key and names[tab.key]
    if custom and custom ~= '' then
        return custom
    end
    local name = tab.container:getName() or ''
    return name:gsub('^%l', string.upper)
end

-- Layout ----------------------------------------------------------------------

local render

-- 4 columns in portrait, 5 in landscape, 4 when 5 do not fit the area
-- beside the game view (client_mobile)
local function columns()
    if portrait() then
        return 4
    end
    local mobile = modules.client_mobile
    local area = mobile and mobile.getModuleColumnWidth and mobile.getModuleColumnWidth()
    if area and 5 * (SLOT + SPACING) + 12 > area then
        return 4
    end
    return 5
end

local function fit()
    local cols = columns()
    local tab = shown and tabFor(shown)
    local capacity = tab and tab.container:getCapacity() or 0
    local rows = math.max(1, math.ceil(capacity / cols))
    local grid = window:getChildById('grid')
    grid:getLayout():setNumColumns(cols)
    local gridWidth = cols * (SLOT + SPACING) - SPACING
    grid:setSize({ width = gridWidth, height = rows * (SLOT + SPACING) - SPACING })
    window:setWidth(gridWidth + window:getPaddingLeft() + window:getPaddingRight())
    local height = 24 + 4 + 28 + 4 + (tab and grid:getHeight() or 56)
    if window.minimized then
        height = 24 + 4 + 28
    end
    window:setHeight(height + window:getPaddingTop() + window:getPaddingBottom())
end

local function useItem(item)
    if item:isContainer() then
        g_game.open(item, nil)
    elseif item:isMultiUse() then
        modules.game_interface.startUseWith(item)
    else
        g_game.use(item)
    end
end

local openMenu, openMove

local function renderGrid()
    local grid = window:getChildById('grid')
    grid:destroyChildren()
    local tab = shown and tabFor(shown)
    window:getChildById('empty'):setVisible(tab == nil)
    grid:setVisible(tab ~= nil and not window.minimized)
    if not tab then
        return
    end
    local container = tab.container
    for slot = 0, container:getCapacity() - 1 do
        local widget = g_ui.createWidget('ContainersSlot', grid)
        widget:setId('slot' .. slot)
        widget.position = container:getSlotPosition(slot)
        local item = container:getItem(slot)
        widget:setItem(item)
        widget.onMouseRelease = function(self, mousePos, mouseButton)
            if not self:containsPoint(mousePos) or g_ui.getDraggingWidget() then
                return false
            end
            local current = self:getItem()
            if not current then
                return true
            end
            if mouseButton == MouseRightButton then
                openMenu(current, tab)
            else
                useItem(current)
            end
            return true
        end
    end
    tab.seen = container:getItemsCount()
end

local function renderTabs()
    local strip = window:getChildById('strip')
    local row = strip:getChildById('tabs')
    row:destroyChildren()
    firstTab = math.max(1, math.min(firstTab, #tabs))
    for index = firstTab, #tabs do
        local tab = tabs[index]
        local widget = g_ui.createWidget('ContainersTab', row)
        local unseen = tab.ground and tab.container:getId() ~= shown and tab.container:getItemsCount() or 0
        widget:setText(displayName(tab) .. (unseen > 0 and ' (' .. unseen .. ')' or '') .. '  x')
        widget:setWidth(widget:getTextSize().width + 12)
        widget:setOn(tab.container:getId() == shown)
        widget:setChecked(tab.ground)
        widget.onMouseRelease = function(self, mousePos, mouseButton)
            if not self:containsPoint(mousePos) then
                return false
            end
            if mouseButton == MouseRightButton then
                openMenu(nil, tab)
            elseif mousePos.x > self:getX() + self:getWidth() - 18 then
                -- the x
                g_game.close(tab.container)
            else
                shown = tab.container:getId()
                render()
            end
            return true
        end
        -- drop an item on a tab: into that container
        widget.onDrop = function(self, dragged, mousePos)
            local item = dragged and dragged.currentDragThing
            if not item or not item:isItem() then
                return false
            end
            local toPos = intoPosition(tab.container)
            if item:getCount() > 1 then
                openMove(item, toPos)
            else
                g_game.move(item, toPos, 1)
            end
            return true
        end
    end
    -- the tabs that do not fit wait behind >
    local more = strip:getChildById('more')
    addEvent(function()
        if not window then
            return
        end
        local hidden = 0
        local limit = strip:getX() + strip:getWidth() - more:getWidth() - 3
        local shownHidden
        for offset, child in ipairs(row:getChildren()) do
            -- (once one does not fit, neither do the ones after it)
            if hidden > 0 or child:getX() + child:getWidth() > limit then
                hidden = hidden + 1
                child:setVisible(false)
                local tab = tabs[firstTab + offset - 1]
                if tab and tab.container:getId() == shown then
                    shownHidden = firstTab + offset - 1
                end
            end
        end
        -- the container shown always has its tab in view
        if shownHidden then
            firstTab = shownHidden
            renderTabs()
            return
        end
        hidden = hidden + (firstTab - 1)
        more:setVisible(hidden > 0)
        more:setText('+' .. hidden .. ' >')
    end)
end

render = function()
    if not window then
        return
    end
    renderTabs()
    renderGrid()
    fit()
end

-- Menus -----------------------------------------------------------------------

local function closeMenu()
    if menu then
        menu:destroy()
        menu = nil
    end
end

local function addMenuButton(rows, text, action, style)
    local button = g_ui.createWidget(style or 'OtButton', rows)
    button:setText(tr(text))
    button.onClick = function()
        closeMenu()
        action()
    end
    return button
end

local function placeNear(panel, anchor)
    local r = rootWidget:getRect()
    panel:setHeight(panel:getChildById('rows'):getHeight() + 28 + 4 + panel:getPaddingTop() + panel:getPaddingBottom())
    local x = anchor.x + 10
    local y = anchor.y
    panel:setPosition({ x = math.max(4, math.min(x, r.width - panel:getWidth() - 4)),
        y = math.max(4, math.min(y, r.height - panel:getHeight() - 4)) })
end

local openRename

-- The item menu (item given) or the tab menu (item nil)
openMenu = function(item, tab)
    closeMenu()
    menu = g_ui.createWidget('ContainersMenu', rootWidget)
    menu.onClick = closeMenu
    menu.onEscape = closeMenu
    local panel = menu:getChildById('panel')
    local rows = panel:getChildById('rows')
    if item then
        local count = item:getCount() > 1 and (' x' .. item:getCount()) or ''
        local name = item.getName and item:getName() or ''
        -- (7.92 items have no names in the client: from the item data)
        local entry = name == '' and modules.client_itemdata and modules.client_itemdata.getItem(item:getId())
        if entry then
            name = entry.n:gsub('^%l', string.upper)
        end
        panel:getChildById('title'):setText((name ~= '' and name or tr('Item')) .. count)
        addMenuButton(rows, 'Look', function() g_game.look(item) end)
        if item:isContainer() then
            addMenuButton(rows, 'Open in a new tab', function() g_game.open(item, nil) end)
        elseif item:isMultiUse() then
            addMenuButton(rows, 'Use with...', function() modules.game_interface.startUseWith(item) end)
        else
            addMenuButton(rows, 'Use', function() g_game.use(item) end)
        end
        if not item:isContainer() then
            local pair = g_ui.createWidget('ContainersMenuPair', rows)
            addMenuButton(pair, 'Left hand', function()
                g_game.move(item, { x = 65535, y = InventorySlotLeft, z = 0 }, item:getCount())
            end)
            addMenuButton(pair, 'Right hand', function()
                g_game.move(item, { x = 65535, y = InventorySlotRight, z = 0 }, item:getCount())
            end)
        end
        addMenuButton(rows, 'Move to...', function() openMove(item, nil) end)
        if item:isPickupable() then
            addMenuButton(rows, 'Trade with...', function() modules.game_interface.startTradeWith(item) end)
        end
    else
        panel:getChildById('title'):setText(displayName(tab))
        if tab.key then
            addMenuButton(rows, 'Rename', function() openRename(tab) end, 'OtButtonPrimary')
        end
        addMenuButton(rows, 'Close', function() g_game.close(tab.container) end)
        addMenuButton(rows, 'Close all others', function()
            for _, other in ipairs(tabs) do
                if other ~= tab then
                    g_game.close(other.container)
                end
            end
        end)
        addMenuButton(rows, 'Close all', function()
            for _, other in ipairs(tabs) do
                g_game.close(other.container)
            end
        end, 'OtButtonDanger')
    end
    addEvent(function()
        if menu then
            placeNear(panel, g_window.getMousePosition())
            -- what the item is and who buys it (client_itemdata), above the
            -- menu, or below it when there is no room
            local itemData = modules.client_itemdata
            if item and itemData and itemData.isReady() then
                local card = g_ui.createWidget('ItemCard', menu)
                local fluid = item:isFluidContainer() and item:getSubType() > 0 and item:getSubType() or nil
                if itemData.fillCard(card, item:getId(), fluid) then
                    -- above the menu, below it, or beside it: wherever it fits
                    local screen = rootWidget:getRect()
                    local x, y = panel:getX(), panel:getY() - card:getHeight() - 4
                    card:setWidth(panel:getWidth())
                    if y < 4 then
                        y = panel:getY() + panel:getHeight() + 4
                    end
                    if y + card:getHeight() > screen.height - 4 then
                        card:setWidth(230)
                        y = math.max(4, math.min(panel:getY(), screen.height - card:getHeight() - 4))
                        x = panel:getX() + panel:getWidth() + 4
                        if x + card:getWidth() > screen.width - 4 then
                            x = panel:getX() - card:getWidth() - 4
                        end
                    end
                    card:setPosition({ x = math.max(4, x), y = y })
                else
                    card:destroy()
                end
            end
        end
    end)
end

-- The move sheet: how many (for a stack) and where to. toPos given: that
-- place (a drop); nil: an open container chosen with < and >
openMove = function(item, toPos)
    if moveSheet then
        moveSheet:destroy()
    end
    moveSheet = g_ui.createWidget('ContainersMoveSheet', rootWidget)
    local panel = moveSheet:getChildById('panel')
    local function close()
        if moveSheet then
            moveSheet:destroy()
            moveSheet = nil
        end
    end
    moveSheet.onClick = close
    moveSheet.onEscape = close
    panel:getChildById('close').onClick = close
    panel:getChildById('cancel').onClick = close
    panel:getChildById('item'):setItem(item)
    local name = item.getName and item:getName() or ''
    panel:getChildById('title'):setText(tr('Move') .. ' ' .. (name ~= '' and name or tr('item')))

    -- how many
    local total = math.max(1, item:getCount())
    local amount = panel:getChildById('amount')
    local countLabel = panel:getChildById('count')
    amount:setMaximum(total)
    amount:setValue(total)
    local function showCount()
        countLabel:setText(amount:getValue() .. '/' .. total)
    end
    amount.onValueChange = showCount
    showCount()
    panel:getChildById('less').onClick = function() amount:setValue(math.max(1, amount:getValue() - 1)) end
    panel:getChildById('more').onClick = function() amount:setValue(math.min(total, amount:getValue() + 1)) end
    for _, id in ipairs({ 'less', 'amount', 'more', 'count' }) do
        panel:getChildById(id):setVisible(total > 1)
    end
    if total == 1 then
        -- no count row: the target row moves up into its place
        panel:getChildById('prev'):addAnchor(AnchorTop, 'item', AnchorBottom)
        panel:setHeight(panel:getHeight() - 48)
    end

    -- where to
    local targets = {}
    local from = item:getPosition()
    for _, tab in ipairs(tabs) do
        if not (from and from.x == 65535 and from.y == 64 + tab.container:getId()) then
            table.insert(targets, tab)
        end
    end
    local choice = 1
    if shown then
        for index, tab in ipairs(targets) do
            if tab.container:getId() == shown then
                choice = index
            end
        end
    end
    local target = panel:getChildById('target')
    target:setOn(true)
    local function showTarget()
        if toPos then
            -- dropped on a tab or slot of an open container: name it
            local tab = toPos.x == 65535 and toPos.y >= 64 and tabFor(toPos.y - 64)
            target:setText(tab and displayName(tab) or tr('Here'))
        elseif #targets == 0 then
            target:setText(tr('No other container open'))
        else
            target:setText(displayName(targets[choice]))
        end
    end
    panel:getChildById('prev').onClick = function()
        choice = choice > 1 and choice - 1 or #targets
        showTarget()
    end
    panel:getChildById('next').onClick = function()
        choice = choice < #targets and choice + 1 or 1
        showTarget()
    end
    for _, id in ipairs({ 'prev', 'next' }) do
        panel:getChildById(id):setVisible(toPos == nil and #targets > 1)
    end
    showTarget()

    panel:getChildById('ok').onClick = function()
        local to = toPos or (targets[choice] and intoPosition(targets[choice].container))
        if to then
            g_game.move(item, to, amount:getValue())
        end
        close()
    end
    panel:setPosition({ x = math.floor((rootWidget:getWidth() - panel:getWidth()) / 2),
        y = math.max(4, math.min(math.floor(rootWidget:getHeight() * 0.55),
            rootWidget:getHeight() - panel:getHeight() - 4)) })
end

openRename = function(tab)
    if renameSheet then
        renameSheet:destroy()
    end
    renameSheet = g_ui.createWidget('ContainersRenameSheet', rootWidget)
    local panel = renameSheet:getChildById('panel')
    local edit = panel:getChildById('name')
    edit:setText(displayName(tab))
    edit:focus()
    local function close()
        if renameSheet then
            renameSheet:destroy()
            renameSheet = nil
        end
    end
    local function save()
        local all, names = namesNode()
        if all and tab.key then
            local text = edit:getText():trim()
            names[tab.key] = text ~= '' and text or nil
            g_settings.setNode(NAMES_SETTING, all)
            g_settings.save()
        end
        close()
        render()
    end
    renameSheet.onEscape = close
    renameSheet.onEnter = save
    panel:getChildById('cancel').onClick = close
    panel:getChildById('ok').onClick = save
end

-- Containers ------------------------------------------------------------------

local function hideClassicWindow(container)
    if container.window then
        container.window:setParent(holder)
        container.window:hide()
    end
end

local function onOpen(container, previousContainer)
    hideClassicWindow(container)
    local pos = pendingPosition
    pendingPosition = nil
    local ground
    if pos then
        ground = pos.x ~= 65535
    else
        -- not opened by the player (a reconnect): what cannot be carried
        -- (corpses, chests) is on the ground
        local item = container:getContainerItem()
        ground = not (item and item:isPickupable())
    end
    local entry = { container = container, ground = ground }
    local replaced = previousContainer and tabFor(previousContainer:getId())
    if replaced then
        local _, index = tabFor(previousContainer:getId())
        tabs[index] = entry
    else
        local existing, index = tabFor(container:getId())
        if existing then
            tabs[index] = entry
        else
            table.insert(tabs, entry)
        end
    end
    entry.key = locationKey(pos)
    -- the ground ones (corpses) wait in the background
    if not ground or not shown then
        shown = container:getId()
        -- keep the new tab in view
        local _, index = tabFor(shown)
        if index and index > firstTab + 2 then
            firstTab = index - 2
        end
    end
    if window then
        window:show()
        window:raise()
    end
    render()
end

local function onClose(container)
    local _, index = tabFor(container:getId())
    if not index then
        return
    end
    table.remove(tabs, index)
    if shown == container:getId() then
        local next = tabs[math.min(index, #tabs)]
        shown = next and next.container:getId() or nil
    end
    render()
end

local function onChange(container)
    if not window then
        return
    end
    if container:getId() == shown then
        renderGrid()
        fit()
    end
    renderTabs()
end

local function onUpdateItem(container, slot, item)
    if container:getId() == shown and window then
        local widget = window:getChildById('grid'):getChildById('slot' .. slot)
        if widget then
            widget:setItem(item)
            return
        end
    end
    onChange(container)
end

local function onGameEnd()
    tabs = {}
    shown = nil
    firstTab = 1
    closeMenu()
    if window then
        render()
    end
end

-- Showing and hiding (the toolbar's containers button)
function toggle()
    if not window then
        return
    end
    if window:isVisible() then
        window:hide()
    else
        window:show()
        window:raise()
        render()
    end
end

-- The open containers you named, as { name = 'Loot', container = c }
-- (client_automations puts loot there)
function getNamedContainers()
    local _, names = namesNode()
    local list = {}
    for _, tab in ipairs(tabs) do
        local custom = names and tab.key and names[tab.key]
        if custom and custom ~= '' and not tab.container:isClosed() then
            table.insert(list, { name = custom, container = tab.container })
        end
    end
    return list
end

-- Whether an open container is on the ground (a corpse), as far as known
function isGroundContainer(container)
    local tab = tabFor(container:getId())
    if tab then
        return tab.ground
    end
end

function getWindow()
    return window
end

function relayout()
    if window then
        render()
    end
end

local function openList()
    closeMenu()
    menu = g_ui.createWidget('ContainersMenu', rootWidget)
    menu.onClick = closeMenu
    menu.onEscape = closeMenu
    local panel = menu:getChildById('panel')
    panel:getChildById('title'):setText(tr('Open containers'))
    local rows = panel:getChildById('rows')
    for index, tab in ipairs(tabs) do
        local button = addMenuButton(rows, displayName(tab), function()
            shown = tab.container:getId()
            firstTab = index
            render()
        end)
        button:setOn(tab.container:getId() == shown)
    end
    if #tabs == 0 then
        g_ui.createWidget('OtHint', rows):setText(tr('No container open.'))
    end
    addEvent(function()
        if menu then
            placeNear(panel, g_window.getMousePosition())
        end
    end)
end

function init()
    if not g_platform.isMobile() then
        return
    end
    g_ui.importStyle('containers')
    holder = g_ui.createWidget('UIWidget', rootWidget)
    holder:setVisible(false)
    -- on the top layer, with the joystick and look/use/attack/follow
    window = g_ui.createWidget('ContainersWindow', rootWidget)
    window:setPosition({ x = 4, y = 4 })
    window:hide()
    local head = window:getChildById('head')
    head:getChildById('minimize').onClick = function()
        window.minimized = not window.minimized
        render()
    end
    head:getChildById('list').onClick = openList
    window:getChildById('strip'):getChildById('more').onClick = function()
        firstTab = firstTab < #tabs and firstTab + 1 or 1
        renderTabs()
    end

    -- remember where opened containers come from
    savedUse, savedOpen = g_game.use, g_game.open
    g_game.use = function(item, ...)
        rememberOpening(item)
        return savedUse(item, ...)
    end
    g_game.open = function(item, ...)
        rememberOpening(item)
        return savedOpen(item, ...)
    end

    -- moving a stack (a drop on a slot) asks with the move sheet
    savedMoveStackable = modules.game_interface.moveStackableItem
    modules.game_interface.moveStackableItem = function(item, toPos)
        openMove(item, toPos)
    end

    connect(Container, { onOpen = onOpen, onClose = onClose, onSizeChange = onChange,
        onAddItem = onChange, onRemoveItem = onChange, onUpdateItem = onUpdateItem })
    connect(g_game, { onGameEnd = onGameEnd })
    connect(root(), { onGeometryChange = relayout })
    for _, container in pairs(g_game.getContainers()) do
        onOpen(container)
    end
end

function terminate()
    if not window then
        return
    end
    disconnect(Container, { onOpen = onOpen, onClose = onClose, onSizeChange = onChange,
        onAddItem = onChange, onRemoveItem = onChange, onUpdateItem = onUpdateItem })
    disconnect(g_game, { onGameEnd = onGameEnd })
    disconnect(root(), { onGeometryChange = relayout })
    if savedUse then
        g_game.use, g_game.open = savedUse, savedOpen
        savedUse, savedOpen = nil, nil
    end
    if savedMoveStackable then
        modules.game_interface.moveStackableItem = savedMoveStackable
        savedMoveStackable = nil
    end
    closeMenu()
    for _, sheet in ipairs({ moveSheet, renameSheet }) do
        if sheet then
            sheet:destroy()
        end
    end
    window:destroy()
    window = nil
    holder:destroy()
    holder = nil
end
