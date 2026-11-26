-- The circles' size on screen (scaled to fit the game view) and in their
-- images (image clips are in image pixels)
imageSizeBroad = 0
imageSizeThin = 0
imageSourceBroad = 0
imageSourceThin = 0
circleScale = 1
-- The circles keep this far from the edges of the game view
local CIRCLE_EDGE = 4

mapPanel = modules.game_interface.getMapPanel()
gameRootPanel = modules.game_interface.gameBottomPanel
gameLeftPanel = modules.game_interface.getLeftPanel()
gameTopMenu = modules.client_topmenu.getTopMenu()

function currentViewMode()
    return modules.game_interface.currentViewMode
end

healthCircle = nil
manaCircle = nil
manaShieldCircle = nil
manaShieldCircleFront = nil
expCircle = nil
skillCircle = nil

healthCircleFront = nil
manaCircleFront = nil
expCircleFront = nil
skillCircleFront = nil

manaShieldImageSizeBroad = 0
manaShieldImageSizeThin = 0
manaShieldImageSourceBroad = 0
manaShieldImageSourceThin = 0
manaShieldCircleOffsetX = -52
manaShieldCircleOffsetY = 7

optionPanel = nil

isHealthCircle = not g_settings.getBoolean('healthcircle_hpcircle')
isManaCircle = not g_settings.getBoolean('healthcircle_mpcircle')
isExpCircle = g_settings.getBoolean('healthcircle_expcircle')
isSkillCircle = g_settings.getBoolean('healthcircle_skillcircle')
skillTypes = g_settings.getNode('healthcircle_skilltypes')
skillsLoaded = false

if not skillTypes then
    skillTypes = {}
end

distanceFromCenter = g_settings.getNumber('healthcircle_distfromcenter')
opacityCircle = g_settings.getNumber('healthcircle_opacity', 0.35)

function init()
    g_ui.importStyle("game_healthcircle.otui")
    healthCircle = g_ui.createWidget('HealthCircle', mapPanel)
    manaCircle = g_ui.createWidget('ManaCircle', mapPanel)
    manaShieldCircle = g_ui.createWidget('ManaShieldCircle', mapPanel)
    expCircle = g_ui.createWidget('ExpCircle', mapPanel)
    skillCircle = g_ui.createWidget('SkillCircle', mapPanel)

    healthCircleFront = g_ui.createWidget('HealthCircleFront', mapPanel)
    manaCircleFront = g_ui.createWidget('ManaCircleFront', mapPanel)
    manaShieldCircleFront = g_ui.createWidget('ManaShieldCircleFront', mapPanel)
    expCircleFront = g_ui.createWidget('ExpCircleFront', mapPanel)
    skillCircleFront = g_ui.createWidget('SkillCircleFront', mapPanel)

    imageSourceBroad = healthCircle:getHeight()
    imageSourceThin = healthCircle:getWidth()
    imageSizeBroad = imageSourceBroad
    imageSizeThin = imageSourceThin
    manaShieldImageSourceBroad = manaShieldCircle:getHeight()
    manaShieldImageSourceThin = manaShieldCircle:getWidth()
    manaShieldImageSizeBroad = manaShieldImageSourceBroad
    manaShieldImageSizeThin = manaShieldImageSourceThin
    manaShieldCircle:setVisible(false)
    manaShieldCircleFront:setVisible(false)

    -- @ MONK
    initMonkWidgets()
    -- @
    whenMapResizeChange()
    initOnHpAndMpChange()
    initOnGeometryChange()
    initOnLoginChange()

    if not isHealthCircle then
        healthCircle:setVisible(false)
        healthCircleFront:setVisible(false)
    end

    if not isManaCircle then
        manaCircle:setVisible(false)
        manaCircleFront:setVisible(false)
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
    end

    if not isExpCircle then
        expCircle:setVisible(false)
        expCircleFront:setVisible(false)
    end

    if not isSkillCircle then
        skillCircle:setVisible(false)
        skillCircleFront:setVisible(false)
    end

    -- Add option window in options module
    addToOptionsModule()

    connect(g_game, {
        onGameStart = setPlayerValues
    })
    if StatusIconBar and StatusIconBar.init then
        StatusIconBar.init()
    end
end

function terminate()
    if StatusIconBar and StatusIconBar.terminate then
        StatusIconBar.terminate()
    end
    healthCircle:destroy()
    healthCircle = nil
    manaCircle:destroy()
    manaCircle = nil
    manaShieldCircle:destroy()
    manaShieldCircle = nil
    expCircle:destroy()
    expCircle = nil
    skillCircle:destroy()
    skillCircle = nil

    healthCircleFront:destroy()
    healthCircleFront = nil
    manaCircleFront:destroy()
    manaCircleFront = nil
    manaShieldCircleFront:destroy()
    manaShieldCircleFront = nil
    expCircleFront:destroy()
    expCircleFront = nil
    skillCircleFront:destroy()
    skillCircleFront = nil
    -- @ Destroy MONK
    terminateMonkWidgets()
    -- @
    terminateOnHpAndMpChange()
    terminateOnGeometryChange()
    terminateOnLoginChange()

    -- Delete from options module
    destroyOptionsModule()

    disconnect(g_game, {
        onGameStart = setPlayerValues
    })
    statsBarMenuLoaded = false
end

-------------------------------------------------
-- Scripts----------------------------------------
-------------------------------------------------

function initOnHpAndMpChange()
    connect(LocalPlayer, {
        onHealthChange = whenHealthChange,
        onManaChange = whenManaChange,
        onSkillChange = whenSkillsChange,
        onManaShieldChange = whenManaShieldChange,
        onMagicLevelChange = whenSkillsChange,
        onLevelChange = whenSkillsChange,
        -- @ MONK in modules\game_interface\widgets\statsbar.lua
        -- onHarmonyChange = whenMonkHarmonyChange,
        -- onSereneChange = whenMonkSereneChange,
        -- onVocationChange = function() checkMonkVocation() end
        -- @
    })
end

function terminateOnHpAndMpChange()
    disconnect(LocalPlayer, {
        onHealthChange = whenHealthChange,
        onManaChange = whenManaChange,
        onSkillChange = whenSkillsChange,
        onManaShieldChange = whenManaShieldChange,
        onMagicLevelChange = whenSkillsChange,
        onLevelChange = whenSkillsChange,
        -- @ MONK in modules\game_interface\widgets\statsbar.lua
        -- onHarmonyChange = whenMonkHarmonyChange,
        -- onSereneChange = whenMonkSereneChange,
        -- onVocationChange = function() checkMonkVocation() end
        -- @
    })
end

function initOnGeometryChange()
    connect(mapPanel, {
        onGeometryChange = whenMapResizeChange
    })
end

function terminateOnGeometryChange()
    disconnect(mapPanel, {
        onGeometryChange = whenMapResizeChange
    })
end

function initOnLoginChange()
    connect(g_game, {
        onGameStart = whenMapResizeChange
    })
end

function terminateOnLoginChange()
    disconnect(g_game, {
        onGameStart = whenMapResizeChange
    })
end

-- The empty part of a bar at percent full: on screen and in the image
local function emptyPart(sizeOnScreen, sizeInImage, percent)
    local empty = 1 - percent / 100
    return math.floor(sizeOnScreen * empty), math.floor(sizeInImage * empty)
end

function whenHealthChange()
    if g_game.isOnline() then
        -- @ MONK
        if isMonkMode then
            whenMonkHealthChange()
            return
        end
        -- @
        -- Fix By TheMaoci ~ if your server doesn't have this properly implemented,
        -- it will cause alot of unnecessary deaths from players which will be unfair.
        -- My friend reported me that while he was using his otcv8 and asked for a fix so here you go :)
        local healthPercent = math.floor(g_game.getLocalPlayer():getHealth() / g_game.getLocalPlayer():getMaxHealth() *
            100)
        -- Old leaved for ppl who have that implemented correctly
        --local healthPercent = math.floor(g_game.getLocalPlayer():getHealthPercent())

        local yhppc, sourceY = emptyPart(imageSizeBroad, imageSourceBroad, healthPercent)
        local restYhppc = imageSizeBroad - yhppc

        healthCircleFront:setY(healthCircle:getY() + yhppc)
        healthCircleFront:setHeight(restYhppc)
        healthCircleFront:setImageClip({
            x = 0,
            y = sourceY,
            width = imageSourceThin,
            height = imageSourceBroad - sourceY
        })

        healthCircle:setHeight(yhppc)
        healthCircle:setImageClip({
            x = 0,
            y = 0,
            width = imageSourceThin,
            height = sourceY
        })

        if healthPercent > 92 then
            healthCircleFront:setImageColor('#00BC00')
        elseif healthPercent > 60 then
            healthCircleFront:setImageColor('#50A150')
        elseif healthPercent > 30 then
            healthCircleFront:setImageColor('#A1A100')
        elseif healthPercent > 8 then
            healthCircleFront:setImageColor('#BF0A0A')
        elseif healthPercent > 3 then
            healthCircleFront:setImageColor('#910F0F')
        else
            healthCircleFront:setImageColor('#850C0C')
        end
    end
end

local defaultManaCircleEmpty = '/data/images/game/healthcircle/right_empty'
local defaultManaCircleFull = '/data/images/game/healthcircle/right_full'
local defaultManaWithManaShieldCircleEmpty = '/data/images/game/healthcircle/right_tiny_empty'
local defaultManaWithManaShieldCircleFull = '/data/images/game/healthcircle/right_tiny_full'
local manaShieldManaCircleEmpty = '/data/images/game/healthcircle/right_extra_empty'
local manaShieldManaCircleFull = '/data/images/game/healthcircle/right_extra_full'

-- A circle's image changes (mana with or without the shield) at the size
-- the circle has: a widget with no height (an empty part at 0) would take
-- the image's own size otherwise, and show at full size beside the scaled
-- circles
local function setCircleImage(widget, source)
    local size = widget:getSize()
    widget:setImageSource(source)
    widget:setSize(size)
end

local function resetManaCircleImages()
    if manaCircle then
        setCircleImage(manaCircle, defaultManaCircleEmpty)
    end

    if manaCircleFront then
        setCircleImage(manaCircleFront, defaultManaCircleFull)
    end
end

local function updateManaShieldDisplay()
    if not manaShieldCircle or not manaShieldCircleFront or not manaCircle or not manaCircleFront then
        return
    end

    if not g_game.isOnline() or not isManaCircle then
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
        resetManaCircleImages()
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local maxShield = player:getMaxManaShield()
    local remainingShield = player:getManaShield()

    if remainingShield <= 0 then
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
        resetManaCircleImages()
        return
    end

    if maxShield <= 0 then
        maxShield = remainingShield
    end

    setCircleImage(manaCircle, defaultManaWithManaShieldCircleEmpty)
    setCircleImage(manaCircleFront, defaultManaWithManaShieldCircleFull)
    setCircleImage(manaShieldCircle, manaShieldManaCircleEmpty)
    setCircleImage(manaShieldCircleFront, manaShieldManaCircleFull)
    manaShieldCircle:setVisible(true)
    manaShieldCircleFront:setVisible(true)

    local clampedShield = math.max(math.min(remainingShield, maxShield), 0)
    local shieldPercent = clampedShield / maxShield

    local emptyPixels, sourceY = emptyPart(manaShieldImageSizeBroad, manaShieldImageSourceBroad,
        shieldPercent * 100)
    emptyPixels = math.max(0, math.min(emptyPixels, manaShieldImageSizeBroad))
    sourceY = math.max(0, math.min(sourceY, manaShieldImageSourceBroad))

    local filledPixels = manaShieldImageSizeBroad - emptyPixels

    manaShieldCircleFront:setY(manaShieldCircle:getY() + emptyPixels)
    manaShieldCircleFront:setHeight(filledPixels)
    manaShieldCircleFront:setImageClip({
        x = 0,
        y = sourceY,
        width = manaShieldImageSourceThin,
        height = manaShieldImageSourceBroad - sourceY
    })

    manaShieldCircle:setHeight(emptyPixels)
    manaShieldCircle:setImageClip({
        x = 0,
        y = 0,
        width = manaShieldImageSourceThin,
        height = sourceY
    })
end

function whenManaShieldChange()
    updateManaShieldDisplay()
end

function whenManaChange()
    if g_game.isOnline() then
        local player = g_game.getLocalPlayer()
        local maxMana = player:getMaxMana()
        if maxMana <= 0 then
            manaCircle:setVisible(false)
            manaCircleFront:setVisible(false)
            if manaShieldCircle and manaShieldCircleFront then
                manaShieldCircle:setVisible(false)
                manaShieldCircleFront:setVisible(false)
            end
            resetManaCircleImages()
            return
        elseif isManaCircle then
            manaCircle:setVisible(true)
            manaCircleFront:setVisible(true)
        end

        updateManaShieldDisplay()

        local manaPercent = math.floor(maxMana - (maxMana - player:getMana())) * 100 / maxMana

        local ymppc, sourceY = emptyPart(imageSizeBroad, imageSourceBroad, manaPercent)
        local restYmppc = imageSizeBroad - ymppc
        if restYmppc <= 0 then
            manaCircleFront:setVisible(false)
        else
            manaCircleFront:setVisible(isManaCircle)

            if isManaCircle then
                manaCircleFront:setY(manaCircle:getY() + ymppc)
                manaCircleFront:setHeight(restYmppc)
                manaCircleFront:setImageClip({
                    x = 0,
                    y = sourceY,
                    width = imageSourceThin,
                    height = imageSourceBroad - sourceY
                })
            end
        end

        manaCircle:setHeight(ymppc)
        manaCircle:setImageClip({
            x = 0,
            y = 0,
            width = imageSourceThin,
            height = sourceY
        })
    end
end

function whenSkillsChange()
    if g_game.isOnline() then
        if isExpCircle then
            local player = g_game.getLocalPlayer()
            local Xexpc, sourceX = emptyPart(imageSizeBroad, imageSourceBroad, player:getLevelPercent())

            expCircleFront:setImageClip({
                x = 0,
                y = 0,
                width = imageSourceBroad - sourceX,
                height = imageSourceThin
            })
            expCircleFront:setWidth(imageSizeBroad - Xexpc)

            expCircle:setImageClip({
                x = imageSourceBroad - sourceX,
                y = 0,
                width = sourceX,
                height = imageSourceThin
            })
            expCircle:setWidth(Xexpc)
            expCircle:setX(expCircleFront:getX() + expCircleFront:getWidth())
        end

        if isSkillCircle then
            local player = g_game.getLocalPlayer()

            local skillPercent
            local skillColor
            local skillType = skillTypes[player:getName()]

            if skillType == 'fist' then
                skillPercent = player:getSkillLevelPercent(0)
                skillColor = '#9900cc'
            elseif skillType == 'club' then
                skillPercent = player:getSkillLevelPercent(1)
                skillColor = '#cc3399'
            elseif skillType == 'sword' then
                skillPercent = player:getSkillLevelPercent(2)
                skillColor = '#FF7F00'
            elseif skillType == 'axe' then
                skillPercent = player:getSkillLevelPercent(3)
                skillColor = '#696969'
            elseif skillType == 'distance' then
                skillPercent = player:getSkillLevelPercent(4)
                skillColor = '#A62A2A'
            elseif skillType == 'shielding' then
                skillPercent = player:getSkillLevelPercent(5)
                skillColor = '#663300'
            elseif skillType == 'fishing' then
                skillPercent = player:getSkillLevelPercent(6)
                skillColor = '#ffff33'
            else
                -- default skill: MAGIC
                skillPercent = player:getMagicLevelPercent()
                skillColor = '#00ffcc'
            end

            local Xskpc, sourceX = emptyPart(imageSizeBroad, imageSourceBroad, skillPercent)
            skillCircleFront:setImageColor(skillColor)

            skillCircleFront:setImageClip({
                x = 0,
                y = 0,
                width = imageSourceBroad - sourceX,
                height = imageSourceThin
            })
            skillCircleFront:setWidth(imageSizeBroad - Xskpc)

            skillCircle:setImageClip({
                x = imageSourceBroad - sourceX,
                y = 0,
                width = sourceX,
                height = imageSourceThin
            })
            skillCircle:setWidth(Xskpc)
            skillCircle:setX(skillCircleFront:getX() + skillCircleFront:getWidth())
        end
    end
end

-- A circle (its empty and its full part) at x, y, whole: the online
-- updates then fill it to the player's values
local function placeCircle(back, front, x, y, width, height, sourceWidth, sourceHeight)
    for _, widget in ipairs({ back, front }) do
        widget:setSize({ width = width, height = height })
        widget:setX(x)
        widget:setY(y)
        widget:setImageClip({ x = 0, y = 0, width = sourceWidth, height = sourceHeight })
    end
end

-- Sizes and places the circles from the game view they sit in: around its
-- centre, scaled down (never up) so that all of them stay inside it, on a
-- small view (a tablet's layout with panels) as on a large one
function whenMapResizeChange()
    local mapWidth, mapHeight = mapPanel:getWidth(), mapPanel:getHeight()
    if mapWidth > 2 * CIRCLE_EDGE and mapHeight > 2 * CIRCLE_EDGE and imageSourceBroad > 0 then
        local barDistance = 90
        if not (math.floor(mapHeight / 2 * 0.2) < 100) then -- 0.381
            barDistance = math.floor(mapHeight / 2 * 0.2)
        end
        -- how far the circles reach from the centre, at full size
        local reach = barDistance + imageSourceThin + math.max(0, distanceFromCenter)
        local scale = math.min(1, (mapHeight - 2 * CIRCLE_EDGE) / imageSourceBroad,
            (mapWidth / 2 - CIRCLE_EDGE) / reach)
        if isExpCircle or isSkillCircle then
            scale = math.min(scale, (mapWidth - 2 * CIRCLE_EDGE) / imageSourceBroad,
                (mapHeight / 2 - CIRCLE_EDGE) / reach)
        end
        circleScale = math.max(scale, 0.1)

        imageSizeBroad = math.floor(imageSourceBroad * circleScale)
        imageSizeThin = math.floor(imageSourceThin * circleScale)
        manaShieldImageSizeBroad = math.floor(manaShieldImageSourceBroad * circleScale)
        manaShieldImageSizeThin = math.floor(manaShieldImageSourceThin * circleScale)
        barDistance = math.floor(barDistance * circleScale)
        local distance = math.floor(distanceFromCenter * circleScale)

        local centerX = mapPanel:getX() + math.floor(mapWidth / 2)
        local centerY = mapPanel:getY() + math.floor(mapHeight / 2)
        local sideY = centerY - math.floor(imageSizeBroad / 2)
        placeCircle(healthCircle, healthCircleFront, centerX - barDistance - imageSizeThin - distance, sideY,
            imageSizeThin, imageSizeBroad, imageSourceThin, imageSourceBroad)
        placeCircle(manaCircle, manaCircleFront, centerX + barDistance + distance, sideY, imageSizeThin,
            imageSizeBroad, imageSourceThin, imageSourceBroad)
        placeCircle(manaShieldCircle, manaShieldCircleFront,
            manaCircle:getX() - manaShieldImageSizeThin - math.floor(manaShieldCircleOffsetX * circleScale),
            sideY + math.floor(manaShieldCircleOffsetY * circleScale), manaShieldImageSizeThin,
            manaShieldImageSizeBroad, manaShieldImageSourceThin, manaShieldImageSourceBroad)
        local acrossX = centerX - math.floor(imageSizeBroad / 2)
        placeCircle(expCircle, expCircleFront, acrossX, centerY - barDistance - imageSizeThin - distance,
            imageSizeBroad, imageSizeThin, imageSourceBroad, imageSourceThin)
        placeCircle(skillCircle, skillCircleFront, acrossX, centerY + barDistance + distance, imageSizeBroad,
            imageSizeThin, imageSourceBroad, imageSourceThin)
        -- @ MONK
        scaleMonkWidgets(circleScale)
        -- @
    end

    if g_game.isOnline() then
        whenHealthChange()
        whenManaChange()
        if isExpCircle or isSkillCircle then
            whenSkillsChange()
        end
        -- @ MONK
        positionMonkWidgets()
        -- @
    end

    updateManaShieldDisplay()
    if StatusIconBar and StatusIconBar.updatePosition then
        StatusIconBar.updatePosition()
    end
end

-------------------------------------------------
-- Controls---------------------------------------
-------------------------------------------------

function setHealthCircle(value)
    value = toboolean(value)
    isHealthCircle = value
    if value then
        -- @ MONK
        checkMonkVocation()
        if isMonkMode then
            healthCircle:setVisible(false)
            healthCircleFront:setVisible(false)
            setMonkWidgetsVisible(true)
        else
            healthCircle:setVisible(true)
            healthCircleFront:setVisible(true)
        end
        whenMapResizeChange()
        updateManaShieldDisplay()
        -- @
    else
        healthCircle:setVisible(false)
        healthCircleFront:setVisible(false)
        -- @ MONK
        setMonkWidgetsVisible(false)
        -- @
        if manaShieldCircle and manaShieldCircleFront then
            manaShieldCircle:setVisible(false)
            manaShieldCircleFront:setVisible(false)
        end
        resetManaCircleImages()
    end

    g_settings.set('healthcircle_hpcircle', not value)
end

function setManaCircle(value)
    value = toboolean(value)
    isManaCircle = value
    if value then
        manaCircle:setVisible(true)
        manaCircleFront:setVisible(true)
        whenMapResizeChange()
    else
        manaCircle:setVisible(false)
        manaCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_mpcircle', not value)
end

function setExpCircle(value)
    value = toboolean(value)
    isExpCircle = value

    if value then
        expCircle:setVisible(true)
        expCircleFront:setVisible(true)
        whenMapResizeChange()
    else
        expCircle:setVisible(false)
        expCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_expcircle', value)
end

function setSkillCircle(value)
    value = toboolean(value)
    isSkillCircle = value

    if value then
        skillCircle:setVisible(true)
        skillCircleFront:setVisible(true)
        whenMapResizeChange()
    else
        skillCircle:setVisible(false)
        skillCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_skillcircle', value)
end

function setSkillType(skill)
    if not skillsLoaded then
        return
    end

    local char = g_game.getCharacterName()

    skillTypes[char] = skill
    whenMapResizeChange()
    g_settings.setNode('healthcircle_skilltypes', skillTypes)
end

function setDistanceFromCenter(value)
    distanceFromCenter = value
    whenMapResizeChange()

    g_settings.set('healthcircle_distfromcenter', value)
end

function setCircleOpacity(value)
    healthCircle:setOpacity(value)
    healthCircleFront:setOpacity(value)
    manaCircle:setOpacity(value)
    manaCircleFront:setOpacity(value)
    if manaShieldCircle then
        manaShieldCircle:setOpacity(value)
    end
    if manaShieldCircleFront then
        manaShieldCircleFront:setOpacity(value)
    end
    expCircle:setOpacity(value)
    expCircleFront:setOpacity(value)
    skillCircle:setOpacity(value)
    skillCircleFront:setOpacity(value)
    -- @ MONK
    setMonkCircleOpacity(value)
    -- @
    g_settings.set('healthcircle_opacity', value)
end

-------------------------------------------------
-- Option Settings--------------------------------
-------------------------------------------------

optionPanel = nil
healthCheckBox = nil
manaCheckBox = nil
experienceCheckBox = nil
skillCheckBox = nil
chooseSkillComboBox = nil
chooseStatsBarDimension = nil
chooseStatsBarPlacement = nil
distFromCenScrollbar = nil
opacityScrollbar = nil

function addToOptionsModule()
    -- Add to options module
    optionPanel = g_ui.loadUI('option_healthcircle', modules.client_options:getPanel())

    -- UI values
    healthCheckBox = optionPanel:recursiveGetChildById('healthCheckBox')
    manaCheckBox = optionPanel:recursiveGetChildById('manaCheckBox')
    experienceCheckBox = optionPanel:recursiveGetChildById('experienceCheckBox')
    skillCheckBox = optionPanel:recursiveGetChildById('skillCheckBox')
    chooseSkillComboBox = optionPanel:recursiveGetChildById('chooseSkillComboBox')
    chooseStatsBarDimension = optionPanel:recursiveGetChildById('chooseStatsBarDimension')
    chooseStatsBarPlacement = optionPanel:recursiveGetChildById('chooseStatsBarPlacement')
    distFromCenScrollbar = optionPanel:recursiveGetChildById('distFromCenScrollbar')
    opacityScrollbar = optionPanel:recursiveGetChildById('opacityScrollbar')

    -- ComboBox start values
    chooseSkillComboBox:addOption('Magic Level', 'magic')
    chooseSkillComboBox:addOption('Fist Fighting', 'fist')
    chooseSkillComboBox:addOption('Club Fighting', 'club')
    chooseSkillComboBox:addOption('Sword Fighting', 'sword')
    chooseSkillComboBox:addOption('Axe Fighting', 'axe')
    chooseSkillComboBox:addOption('Distance Fighting', 'distance')
    chooseSkillComboBox:addOption('Shielding', 'shielding')
    chooseSkillComboBox:addOption('Fishing', 'fishing')

    chooseStatsBarPlacement:addOption(tr('Top'), 'top')
    chooseStatsBarPlacement:addOption(tr('Bottom'), 'bottom')

    chooseStatsBarDimension:addOption(tr('Hide'), 'hide')
    chooseStatsBarDimension:addOption(tr('Compact'), 'compact')
    chooseStatsBarDimension:addOption(tr('Default'), 'default')
    chooseStatsBarDimension:addOption(tr('Large'), 'large')
    chooseStatsBarDimension:addOption(tr('Parallel'), 'parallel')

    statsBarMenuLoaded = true

    -- fall back to the same defaults as the stats bar itself, otherwise an
    -- empty/unknown setting would silently select the first option ('hide')
    local storedDimension = g_settings.getString('statsbar_dimension')
    local storedPlacement = g_settings.getString('statsbar_placement')
    chooseStatsBarDimension:setCurrentOptionByData(storedDimension ~= "" and storedDimension or 'compact', true)
    chooseStatsBarPlacement:setCurrentOptionByData(storedPlacement ~= "" and storedPlacement or 'top', true)

    -- Set values
    healthCheckBox:setChecked(isHealthCircle)
    manaCheckBox:setChecked(isManaCircle)
    experienceCheckBox:setChecked(isExpCircle)
    skillCheckBox:setChecked(isSkillCircle)

    -- Prevent skill overwritten before initialize
    skillsLoaded = true

    distFromCenScrollbar:setText(tr('Distance') .. ': ' .. distanceFromCenter)
    distFromCenScrollbar:setValue(distanceFromCenter)
    opacityScrollbar:setText(tr('Opacity') .. ': ' .. opacityCircle)
    opacityScrollbar:setValue(opacityCircle * 100)
    modules.client_options.addButton("Interface", "HP/MP Circle", optionPanel)
end

function updateStatsBar()
    if not statsBarMenuLoaded then
        return
    end

    local dimensionOption = chooseStatsBarDimension:getCurrentOption()
    local placementOption = chooseStatsBarPlacement:getCurrentOption()
    -- a selection can be empty while the stored stats bar state is still unknown,
    -- there is nothing to apply in that case
    if not dimensionOption or not placementOption then
        return
    end

    modules.game_interface.updateStatsBar(dimensionOption.data, placementOption.data)
end

function setPlayerValues()
    local skillType = skillTypes[g_game.getCharacterName()]
    if not skillType then
        skillType = 'magic'
    end
    chooseSkillComboBox:setCurrentOptionByData(skillType, true)
end

function setStatsBarOption(dimension, placement)
    if not chooseStatsBarDimension or not chooseStatsBarPlacement then
        return
    end
    chooseStatsBarDimension:setCurrentOptionByData(dimension, true)
    chooseStatsBarPlacement:setCurrentOptionByData(placement, true)
end

function destroyOptionsModule()
    healthCheckBox = nil
    manaCheckBox = nil
    experienceCheckBox = nil
    skillCheckBox = nil
    chooseSkillComboBox = nil
    distFromCenScrollbar = nil
    opacityScrollbar = nil
    chooseStatsBarDimension = nil
    chooseStatsBarPlacement = nil

    modules.client_options.removeButton("Interface", "HP/MP Circle")
    optionPanel = nil
end
