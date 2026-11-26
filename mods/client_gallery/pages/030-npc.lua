-- The NPC dialog
return function(G)
    local receive = G.receive

    G.page('npc', { about = 'the NPC dialog with a sample NPC (text, keywords, shop)' }, function()
        receive(103, {
            id = 1, npc = 'Benjamin', money = 1500,
            text = 'Hello, traveller. I sell runes and fluids. Ask me for a trade, or about the news.',
            -- every word the NPC takes (ot-server#88): more than four rows scroll
            keywords = { 'trade', 'news', 'job', 'name', 'time', 'king', 'thais', 'carlin', 'venore', 'magic',
                'fluids', 'runes', 'blessings', 'rumours', 'tibia', 'excalibug', 'ferumbras', 'library' },
            buy = {
                { item = 3160, name = 'ultimate healing rune', price = 175, words = 'buy ultimate healing rune' },
                { item = 3155, name = 'sudden death rune', price = 325, words = 'buy sudden death rune' },
                { item = 3152, name = 'intense healing rune', price = 95, words = 'buy intense healing rune' },
            },
            sell = { { item = 3147, name = 'blank rune', price = 5, words = 'sell blank rune' } },
        })
        for _, child in ipairs(g_ui.getRootWidget():getChildren()) do
            if child:getStyleName() == 'NpcDialogWindow' then
                return { child }
            end
        end
    end)
end
