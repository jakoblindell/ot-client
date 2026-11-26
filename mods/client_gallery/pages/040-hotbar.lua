-- The hotbar settings sheet
return function(G)
    G.page('hotbar', { about = 'the hotbar settings sheet' }, function()
        local mobile = modules.client_mobile
        if mobile and mobile.openHotbarSettings then
            mobile.openHotbarSettings()
        end
    end)
end
