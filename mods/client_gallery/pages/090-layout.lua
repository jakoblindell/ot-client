return function(G)
    local widget, section, column = G.widget, G.section, G.column

    -- The touch layout without a game (client_mobile): the game screen with
    -- the pieces in their default places and some panels open, in portrait or
    -- landscape as the device is. Desktop devices show a note instead.
    local function sampleBars(game)
        local stats = game:recursiveGetChildById('mobileStats')
        if not stats then
            return
        end
        for id, part in pairs({ health = 1, mana = 0.72 }) do
            local bar = stats:getChildById(id)
            local fill = bar:getChildById('fill')
            fill:setWidth(math.floor((bar:getWidth() - 2) * part))
            fill:setVisible(true)
            bar:getChildById('text'):setText(math.floor(345 * part) .. ' / 345')
        end
    end

    local function layoutPage(panels, edit, setup, hotbar)
        return function(page)
            local mobile = modules.client_mobile
            if not (mobile and mobile.startLayoutPreview and mobile.startLayoutPreview(panels, edit, setup, hotbar)) then
                local c = column(page, 560)
                widget('OtHint', section(c, 'Touch layout', 40), function(w)
                    w:setWidth(500)
                    w:setText('The touch layout shows on phones and tablets only; the desktop layout is unchanged.')
                end)
                return
            end
            -- nothing of the gallery's own behind the game screen: it shows as on
            -- the device
            page:setBackgroundColor('#00000000')
            local game = modules.game_interface.getRootPanel()
            -- The empty game view (no map without a game) draws an animation
            -- whose phase depends on timing: covered with plain black, right
            -- above it and under everything else, so the screenshots repeat
            local map = modules.game_interface.getMapPanel()
            local cover = g_ui.createWidget('UIWidget', game)
            cover:setId('galleryMapCover')
            cover:setBackgroundColor('#000000')
            cover:setPhantom(true)
            cover:fill(map:getId())
            game:moveChildToIndex(cover, game:getChildIndex(map) + 1)
            local shown = { game }
            -- (windows of their own over the game screen)
            local containers = modules.client_containers and modules.client_containers.getWindow()
            local keypad = modules.game_joystick and modules.game_joystick.getPanel and modules.game_joystick.getPanel()
            for _, window in ipairs({ keypad and keypad:getParent(), containers }) do
                if window and window ~= rootWidget then
                    table.insert(shown, window)
                end
            end
            -- (the bars once they have their width)
            scheduleEvent(function() sampleBars(game) end, 600)
            return shown
        end
    end

    -- Containers and equipment; the map, skills and the hunt analyzer; Edit
    -- layout with containers and equipment
    G.page('layout-panels', { about = 'the touch layout (no game) with Containers and Equipment open in their ' ..
        'default places' }, layoutPage({ 'bag', 'equipment' }))
    G.page('layout-lists', { about = 'the touch layout with the Map, Skills and the Hunt analyzer open (the oldest ' ..
        'gives way when they do not all fit)' }, layoutPage({ 'map', 'skills', 'hunt' }))
    G.page('layout-edit', { about = 'Edit layout with Containers and Equipment open: outlines, - and +, the ' ..
        '"Customize Layout" window' }, layoutPage({ 'bag', 'equipment' }, true))
    -- The UI setup's first step, the piece placed partly over the game view;
    -- the same with a finger on the piece (the prompt hidden)
    G.page('layout-setup', { about = '"Let\'s build your UI", first step: the piece being placed partly over the ' ..
        'game view, with the prompt' }, layoutPage({}, false, 'placing'))
    G.page('layout-setup-held', { about = 'the same with a finger held on the piece: the prompt is hidden' },
        layoutPage({}, false, 'held'))
    -- The 3x3 hotbar with both extra rows on
    G.page('layout-extra-rows', { about = 'the touch layout with the 3x3 hotbar and both extra rows on' },
        layoutPage({}, false, nil, { extra1 = true, extra2 = true }))
end
