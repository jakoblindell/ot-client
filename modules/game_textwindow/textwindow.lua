local windows = {}

-- On a phone, the on-screen keyboard covers the lower part of the game. The
-- page tells which part is still visible (shell.html: keyboardVisibleTop and
-- keyboardVisibleBottom, fractions of the screen's height, set only while the
-- keyboard is open). A text window moves into that part and shrinks to fit,
-- so its text and its buttons stay in reach; it goes back to the middle when
-- the keyboard closes. A window also never reaches past the screen.
local SCREEN_MARGIN = 4
local KEYBOARD_CHECK_MS = 250
local keyboardCheck

local function visibleArea()
    local root = rootWidget
    local top = tonumber(g_platform.getBrowserConfigString('keyboardVisibleTop'))
    local bottom = tonumber(g_platform.getBrowserConfigString('keyboardVisibleBottom'))
    local y, height = root:getY(), root:getHeight()
    if not top or not bottom or bottom <= top then
        return y, y + height, false
    end
    return y + math.floor(height * top), y + math.floor(height * bottom), true
end

local function fitWindow(window, areaTop, areaBottom, keyboard)
    local root = rootWidget
    if not root or window:isDestroyed() then
        return
    end
    local available = areaBottom - areaTop - 2 * SCREEN_MARGIN
    local height = math.max(0, math.min(window.designHeight, available))
    if height ~= window:getHeight() then
        window:setHeight(height)
    end
    if keyboard then
        window:breakAnchors()
        window:setX(root:getX() + math.floor((root:getWidth() - window:getWidth()) / 2))
        window:setY(areaTop + SCREEN_MARGIN + math.floor((available - height) / 2))
        window.keyboardPlaced = true
    elseif window.keyboardPlaced then
        window.keyboardPlaced = false
        window:centerIn('parent')
    else
        window:bindRectToParent()
    end
end

-- Touch layouts (ot-client#124, option 1): a small modal over the dimmed game
-- (TouchTextWindow): 16 px from the screen's edges in portrait, 470 px wide
-- in landscape, at most 400 px high. While the keyboard is open it sits at
-- the top of the part still visible and its text shrinks, so Save and close
-- stay in reach. With little height (landscape with the keyboard) title,
-- Save and close share one header row over the text.
local TOUCH_MARGIN = 16
local TOUCH_KEYBOARD_MARGIN = 6
local TOUCH_LANDSCAPE_WIDTH = 470
local TOUCH_MAX_HEIGHT = 400
local TOUCH_COMPACT_BELOW = 220

local function setTouchCompact(window, compact)
    if window.compact == compact then
        return
    end
    window.compact = compact
    local panel = window.panel
    local title = panel:getChildById('title')
    local writer = panel:getChildById('writer')
    local paper = panel:getChildById('paper')
    local count = panel:getChildById('count')
    local save = panel:getChildById('saveButton')

    title:breakAnchors()
    title:addAnchor(AnchorVerticalCenter, 'closeButton', AnchorVerticalCenter)
    if compact then
        title:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        title:setMarginLeft(4)
    else
        title:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        title:setMarginLeft(0)
    end

    writer:setVisible(not compact and writer:getText() ~= '')

    -- Save under the text, or in the header beside close
    save:setVisible(window.editable)
    save:breakAnchors()
    if compact then
        save:addAnchor(AnchorTop, 'closeButton', AnchorTop)
        save:addAnchor(AnchorRight, 'closeButton', AnchorLeft)
        save:setMarginRight(6)
        save:setWidth(96)
    else
        save:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        save:addAnchor(AnchorRight, 'parent', AnchorRight)
        save:setMarginRight(0)
        save:setWidth(120)
    end
    local footer = window.editable and not compact
    count:setVisible(footer and count:getText() ~= '')

    paper:breakAnchors()
    paper:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    paper:addAnchor(AnchorRight, 'textScroll', AnchorLeft)
    paper:addAnchor(AnchorTop, writer:isVisible() and 'writer' or 'closeButton', AnchorBottom)
    paper:setMarginTop(compact and 4 or 6)
    if footer then
        paper:addAnchor(AnchorBottom, 'saveButton', AnchorTop)
        paper:setMarginBottom(8)
    else
        paper:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        paper:setMarginBottom(0)
    end
end

local function fitTouchWindow(window, areaTop, areaBottom, keyboard)
    local root = rootWidget
    if not root or window:isDestroyed() then
        return
    end
    local rootWidth, rootHeight = root:getWidth(), root:getHeight()
    local width = rootWidth - 2 * TOUCH_MARGIN
    if rootWidth > rootHeight then
        width = math.min(TOUCH_LANDSCAPE_WIDTH, width)
    end
    local margin = keyboard and TOUCH_KEYBOARD_MARGIN or TOUCH_MARGIN
    local height = math.max(0, math.min(TOUCH_MAX_HEIGHT, areaBottom - areaTop - 2 * margin))
    setTouchCompact(window, height < TOUCH_COMPACT_BELOW)
    local panel = window.panel
    panel:setSize({ width = width, height = height })
    local y = keyboard and areaTop + margin or areaTop + math.floor((areaBottom - areaTop - height) / 2)
    panel:setPosition({ x = root:getX() + math.floor((rootWidth - width) / 2), y = y })
end

local function fitWindows()
    if not rootWidget then
        return
    end
    local areaTop, areaBottom, keyboard = visibleArea()
    for _, window in pairs(windows) do
        if window.touch then
            fitTouchWindow(window, areaTop, areaBottom, keyboard)
        else
            fitWindow(window, areaTop, areaBottom, keyboard)
        end
    end
end

local function stopKeyboardCheck()
    if keyboardCheck then
        removeEvent(keyboardCheck)
        keyboardCheck = nil
    end
end

local function addWindow(window)
    window.designHeight = window:getHeight()
    table.insert(windows, window)
    fitWindows()
    -- the page has no way to call the game, so the game looks (browser only)
    if g_platform.isBrowser() and not keyboardCheck then
        keyboardCheck = cycleEvent(fitWindows, KEYBOARD_CHECK_MS)
    end
end

local function removeWindow(window)
    table.removevalue(windows, window)
    if #windows == 0 then
        stopKeyboardCheck()
    end
end

-- A touch text window (TouchTextWindow): Save sends the text, close (and
-- Escape) cancels. Returns the window and its text field.
local function openTouchWindow(title, editable, onSave)
    local window = g_ui.createWidget('TouchTextWindow', rootWidget)
    window.touch = true
    window.editable = editable
    window.panel = window:getChildById('panel')
    window.panel:getChildById('title'):setText(title)
    local textEdit = window.panel:getChildById('paper'):getChildById('text')
    textEdit:setVerticalScrollBar(window.panel:getChildById('textScroll'))

    local function destroy()
        if not window:isDestroyed() then
            window:destroy()
        end
        removeWindow(window)
    end

    window.panel:getChildById('closeButton').onClick = destroy
    window.panel:getChildById('saveButton').onClick = function()
        if editable then
            onSave(textEdit:getText())
        end
        destroy()
    end
    window.onEscape = destroy
    if not editable then
        window.onEnter = destroy
    end
    return window, textEdit
end

local function focusTouchWindow(window, textEdit, editable)
    window:focus()
    window.panel:focus()
    if editable then
        textEdit:focus()
        textEdit:setCursorPos(#textEdit:getText())
    end
end

local function touchEditText(id, maxLength, text, writer, time)
    local writeable = #text < maxLength and maxLength > 0
    local window, textEdit = openTouchWindow(writeable and tr('Edit Text') or tr('Show Text'), writeable,
        function(newText)
            g_game.editText(id, newText)
        end)
    local panel = window.panel

    textEdit:setMaxLength(maxLength)
    textEdit:setText(text)
    textEdit:setEditable(writeable)
    textEdit:setCursorVisible(writeable)

    local line
    if #writer > 0 and #time > 0 then
        line = tr('Written by %s, %s', writer, time)
    elseif #writer > 0 then
        line = tr('Written by %s', writer)
    elseif #time > 0 then
        line = tr('Written on %s', time)
    end
    if #text == 0 and not writeable then
        line = (line and line .. '. ' or '') .. tr('It is empty.')
    end
    panel:getChildById('writer'):setText(line or '')

    -- how much of the limit the text uses
    if writeable then
        local count = panel:getChildById('count')
        local function update()
            count:setText(string.format('%d / %d', #textEdit:getText(), maxLength))
        end
        update()
        textEdit.onTextChange = update
    end

    focusTouchWindow(window, textEdit, writeable)
    addWindow(window)
end

local function countNames(text)
    local names = 0
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        if line:find('%S') then
            names = names + 1
        end
    end
    return names
end

local function touchEditList(id, doorId, text)
    local window, textEdit = openTouchWindow(tr('Edit List'), true, function(newText)
        g_game.editList(id, doorId, newText)
    end)
    local panel = window.panel

    textEdit:setMaxLength(8192)
    textEdit:setText(text)
    textEdit:setEditable(true)
    panel:getChildById('writer'):setText(tr('One name per line.'))

    local count = panel:getChildById('count')
    local function update()
        local names = countNames(textEdit:getText())
        count:setText(names == 1 and tr('1 name') or tr('%d names', names))
    end
    update()
    textEdit.onTextChange = update

    focusTouchWindow(window, textEdit, true)
    addWindow(window)
end

function init()
    g_ui.importStyle('textwindow')

    connect(g_game, {
        onEditText = onGameEditText,
        onEditList = onGameEditList,
        onGameEnd = destroyWindows
    })
    connect(rootWidget, { onGeometryChange = fitWindows })
end

function terminate()
    disconnect(g_game, {
        onEditText = onGameEditText,
        onEditList = onGameEditList,
        onGameEnd = destroyWindows
    })
    disconnect(rootWidget, { onGeometryChange = fitWindows })

    destroyWindows()
    stopKeyboardCheck()
end

function destroyWindows()
    for _, window in pairs(windows) do
        window:destroy()
    end
    windows = {}
    stopKeyboardCheck()
end

function onGameEditText(id, itemId, maxLength, text, writer, time)
    if g_platform.isMobile() then
        return touchEditText(id, maxLength, text, writer, time)
    end
    local textWindow = g_ui.createWidget('TextWindow', rootWidget)

    local writeable = #text < maxLength and maxLength > 0
    local textItem = textWindow:getChildById('textItem')
    local description = textWindow:getChildById('description')
    local textEdit = textWindow:getChildById('text')
    local okButton = textWindow:getChildById('okButton')
    local cancelButton = textWindow:getChildById('cancelButton')

    local textScroll = textWindow:getChildById('textScroll')

    if textItem:isHidden() then
        textItem:show()
    end

    textItem:setBackgroundColor('#00000000')
    textItem:setItemId(itemId)
    textEdit:setMaxLength(maxLength)
    textEdit:setText(text)
    textEdit:setEditable(writeable)
    textEdit:setCursorVisible(writeable)

    local desc = tr('You read the following')
    if #writer > 0 then
        desc = desc .. tr(', written by \n%s\n', writer)
        if #time > 0 then
            desc = desc .. tr('on %s.\n', time)
        end
    elseif #time > 0 then
        desc = desc .. tr(', written on \n%s.\n', time)
    else
        desc = desc .. '.\n'
    end

    if #text == 0 and not writeable then
        desc = desc .. tr('It is empty.')
    elseif writeable then
        desc = desc .. tr('You can enter new text.')
    end

    local lines = #{string.find(desc, '\n')}
    if lines < 2 then
        desc = desc .. '\n'
    end

    description:setText(desc)

    if not writeable then
        textWindow:setText(tr('Show Text'))
        cancelButton:hide()
        cancelButton:setWidth(0)
        okButton:setMarginRight(0)
    else
        textWindow:setText(tr('Edit Text'))
        textEdit:focus()
        textEdit:setCursorPos(#text)
    end

    if description:getHeight() < 64 then
        description:setHeight(64)
    end

    local function destroy()
        textWindow:destroy()
        removeWindow(textWindow)
    end

    local doneFunc = function()
        if writeable then
            g_game.editText(id, textEdit:getText())
        end
        destroy()
    end

    okButton.onClick = doneFunc
    cancelButton.onClick = destroy

    if not writeable then
        textWindow.onEnter = doneFunc
    end

    textWindow.onEscape = destroy

    addWindow(textWindow)
end

function onGameEditList(id, doorId, text)
    if g_platform.isMobile() then
        return touchEditList(id, doorId, text)
    end
    local textWindow = g_ui.createWidget('TextWindow', rootWidget)

    local textEdit = textWindow:getChildById('text')
    local description = textWindow:getChildById('description')
    local okButton = textWindow:getChildById('okButton')
    local cancelButton = textWindow:getChildById('cancelButton')

    local textItem = textWindow:getChildById('textItem')
    if textItem and not textItem:isHidden() then
        textItem:hide()
    end

    textEdit:setMaxLength(8192)
    textEdit:setText(text)
    textEdit:setEditable(true)
    textEdit:focus()
    textEdit:setCursorPos(#text)
    description:setText(tr('Enter one name per line.'))
    textWindow:setText(tr('Edit List'))

    if description:getHeight() < 64 then
        description:setHeight(64)
    end

    local function destroy()
        textWindow:destroy()
        removeWindow(textWindow)
    end

    local doneFunc = function()
        g_game.editList(id, doorId, textEdit:getText())
        destroy()
    end

    okButton.onClick = doneFunc
    cancelButton.onClick = destroy
    textWindow.onEscape = destroy

    addWindow(textWindow)
end
