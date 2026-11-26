-- Client updates (ot-client#32): the browser build knows its own build
-- (/build.json, stamped by the Web Build workflow) and asks the website for
-- the newest one (version.json next to the page) at login and every 15
-- minutes. When they differ a gold icon appears; the new build loads when
-- the player logs out, or straight away with Apply now. Nothing changes in
-- the middle of a game.

local CHECK_EVERY = 15 * 60 * 1000
-- After a game ends the page reloads once the player has been out of the
-- game this long (the other modules have saved their settings by then, and a
-- quick pick of another character starts a login first)
local OUT_FOR = 1500
local WATCH_EVERY = 250
local LAST_BUILD_SETTING = 'clientUpdatesLastBuild'
local BUTTON_ID = 'clientUpdateButton'

local ownBuild -- {build = '2026-10-28-0927', commit = '46aee97'} or nil: a local build
local pending -- the newer build's version.json
local notified -- the build the toast was shown for
local checkEvent, toast, toastEvent, sheet, button
local exitEvent -- watches for the player to be out of the game
local outSince -- when the player was first seen out of the game
local justUpdated = false


local function readOwnBuild()
    for _, file in ipairs({ '/build.json', '/data/build.json' }) do
        if g_resources.fileExists(file) then
            local ok, info = pcall(function()
                return json.decode(g_resources.readFileContents(file))
            end)
            if ok and type(info) == 'table' and info.build then
                return info
            end
        end
    end
end

local function showToast(text)
    if toast then
        toast:destroy()
    end
    if toastEvent then
        removeEvent(toastEvent)
    end
    toast = g_ui.createWidget('UpdateToast', rootWidget)
    toast.text:setText(text)
    toast:setHeight(toast.text:getHeight() + 16)
    toastEvent = scheduleEvent(function()
        toastEvent = nil
        if toast then
            toast:destroy()
            toast = nil
        end
    end, 6000)
end

local function reload()
    if g_platform.reloadPage then
        g_platform.reloadPage()
    end
end

local function closeSheet()
    if sheet then
        sheet:destroy()
        sheet = nil
    end
end

local function applyNow()
    closeSheet()
    if g_game.isOnline() then
        -- the reload follows the logout (onGameEnd); a fight keeps you in
        g_game.safeLogout()
    else
        reload()
    end
end

function openSheet()
    if not pending then
        return
    end
    closeSheet()
    sheet = g_ui.createWidget('UpdateSheet', rootWidget)
    local panel = sheet.panel
    panel.text:setText(tr('A new version of the client is ready. It loads when you log out, or now if you like (this logs you out).'))
    panel.build:setText(tr('Build %s, you have build %s.', pending.build, ownBuild.build))
    panel.close.onClick = closeSheet
    panel.later.onClick = closeSheet
    panel.apply.onClick = applyNow
    sheet.onClick = closeSheet
    sheet.onEscape = closeSheet
    sheet:raise()
    sheet:focus()
end

local function showButton()
    if button or not pending then
        return
    end
    local mobile = modules.client_mobile
    if mobile and mobile.addToolbarButton then
        button = mobile.addToolbarButton(BUTTON_ID, 'update', tr('Update ready'), openSheet)
    end
    if not button and modules.client_topmenu then
        button = modules.client_topmenu.addRightGameButton(BUTTON_ID, tr('Update ready'),
            '/images/ui/ot/icons/update_on', openSheet)
    end
end

local function hideButton()
    if not button then
        return
    end
    local mobile = modules.client_mobile
    if mobile and mobile.removeToolbarButton then
        mobile.removeToolbarButton(BUTTON_ID)
    end
    if button and not button:isDestroyed() then
        button:destroy()
    end
    button = nil
end

local function onVersion(info)
    if type(info) ~= 'table' or not info.build or info.build == ownBuild.build then
        return false
    end
    pending = info
    showButton()
    if notified ~= info.build then
        notified = info.build
        showToast(tr('A client update is ready. It is applied when you log out.'))
    end
    return true
end

-- done(found): optional; found is nil when the website did not answer
function check(done)
    if not ownBuild or not HTTP then
        return
    end
    -- (next to the page; the time keeps caches out of it)
    HTTP.getJSON('version.json?t=' .. os.time(), function(info, err)
        local found
        if not err then
            found = onVersion(info)
        end
        if done then
            done(found)
        end
    end)
end

-- Out of the game: at the login screen or the character list, with no login
-- in flight and no reconnect going on. A character switch, the OK after a
-- death, a waiting list or a reconnect are not out.
local function isOut()
    if g_game.isOnline() or g_game.isLogging() then
        return false
    end
    local reconnect = modules.client_reconnect
    if reconnect and reconnect.isReconnecting and reconnect.isReconnecting() then
        return false
    end
    if CharacterList and CharacterList.isVisible() then
        return true
    end
    return EnterGame ~= nil and EnterGame.isVisible ~= nil and EnterGame.isVisible()
end

local function stopWatching()
    if exitEvent then
        removeEvent(exitEvent)
        exitEvent = nil
    end
    outSince = nil
end

local function watch()
    if not pending then
        stopWatching()
        return
    end
    if not isOut() then
        outSince = nil
        return
    end
    local now = g_clock.millis()
    outSince = outSince or now
    if now - outSince >= OUT_FOR then
        stopWatching()
        reload()
    end
end

local function onGameStart()
    -- back in a game: the update waits for the next logout
    stopWatching()
    if justUpdated then
        justUpdated = false
        showToast(tr('Updated to build %s.', ownBuild.build))
    end
    check()
    if checkEvent then
        removeEvent(checkEvent)
    end
    checkEvent = cycleEvent(check, CHECK_EVERY)
    showButton()
end

local function onGameEnd()
    if checkEvent then
        removeEvent(checkEvent)
        checkEvent = nil
    end
    closeSheet()
    if not pending or exitEvent then
        return
    end
    -- (it keeps watching until the player is out or the next game starts, so
    -- a login that fails still ends in the reload)
    outSince = nil
    exitEvent = cycleEvent(watch, WATCH_EVERY)
end

function getBuild()
    return ownBuild and ownBuild.build
end

-- "2026-10-28-0927" (when it was made, UTC), or nil for a local build
function getBuildText()
    return ownBuild and ownBuild.build
end

function isUpdatePending()
    return pending ~= nil
end

-- The login screen's version text says which build this is
local function labelLoginScreen()
    local label = rootWidget:recursiveGetChildById('clientVersionLabel')
    if label then
        label:setText(g_app.getName() .. '\n' .. tr('Build: %s', ownBuild.build) ..
            (ownBuild.commit and (' (' .. ownBuild.commit .. ')') or ''))
    end
end

function init()
    if not (g_platform.isBrowser and g_platform.isBrowser()) then
        return
    end
    ownBuild = readOwnBuild()
    if not ownBuild then
        return
    end
    g_ui.importStyle('updates')
    labelLoginScreen()
    -- the first game of a new build says so
    local last = g_settings.getString(LAST_BUILD_SETTING)
    if last ~= ownBuild.build then
        g_settings.set(LAST_BUILD_SETTING, ownBuild.build)
        g_settings.save()
        -- (said in the game: the login screen covers anything shown earlier)
        justUpdated = last ~= ''
    end
    connect(g_game, { onGameStart = onGameStart })
    -- first: a slot that returns true ends the others' turn
    connect(g_game, { onGameEnd = onGameEnd }, true)
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
    if checkEvent then
        removeEvent(checkEvent)
        checkEvent = nil
    end
    stopWatching()
    if toastEvent then
        removeEvent(toastEvent)
        toastEvent = nil
    end
    if toast then
        toast:destroy()
        toast = nil
    end
    closeSheet()
    hideButton()
end
