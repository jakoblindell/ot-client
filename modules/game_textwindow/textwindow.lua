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

local function fitWindows()
    if not rootWidget then
        return
    end
    local areaTop, areaBottom, keyboard = visibleArea()
    for _, window in pairs(windows) do
        fitWindow(window, areaTop, areaBottom, keyboard)
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
