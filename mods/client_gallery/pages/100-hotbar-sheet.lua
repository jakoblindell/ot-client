return function(G)
    local widget = G.widget

    -- The sheet a long press on a hotbar slot opens (ot-client#159), for slot 3
    -- of bar 1 (a stand-in: the sheet reads the ids "bar.slot"). No character
    -- here: the page names the tab and the vocation (spell data ids).
    local function hotbarSheet(page, tab, vocation)
        local mobile = modules.client_mobile
        if not (mobile and mobile.openHotbarSheet) then
            return
        end
        local bar = widget('UIWidget', page, function(w) w:hide() end)
        local slot = widget('UIWidget', widget('UIWidget', bar), function(w) w:setId('1.3') end)
        mobile.openHotbarSheet(slot, { tab = tab, vocation = vocation })
    end

    -- A druid's spells, by magic level
    G.page('hotbar-sheet', { about = "the sheet a long press on a hotbar slot opens: a druid's Spells tab" }, function(page)
        hotbarSheet(page, 'spells', 2)
    end)

    -- The house spells, for every vocation
    G.page('hotbar-sheet-house', { about = "that sheet's House tab (the house spells)" }, function(page)
        hotbarSheet(page, 'house', 2)
    end)

    -- A character without a vocation (Rookgaard): no spells yet
    G.page('hotbar-sheet-novocation', { about = 'its Spells tab for a character without a vocation' }, function(page)
        hotbarSheet(page, 'spells', 0)
    end)
end
