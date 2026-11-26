return function(G)
    -- The outfit screen for touch screens (ot-client#101), with sample outfits
    G.page('outfit', { about = 'the outfit screen for touch screens, with sample outfits' }, function()
        local mobile = modules.client_mobile
        if mobile and mobile.openOutfitSheet then
            mobile.openOutfitSheet({ type = 128, head = 78, body = 69, legs = 58, feet = 76, addons = 1 }, {
                { 128, 'Citizen', 3 }, { 129, 'Hunter', 3 }, { 130, 'Mage', 0 }, { 131, 'Knight', 1 },
            }, function() end)
        end
    end)
end
