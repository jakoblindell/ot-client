-- Movement control for touch screens. Three styles (Options > Controls >
-- Movement, kept on this device):
--   dpad4  arrows up, down, left and right
--   dpad8  the same with the diagonals
--   stick  an analog stick: the knob follows the thumb, the direction is
--          its angle snapped to the 8 directions
-- Every style walks like a held arrow key (game_walk), so the first step
-- delay and the walking speed are the same as with the keyboard.
-- Turn from the centre (on unless turned off): a touch that starts in the
-- centre turns the character towards the thumb, like Ctrl+arrow, and never
-- walks; a touch that starts outside it walks.

local STYLE_SETTING = 'mobileMovementStyle'
local DEFAULT_STYLE = 'stick'
local TURN_SETTING = 'mobileTurnFromCentre'
STYLES = {
  { id = 'dpad4', name = 'D-Pad' },
  { id = 'dpad8', name = 'D-Pad (8-way)' },
  { id = 'stick', name = 'Analog stick' },
}
-- The centre that does not walk, as a share of the radius
local DEAD_ZONE = { dpad4 = 0.22, dpad8 = 0.22, stick = 0.18 }
local ARROWS = {
  { id = 'n', dir = Directions.North, x = 0, y = -1 },
  { id = 'ne', dir = Directions.NorthEast, x = 0.7071, y = -0.7071, diagonal = true },
  { id = 'e', dir = Directions.East, x = 1, y = 0 },
  { id = 'se', dir = Directions.SouthEast, x = 0.7071, y = 0.7071, diagonal = true },
  { id = 's', dir = Directions.South, x = 0, y = 1 },
  { id = 'sw', dir = Directions.SouthWest, x = -0.7071, y = 0.7071, diagonal = true },
  { id = 'w', dir = Directions.West, x = -1, y = 0 },
  { id = 'nw', dir = Directions.NorthWest, x = -0.7071, y = -0.7071, diagonal = true },
}
-- Directions by 45 degree sector, clockwise from east
local SECTORS = { Directions.East, Directions.SouthEast, Directions.South, Directions.SouthWest,
  Directions.West, Directions.NorthWest, Directions.North, Directions.NorthEast }

local style = DEFAULT_STYLE

local overlay
local keypad
local keypadUpdateEvent
local keypadMousePos = {x=0.5, y=0.5}
local firstStep = true
-- The keypad gets its own finger (touch-control), so the mouse button state
-- does not say whether it is held
local keypadHeld = false
local moveListener
local turnListener
-- Turn from the centre is on (the setting); this touch turns (it started in
-- the centre; nil: not decided yet, until its first update)
local turnFromCentre = true
local turnTouch
-- The last turn sent: the direction the character faces until the server
-- has had time to show it (getDirection still gives the old one), so a
-- quick circle neither sends a turn twice nor leaves one out
local sentTurn
local SENT_TURN_TIME = 1000 -- ms, plus the ping
-- A turn that had to wait for the shortest time between turns, and the
-- retry after the thumb was lifted
local wantedTurn
local turnRetryEvent

function init()
  if not g_platform.isMobile() then return end

  g_ui.importStyle('joystick_styles')
  overlay = g_ui.displayUI('joystick')
  keypad = overlay.keypad
  keypad.onGeometryChange = placeArrows
  setStyle(g_settings.getString(STYLE_SETTING), true)
  if g_settings.exists(TURN_SETTING) then
    turnFromCentre = g_settings.getBoolean(TURN_SETTING)
  end
  setupOptions()

  connect(keypad, {
    onMousePress = onKeypadTouchPress,
    onMouseRelease = onKeypadTouchRelease,  
    onMouseMove = onKeypadTouchMove
  })

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })
end

function terminate()
  if not g_platform.isMobile() then return end

  removeEvent(keypadUpdateEvent)
  removeEvent(turnRetryEvent)
  turnRetryEvent = nil

  disconnect(keypad, {
    onMousePress = onKeypadTouchPress,
    onMouseRelease = onKeypadTouchRelease,  
    onMouseMove = onKeypadTouchMove
  })

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })

  overlay:destroy()
  overlay = nil
  keypadUpdateEvent = nil
end

function hide()
  overlay:hide()
end

function show()
  overlay:show()
end

function onGameStart()
  keypad:raise()
  keypad:show()
end

function onGameEnd()
  -- a dropped connection being reconnected keeps the game screen as it is
  if modules.client_reconnect and modules.client_reconnect.willReconnect() then
    return
  end
  keypad:hide()
end

function addOnJoystickMoveListener(callback)
  moveListener = callback
end

-- callback(dir) sends a turn; returns false when it has to wait
function addOnJoystickTurnListener(callback)
  turnListener = callback
end

function onKeypadTouchPress(widget, pos, button)
  if button ~= MouseLeftButton then return false end

  keypadMousePos = {x=(pos.x - widget:getPosition().x) / widget:getWidth(), 
                    y=(pos.y - widget:getPosition().y) / widget:getHeight()}

  firstStep = true
  keypadHeld = true
  turnTouch = nil
  wantedTurn = nil
  removeEvent(turnRetryEvent)
  turnRetryEvent = nil
  executeWalk()

  return true
end

function onKeypadTouchMove(widget, pos, offset)
  keypadMousePos = {x=(pos.x - widget:getPosition().x) / widget:getWidth(), 
                    y=(pos.y - widget:getPosition().y) / widget:getHeight()}

  return true
end

function onKeypadTouchRelease(widget, pos, button)
  if button ~= MouseLeftButton then return false end

  keypadMousePos = {x=(pos.x - widget:getPosition().x) / widget:getWidth(), 
                    y=(pos.y - widget:getPosition().y) / widget:getHeight()}

  firstStep = false
  keypadHeld = false
  executeWalk()
  removeEvent(keypadUpdateEvent)
  -- the last direction the thumb turned to, if the turn had to wait
  if turnTouch and wantedTurn then
    turnRetryEvent = scheduleEvent(retryTurn, 60)
  end
  turnTouch = nil
  if moveListener then
    moveListener(nil)
  end

  keypad.pointer:setMarginTop(0)
  keypad.pointer:setMarginLeft(0)

  return true
end

-- The thumb's offset from the keypad's centre, -1..1 on each axis (the
-- keypad's shorter side is the diameter)
local function thumbOffset()
  local radius = math.min(keypad:getWidth(), keypad:getHeight()) / 2
  local x = (keypadMousePos.x - 0.5) * keypad:getWidth() / radius
  local y = (keypadMousePos.y - 0.5) * keypad:getHeight() / radius
  local length = math.sqrt(x * x + y * y)
  if length > 1 then
    x, y = x / length, y / length
  end
  return x, y
end

local function directionFor(x, y)
  if math.sqrt(x * x + y * y) < (DEAD_ZONE[style] or 0.2) then
    return nil
  end
  if style == 'dpad4' then
    if math.abs(y) > math.abs(x) then
      return y < 0 and Directions.North or Directions.South
    end
    return x < 0 and Directions.West or Directions.East
  end
  local sector = math.floor(math.atan2(y, x) / (math.pi / 4) + 0.5) % 8
  return SECTORS[sector + 1]
end

-- Turning: the 4 directions the character can face; a diagonal goes to the
-- larger axis
local function turnDirectionFor(x, y)
  if not directionFor(x, y) then
    return nil
  end
  if math.abs(y) > math.abs(x) then
    return y < 0 and Directions.North or Directions.South
  end
  return x < 0 and Directions.West or Directions.East
end

-- The direction the character faces, or will once the server has the turn
-- just sent
local function facing(player)
  if sentTurn and g_clock.millis() - sentTurn.at < SENT_TURN_TIME + g_game.getPing() then
    return sentTurn.dir
  end
  sentTurn = nil
  return player:getDirection()
end

-- Turns towards dir unless the character already faces it. False when the
-- turn has to wait (the shortest time between turns)
local function turnTowards(dir)
  local player = g_game.getLocalPlayer()
  if not player or not turnListener or facing(player) == dir then
    return true
  end
  if not turnListener(dir) then
    return false
  end
  sentTurn = { dir = dir, at = g_clock.millis() }
  return true
end

-- (once: after 60 ms the shortest time between turns has passed)
function retryTurn()
  turnRetryEvent = nil
  if wantedTurn and not keypadHeld then
    turnTowards(wantedTurn)
  end
  wantedTurn = nil
end

local function highlight(dir)
  for _, arrow in ipairs(keypad.arrows or {}) do
    arrow:setOn(arrow.dir == dir)
  end
end

function executeWalk()
  removeEvent(keypadUpdateEvent)
  keypadUpdateEvent = nil

  if not keypadHeld then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
    highlight(nil)
    return
  end

  keypadUpdateEvent = scheduleEvent(executeWalk, 20)
  local x, y = thumbOffset()
  if style == 'stick' then
    -- The knob follows the thumb up to the edge of the pad
    local radius = math.min(keypad:getWidth(), keypad:getHeight()) / 2
    keypad.pointer:setMarginLeft(x * radius)
    keypad.pointer:setMarginTop(y * radius)
  end

  local dir = directionFor(x, y)
  if turnTouch == nil then
    turnTouch = turnFromCentre and dir == nil
    if not turnTouch then
      -- walking: the character faces where it walks
      sentTurn = nil
    end
  end
  if turnTouch then
    dir = turnDirectionFor(x, y)
    highlight(dir)
    wantedTurn = dir and not turnTowards(dir) and dir or nil
    return
  end
  highlight(dir)
  if dir and moveListener then
    moveListener(dir, firstStep)
  end
end

-- Styles ---------------------------------------------------------------------

-- Puts the D-pad arrows around the centre (again when the pad is resized in
-- the layout editor)
function placeArrows(pad)
  pad = pad or keypad
  if not pad then
    return
  end
  local side = math.min(pad:getWidth(), pad:getHeight())
  local radius = side * 0.34
  local arrowSize = math.floor(side * 0.27)
  for _, arrow in ipairs(pad.arrows or {}) do
    arrow:setSize({ width = arrowSize, height = arrowSize })
    arrow:setMarginLeft(math.floor(arrow.offsetX * radius))
    arrow:setMarginTop(math.floor(arrow.offsetY * radius))
  end
end

function getStyle()
  return style
end

function getTurnFromCentre()
  return turnFromCentre
end

function setTurnFromCentre(on)
  turnFromCentre = on and true or false
  g_settings.set(TURN_SETTING, turnFromCentre)
end

function setStyle(newStyle, initial)
  local known = false
  for _, entry in ipairs(STYLES) do
    known = known or entry.id == newStyle
  end
  style = known and newStyle or DEFAULT_STYLE
  if not initial then
    g_settings.set(STYLE_SETTING, style)
  end

  dressPad(keypad, style)
end

-- Gives a pad the picture (and arrows) of a style: the keypad, or a picture
-- of one (the UI gallery)
function dressPad(pad, padStyle)
  for _, arrow in ipairs(pad.arrows or {}) do
    arrow:destroy()
  end
  pad.arrows = {}
  local stick = padStyle == 'stick'
  if pad.pointer then
    pad.pointer:setVisible(stick)
  end
  if stick then
    pad:setImageSource('/images/game/mobile/keypad')
  else
    pad:setImageSource('/images/game/mobile/dpad')
    for _, entry in ipairs(ARROWS) do
      if padStyle == 'dpad8' or not entry.diagonal then
        local arrow = g_ui.createWidget('JoystickArrow', pad)
        arrow:setImageSource('/images/game/mobile/dpad_' .. entry.id)
        arrow.dir = entry.dir
        arrow.offsetX, arrow.offsetY = entry.x, entry.y
        table.insert(pad.arrows, arrow)
      end
    end
    placeArrows(pad)
  end
end

-- The Movement choice at the top of Options > Controls (touch screens only)
function setupOptions()
  local options = modules.client_options
  local panel = options and options.getPanel and options.getPanel('generalPanel')
  local row = panel and panel:recursiveGetChildById('movementStylePanel')
  if not row then
    return
  end
  local box = row:getChildById('movementStyleBox')
  box:clearOptions()
  for _, entry in ipairs(STYLES) do
    box:addOption(tr(entry.name), entry.id)
  end
  box:setCurrentOptionByData(style, true)
  box.onOptionChange = function(widget, text, id)
    setStyle(id)
  end
  row:setHeight(30)
  row:setVisible(true)
end

function getPanel()
  return keypad
end