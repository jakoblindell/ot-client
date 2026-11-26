-- Throwaway page (demo for #181): a page added in its own file, no baseline
return function(G)
    G.page('demo-new', { about = 'a new page with no baseline yet' }, function(page)
        local c = G.column(page, 560)
        G.button('OtButton', G.section(c, 'A new page', 40), 'New', 110)
    end)
end
