return function(G)
    -- Text over the map (ot-client#112): names, health and mana bars and a
    -- yell, and names at the view's edges, drawn by the map itself at the size
    -- the game screen gives them. No server and no game sprites in this build:
    -- the game screen without a game, the creatures and ground not drawn (the
    -- map shows what is behind it). Damage numbers are left out: they move, so
    -- no two screenshots would match.
    G.page('map', { about = 'the game screen without a server: a player and monsters with names, health and mana ' ..
        "bars and a yell, two of them on the view's top row and left edge, drawn by the map at its real size " ..
        '(no game sprites: creatures and ground are not drawn)' }, function()
        local gi = modules.game_interface
        if not g_game.startPreview or not gi or not gi.getMapPanel then
            g_logger.error('[gallery] map: this build has no map preview')
            return
        end
        local map = gi.getMapPanel()
        local center = { x = 1000, y = 1000, z = 7 }
        local player = g_game.startPreview()
        player:setId(0x10000001)
        player:setName('Ludacrix')
        player:setHealthPercent(100)
        player:setHealth(955, 955)
        player:setMana(4710, 4710)
        g_map.addThing(player, center, -1)

        local ghostPos = { x = center.x - 2, y = center.y + 1, z = center.z }
        local ghost = Creature.create()
        ghost:setId(0x40000001)
        ghost:setName('Ghost')
        ghost:setHealthPercent(60)
        g_map.addThing(ghost, ghostPos, -1)
        -- on the top row and at the left edge of the 15x11 view: their names and
        -- bars stay inside it
        local edges = {
            { 0x40000002, 'Rat', 100, { x = center.x + 3, y = center.y - 5, z = center.z } },
            { 0x40000003, 'Cave Rat', 30, { x = center.x - 7, y = center.y + 3, z = center.z } },
        }
        for _, edge in ipairs(edges) do
            local creature = Creature.create()
            creature:setId(edge[1])
            creature:setName(edge[2])
            creature:setHealthPercent(edge[3])
            g_map.addThing(creature, edge[4], -1)
        end
        -- (a yell: shown twice as long as a word, well past the screenshot)
        local text = StaticText.create()
        text:addMessage('Ghost', MessageModes.MonsterYell, 'LET ME OUT!')
        g_map.addStaticText(text, ghostPos)

        map:setDrawNames(true)
        map:setDrawHealthBars(true)
        map:setDrawManaBar(true)
        -- (no light from the server: the map would be night-dark)
        map:setDrawLights(false)
        map:setCameraPosition(center)
        -- the whole game screen, laid out as in a game; its texts are not this
        -- page's to check
        local screen = gi.getRootPanel()
        screen:show()
        local mobile = modules.client_mobile
        if mobile and mobile.relayout then
            mobile.relayout()
        end
        return { screen }, true
    end)
end
