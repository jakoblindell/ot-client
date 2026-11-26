-- Edit layout for the touch layout (ot-client#23, #124): the pieces (chat
-- button, hotbar, joystick and the panels on the screen) can be moved and
-- sized. The health and mana bars stay where the layout puts them (under
-- the game view in portrait, in the bottom bar in landscape). While editing:
--   - each piece has a dashed gold outline exactly its size, its name, and
--     round - and + in its middle (70% to 160%); one finger drags it;
--   - the game view dims;
--   - a small "Customize Layout" window offers Save (keep the changes),
--     Reset (every piece to its default place), Center (the selected piece
--     to the middle of its area) and Cancel (back to the layout from before).
-- Pieces go anywhere on the screen above the bottom bar, over the game view
-- too (ot-client#155): the player chooses what covers it; only the bars are
-- never covered. They snap lightly to the screen edges, the top of the
-- bottom bar, the bars and each other.
--
-- Positions and sizes are saved per character and separately for portrait
-- and landscape (positions as fractions of the screen), and applied on top
-- of the default layout (so "Reset" just forgets them). A panel the player
-- never moved stays in its default place (panels.lua).

local SETTINGS_NODE = 'client_mobile_layouts'
local SNAP_DISTANCE = 6
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.7, 1.6, 0.1

-- The pieces besides the panels; resize: what an older saved width means
local STATIC_PIECES = {
    { key = 'chat', name = 'Chat', resize = 'square', maxSize = 96 },
    { key = 'grid', name = 'Hotbar' },
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

-- The room a piece needs above its widget: P and the pencil ride on top of
-- the hotbar (mobile.lua anchors them there), so they count as part of it
local function topExtra(key)
    local row = key == 'grid' and getHotbarPresetRow and getHotbarPresetRow()
    if row and not row:isDestroyed() then
        return row:getHeight() + row:getMarginBottom()
    end
    return 0
end

-- The rect a piece takes on the screen (the hotbar with P and the pencil)
local function pieceRect(key, widget)
    local rect = widget:getRect()
    local extra = topExtra(key)
    return { x = rect.x, y = rect.y - extra, width = rect.width, height = rect.height + extra }
end

-- The health and mana bars: not a piece, and never covered by one
local function bars()
    local widget = root():getChildById('mobileStats')
    return widget and widget:isVisible() and widget or nil
end

-- x, y for a piece's widget kept on the screen, above the bottom bar and
-- off the health and mana bars (moved the shortest way past them)
local function clampToScreen(key, widget, x, y)
    local r = root():getRect()
    local w, h, extra = widget:getWidth(), widget:getHeight(), topExtra(key)
    local left, right = r.x, r.x + r.width - w
    local top, bottom = r.y + extra, bottomLimit() - h
    x = math.max(left, math.min(math.floor(x), right))
    y = math.max(top, math.min(math.floor(y), bottom))
    local stats = bars()
    if not stats then
        return x, y
    end
    local b = stats:getRect()
    if x + w <= b.x or x >= b.x + b.width or y + h <= b.y or y - extra >= b.y + b.height then
        return x, y
    end
    local best, bestDistance
    for _, spot in ipairs({
        { x = x, y = b.y - h }, { x = x, y = b.y + b.height + extra },
        { x = b.x - w, y = y }, { x = b.x + b.width, y = y },
    }) do
        if spot.x >= left and spot.x <= right and spot.y >= top and spot.y <= bottom then
            local distance = math.abs(spot.x - x) + math.abs(spot.y - y)
            if not bestDistance or distance < bestDistance then
                best, bestDistance = spot, distance
            end
        end
    end
    if best then
        return best.x, best.y
    end
    return x, y
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
    if entry.w and piece.resize == 'square' then
        local size = math.max(36, math.min(piece.maxSize, math.floor(entry.w * r.width)))
        widget:setSize({ width = size, height = size })
    end
    widget:breakAnchors()
    -- where the player put it, over the game view too; kept on the screen
    local x, y = clampToScreen(piece.key, widget, r.x + math.floor(entry.x * r.width),
        r.y + math.floor(entry.y * r.height))
    widget:setPosition({ x = x, y = y })
end

-- The piece the setup is placing (setup.lua) keeps its spot through a new
-- layout until it is saved, and is drawn over the other pieces
local placingSpot

local function raisePlacing(key, widget)
    widget:raise()
    local row = key == 'grid' and getHotbarPresetRow and getHotbarPresetRow()
    if row and not row:isDestroyed() then
        row:raise()
    end
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
    if editing and editing.only then
        local widget = widgets[editing.only]
        if widget then
            if placingSpot and not (saved[editing.only] and saved[editing.only].x) then
                local x, y = clampToScreen(editing.only, widget, placingSpot.x, placingSpot.y)
                widget:breakAnchors()
                widget:setPosition({ x = x, y = y })
            end
            raisePlacing(editing.only, widget)
        end
    end
    -- the bars' fill follows their width
    refreshStats()
    if editing then
        syncFrames()
    end
end

-- Edges a piece snaps to: the screen, the top of the bottom bar, the health
-- and mana bars and the other pieces (not the game view: pieces may go over
-- it)
local function snapLines(except)
    local r = root():getRect()
    local xs, ys = { r.x, r.x + r.width }, { r.y, r.y + r.height }
    local function add(rect)
        table.insert(xs, rect.x)
        table.insert(xs, rect.x + rect.width)
        table.insert(ys, rect.y)
        table.insert(ys, rect.y + rect.height)
    end
    local toolbar = root():getChildById('mobileToolbar')
    if toolbar and toolbar:isVisible() then
        table.insert(ys, toolbar:getY())
    end
    if bars() then
        add(bars():getRect())
    end
    for key, widget in pairs(getMovableWidgets()) do
        if key ~= except and widget:isVisible() then
            add(pieceRect(key, widget))
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

-- Puts a piece's widget at x, y: on the screen and above the toolbar (over
-- the game view too)
local function moveTo(key, widget, x, y)
    x, y = clampToScreen(key, widget, x, y)
    widget:breakAnchors()
    widget:setPosition({ x = x, y = y })
    if editing and editing.only == key then
        placingSpot = { x = x, y = y }
    end
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
        moveTo(piece.key, widget, centre.x - widget:getWidth() / 2, centre.y - widget:getHeight() / 2)
        storePiece(piece, widget)
    end
    syncFrames()
end

-- The outlines ----------------------------------------------------------------

-- The outline is exactly the piece. Its name and - + go in its middle: the
-- name above - +, or between them on a wide, low piece, or - + beside
-- the piece when it is too small for both (the chat button)
local SIZE_BUTTON = 34
local SIZES_WIDTH = 2 * SIZE_BUTTON + 8

local function placeFrame(frame, widget)
    -- (the hotbar's outline takes in P and the pencil above it)
    local rect = pieceRect(frame.key, widget)
    frame:setRect(rect)
    local name, sizes = frame:getChildById('name'), frame.sizes
    name:breakAnchors()
    local cx = rect.x + math.floor(rect.width / 2)
    local cy = rect.y + math.floor(rect.height / 2)
    local nameWidth, nameHeight = name:getTextSize().width + 8, name:getHeight()
    name:setWidth(nameWidth)
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
        -- above it in landscape (the chat button: P and the pencil are
        -- beside it), beside it in portrait (the bars are above it), else
        -- below
        sizes:setSize({ width = SIZES_WIDTH, height = SIZE_BUTTON })
        local y = cy - math.floor(SIZE_BUTTON / 2)
        local above = rect.y - SIZE_BUTTON - 2
        if orientation() == 'landscape' and above >= r.y then
            sizes:setPosition({ x = x, y = above })
        elseif rect.x - SIZES_WIDTH - 2 >= r.x then
            sizes:setPosition({ x = rect.x - SIZES_WIDTH - 2, y = y })
        elseif rect.x + rect.width + 2 + SIZES_WIDTH <= r.x + r.width then
            sizes:setPosition({ x = rect.x + rect.width + 2, y = y })
        else
            y = rect.y - SIZE_BUTTON - 2
            if y < r.y then
                y = rect.y + rect.height + 2
            end
            sizes:setPosition({ x = x, y = y })
        end
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
    frame.key = piece.key
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

    -- A finger on the piece the setup is placing: its prompt makes way
    -- (setup.lua) until the finger lifts
    local function held(down)
        if editing and editing.only == piece.key and onPlacingPieceHeld then
            onPlacingPieceHeld(down)
        end
    end
    -- Tapping or dragging a piece selects it (Center moves that one)
    frame.onMousePress = function()
        held(true)
        if selected ~= piece.key then
            selected = piece.key
            updateFrames()
        end
        return false
    end
    frame.onMouseRelease = function()
        held(false)
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
        local extra = topExtra(piece.key)
        local x = snap(mousePos.x - self.grab.x, current:getWidth(), xs)
        -- (the hotbar snaps with P and the pencil on top of it)
        local y = snap(mousePos.y - self.grab.y - extra, current:getHeight() + extra, ys) + extra
        moveTo(piece.key, current, x, y)
        placeFrame(self, current)
        return true
    end
    frame.onDragLeave = function()
        held(false)
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
-- in portrait; in landscape across its side column when it is in one,
-- else across the screen (it stays at its height, over the game view or not)
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
        if widget:getX() + widget:getWidth() <= map.x then
            right = map.x
        elseif widget:getX() >= map.x + map.width then
            left = map.x + map.width
        end
    end
    moveTo(key, widget, left + (right - left - widget:getWidth()) / 2, widget:getY())
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
    placingSpot = nil
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
    -- (the setup put it where it is: it stays there, over everything)
    placingSpot = { x = widget:getX(), y = widget:getY() }
    raisePlacing(key, widget)
    syncFrames()
    return true
end

-- Moves the piece being placed (the UI gallery shows one placed over the
-- game view)
function movePlacingPiece(x, y)
    local key = editing and editing.only
    local widget = key and getMovableWidgets()[key]
    if widget then
        moveTo(key, widget, x, y)
        updateFrames()
    end
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
    placingSpot = nil
end

-- Keeps a piece where the player put it (over the game view too)
function confirmPlacedPiece(key)
    local widget = getMovableWidgets()[key]
    local piece = findPiece(key)
    if not widget or not piece then
        return
    end
    moveTo(key, widget, widget:getX(), widget:getY())
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
