-- Report a problem (ot-client#67, ot-server#48).
--
-- Opened from the hub (Settings › Report a problem). A screenshot is taken as
-- the sheet opens (so it shows the game, not the sheet). Send asks the game
-- server for a one-time token (extended opcode 106, "reportToken"; the answer
-- arrives through client_tasks), then posts the report to the website:
--   text, info (device, client, UI), the last log lines, the screenshot.
-- Nothing is sent before the player taps Send.

local OPCODE = 106
local SCREENSHOT = '/report-screenshot.png'
local LOG_LINES = 200
-- how long the website gets for the upload (seconds)
local POST_TIMEOUT = 60

local sheet
local sending = false
local tokenTimeout

local function setStatus(text, isError)
    if sheet then
        local status = sheet.panel.status
        status:setText(text or '')
        status:setColor(isError and '#e05050' or '#a8a8a8')
    end
end

local function close()
    if tokenTimeout then
        removeEvent(tokenTimeout)
        tokenTimeout = nil
    end
    sending = false
    if sheet then
        sheet:destroy()
        sheet = nil
    end
end

-- Details ------------------------------------------------------------------------

local function rectOf(widget)
    local r = widget:getRect()
    return { x = r.x, y = r.y, w = r.width, h = r.height }
end

-- What is on screen: visible widgets with an id, a few levels deep
local function uiState()
    local list = {}
    local function walk(widget, depth, path)
        for _, child in ipairs(widget:getChildren()) do
            if #list >= 300 then
                return
            end
            if child:isVisible() then
                local id = child:getId() or ''
                local name = path .. '/' .. id
                if id ~= '' and not id:match('^widget%d+$') then
                    table.insert(list, { id = name, style = child:getStyleName(), rect = rectOf(child) })
                end
                if depth < 3 then
                    walk(child, depth + 1, name)
                end
            end
        end
    end
    walk(g_ui.getRootWidget(), 1, '')
    return list
end

local function details()
    local browser = {}
    pcall(function() browser = json.decode(g_platform.getBrowserInfo()) end)
    local build = {}
    pcall(function() build = json.decode(g_resources.readFileContents('/build.json')) end)
    local ratio = g_window.getPixelRatio and g_window.getPixelRatio() or 1
    return {
        device = {
            platform = g_platform.isMobile() and 'touch' or 'desktop',
            screen = (browser.window or '?') .. ' @' .. tostring(browser.pixelRatio or ratio),
            browser = browser,
            canvas = g_window.getWidth() .. 'x' .. g_window.getHeight(),
            pixelRatio = ratio,
            density = g_window.getDisplayDensity(),
            renderer = g_graphics.getRenderer(),
            gl = g_graphics.getVersion(),
        },
        client = {
            build = build.build or g_app.getVersion(),
            commit = build.commit,
            fps = g_app.getFps(),
            ping = g_game.isOnline() and g_game.getPing() or -1,
            hudScale = g_window.getDisplayDensity() / ratio,
            sharpness = modules.client_mobile and modules.client_mobile.getSharpness and modules.client_mobile.getSharpness() or 1,
            touchMode = g_platform.getTouchMode and g_platform.getTouchMode() or '',
            character = g_game.isOnline() and g_game.getCharacterName() or '',
            position = (function()
                local player = g_game.getLocalPlayer()
                local pos = player and player:getPosition()
                return pos and (pos.x .. ',' .. pos.y .. ',' .. pos.z) or ''
            end)(),
        },
        ui = uiState(),
    }
end

local function screenshotBase64()
    if not g_resources.fileExists(SCREENSHOT) then
        return nil
    end
    local ok, data = pcall(g_resources.readFileContents, SCREENSHOT)
    if not ok or not data or #data == 0 then
        return nil
    end
    return base64.encode(data)
end

-- Sending ---------------------------------------------------------------------------

local function failed(text)
    sending = false
    setStatus(text, true)
    if sheet then
        sheet.panel.footer.send:setEnabled(true)
    end
end

local function post(url, payload)
    if url == nil or url == '' then
        url = '/api/client-report'
    end
    local operation = g_http.post(url, json.encode(payload), POST_TIMEOUT, true)
    if not operation or operation < 0 then
        failed(tr('The report could not be sent.'))
        return
    end
    HTTP.operations[operation] = {
        type = 'post', json = true, url = url,
        callback = function(data, err)
            if err then
                local status = tostring(err):match('http_status::(%d+)')
                if status == '403' then
                    failed(tr('The report expired. Please send it again.'))
                elseif status == '413' then
                    failed(tr('The report is too large.'))
                elseif status == '429' then
                    failed(tr('Too many reports. Try again later.'))
                else
                    failed(tr('The report could not be sent') .. ' (' .. tostring(err) .. ').')
                end
                return
            end
            sending = false
            setStatus(tr('Sent. Thank you!'))
            if sheet then
                sheet.panel.text:setEnabled(false)
            end
            scheduleEvent(close, 1500)
        end,
    }
end

-- The game server's answer to "reportToken" (through client_tasks)
function onToken(answer)
    if not sending or not sheet then
        return
    end
    if tokenTimeout then
        removeEvent(tokenTimeout)
        tokenTimeout = nil
    end
    if type(answer) ~= 'table' or answer.error or not answer.token then
        failed(type(answer) == 'table' and answer.error or tr('The report could not be sent.'))
        return
    end
    setStatus(tr('Sending...'))
    local ok, info = pcall(details)
    post(answer.url, {
        token = answer.token,
        text = sheet.panel.text:getText(),
        info = ok and info or { error = tostring(info) },
        logs = g_logger.getRecentMessages and g_logger.getRecentMessages(LOG_LINES) or '',
        screenshot = screenshotBase64(),
    })
end

local function send()
    if sending or not sheet then
        return
    end
    local protocol = g_game.getProtocolGame()
    if not g_game.isOnline() or not protocol then
        failed(tr('Log in to a character to send a report.'))
        return
    end
    if sheet.panel.text:getText():trim() == '' then
        failed(tr('Please say what went wrong.'))
        return
    end
    sending = true
    sheet.panel.footer.send:setEnabled(false)
    setStatus(tr('Preparing...'))
    protocol:sendExtendedOpcode(OPCODE, 'reportToken')
    tokenTimeout = scheduleEvent(function()
        tokenTimeout = nil
        failed(tr('The server did not answer. Try again.'))
    end, 10000)
end

-- Opening ---------------------------------------------------------------------------

local opening = false

local function show()
    opening = false
    if sheet then
        return
    end
    sheet = g_ui.createWidget('ReportSheet', g_ui.getRootWidget())
    sheet.onMouseRelease = function(widget, pos)
        -- a tap beside the panel closes it, unless sending
        if not sending and not widget.panel:containsPoint(pos) then
            close()
        end
        return true
    end
    sheet.panel.footer.cancel.onClick = close
    sheet.panel.footer.send.onClick = send
    sheet.panel.text:focus()
    sheet:raise()
end

function open()
    if sheet or opening then
        return
    end
    -- the screen as the player sees it: a moment after the hub closed (the
    -- interface is redrawn a frame or two later), then the sheet, once the
    -- picture is taken (after the next frame)
    opening = true
    scheduleEvent(function()
        pcall(g_app.doScreenshot, SCREENSHOT)
        scheduleEvent(show, 250)
    end, 200)
end

function init()
    g_ui.importStyle('report')
end

function terminate()
    close()
end
