return function(G)
    -- Text windows (ot-client#124): a letter as the server opens it (Edit Text),
    -- the same letter only to read, and a house list (Edit List). The -keyboard
    -- pages are the same windows with the on-screen keyboard open: gallery.js
    -- sets keyboardVisibleTop/Bottom as the page would (shell.html).
    local SAMPLE_LETTER = 'Dear Aren,\n\nthe ferry leaves at dawn. Bring the map, two ropes and something to eat; ' ..
        'the island has nothing but rats.\n\nIf the weather turns, wait for me at the lighthouse.\n\n- Mira'

    local function textWindows()
        return modules.game_textwindow
    end

    local function letter()
        textWindows().onGameEditText(1, 0, 1000, SAMPLE_LETTER, 'Mira', '18 Nov 2026')
    end
    G.page('letter', { about = 'a letter in Edit Text, to write (with its limit)' }, letter)
    G.page('letter-keyboard', { about = 'the same with the on-screen keyboard open', keyboard = true }, letter)

    G.page('letter-read', { about = 'the same letter, only to read' }, function()
        textWindows().onGameEditText(2, 0, #SAMPLE_LETTER, SAMPLE_LETTER, 'Mira', '18 Nov 2026')
    end)

    local function houseList()
        textWindows().onGameEditList(3, 1, 'Mira\nToren\nLune\nKasimir\nOld Bess')
    end
    G.page('house-list', { about = 'a house list in Edit List' }, houseList)
    G.page('house-list-keyboard', { about = 'the same with the on-screen keyboard open', keyboard = true }, houseList)
end
