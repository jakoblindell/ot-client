return function(G)
    local tap, openHub = G.tap, G.openHub

    -- The hub's Settings, one page per tab
    for _, tab in ipairs({ 'Gameplay', 'Display', 'Controls', 'Layout', 'Optimization' }) do
        G.page('settings-' .. tab:lower(), { about = "the hub's Settings, " .. tab .. ' tab' }, function()
            openHub()
            tap(tr('Settings'))
            tap(tr(tab))
        end)
    end
end
