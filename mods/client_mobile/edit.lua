-- Edit layout for the touch layout (ot-client#23, #124): the pieces around
-- the game view (health and mana bars, chat button, hotbar, joystick and
-- the panels on the screen) can be moved and sized. While editing:
--   - each piece has a dashed gold outline exactly its size, its name, and
--     round - and + in its middle (70% to 160%); one finger drags it;
--   - the game view dims;
--   - a small "Customize Layout" window offers Save (keep the changes),
--     Reset (every piece to its default place), Center (the selected piece
--     to the middle of its area) and Cancel (back to the layout from before).
-- Pieces snap to the screen edges, the game view and each other.
--
-- Positions and sizes are saved per character and separately for portrait
-- and landscape (positions as fractions of the screen), and applied on top
-- of the default layout (so "Reset" just forgets them). A panel the player
-- never moved stays in its default place (panels.lua).

local SETTINGS_NODE = 'client_mobile_layouts'
local SNAP_DISTANCE = 12
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.7, 1.6, 0.1

-- The pieces besides the panels; resize: what an older saved width means
local STATIC_PIECES = {
    { key = 'stats', name = 'Health and mana', resize = 'width', minWidth = 100 },
    { key = 'chat', name = 'Chat', resize = 'square', maxSize = 96 },
    { key = 'grid', name = 'Hotbar', resize = 'width', minWidth = 52 },
    { key = 'joystick', name = 'Joystick' },
}

-- Every piece: the static ones and one per panel (panels.lua)
local function allPieces()
    local pieces = {}
    for _, piece in ipairs(STATIC_PIECES) do
        table.insert(pieces, piece)
    end
    for _, def in ipairs(PANELS) do
        table.insert(pieces, { key = def.key, name = def.name, panel = def.id, scalable = def.kind == 'list' })
    end
    return pieces
end

local function findPiece(key)
    for _, piece in ipairs(allPieces()) do
        if piece.key == key then
            return piece
        end
    end
end

-- - and + apply to the static pieces and the lists (equipment and the map
-- are drawn at one size)
local function canScale(piece)
    return not piece.panel or piece.scalable
end

local editing = false
local frames = {} -- piece key -> its outline
local selected -- the piece Center applies to
local dialog, dim
-- The full editor's changes until Save (Cancel forgets them): the pieces of
-- this orientation
local draft
-- The layout without a game (the UI gallery): kept in memory only
local previewLayouts = {}

local function root()
    return modules.game_interface.getRootPanel()
end

local function orientation()
    local r = root()
    return r:getHeight() > r:getWidth() and 'portrait' or 'landscape'
end

local function characterLayouts()
    if isLayoutPreview() then
        return previewLayouts, previewLayouts
    end
    local name = g_game.getCharacterName()
    if not name or name == '' then
        return nil
    end
    local all = g_settings.getNode(SETTINGS_NODE) or {}
    all[name] = all[name] or {}
    return all, all[name]
end

local function storedPieces()
    local _, layouts = characterLayouts()
    return layouts and layouts[orientation()] or {}
end

local function savedPieces()
    return draft or storedPieces()
end

local function writeStored(pieces)
    local all, layouts = characterLayouts()
    if not all then
        return
    end
    layouts[orientation()] = pieces
    if all ~= previewLayouts then
        g_settings.setNode(SETTINGS_NODE, all)
        -- right away: a phone browser may close the tab without warning
        g_settings.save()
    end
end

local function savePiece(key, entry)
    if draft then
        draft[key] = entry
        return
    end
    local pieces = storedPieces()
    pieces[key] = entry
    writeStored(pieces)
end

-- A piece's saved place and size ({ x, y, s, w } as fractions of the
-- screen), nil when it has its default one
function getSavedPiece(key)
    return savedPieces()[key]
end

-- The lowest a piece may reach: the top of the toolbar
local function bottomLimit()
    local r = root():getRect()
    local toolbar = root():getChildById('mobileToolbar')
    if toolbar and toolbar:isVisible() then
        return math.min(r.y + r.height, toolbar:getY())
    end
    return r.y + r.height
end

-- A piece's size when the player has not changed it: set by the layout
-- (a joystick in a narrow column is drawn smaller to fit it)
pieceDefaultScales = {}

-- The size of a piece (+ and -), 1 when not changed
function getPieceScale(key)
    local entry = savedPieces()[key]
    return entry and tonumber(entry.s) or pieceDefaultScales[key] or 1
end

-- The size a widget had before any scaling (kept on the widget)
local function base(widget)
    if not widget.baseGeometry then
        widget.baseGeometry = {
            width = widget:getWidth(), height = widget:getHeight(),
            left = widget:getMarginLeft(), right = widget:getMarginRight(),
            top = widget:getMarginTop(), bottom = widget:getMarginBottom(),
        }
    end
    return widget.baseGeometry
end

function getPieceBaseSize(widget)
    return base(widget)
end

local function scaleBox(widget, scale)
    local b = base(widget)
    widget:setSize({ width = math.floor(b.width * scale), height = math.floor(b.height * scale) })
    widget:setMarginLeft(math.floor(b.left * scale))
    widget:setMarginRight(math.floor(b.right * scale))
    widget:setMarginTop(math.floor(b.top * scale))
    widget:setMarginBottom(math.floor(b.bottom * scale))
end

-- How + and - change each static piece (the hotbar reads its scale when it
-- lays out its slots, the panels when they are placed)
local SCALERS = {
    joystick = function(widget, scale)
        local b = base(widget)
        widget:setSize({ width = math.floor(b.width * scale), height = math.floor(b.height * scale) })
        -- the pad's picture is drawn in a fixed square (image-rect)
        widget:setImageRect({ x = math.floor(12 * scale), y = 0,
            width = math.floor(150 * scale), height = math.floor(150 * scale) })
        if widget.pointer then
            scaleBox(widget.pointer, scale)
        end
        -- the D-pad arrows follow the pad's size by themselves
    end,
    -- (only their size: the layout places them, with margins)
    stats = function(widget, scale)
        widget:setHeight(math.floor(base(widget).height * scale))
        for _, bar in ipairs(widget:getChildren()) do
            bar:setHeight(math.floor(base(bar).height * scale))
        end
    end,
    chat = function(widget, scale)
        local b = base(widget)
        widget:setSize({ width = math.floor(b.width * scale), height = math.floor(b.height * scale) })
        if widget.icon then
            local size = math.floor(28 * scale)
            widget.icon:setSize({ width = size, height = size })
        end
    end,
}

-- Moves a piece to a saved position (fractions of the screen)
local function placePiece(piece, widget, entry)
    local r = root():getRect()
    if entry.w and piece.resize == 'width' then
        if piece.key == 'grid' then
            resizeActionGrid(math.floor(entry.w * r.width))
        else
            widget:setWidth(math.max(piece.minWidth or 36, math.floor(entry.w * r.width)))
        end
    elseif entry.w and piece.resize == 'square' then
        local size = math.max(36, math.min(piece.maxSize, math.floor(entry.w * r.width)))
        widget:setSize({ width = size, height = size })
    end
    widget:breakAnchors()
    local x = r.x + math.floor(entry.x * r.width)
    local y = r.y + math.floor(entry.y * r.height)
    -- keep it on the screen and off the game view
    x = math.max(r.x, math.min(x, r.x + r.width - widget:getWidth()))
    y = math.max(r.y, math.min(y, bottomLimit() - widget:getHeight()))
    x, y = keepOffGameView(x, y, widget:getWidth(), widget:getHeight())
    widget:setPosition({ x = x, y = y })
end

local syncFrames

-- Called at the end of the touch layout: saved positions win over the
-- default ones
function applySavedLayout()
    local widgets = getMovableWidgets()
    local saved = savedPieces()
    for _, piece in ipairs(allPieces()) do
        local widget = widgets[piece.key]
        if widget and SCALERS[piece.key] then
            SCALERS[piece.key](widget, getPieceScale(piece.key))
        end
        if widget and saved[piece.key] and saved[piece.key].x then
            placePiece(piece, widget, saved[piece.key])
        end
    end
    -- the bars' fill follows their width
    refreshStats()
    if editing then
        syncFrames()
    end
end

-- Edges a piece snaps to: the screen, the game view and the other pieces
local function snapLines(except)
    local r = root():getRect()
    local xs, ys = { r.x, r.x + r.width }, { r.y, r.y + r.height }
    local function add(rect)
        table.insert(xs, rect.x)
        table.insert(xs, rect.x + rect.width)
        table.insert(ys, rect.y)
        table.insert(ys, rect.y + rect.height)
    end
    add(modules.game_interface.getMapPanel():getRect())
    local toolbar = root():getChildById('mobileToolbar')
    if toolbar then
        table.insert(ys, toolbar:getY())
    end
    for key, widget in pairs(getMovableWidgets()) do
        if key ~= except and widget:isVisible() then
            add(widget:getRect())
        end
    end
    return xs, ys
end

local function snap(value, size, lines)
    for _, line in ipairs(lines) do
        if math.abs(value - line) <= SNAP_DISTANCE then
            return line
        end
        if math.abs(value + size - line) <= SNAP_DISTANCE then
            return line - size
        end
    end
    return value
end

local function storePiece(piece, widget)
    local r = root():getRect()
    local entry = {
        x = (widget:getX() - r.x) / r.width,
        y = (widget:getY() - r.y) / r.height,
        s = getPieceScale(piece.key),
    }
    if piece.resize then
        entry.w = widget:getWidth() / r.width
    end
    savePiece(piece.key, entry)
end

-- Puts a widget at x, y: on the screen, above the toolbar, off the game view
local function moveTo(widget, x, y)
    local r = root():getRect()
    x = math.max(r.x, math.min(math.floor(x), r.x + r.width - widget:getWidth()))
    y = math.max(r.y, math.min(math.floor(y), bottomLimit() - widget:getHeight()))
    x, y = keepOffGameView(x, y, widget:getWidth(), widget:getHeight())
    widget:breakAnchors()
    widget:setPosition({ x = x, y = y })
end

-- + and -: a step bigger or smaller, around the piece's middle. A piece in
-- its default place stays there (a panel keeps its place among the others)
local function changeScale(piece, delta)
    local widget = getMovableWidgets()[piece.key]
    if not widget then
        return
    end
    local scale = math.floor((getPieceScale(piece.key) + delta) * 10 + 0.5) / 10
    scale = math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
    local entry = savedPieces()[piece.key] or {}
    local placed = entry.x ~= nil
    local centre = { x = widget:getX() + widget:getWidth() / 2, y = widget:getY() + widget:getHeight() / 2 }
    entry.s = scale
    savePiece(piece.key, entry)
    if SCALERS[piece.key] then
        SCALERS[piece.key](widget, scale)
    end
    relayout()
    if placed and piece.key ~= 'grid' then
        widget = getMovableWidgets()[piece.key] or widget
        moveTo(widget, centre.x - widget:getWidth() / 2, centre.y - widget:getHeight() / 2)
        storePiece(piece, widget)
        if piece.key == 'stats' then
            refreshStats()
        end
    end
    syncFrames()
end

-- The outlines ----------------------------------------------------------------

-- The outline is exactly the piece. Its name and - + go in its middle: the
-- name above - +, or between them on a low piece (the bars), or - + over
-- the piece when it is too small for both (the chat button)
local SIZE_BUTTON = 34
local SIZES_WIDTH = 2 * SIZE_BUTTON + 8

local function placeFrame(frame, widget)
    local rect = widget:getRect()
    frame:setRect(rect)
    local name, sizes = frame:getChildById('name'), frame.sizes
    name:breakAnchors()
    local cx = rect.x + math.floor(rect.width / 2)
    local cy = rect.y + math.floor(rect.height / 2)
    local nameWidth, nameHeight = name:getTextSize().width, name:getHeight()
    local function nameAt(y)
        name:setPosition({ x = cx - math.floor(nameWidth / 2), y = y })
    end
    if not frame.scalable then
        nameAt(cy - math.floor(nameHeight / 2))
    elseif rect.height >= SIZE_BUTTON + nameHeight + 6 then
        nameAt(cy - nameHeight - 2)
        sizes:setSize({ width = SIZES_WIDTH, height = SIZE_BUTTON })
        sizes:setPosition({ x = cx - math.floor(SIZES_WIDTH / 2), y = cy })
    elseif rect.width >= 2 * SIZE_BUTTON + nameWidth + 12 then
        nameAt(cy - math.floor(nameHeight / 2))
        sizes:setSize({ width = rect.width - 4, height = SIZE_BUTTON })
        sizes:setPosition({ x = rect.x + 2, y = cy - math.floor(SIZE_BUTTON / 2) })
    else
        nameAt(cy - math.floor(nameHeight / 2))
        local r = root():getRect()
        local x = math.max(r.x, math.min(cx - math.floor(SIZES_WIDTH / 2), r.x + r.width - SIZES_WIDTH))
        -- (above it, where the bars or the hotbar are not; below at the top)
        local y = rect.y - SIZE_BUTTON - 2
        if y < r.y then
            y = rect.y + rect.height + 2
        end
        sizes:setSize({ width = SIZES_WIDTH, height = SIZE_BUTTON })
        sizes:setPosition({ x = x, y = y })
    end
end

-- The "Customize Layout" window: in the middle of the game view
local function placeDialog()
    local map = modules.game_interface.getMapPanel():getRect()
    dialog:setPosition({ x = map.x + math.floor((map.width - dialog:getWidth()) / 2),
        y = map.y + math.floor((map.height - dialog:getHeight()) / 2) })
    dialog:raise()
end

function updateFrames()
    local widgets = getMovableWidgets()
    for key, frame in pairs(frames) do
        local widget = widgets[key]
        if widget then
            frame:setVisible(widget:isVisible())
            frame.sizes:setVisible(widget:isVisible() and frame.scalable)
            placeFrame(frame, widget)
            frame:setOn(selected == key)
            frame:raise()
            frame.sizes:raise()
        end
    end
    if dialog then
        placeDialog()
    end
end

local function createFrame(piece, widget)
    local frame = g_ui.createWidget('MobileEditFrame', rootWidget)
    frame:setId('mobileEditFrame_' .. piece.key)
    frame:getChildById('name'):setText(tr(piece.name))
    placeFrame(frame, widget)

    -- the outline follows the piece (anchored pieces settle after a layout)
    frame.follow = function()
        local current = getMovableWidgets()[piece.key]
        if current and not frame:isDestroyed() then
            placeFrame(frame, current)
        end
    end
    frame.followed = widget
    connect(widget, { onGeometryChange = frame.follow })

    -- Tapping or dragging a piece selects it (Center moves that one)
    frame.onMousePress = function()
        if selected ~= piece.key then
            selected = piece.key
            updateFrames()
        end
        return false
    end
    frame.onDragEnter = function(self, mousePos)
        local current = getMovableWidgets()[piece.key] or widget
        self.grab = { x = mousePos.x - current:getX(), y = mousePos.y - current:getY() }
        return true
    end
    frame.onDragMove = function(self, mousePos)
        local current = getMovableWidgets()[piece.key] or widget
        local xs, ys = snapLines(piece.key)
        local x = snap(mousePos.x - self.grab.x, current:getWidth(), xs)
        local y = snap(mousePos.y - self.grab.y, current:getHeight(), ys)
        -- never onto the game view: it slides along its edge instead
        moveTo(current, x, y)
        placeFrame(self, current)
        return true
    end
    frame.onDragLeave = function()
        storePiece(piece, getMovableWidgets()[piece.key] or widget)
        return true
    end

    -- (- and + on the screen's top layer: they may reach past the outline)
    local sizes = frame:getChildById('sizes')
    sizes:setParent(rootWidget)
    sizes:setId('mobileEditSizes_' .. piece.key)
    frame.sizes = sizes
    frame.scalable = canScale(piece)
    sizes:setVisible(frame.scalable)
    for id, delta in pairs({ smaller = -SCALE_STEP, bigger = SCALE_STEP }) do
        local button = sizes:getChildById(id)
        setRoundFace(button, 'gold')
        button.onClick = function()
            selected = piece.key
            changeScale(piece, delta)
        end
    end
    return frame
end

local function destroyFrame(key)
    local frame = frames[key]
    if frame then
        if frame.followed and not frame.followed:isDestroyed() then
            disconnect(frame.followed, { onGeometryChange = frame.follow })
        end
        frame.sizes:destroy()
        frame:destroy()
        frames[key] = nil
    end
end

-- An outline for each piece on the screen (a panel shown or hidden while
-- editing gets or loses its own)
syncFrames = function()
    if not editing then
        return
    end
    local widgets = getMovableWidgets()
    for key, frame in pairs(frames) do
        if not widgets[key] or frame.followed ~= widgets[key] then
            destroyFrame(key)
        end
    end
    for _, piece in ipairs(allPieces()) do
        local widget = widgets[piece.key]
        if widget and not frames[piece.key] and (not editing.only or editing.only == piece.key) then
            frames[piece.key] = createFrame(piece, widget)
        end
    end
    updateFrames()
    -- again once anchored pieces have their new place
    addEvent(function()
        if editing then
            updateFrames()
        end
    end)
end

local function destroyFrames()
    for key in pairs(frames) do
        destroyFrame(key)
    end
    for _, widget in ipairs({ dialog, dim }) do
        if widget then
            widget:destroy()
        end
    end
    dialog, dim = nil, nil
end

-- Over the game view while editing
local function createDim()
    local map = modules.game_interface.getMapPanel()
    dim = g_ui.createWidget('MobileEditDim', root())
    dim:setId('mobileEditDim')
    dim:addAnchor(AnchorLeft, map:getId(), AnchorLeft)
    dim:addAnchor(AnchorRight, map:getId(), AnchorRight)
    dim:addAnchor(AnchorTop, map:getId(), AnchorTop)
    dim:addAnchor(AnchorBottom, map:getId(), AnchorBottom)
    -- (right above the game view, under every piece)
    root():moveChildToIndex(dim, root():getChildIndex(map) + 1)
end

-- Center: the selected piece to the middle of its area, across the screen
-- in portrait, across its side column in landscape
local function centerSelected()
    local key = selected
    local widget = key and getMovableWidgets()[key]
    local piece = key and findPiece(key)
    if not widget or not piece then
        return
    end
    local r = root():getRect()
    local left, right = r.x, r.x + r.width
    if orientation() == 'landscape' then
        local map = modules.game_interface.getMapPanel():getRect()
        local middle = widget:getX() + widget:getWidth() / 2
        if widget:getWidth() <= map.x - r.x then
            if middle < map.x + map.width / 2 then
                right = map.x
            else
                left = map.x + map.width
            end
        end
    end
    moveTo(widget, left + (right - left - widget:getWidth()) / 2, widget:getY())
    storePiece(piece, widget)
    updateFrames()
end

-- The editor ------------------------------------------------------------------

function isEditingLayout()
    return editing and true or false
end

local function finishEditing()
    editing = false
    selected = nil
    draft = nil
    destroyFrames()
    local toolbar = root():getChildById('mobileToolbar')
    if toolbar then
        toolbar:setOpacity(1)
    end
    if onEditLayoutChange then
        onEditLayoutChange(false)
    end
end

-- Save: the changes are kept
function saveEditLayout()
    if not editing or not draft then
        return
    end
    local pieces = draft
    draft = nil
    writeStored(pieces)
    finishEditing()
    relayout()
end

-- Cancel (and logging out while editing): back to the layout from before
function stopEditLayout()
    if not editing then
        return
    end
    finishEditing()
    relayout()
end

-- Reset UI: every piece back to its default place and size, in both
-- orientations (hotbar slots and presets stay)
local resetBox

function resetLayout()
    local all = characterLayouts()
    if all and all ~= previewLayouts then
        local name = g_game.getCharacterName()
        all[name] = nil
        g_settings.setNode(SETTINGS_NODE, all)
        g_settings.save()
    elseif all then
        previewLayouts = {}
    end
    if draft then
        draft = {}
    end
    relayout()
end

function confirmResetLayout()
    if resetBox or not g_game.isOnline() then
        return
    end
    local function done()
        if resetBox then
            resetBox:destroy()
            resetBox = nil
        end
    end
    resetBox = displayGeneralBox(tr('Reset UI'), tr('Do you want to reset the UI to default values?'), {
        { text = tr('Yes'), callback = function() done(); resetLayout() end },
        { text = tr('No'), callback = done },
    }, function() done(); resetLayout() end, done)
end

function startEditLayout()
    if editing or not (g_game.isOnline() or isLayoutPreview()) then
        return
    end
    editing = { only = nil }
    -- a copy to change; the saved layout stays until Save
    draft = {}
    for key, entry in pairs(storedPieces()) do
        local copy = {}
        for field, value in pairs(entry) do
            copy[field] = value
        end
        draft[key] = copy
    end
    createDim()
    local toolbar = root():getChildById('mobileToolbar')
    if toolbar then
        -- (dimmed, still there: its buttons show and hide panels to place)
        toolbar:setOpacity(0.6)
    end
    dialog = g_ui.createWidget('MobileEditDialog', rootWidget)
    dialog:setId('mobileEditDialog')
    placeDialog()
    dialog:getChildById('save').onClick = saveEditLayout
    dialog:getChildById('reset').onClick = function()
        draft = {}
        relayout()
    end
    dialog:getChildById('center').onClick = centerSelected
    dialog:getChildById('cancel').onClick = stopEditLayout
    if onEditLayoutChange then
        onEditLayoutChange(true)
    end
    relayout()
end

function toggleEditLayout()
    if editing then
        stopEditLayout()
    else
        startEditLayout()
    end
end

-- One piece at a time, for the first-login setup (setup.lua): the piece
-- gets its outline (drag, - and +) and nothing else does; each placement
-- is saved at once
function startPlacingPiece(key)
    stopPlacingPiece()
    local widget = getMovableWidgets()[key]
    if not widget or not findPiece(key) then
        return false
    end
    editing = { only = key }
    selected = key
    syncFrames()
    return true
end

function stopPlacingPiece()
    -- (the full editor has its own window and is stopped with it)
    if dialog then
        return
    end
    for key in pairs(frames) do
        destroyFrame(key)
    end
    editing = false
    selected = nil
end

-- Keeps a piece where the player put it (moved off the game view if it is
-- still on it)
function confirmPlacedPiece(key)
    local widget = getMovableWidgets()[key]
    local piece = findPiece(key)
    if not widget or not piece then
        return
    end
    moveTo(widget, widget:getX(), widget:getY())
    storePiece(piece, widget)
end

-- Forgets a piece's place: back to its default
function forgetPiece(key)
    savePiece(key, nil)
end

-- Whether the player has placed or sized anything in this orientation
function hasSavedLayout()
    return next(storedPieces()) ~= nil
end
