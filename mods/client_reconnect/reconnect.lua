-- Reconnects to the game after a dropped connection (Wi-Fi to mobile data, a
-- phone going to sleep, a tab left in the background). The game screen stays
-- behind an overlay while the same character is logged in again; the server
-- keeps the character in the world and shields it from monsters meanwhile.
-- A logout, a death, or a session the server ended on purpose (it says why:
-- kick, login from another location, shutdown) is not reconnected.

-- Seconds to wait before each attempt; after the last one the player chooses
local RETRY_DELAYS = { 1, 2, 4, 8, 15, 30 }
-- The server pings every few seconds: this long without any data means the
-- connection is dead, even if the socket still looks open
local SILENCE_LIMIT = 15000
-- An attempt that has not entered the game after this long has failed
local ATTEMPT_TIMEOUT = 10000
-- A logout asked for this recently explains the end of the game
local LOGOUT_WINDOW = 5000
-- The first attempts only show a small "Reconnecting..." notice (a phone
-- back from the background is usually in again within seconds); the box
-- with its buttons comes after these
local QUIET_ATTEMPTS = 3
-- Server messages worth another try: the server is still busy with the old
-- connection, or it is restarting
local RETRYABLE_ERRORS = {
    ['You are already logged in.'] = true,
    ['The server is shutting down.'] = true,
    ['The game is just going down.\nPlease try again later.'] = true,
    ['Gameworld is starting up. Please wait.'] = true,
}

local overlay
local tickEvent
local state = 'idle' -- idle, waiting, connecting, failed, final
local attempt = 0
local nextAttemptAt = 0
local attemptStartedAt = 0
local finalMessage
local login -- account, password, token, session key and the character entry
local logoutRequestedAt = 0
local sessionEnded = false -- the server said why it ended the session
local restore -- attack and follow targets to take up again
local lastTick = 0
local silenceGraceUntil = 0
local wasNetworkOnline, wasPageVisible = true, true
local originalLogout = {}

function isReconnecting()
    return state ~= 'idle'
end

-- Whether the game that is ending right now lost its connection and will be
-- reconnected. The game interface and the character list ask this from their
-- own onGameEnd handlers, which run before ours.
function willReconnect()
    if state ~= 'idle' then
        return true
    end
    if not login or sessionEnded or g_clock.millis() - logoutRequestedAt < LOGOUT_WINDOW then
        return false
    end
    local player = g_game.getLocalPlayer()
    return not (player and player:getHealth() == 0)
end

local function updateOverlay()
    if state == 'idle' then
        if overlay then
            overlay:hide()
        end
        return
    end
    if not overlay then
        overlay = g_ui.createWidget('ReconnectOverlay', rootWidget)
        local box = overlay:getChildById('box')
        box:getChildById('reconnectButton').onClick = reconnectNow
        box:getChildById('loginButton').onClick = backToLogin
    end
    local box = overlay:getChildById('box')
    local status = box:getChildById('status')
    local reconnectButton = box:getChildById('reconnectButton')
    local count = #RETRY_DELAYS

    local quiet = (state == 'waiting' or state == 'connecting') and attempt <= QUIET_ATTEMPTS and
                      g_platform.isNetworkOnline()
    overlay:setBackgroundColor(quiet and '#00000000' or '#000000a0')
    overlay:setPhantom(quiet)
    box:setVisible(not quiet)
    overlay:getChildById('notice'):setVisible(quiet)

    if state == 'waiting' and not g_platform.isNetworkOnline() then
        status:setText(tr('No network connection.\nReconnecting as soon as it is back...'))
    elseif state == 'waiting' then
        local seconds = math.max(1, math.ceil((nextAttemptAt - g_clock.millis()) / 1000))
        status:setText(tr('Reconnecting in %d s (attempt %d of %d)...', seconds, attempt, count))
    elseif state == 'connecting' then
        status:setText(tr('Reconnecting (attempt %d of %d)...', attempt, count))
    elseif state == 'failed' then
        status:setText(tr('Could not reconnect to the server.\nCheck your connection and try again.'))
    elseif state == 'final' then
        status:setText(finalMessage)
    end
    reconnectButton:setEnabled(state ~= 'connecting')
    reconnectButton:setText(state == 'waiting' and tr('Now') or tr('Reconnect'))

    overlay:show()
    overlay:raise()
end

local function scheduleNextAttempt()
    attempt = attempt + 1
    if attempt > #RETRY_DELAYS then
        state = 'failed'
    else
        state = 'waiting'
        nextAttemptAt = g_clock.millis() + RETRY_DELAYS[attempt] * 1000
    end
    updateOverlay()
end

local function startRound()
    attempt = 0
    scheduleNextAttempt()
end

local function attemptFailed()
    if state ~= 'connecting' then
        return
    end
    -- the protocol of a failed attempt may still be around
    if g_game.getProtocolGame() and not g_game.isOnline() then
        g_game.dropConnection()
    end
    scheduleNextAttempt()
end

local function startAttempt()
    if g_game.isOnline() then
        return
    end
    if g_game.getProtocolGame() then
        g_game.dropConnection()
    end
    state = 'connecting'
    attemptStartedAt = g_clock.millis()
    updateOverlay()
    local info = login.info
    local ok, err = pcall(g_game.loginWorld, login.account, login.password, info.worldName, info.worldHost,
                          info.worldPort, info.characterName, login.token, login.sessionKey)
    if not ok then
        g_logger.warning('Reconnect: ' .. tostring(err))
        attemptFailed()
    end
end

local function stop(newState, message)
    state = newState
    finalMessage = message
    updateOverlay()
end

function reconnectNow()
    if state == 'waiting' then
        nextAttemptAt = g_clock.millis()
    elseif state == 'failed' or state == 'final' then
        state = 'waiting'
        attempt = 1
        nextAttemptAt = g_clock.millis()
        updateOverlay()
    end
end

function backToLogin()
    stop('idle')
    restore = nil
    if g_game.getProtocolGame() and not g_game.isOnline() then
        g_game.dropConnection()
    end
    modules.game_interface.hide()
    modules.client_entergame.CharacterList.showAgain()
end

-- A connection with no data for too long is dead: end it, so the game end
-- handler reconnects. Not right after the page was suspended (background
-- tab, phone asleep): data that arrived meanwhile has not been read yet.
local function checkSilence(now)
    if not g_game.isOnline() or now < silenceGraceUntil then
        return
    end
    local protocol = g_game.getProtocolGame()
    if protocol and protocol:getElapsedTicksSinceLastRead() > SILENCE_LIMIT then
        g_logger.info('Reconnect: no data from the server for ' .. SILENCE_LIMIT / 1000 .. ' s')
        g_game.dropConnection()
    end
end

local function tick()
    local now = g_clock.millis()
    -- The client does not run while the page is suspended
    local resumed = lastTick > 0 and now - lastTick > 3000
    lastTick = now
    local networkOnline, pageVisible = g_platform.isNetworkOnline(), g_platform.isPageVisible()
    local cameBack = resumed or (networkOnline and not wasNetworkOnline) or (pageVisible and not wasPageVisible)
    wasNetworkOnline, wasPageVisible = networkOnline, pageVisible
    if cameBack then
        silenceGraceUntil = now + 5000
    end

    if state == 'idle' then
        checkSilence(now)
    elseif state == 'waiting' then
        if not networkOnline then
            updateOverlay()
        elseif cameBack or now >= nextAttemptAt then
            startAttempt()
        else
            updateOverlay()
        end
    elseif state == 'connecting' and not g_game.isOnline() then
        if not g_game.getProtocolGame() or now - attemptStartedAt > ATTEMPT_TIMEOUT then
            attemptFailed()
        end
    end
end

local function restoreTargets()
    local targets = restore
    restore = nil
    if not targets or not g_game.isOnline() then
        return
    end
    local attacking = targets.attack and g_map.getCreatureById(targets.attack)
    if attacking and not g_game.getAttackingCreature() then
        g_logger.info('Reconnect: attacking ' .. attacking:getName() .. ' again')
        g_game.attack(attacking)
    end
    local following = targets.follow and g_map.getCreatureById(targets.follow)
    if following and not g_game.getFollowingCreature() then
        g_logger.info('Reconnect: following ' .. following:getName() .. ' again')
        g_game.follow(following)
    end
end

local function onGameStart()
    sessionEnded = false
    logoutRequestedAt = 0
    if G.lastLogin then
        login = {
            account = G.account,
            password = G.password,
            token = G.authenticatorToken,
            sessionKey = G.sessionKey,
            info = G.lastLogin,
        }
    end
    if state ~= 'idle' then
        g_logger.info('Reconnect: back in the game after ' .. attempt .. ' attempt(s)')
        stop('idle')
        -- the creatures arrive with the first map packets
        scheduleEvent(restoreTargets, 300)
    end
end

local function onGameEnd()
    if state ~= 'idle' or not willReconnect() then
        return
    end
    local attacking, following = g_game.getAttackingCreature(), g_game.getFollowingCreature()
    restore = {
        attack = attacking and attacking:getId(),
        follow = following and following:getId(),
    }
    g_logger.info('Reconnect: connection lost')
    startRound()
end

local function onLoginError(message)
    if state == 'idle' then
        -- while playing, this is the server saying why it ends the session
        if g_game.isOnline() and not RETRYABLE_ERRORS[message] then
            sessionEnded = true
        end
    elseif state == 'connecting' then
        if RETRYABLE_ERRORS[message] then
            attemptFailed()
        else
            stop('final', message)
        end
    end
end

local function onSessionEnd()
    sessionEnded = true
end

local function onConnectionError()
    attemptFailed()
end

local function onLoginWait(message, seconds)
    if state == 'connecting' then
        state = 'waiting'
        nextAttemptAt = g_clock.millis() + seconds * 1000
        updateOverlay()
    end
end

function init()
    g_ui.importStyle('reconnect')
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onLoginError = onLoginError,
        onSessionEnd = onSessionEnd,
        onConnectionError = onConnectionError,
        onLoginWait = onLoginWait,
    })
    -- Remember logouts asked for by the player (the C++ side calls its own
    -- functions, so a lost connection does not count)
    for _, name in ipairs({ 'safeLogout', 'forceLogout', 'cancelLogin' }) do
        local original = g_game[name]
        originalLogout[name] = original
        g_game[name] = function(...)
            logoutRequestedAt = g_clock.millis()
            return original(...)
        end
    end
    tickEvent = cycleEvent(tick, 250)
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onLoginError = onLoginError,
        onSessionEnd = onSessionEnd,
        onConnectionError = onConnectionError,
        onLoginWait = onLoginWait,
    })
    for name, original in pairs(originalLogout) do
        g_game[name] = original
    end
    originalLogout = {}
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    if overlay then
        overlay:destroy()
        overlay = nil
    end
end
