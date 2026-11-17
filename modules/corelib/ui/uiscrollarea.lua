-- @docclass
UIScrollArea = extends(UIWidget, 'UIScrollArea')

-- public functions
function UIScrollArea.create()
    local scrollarea = UIScrollArea.internalCreate()
    scrollarea:setClipping(true)
    scrollarea.inverted = false
    scrollarea.alwaysScrollMaximum = false
    return scrollarea
end

function UIScrollArea:onStyleApply(styleName, styleNode)
    for name, value in pairs(styleNode) do
        if name == 'vertical-scrollbar' then
            addEvent(function()
                local parent = self:getParent()
                if parent then
                    self:setVerticalScrollBar(parent:getChildById(value))
                end
            end)
        elseif name == 'horizontal-scrollbar' then
            addEvent(function()
                local parent = self:getParent()
                if parent then
                    self:setHorizontalScrollBar(self:getParent():getChildById(value))
                end
            end)
        elseif name == 'inverted-scroll' then
            self:setInverted(value)
        elseif name == 'always-scroll-maximum' then
            self:setAlwaysScrollMaximum(value)
        end
    end
end

function UIScrollArea:updateScrollBars()
    local scrollWidth = math.max(self:getChildrenRect().width - self:getPaddingRect().width, 0)
    local scrollHeight = math.max(self:getChildrenRect().height - self:getPaddingRect().height, 0)

    local scrollbar = self.verticalScrollBar
    if scrollbar then
        if self.inverted then
            scrollbar:setMinimum(-scrollHeight)
            scrollbar:setMaximum(0)
        else
            scrollbar:setMinimum(0)
            scrollbar:setMaximum(scrollHeight)
        end
    end

    local scrollbar = self.horizontalScrollBar
    if scrollbar then
        if self.inverted then
            scrollbar:setMinimum(-scrollWidth)
            scrollbar:setMaximum(0)
        else
            scrollbar:setMinimum(0)
            scrollbar:setMaximum(scrollWidth)
        end
    end

    if self.lastScrollWidth ~= scrollWidth then
        self:onScrollWidthChange()
    end
    if self.lastScrollHeight ~= scrollHeight then
        self:onScrollHeightChange()
    end

    self.lastScrollWidth = scrollWidth
    self.lastScrollHeight = scrollHeight
end

function UIScrollArea:setVerticalScrollBar(scrollbar)
    self.verticalScrollBar = scrollbar
    connect(self.verticalScrollBar, 'onValueChange', function(scrollbar, value)
        local virtualOffset = self:getVirtualOffset()
        virtualOffset.y = value
        self:setVirtualOffset(virtualOffset)
        signalcall(self.onScrollChange, self, virtualOffset)
    end)
    self:updateScrollBars()
end

function UIScrollArea:setHorizontalScrollBar(scrollbar)
    self.horizontalScrollBar = scrollbar
    connect(self.horizontalScrollBar, 'onValueChange', function(scrollbar, value)
        local virtualOffset = self:getVirtualOffset()
        virtualOffset.x = value
        self:setVirtualOffset(virtualOffset)
        signalcall(self.onScrollChange, self, virtualOffset)
    end)
    self:updateScrollBars()
end

function UIScrollArea:setInverted(inverted)
    self.inverted = inverted
    self:updateScrollBars()
end

function UIScrollArea:setInvertedScroll(inverted)
    self:setInverted(inverted)
end

function UIScrollArea:setAlwaysScrollMaximum(value)
    self.alwaysScrollMaximum = value
end

function UIScrollArea:onLayoutUpdate()
    self:updateScrollBars()
end

-- Touch: a finger dragged over the list scrolls it (ot-client#76) -----------------
-- The press goes to the row under the finger (a button, a check); once the
-- finger has moved DRAG_START pixels it is a scroll instead: the press is
-- cancelled (no click) and the list follows the finger, then coasts on a
-- little after the finger lifts. Dragging an item still drags the item.
-- Touch mode only: on desktop the mouse wheel and the scroll bar do this.

local DRAG_START = 10      -- pixels before a press becomes a scroll
local COAST_FRICTION = 0.92 -- speed kept each frame after the finger lifts
local COAST_STOP = 0.5      -- pixels per frame below which coasting stops
local FRAME = 16           -- ms
local NEW_TOUCH_GAP = 400  -- ms without a move: a new touch (nothing was pressed)

-- What identifies this touch: the pressed widget and where it was pressed;
-- with nothing pressed, a pause in the moves
local function pressKey(self)
    local pressed = g_ui.getPressedWidget()
    if pressed then
        local at = pressed:getLastClickPosition()
        return tostring(pressed:getId()) .. '@' .. at.x .. ',' .. at.y
    end
    local now = g_clock.millis()
    if not self.lastMoveAt or now - self.lastMoveAt > NEW_TOUCH_GAP then
        self.freeTouch = (self.freeTouch or 0) + 1
    end
    self.lastMoveAt = now
    return 'free' .. self.freeTouch
end

local function touchScrolling()
    return g_platform and g_platform.isMobile and g_platform.isMobile()
end

local function scrollBy(self, dx, dy)
    local moved = false
    local vertical, horizontal = self.verticalScrollBar, self.horizontalScrollBar
    if vertical and dy ~= 0 then
        local before = vertical:getValue()
        vertical:setValue(before - dy)
        moved = vertical:getValue() ~= before
    elseif horizontal and dx ~= 0 then
        local before = horizontal:getValue()
        horizontal:setValue(before - dx)
        moved = horizontal:getValue() ~= before
    end
    return moved
end

local function stopCoasting(self)
    if self.coastEvent then
        removeEvent(self.coastEvent)
        self.coastEvent = nil
    end
end

local function coast(self)
    stopCoasting(self)
    self.coastEvent = cycleEvent(function()
        if self:isDestroyed() then
            return
        end
        self.dragVelocity = self.dragVelocity * COAST_FRICTION
        if math.abs(self.dragVelocity) < COAST_STOP or not scrollBy(self, 0, self.dragVelocity) then
            stopCoasting(self)
        end
    end, FRAME)
end

-- The finger lifted: the scroll ends (and coasts on)
local function endDrag(self)
    if self.dragWatch then
        removeEvent(self.dragWatch)
        self.dragWatch = nil
    end
    local wasDragging = self.dragging
    self.dragging = false
    self.dragDistance = 0
    -- the next touch is a new one, wherever it lands
    self.touchKey = nil
    if wasDragging and math.abs(self.dragVelocity or 0) >= 1 then
        coast(self)
    end
end

function UIScrollArea:onMouseMove(mousePos, mouseMoved)
    if not touchScrolling() or not self.verticalScrollBar or not g_mouse.isPressed(MouseLeftButton) then
        return false
    end
    -- A new touch? Each press has its own pressed widget and spot; its first
    -- move is a jump from where the last touch ended, not a drag, so the
    -- counting starts here. (While scrolling, the press is already cancelled.)
    if not self.dragging then
        local key = pressKey(self)
        if key ~= self.touchKey then
            self.touchKey = key
            stopCoasting(self)
            self.dragDistance = 0
            return false
        end
    end
    if not self.dragging then
        self.dragDistance = (self.dragDistance or 0) + math.abs(mouseMoved.y)
        if self.dragDistance < DRAG_START or not self.verticalScrollBar:isOn() then
            return false
        end
        -- it is a scroll, not a tap: the row under the finger is not clicked
        self.dragging = true
        self.dragVelocity = 0
        if g_ui.cancelMousePress then
            g_ui.cancelMousePress()
        end
        -- (the release may go elsewhere: watch for the finger lifting)
        self.dragWatch = cycleEvent(function()
            if self:isDestroyed() or not g_mouse.isPressed(MouseLeftButton) then
                endDrag(self)
            end
        end, FRAME)
    end
    scrollBy(self, 0, mouseMoved.y)
    -- the speed, smoothed, for coasting after the finger lifts
    self.dragVelocity = (self.dragVelocity or 0) * 0.5 + mouseMoved.y * 0.5
    return true
end

function UIScrollArea:onMouseRelease(mousePos, mouseButton)
    if self.dragging then
        endDrag(self)
        return true
    end
    self.dragDistance = 0
    return false
end

function UIScrollArea:onMouseWheel(mousePos, mouseWheel)
    if self.verticalScrollBar then
        if not self.verticalScrollBar:isOn() then
            return false
        end
        if mouseWheel == MouseWheelUp then
            local minimum = self.verticalScrollBar:getMinimum()
            if self.verticalScrollBar:getValue() <= minimum then
                return false
            end
            self.verticalScrollBar:decrement()
        else
            local maximum = self.verticalScrollBar:getMaximum()
            if self.verticalScrollBar:getValue() >= maximum then
                return false
            end
            self.verticalScrollBar:increment()
        end
    elseif self.horizontalScrollBar then
        if not self.horizontalScrollBar:isOn() then
            return false
        end
        if mouseWheel == MouseWheelUp then
            local maximum = self.horizontalScrollBar:getMaximum()
            if self.horizontalScrollBar:getValue() >= maximum then
                return false
            end
            self.horizontalScrollBar:increment()
        else
            local minimum = self.horizontalScrollBar:getMinimum()
            if self.horizontalScrollBar:getValue() <= minimum then
                return false
            end
            self.horizontalScrollBar:decrement()
        end
    end
    return true
end

function UIScrollArea:ensureChildVisible(child)
    if child then
        local paddingRect = self:getPaddingRect()
        if self.verticalScrollBar then
            local deltaY = paddingRect.y - child:getY()
            if deltaY > 0 then
                self.verticalScrollBar:decrement(deltaY)
            end

            deltaY = (child:getY() + child:getHeight()) - (paddingRect.y + paddingRect.height)
            if deltaY > 0 then
                self.verticalScrollBar:increment(deltaY)
            end
        elseif self.horizontalScrollBar then
            local deltaX = paddingRect.x - child:getX()
            if deltaX > 0 then
                self.horizontalScrollBar:decrement(deltaX)
            end

            deltaX = (child:getX() + child:getWidth()) - (paddingRect.x + paddingRect.width)
            if deltaX > 0 then
                self.horizontalScrollBar:increment(deltaX)
            end
        end
    end
end

function UIScrollArea:onChildFocusChange(focusedChild, oldFocused, reason)
    if focusedChild and (reason == MouseFocusReason or reason == KeyboardFocusReason) then
        self:ensureChildVisible(focusedChild)
    end
end

function UIScrollArea:onScrollWidthChange()
    if self.alwaysScrollMaximum and self.horizontalScrollBar then
        self.horizontalScrollBar:setValue(self.horizontalScrollBar:getMaximum())
    end
end

function UIScrollArea:onScrollHeightChange()
    if self.alwaysScrollMaximum and self.verticalScrollBar then
        self.verticalScrollBar:setValue(self.verticalScrollBar:getMaximum())
    end
end
