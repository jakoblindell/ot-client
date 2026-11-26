-- The hub and the journal, with sample data sent as the server would
return function(G)
    local FIXED_TIME, receive, tap, openHub = G.FIXED_TIME, G.receive, G.tap, G.openHub

    local SAMPLE_ACHIEVEMENTS = {
        unlocked = 1, count = 4, points = 1, totalPoints = 9,
        categories = { { id = 'milestones', name = 'Milestones' }, { id = 'hunting', name = 'Hunting' }, { id = 'luck', name = 'Luck' } },
        list = {
            { id = 1, category = 'milestones', points = 1, name = 'First Steps', text = 'Reach level 20.', unlockedAt = FIXED_TIME },
            { id = 2, category = 'milestones', points = 2, name = 'Seasoned', text = 'Reach level 50.' },
            { id = 20, category = 'hunting', points = 1, name = 'Rat Catcher', text = 'Kill 100 rats.', progress = 45, target = 100 },
            { category = 'luck', points = 5, hidden = true },
        },
    }

    local SAMPLE_QUESTS = {
        part = 'quests', regions = { 'Mainland', 'Rookgaard' },
        quests = {
            { name = 'The Ancient Tombs', started = true, complete = false, done = 2, missions = 7, text = 'Find the third tomb under the desert.' },
            { name = 'Factions', started = false, done = 0, missions = 3 },
            { name = "Sam's Old Backpack", started = true, complete = true, done = 2, missions = 2, text = 'Sam has his backpack back.' },
        },
    }

    local SAMPLE_CHESTS = {
        part = 'chests', first = true, more = false,
        chests = {
            { name = 'Boots Of Haste Quest', reward = 'Boots Of Haste', region = 'Mainland', opened = true },
            { name = '100x Gold Coin Quest', reward = '100x Gold Coin', region = 'Rookgaard', opened = false },
        },
    }

    local function journalData()
        receive(106, { achievements = SAMPLE_ACHIEVEMENTS })
        receive(106, { journal = SAMPLE_QUESTS })
        receive(106, { journal = SAMPLE_CHESTS })
    end

    G.page('hub', { about = "the hub's front page" }, function()
        openHub()
    end)

    G.page('journal', { about = 'Journal > Quests, with sample quests' }, function()
        journalData()
        openHub()
        tap(tr('Journal'))
    end)

    G.page('achievements', { about = 'Journal > Achievements: unlocked, in progress, hidden' }, function()
        journalData()
        openHub()
        tap(tr('Journal'))
        tap(tr('Achievements'))
    end)
end
