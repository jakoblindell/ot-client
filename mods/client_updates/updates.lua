-- Client updates (ot-client#32): the browser build knows its own build
-- (/build.json, stamped by the Web Build workflow) and asks the website for
-- the newest one (version.json next to the page) at login and every 15
-- minutes. When they differ a gold icon appears; the new build loads when
-- the player logs out, or straight away with Apply now. Nothing changes in
-- the middle of a game.

local CHECK_EVERY = 15 * 60 * 1000
local LAST_BUILD_SETTING = 'clientUpdatesLastBuild'
local BUTTON_ID = 'clientUpdateButton'

local ownBuild -- {build = '2026-10-28-0927', commit = '46aee97'} or nil: a local build
local pending -- the newer build's version.json
local notified -- the build the toast was shown for
local checkEvent, toast, toastEvent, sheet, button
local applying = false
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
        applying = true
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

local function onGameStart()
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
    if not pending then
        return
    end
    -- a dropped connection that reconnects is not a logout
    local reconnect = modules.client_reconnect
    if not applying and reconnect and reconnect.willReconnect and reconnect.willReconnect() then
        return
    end
    -- (after the other modules have saved their settings for this game)
    scheduleEvent(reload, 1500)
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
