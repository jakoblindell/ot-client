-- The components on their own: buttons, controls, text, the touch pieces and
-- the movement pad
return function(G)
    local widget, section, button, centered, column, roundFace =
        G.widget, G.section, G.button, G.centered, G.column, G.roundFace

    G.page('buttons', { about = 'OtButton states, primary, danger, icon and help buttons, tabs' }, function(page)
        local c = column(page, 560)
        local row = section(c, 'OtButton: normal, checked, on, disabled', 40)
        button('OtButton', row, 'Normal 2', 110)
        button('OtButton', row, 'Checked', 110, 'checked')
        button('OtButton', row, 'On', 110, 'on')
        button('OtButton', row, 'Disabled', 110, 'disabled')

        row = section(c, 'OtButtonPrimary, OtButtonDanger, OtIconButton, OtHelpButton', 40)
        button('OtButtonPrimary', row, 'Confirm', 110)
        button('OtButtonDanger', row, 'Delete', 110)
        button('OtIconButton', row, 'X')
        button('OtIconButton', row, '-')
        button('OtIconButton', row, '+')
        centered('OtHelpButton', row, 30)

        row = section(c, 'OtTabRow with OtTab (first checked)', 36)
        local tabs = widget('OtTabRow', row, function(w) w:setWidth(400) end)
        button('OtTab', tabs, 'Quests', nil, 'checked')
        button('OtTab', tabs, 'Tasks')
        button('OtTab', tabs, 'Achievements')
        button('OtTab', tabs, 'Chests')
    end)

    G.page('controls', { about = 'checks, progress bars, a stepper, setting rows in a panel, contrast panel' }, function(page)
        local c = column(page, 560)
        local row = section(c, 'OtCheck: off, on, disabled on', 40)
        widget('OtCheck', row)
        widget('OtCheck', row, function(w) w:setChecked(true) end)
        widget('OtCheck', row, function(w) w:setChecked(true); w:setEnabled(false) end)

        row = section(c, 'OtProgress: 0, 45 and 100 percent', 24)
        for _, percent in ipairs({ 0, 45, 100 }) do
            widget('OtProgress', row, function(w)
                w:setWidth(150)
                w:setPercent(percent)
                w:setText(percent .. ' / 100')
            end)
        end

        row = section(c, 'Stepper: OtIconButton, OtValue, OtIconButton', 40)
        button('OtIconButton', row, '-')
        widget('OtValue', row, function(w) w:setText('5') end)
        button('OtIconButton', row, '+')

        row = section(c, 'OtSettingRow in an OtPanel; an OtPanel on (contrast)', 136)
        local panel = widget('OtPanel', row, function(w)
            w:setSize({ width = 380, height = 136 })
            w:setLayout(UIVerticalLayout.create(w))
        end)
        local setting = widget('OtSettingRow', panel)
        setting:getChildById('title'):setText('Sharpness')
        local controls = setting:getChildById('controls')
        button('OtButton', controls, 'Normal', 90, 'checked')
        button('OtButton', controls, 'High', 90)
        setting = widget('OtSettingRow', panel)
        setting:getChildById('title'):setText('Vibration')
        widget('OtCheck', setting:getChildById('controls'), function(w) w:setChecked(true) end)

        local contrast = widget('OtPanel', row, function(w)
            w:setSize({ width = 160, height = 136 })
            w:setOn(true)
        end)
        widget('OtLabel', contrast, function(w)
            w:setText('Contrast on')
            w:addAnchor(AnchorTop, 'parent', AnchorTop)
            w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            w:resizeToText()
        end)
    end)

    G.page('text', { about = 'title, heading, label, text, hint, the colour tokens' }, function(page)
        local c = column(page, 560)
        local row = section(c, 'OtTitle', 20)
        widget('OtTitle', row, function(w) w:setText('Journal') end)

        row = section(c, 'OtHeading', 28)
        widget('OtHeading', row, function(w)
            w:setWidth(400)
            w:getChildById('text'):setText('QUESTS')
        end)

        row = section(c, 'OtLabel, small font', 16)
        widget('OtLabel', row, function(w) w:setText('Hunter rank: Skilled Hunter'); w:resizeToText() end)
        widget('GalleryFontSmall', row, function(w) w:setText('Small text: 12 of 21 unlocked') end)

        row = section(c, 'OtText (wraps), OtHint', 60)
        widget('OtText', row, function(w)
            w:setWidth(260)
            w:setText('Kill 100 rotworms in the sewers under Thais and report back to the Taskmaster.')
        end)
        widget('OtHint', row, function(w)
            w:setWidth(260)
            w:setText('Hidden achievements show their name once you have them.')
        end)

        row = section(c, 'Colours: gold, gold dark, positive, negative, muted', 28)
        widget('GallerySwatchGold', row, function(w) w:setText('gold') end)
        widget('GallerySwatchGoldDark', row, function(w) w:setText('dark') end)
        widget('GallerySwatchPositive', row, function(w) w:setText('positive') end)
        widget('GallerySwatchNegative', row, function(w) w:setText('negative') end)
        widget('GallerySwatchMuted', row, function(w) w:setText('muted') end)
    end)

    G.page('touch', { about = 'round hotbar slots at 32-64 px, chat, P1 and pencil buttons, health/mana bars, ' ..
        'toolbar' }, function(page)
        local c = column(page, 560)
        -- (no items in them: the game's sprites are not part of the client build)
        local row = section(c, 'Hotbar slot: 32, 40, 48 and 64 px', 64)
        for _, size in ipairs({ 32, 40, 48, 64 }) do
            centered('MobileHotbarRoundButton', row, size, function(w)
                w:setSize({ width = size, height = size })
                roundFace(w, 'gold')
            end)
        end

        row = section(c, 'Chat button: closed, open; preset and edit: off, on', 48)
        centered('MobileChatButton', row, 48, function(w) roundFace(w, 'gold') end)
        centered('MobileChatButton', row, 48, function(w)
            roundFace(w, 'gold')
            w:setChecked(true)
            w:getChildById('icon'):setImageSource('/images/ui/ot/icons/chat_on')
        end)
        for _, on in ipairs({ false, true }) do
            centered('MobileHotbarPresetRow', row, 84, function(w)
                for _, id in ipairs({ 'preset', 'edit' }) do
                    local b = w:getChildById(id)
                    roundFace(b, 'silver')
                    b:setOn(on)
                end
                if on then
                    w:getChildById('edit'):getChildById('icon'):setImageSource('/images/ui/ot/icons/edit_on')
                end
            end)
        end

        row = section(c, 'Health and mana bars: full, 30 percent', 22)
        for _, part in ipairs({ 1, 0.3 }) do
            widget('MobileStats', row, function(w)
                w:setWidth(260)
                for _, id in ipairs({ 'health', 'mana' }) do
                    local bar = w:getChildById(id)
                    local fill = bar:getChildById('fill')
                    if id == 'mana' then
                        fill:setImageSource('/mods/client_mobile/images/bar_mana')
                    end
                    fill:setWidth(math.floor((130 - 3 - 2) * part))
                    bar:getChildById('text'):setText(math.floor(345 * part) .. ' / 345')
                end
            end)
        end

        row = section(c, 'Toolbar: the menu, then panels with dividers; boxed: the panel is on the screen', 44)
        widget('MobileToolbar', row, function(w)
            w:setWidth(340)
            local buttons = w:getChildById('buttons')
            for i, icon in ipairs({ 'menu', 'equipment', 'map', 'battle', 'containers' }) do
                if i > 1 then
                    widget('MobileToolbarDivider', buttons)
                end
                widget(i == 1 and 'MobileToolbarMenuButton' or 'MobileToolbarButton', buttons, function(b)
                    b:setIcon('/images/ui/ot/icons/' .. icon)
                    b:setChecked(i == 3 or i == 5)
                end)
            end
        end)
    end)


    -- The movement pad's styles at their first size, as game_joystick draws them
    G.page('movement', { about = 'the movement pad: D-Pad, D-Pad (8-way), a lit arrow, analog stick' }, function(page)
        local joystick = modules.game_joystick
        if not joystick or not joystick.dressPad then
            return
        end
        local c = column(page, 360)
        local function pad(parent, style, lit)
            local w = widget('GalleryPad', parent)
            joystick.dressPad(w, style)
            for _, arrow in ipairs(w.arrows) do
                arrow:setOn(arrow.dir == lit)
            end
        end
        local row = section(c, 'Movement: D-Pad, D-Pad (8-way)', 150)
        pad(row, 'dpad4')
        pad(row, 'dpad8')
        row = section(c, 'A lit arrow (walking or turning); analog stick', 150)
        pad(row, 'dpad8', Directions.North)
        pad(row, 'stick')
    end)
end
