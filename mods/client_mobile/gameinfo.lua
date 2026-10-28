-- Game info (ot-client#32): frame rate, latency and the client build over
-- the game view's top left corner, switched on in Settings > Display (the
-- top menu shows the first two on a desktop).

local gameInfo, gameInfoEvent

local function gameInfoLines()
    local options = modules.client_options
    local lines = {}
    if options.getOption('showFps') then
        table.insert(lines, tr('Frame rate: %dfps', g_app.getFps()))
    end
    -- (7.92 servers do not answer pings: no line then)
    local ping = g_game.getPing()
    if options.getOption('showPing') and ping >= 0 then
        table.insert(lines, tr('Ping: %dms', ping))
    end
    local updates = modules.client_updates
    local build = updates and updates.getBuildText and updates.getBuildText()
    if #lines > 0 and build then
        table.insert(lines, tr('Build: %s', build))
    end
    return lines
end

function updateGameInfo()
    if not gameInfo then
        return
    end
    local lines = gameInfoLines()
    -- in place of the top menu's own counters over the map (pingFps.otui)
    for _, child in ipairs(gameInfo:getParent():getChildren()) do
        if child ~= gameInfo and child:recursiveGetChildById('fps') then
            child:setVisible(false)
        end
    end
    gameInfo:setVisible(#lines > 0)
    gameInfo:setText(table.concat(lines, '\n'))
end

function stopGameInfo()
    if gameInfoEvent then
        removeEvent(gameInfoEvent)
        gameInfoEvent = nil
    end
    if gameInfo then
        gameInfo:destroy()
        gameInfo = nil
    end
end

function startGameInfo()
    stopGameInfo()
    local map = modules.game_interface.getMapPanel()
    if not map then
        return
    end
    gameInfo = g_ui.createWidget('MobileGameInfo', map)
    updateGameInfo()
    gameInfoEvent = cycleEvent(updateGameInfo, 1000)
end
