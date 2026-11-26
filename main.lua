-- Made with help from AI - Claude

anim8 = require 'libraries/anim8'
 
local function loadSheet(path, frameTime)
    local image = love.graphics.newImage(path)
    local grid = anim8.newGrid(32, 32, image:getWidth(), image:getHeight())
    local animation = anim8.newAnimation(grid('1-2', 1, '1-2', 2), frameTime)
    return image, animation
end

local function loadFireball(path, frameTime)
    local image = love.graphics.newImage(path)
    local iw, ih = image:getDimensions()

    local grid, frames, fw, fh
    if iw > ih then
        fw, fh = iw / 2, ih
        grid = anim8.newGrid(fw, fh, iw, ih)
        frames = grid('1-2', 1)
    else                       -- 2 frames stacked
        fw, fh = iw, ih / 2
        grid = anim8.newGrid(fw, fh, iw, ih)
        frames = grid(1, '1-2')
    end

    return image, anim8.newAnimation(frames, frameTime), fw, fh
end

local HIT_FLASH_TIME = 0.1          -- seconds to flash red when player, enemy is hit
local PLAYER_INVULN_TIME = 0.5      -- seconds of invulnerability after being hit
local MAX_DASH_DISTANCE = 150
local BASE_SHOOT_RATE = 0.5         -- seconds between shots
local BASE_SPEED = 200

-- Each projectile type: whcih power stat it scales with, and what % of player power it deals
local PROJECTILES = {
    fireball = { stat = "magic", pct = 1.0 },
    bullet   = { stat = "attack", pct = 1.0 },
}

-- Base power stat * the shared damage multiplier 
local function getPower(stat)
    local base = (stat == "magic") and player.magicPower or player.attackPower
    return base * player.damageMult
end
--What a given projectile's damage deals right now
local function getProjectileDamage(kind)
    return getPower(kind.stat) * kind.damagePct
end
 
-- Helper function to find the distance between two points
local function getDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Fires 2 bullets at the closest enemy, each dealing 100% of the player's attack
local function fireBulletVolley()
    local target, shortest = nil, math.huge
    for _, e in ipairs(enemies) do
        local d = getDistance(player.x, player.y, e.x, e.y)
        if d < shortest then
            shortest = d
            target = e
        end
    end
    if not target then return end

    local angle = math.atan2(target.y - player.y, target.x - player.x)
    local dirX, dirY = math.cos(angle), math.sin(angle)

    -- Spawn the pair side by side so they don't overlap
    for _, offset in ipairs({ -6, 6 }) do
        table.insert(bullets, {
            kind = "bullet",
            x = player.x - dirY * offset,
            y = player.y + dirX * offset,
            dx = dirX,
            dy = dirY,
            angle = angle,
            speed = 500,
            radius = 4,
            stat = PROJECTILES.bullet.stat,
            damagePct = PROJECTILES.bullet.pct,
        })
    end
end
 
--
-- Upgrades -------------------------------------------------------------------
--
-- Random multiplier between 0.8 and 1.2 to add some variety to the upgrades
local function rollMultiplier()
    return 0.8 + math.random() * 0.4
end

local function roundTo(x, decimals)
    local m = 10 ^ decimals
    return math.floor(x * m + 0.5) / m
end

--Formats a number with at most 1 decimal
local function fmt(n)
    local s = string.format("%.1f", n)
    return (s:gsub("%.0$", ""))  -- remove trailing .0
end

-- Add a new entry here and it automatically joins the random pool.
-- Avoid [ ] { } | characters in label/text, since they become ink source.
local upgradePool = {
    { id = "max_hp", base = 20, decimals = 0,
      label = function(v) return "Vitality - +" .. fmt(v) .. " max HP" end,
      text = "Your body hardens against the wastes.",
      apply = function(v)
          player.maxHp = player.maxHp + v
          player.hp = math.min(player.maxHp, player.hp + v)
      end },
    { id = "regen", base = 1,
      label = function(v) return "Regeneration - +" .. fmt(v) .. " HP per second" end,
      text = "Your wounds begin to close on their own.",
      apply = function(v) player.regen = roundTo(player.regen + v, 1) end },
    { id = "fire_rate", base = 10, decimals = 0,   -- percent
      label = function(v) return "Quickened Spells - +" .. fmt(v) .. "% attack speed" end,
      text = "Your staff hums with eager energy.",
      apply = function(v) player.attackSpeed = roundTo(player.attackSpeed + v / 100, 2) end },
    { id = "defense", base = 2,
      label = function(v) return "Warding - +" .. fmt(v) .. " armor" end,
      text = "A faint barrier shimmers around you.",
      apply = function(v) player.defense = roundTo(player.defense + v, 1) end },
    { id = "attack_power", base = 2,
      label = function(v) return "Hardened Rounds - +" .. fmt(v) .. " attack power" end,
      text = "Your ammunition hits like a hammer.",
      apply = function(v) player.attackPower = roundTo(player.attackPower + v, 1) end },
    { id = "magic_power", base = 2,
      label = function(v) return "Arcane Might - +" .. fmt(v) .. " magic power" end,
      text = "Raw magic surges through you.",
      apply = function(v) player.magicPower = roundTo(player.magicPower + v, 1) end },
    { id = "all_power", base = 1.5,
      label = function(v) return "Balanced Might - +" .. fmt(v) .. " attack and magic power" end,
      text = "Steel and sorcery rise together.",
      apply = function(v)
        player.attackPower = roundTo(player.attackPower + v, 1)
        player.magicPower = roundTo(player.magicPower + v, 1)
        end },
    { id = "speed", base = 10, decimals = 0,       -- percent
      label = function(v) return "Fleet of Foot - +" .. fmt(v) .. "% move speed" end,
      text = "The ground slips away beneath your boots.",
      apply = function(v) player.speed = player.speed + v / 100 * BASE_SPEED end },
    --rare 1% chance upgrades
      { id = "damage_mult", base = 2.5, rare = 0.01,
      label = function(v) return "Overwhelming Force - +" .. fmt(v) .. "% damage" end,
      text = "Every strike lands harder than it should.",
      apply = function(v) player.damageMult = roundTo(player.damageMult + v / 100, 3) end },
    { id = "damage_reduction", base = 2.5, rare = 0.01,
      label = function(v) return "Aegis - +" .. fmt(v) .. "% damage reduction" end,
      text = "Blows seem to glance off you.",
      apply = function(v) player.damageReduction = math.min(0.95, roundTo(player.damageReduction + v / 100, 3)) end },
}

local MAX_MAJOR = 3

-- The effects aren't implemented yet; the text lines are placeholder flavor.
local majorPools = {
    { name = "Wizard", upgrades = {
        { id = "frostbite",      name = "Frostbite",        text = "Cold creeps along your staff." },
        { id = "giant_fireball", name = "Giant fireball",   text = "Your flames swell beyond reason." },
        { id = "celestial_cloak",name = "Celestial Cloak",  text = "Starlight settles over your shoulders." },
        { id = "arcane_orbit",   name = "Arcane Orbit",     text = "Orbs of power circle you." },
    }},
    { name = "Cybernetic", upgrades = {
        { id = "pulse_cannon",   name = "Pulse Cannon arm",       text = "Your arm whirs and splits into a cannon." },
        { id = "titanium_bio",   name = "Titanium Bioskeleton",   text = "Metal laces through your bones." },
        { id = "orbital_strike", name = "Orbital Strike Uplink",  text = "Somewhere above, a satellite wakes." },
        { id = "rapid_boots", name = "Rapid-fire Boots",
          text = "Your boots hum with restless energy.",
          desc = "Halves your dash cooldown. After each dash, fire 2 bullets at the closest enemy." },
    }},
}

local function hasMajor(id)
    for _, m in ipairs(player.majorUpgrades) do
        if m.id == id then return true end
    end
    return false
end
-- Effects that run once, when a major upgrade is picked
local majorEffects = {
    rapid_boots = function()
        player.dashDelay = player.dashDelay * 0.5
    end,
}

-- One random not-yet-owned upgrade from each pool
local function pickMajorUpgrades()
    local choices = {}
    for _, pool in ipairs(majorPools) do
        local available = {}
        for _, u in ipairs(pool.upgrades) do
            if not hasMajor(u.id) then table.insert(available, u) end
        end
        if #available > 0 then
            local u = available[math.random(#available)]
            table.insert(choices, {
                id = u.id,
                label = pool.name .. " - " .. u.name,
                text = u.text,
                desc = u.desc,
                apply = function()
                    table.insert(player.majorUpgrades, { id = u.id, name = u.name, pool = pool.name })
                    -- The first major upgrade decides the player's look
                    if #player.majorUpgrades == 1 then
                        player.spriteKey = pool.name
                    end
                    if majorEffects[u.id] then majorEffects[u.id]() end
                end,
            })
        end
    end
    return choices
end

local pendingUpgrade = nil  -- set by the ink observer, applied when the dialogue closes
local ignoreDash = false    -- stops a held space (used to close the dialogue) from dashing
 
local function pickUpgrades(n)
    local common, chosen = {}, {}

    -- Roll each rare upgrade separately; everything else goes in the normal pool
    for _, u in ipairs(upgradePool) do
        if u.rare then
            if #chosen < n and math.random() < u.rare then
                table.insert(chosen, u)
            end
        else
            table.insert(common, u)
        end
    end

    -- Fill the remaining slots from the normal pool
    while #chosen < n and #common > 0 do
        table.insert(chosen, table.remove(common, math.random(#common)))
    end

    -- Shuffle so a rare upgrade isn't always the first option
    for i = #chosen, 2, -1 do
        local j = math.random(i)
        chosen[i], chosen[j] = chosen[j], chosen[i]
    end

    local picked = {}
    for _, u in ipairs(chosen) do
        local value = roundTo(u.base * rollMultiplier(), u.decimals or 1)
        table.insert(picked, {
            id = u.id,
            label = u.label(value),
            text = u.text,
            apply = function() u.apply(value) end,
        })
    end
    return picked
end
 
-- Builds ink source containing only the chosen upgrades
local function buildUpgradeScript(choices, intro)
    local lines = {
        'VAR upgrade = ""',
        "",
        intro,
        "",
    }
    for _, u in ipairs(choices) do
        table.insert(lines, "* [" .. u.label .. "]")
        table.insert(lines, "    " .. u.text)
        if u.desc then
            table.insert(lines, "    " .. u.desc)
        end
        table.insert(lines, '    ~ upgrade = "' .. u.id .. '"')
        table.insert(lines, "    -> END")
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
 
local function startUpgrade(choices, intro)
    pendingUpgrade = nil
 
    local byId = {}
    for _, u in ipairs(choices) do byId[u.id] = u end
 
    narrator:startScript("upgrade", {
        content = buildUpgradeScript(choices, intro),
        observe = {
            upgrade = function(value)
                if value and value ~= "" then pendingUpgrade = byId[value] end
            end,
        },
    })
    love.update = love.upgrade
end
 
--
-- Input ----------------------------------------------------------------------
--
 
function love.keypressed(key)
    --Game over: Enter returns to the main menu
    if love.update == love.gameover then
        if key == "return" or key == "kpenter" then
            love.update = love.menu
        end
        return
    end

    -- Main menu: Enter starts the game
    if love.update == love.menu then
        if key == "return" or key == "kpenter" then
            startGame()
        end
        return
    end

    --Pause / resume 
    if key == "escape" then
        if love.update == love.gameplay then
            love.update = love.paused
        elseif love.update == love.paused then
            love.update = love.gameplay
        end
        return
    end
    if love.update == love.paused then return end
 
    -- Dialogue controls (intro and upgrade screens)
    local inDialogue = (love.update == love.introDialogue or love.update == love.upgrade)
        and narrator:isOpen()
    if not inDialogue then return end
 
    if key == "space" or key == "return" then
        narrator:onAction()
        if not narrator:isOpen() then
            if love.update == love.upgrade then
                if pendingUpgrade then
                    pendingUpgrade.apply()
                    pendingUpgrade = nil
                end
                ignoreDash = true
            end
            love.update = love.gameplay
        end
    elseif key == "up" then
        narrator:prevOption()
    elseif key == "down" then
        narrator:nextOption()
    end
end
 
--
-- Setup ----------------------------------------------------------------------
--
 
function love.load()
    sti = require 'libraries/sti'
    narrator = require 'libraries/narrator'
    camera = require 'libraries/camera'
 
    math.randomseed(os.time())
 
    cam = camera()
 
    -- Get the screen dimensions so we know where to spawn things
    screenWidth = love.graphics.getWidth()
    screenHeight = love.graphics.getHeight()
 
    gameMap = sti('maps/testMap.lua')
    gameMap:resize(love.graphics.getWidth() * 2, love.graphics.getHeight())
 
    -- Set custom cursor
    local customCursor = love.mouse.newCursor("sprites/cursor.png", 16, 16)
    love.mouse.setCursor(customCursor)
 
    local function newSprite(path)
        local image, animation = loadSheet(path, 0.2)
        return { image = image, animation = animation }
    end

    -- Keys match the major upgrade pool names ("Wizard" and "Cybernetic")
    playerSprites = {
        starter    = newSprite("sprites/starter_wizard.png"),
        Wizard     = newSprite("sprites/wizard.png"),
        Cybernetic = newSprite("sprites/cyber_wizard.png"),
    }    



    cyborgImage, cyborgAnimation = loadSheet("sprites/cyborg.png", 0.2)
    fireballImage, fireballAnimation, fireballW, fireballH = loadFireball("sprites/fireball.png", 0.1)
    bulletImage, bulletAnimation, bulletW, bulletH = loadFireball("sprites/simple_bullet.png", 0.1)

    background = love.graphics.newImage("sprites/background.png")
    defaultFont = love.graphics.getFont()
    menuFont = love.graphics.newFont(24)

    narrator:init()

    resetGame()
    love.update = love.menu
end

--Resets everything that changes during a run
function resetGame()
    -- Set up the player
    player = {
        x = screenWidth / 2,
        y = screenHeight / 2,
        rotation = 0,
        speed = 200,
        radius = 16,
        hp = 100,                   -- current HP
        maxHp = 100,
        regen = 0,                  -- HP per second
        defense = 0,                -- flat reduction from upgrades
        attackPower = 5,            -- flat attack added from upgrades
        magicPower = 5,             -- flat magic added from upgrades
        damageMult = 1.0,           -- 1.0 = 100% damage, increases attack and magic power
        damageReduction = 0,        -- 0 = 0% damage reduction
        attackSpeed = 1.0,          -- 1.0 = 100% attack speed

        hitFlashTimer = 0,          -- Time left for hit flash effect
        invulnTimer = 0,            -- Time left before player can be hit again (after taking damage)
 
        --upgrade variables
        lastupgradescore = 0,
        lastMajorscore = 0,
        majorUpgrades = {},         -- list of major upgrades the player has chosen

        -- Dash variables
        dashForce = 1200,    -- dash speed in pixels per second
        dashCooldown = 0,    -- timer until the next dash
        dashDelay = 1.0,     -- seconds between dashes
        dashing = false,     -- true while a dash is in progress
        dashDirX = 0,
        dashDirY = 0,
        dashRemaining = 0,   -- distance left to travel

        spriteKey = "starter",  -- which entry of playerSprites to draw
        weapon = "fireball",  -- fireball or bullet; set by the intro choice
    }
 
    -- Lists to keep track of all active objects on screen
    enemies = {}
    bullets = {}
 
    -- Timers for enemies
    enemySpawnTimer = 0
    enemySpawnRate = 0.5 -- Spawn an enemy every x seconds
 
    shootTimer = 0
 
    score = 0
    pendingUpgrade = nil
    ignoreDash = false
end
 
--
-- Update states --------------------------------------------------------------
--

function startGame()
    resetGame()
    love.update = love.introDialogue
end

function love.menu(dt)
    -- Menu input is handled in love.keypressed
end

function love.gameover(dt)
    -- Game over input is handled in love.keypressed
end

function love.paused(dt)
    -- Paused input is handled in love.keypressed
end
 
function love.introDialogue(dt)
    if not narrator:isOpen() then
        narrator:startScript("intro", {
            observe = {
                origin = function(value)
                    if value == "wizard" then
                        player.spriteKey = "starter"
                        player.weapon = "fireball"
                    elseif value == "cyber" then
                        player.spriteKey = "Cybernetic"
                        player.weapon = "bullet"
                    end
                end,
            },
        })
    end
    narrator:update(dt)
end
 
function love.upgrade(dt)
    -- Input is handled in love.keypressed
    narrator:update(dt)
end
 
function love.gameplay(dt)
    if player.hp <= 0 then
        love.update = love.gameover
        return
    end
 
    playerSprites[player.spriteKey].animation:update(dt)
    fireballAnimation:update(dt)
    bulletAnimation:update(dt)

    -- Update the hit flash timer
    if player.hitFlashTimer > 0 then
        player.hitFlashTimer = player.hitFlashTimer - dt
    end

    -- Update the invulnerability timer
    if player.invulnTimer > 0 then
        player.invulnTimer = player.invulnTimer - dt
    end
    
    --major upgrade after every 100 score
    if score > 0 and score % 100 == 0 and score ~= player.lastMajorscore and 
        #player.majorUpgrades < MAX_MAJOR then
        player.lastMajorscore = score

        local majorChoices = pickMajorUpgrades()
        if #majorChoices > 0 then
            startUpgrade(majorChoices, "A greater power calls to you. Choose your path.")
            return
        end
    end

    -- minor upgrade after every 15 score
    if score > 0 and score % 15 == 0 and score ~= player.lastupgradescore then
        player.lastupgradescore = score
        startUpgrade(pickUpgrades(3), "Power surges through you. Choose your boon.")
        return
    end
 
    -- Health regeneration
    if player.regen > 0 then
        player.hp = math.min(player.maxHp, player.hp + player.regen * dt)
    end
 
    -- Keep track of player rotation based on mouse position
    local mouseX, mouseY = love.mouse.getPosition()
    player.rotation = math.atan2(mouseY - player.y, mouseX - player.x)
 
    -- Player movement
    local moveX, moveY = 0, 0
    if love.keyboard.isDown("w", "up") then moveY = moveY - 1 end
    if love.keyboard.isDown("s", "down") then moveY = moveY + 1 end
    if love.keyboard.isDown("a", "left") then moveX = moveX - 1 end
    if love.keyboard.isDown("d", "right") then moveX = moveX + 1 end
 
    local moveLength = math.sqrt(moveX^2 + moveY^2)
    if moveLength > 0 then
        moveX = moveX / moveLength
        moveY = moveY / moveLength
    end
 
    player.x = player.x + (moveX * player.speed * dt)
    player.y = player.y + (moveY * player.speed * dt)
 
    -- Dash toward the mouse, stopping at the cursor if it's closer than the max distance
    if player.dashCooldown > 0 then
        player.dashCooldown = player.dashCooldown - dt
    end
    if not love.keyboard.isDown("space") then
        ignoreDash = false
    end

    if love.keyboard.isDown("space") and not ignoreDash
        and not player.dashing and player.dashCooldown <= 0 then
        local dx, dy = mouseX - player.x, mouseY - player.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist > 1 then  -- ignore the dash if the cursor is right on top of the player
            player.dashing = true
            player.dashDirX = dx / dist
            player.dashDirY = dy / dist
            player.dashRemaining = math.min(dist, MAX_DASH_DISTANCE)
            player.dashCooldown = player.dashDelay
        end
    end

    if player.dashing then
        local step = math.min(player.dashForce * dt, player.dashRemaining)
        player.x = player.x + player.dashDirX * step
        player.y = player.y + player.dashDirY * step
        player.dashRemaining = player.dashRemaining - step

        if player.dashRemaining <= 0 then
            player.dashing = false
            --if the player has the rapid boots major upgrade, fire a pair of bullets at the closest enemy after dashing
            if hasMajor("rapid_boots") then
                fireBulletVolley()
            end
        end
    end
 
    -- Keep player on screen
    player.x = math.max(0, math.min(player.x, screenWidth - player.radius))
    player.y = math.max(0, math.min(player.y, screenHeight - player.radius))
 
    -- Spawn enemies
    enemySpawnTimer = enemySpawnTimer + dt
    if enemySpawnTimer >= enemySpawnRate then
        enemySpawnTimer = 0
 
        -- Randomize which side the enemies come from
        local side = math.random(1, 4)
        local spawnX, spawnY
 
        if side == 1 then       -- Top
            spawnX = math.random(0, screenWidth)
            spawnY = -30
        elseif side == 2 then   -- Bottom
            spawnX = math.random(0, screenWidth)
            spawnY = screenHeight + 30
        elseif side == 3 then   -- Left
            spawnX = -30
            spawnY = math.random(0, screenHeight)
        else                    -- Right
            spawnX = screenWidth + 30
            spawnY = math.random(0, screenHeight)
        end
 
        local newEnemy = {
            x = spawnX,
            y = spawnY,
            enemy_hp = 10 + math.floor(score / 5),  -- enemy hp grows with score
            damage = 10 + math.floor(score / 15),   -- enemy damage grows with score
            speed = 150,
            radius = 16,

            hitFlash = 0,                           -- Time left for hit flash effect
            animation = cyborgAnimation:clone()     -- each enemy gets its own animation clock
        }
        newEnemy.animation:gotoFrame(math.random(1, 4)) -- so they don't all animate in sync
        table.insert(enemies, newEnemy)
    end
 
    -- Enemy movement (loop backwards so removing entries is safe)
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        e.animation:update(dt)

        -- Update the hit flash timer
        if e.hitFlash > 0 then
            e.hitFlash = math.max(0, e.hitFlash - dt)
        end
 
        local angle = math.atan2(player.y - e.y, player.x - e.x)
        e.x = e.x + math.cos(angle) * e.speed * dt
        e.y = e.y + math.sin(angle) * e.speed * dt

        -- Check if enemy touched the player (only if the player isn't locked out)
        if player.invulnTimer <= 0
            and getDistance(player.x, player.y, e.x, e.y) < player.radius + e.radius then
            -- flat defense first (minimum 1), then percent reduction
            local damage = math.max(1, e.damage - player.defense) * (1 - player.damageReduction)
            player.hp = player.hp - damage
            player.hitFlashTimer = HIT_FLASH_TIME
            player.invulnTimer = PLAYER_INVULN_TIME
        end
    end
 
    -- Automatic shooting toward the mouse
    shootTimer = shootTimer + dt
    if shootTimer >= BASE_SHOOT_RATE / player.attackSpeed then
        shootTimer = 0
 
        local aimAngle = math.atan2(mouseY - player.y, mouseX - player.x)
        local proj = PROJECTILES[player.weapon]
        table.insert(bullets, {
            kind = player.weapon,
            x = player.x,
            y = player.y,
            dx = math.cos(aimAngle),
            dy = math.sin(aimAngle),
            angle = aimAngle,
            speed = 400,
            radius = 5,
            stat = proj.stat,
            damagePct = proj.pct,
        })
    end
 
    -- Movement of bullets + enemy collision
    for b_idx = #bullets, 1, -1 do
        local b = bullets[b_idx]
 
        b.x = b.x + b.dx * b.speed * dt
        b.y = b.y + b.dy * b.speed * dt
 
        -- Remove bullet if it goes off screen
        if b.x < 0 or b.x > screenWidth or b.y < 0 or b.y > screenHeight then
            table.remove(bullets, b_idx)
        else
            local hit = false
            for e_idx = #enemies, 1, -1 do
                local e = enemies[e_idx]
                --if bullet hits enemy, reduce enemy hp and remove bullet
                if getDistance(b.x, b.y, e.x, e.y) < b.radius + e.radius then
                    e.enemy_hp = e.enemy_hp - getProjectileDamage(b)
                    e.hitFlash = HIT_FLASH_TIME
                    if e.enemy_hp <= 0 then
                        table.remove(enemies, e_idx)
                    end
                    hit = true
                    score = score + 1
                    break -- Stop checking other enemies for this bullet
                end
            end
 
            if hit then
                table.remove(bullets, b_idx)
            end
        end
    end
end
 
--
-- Drawing --------------------------------------------------------------------
--
 
local function printShadowed(text, y)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.printf(text, 2, y + 2, screenWidth, "center")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(text, 0, y, screenWidth, "center")
end

local function drawMenu()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(background, 0, 0, 0,
        screenWidth / background:getWidth(),
        screenHeight / background:getHeight())
    printShadowed("Press Enter to start", screenHeight - 70)
    love.graphics.setFont(defaultFont)
end

function drawPauseMenu()
    -- Dim the frozen game underneath
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)

    local boxW, boxH = 380, 500
    local boxX = (screenWidth - boxW) / 2
    local boxY = (screenHeight - boxH) / 2
    love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 8, 8)

    love.graphics.setFont(menuFont)
    love.graphics.printf("PAUSED", boxX, boxY + 15, boxW, "center")
    love.graphics.setFont(defaultFont)

    local function pct(x) return fmt(x * 100) .. "%" end

    local lines = {
        "Health: " .. math.floor(math.max(0, player.hp)) .. " / " .. fmt(player.maxHp),
        string.format("Health regen: %.1f HP/s", player.regen),
        "Speed: " .. pct(player.speed / BASE_SPEED),
        "",
        "Defense",
        "    Armor: " .. fmt(player.defense),
        "    Damage reduction: " .. pct(player.damageReduction),
        "",
        "Damage",
        "    Attack speed: " .. pct(player.attackSpeed),        
        "    Attack power: " .. fmt(player.attackPower),
        "    Magic power: " .. fmt(player.magicPower),
        "    Damage multiplier: " .. pct(player.damageMult),
    }
    table.insert(lines, "")
    table.insert(lines, "Major upgrades")
    for i = 1, MAX_MAJOR do
        local m = player.majorUpgrades[i]
        table.insert(lines, "    " .. i .. ". " .. (m and (m.pool .. " - " .. m.name) or "(empty)"))
    end

    for i, line in ipairs(lines) do
        love.graphics.print(line, boxX + 24, boxY + 65 + (i - 1) * 20)
    end

    love.graphics.printf("Press Escape to resume", boxX, boxY + boxH - 35, boxW, "center")
end

function love.draw()
    --draw game over screen if player is dead
    if love.update == love.gameover then
        love.graphics.clear(0, 0, 0)
        love.graphics.setColor(1, 0, 0)
        love.graphics.printf("GAME OVER", 0, screenHeight / 2 - 30, screenWidth, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Score: " .. score, 0, screenHeight / 2, screenWidth, "center")
        love.graphics.printf("Press Enter to continue", 0, screenHeight / 2 + 30, screenWidth, "center")
        return
    end
    --draw main menu if in main menu state
    if love.update == love.menu then
        drawMenu()
        return
    end
 
    love.graphics.setColor(1, 1, 1, 1)
 
    cam:attach()
        gameMap:drawLayer(gameMap.layers["Ground"])
        gameMap:drawLayer(gameMap.layers["Trees"])
    cam:detach()
 
    -- Draw player
    local flash = player.hitFlashTimer / HIT_FLASH_TIME
    love.graphics.setColor(1, 1 - 0.8 * flash, 1 - 0.8 * flash, 1)
    local sprite = playerSprites[player.spriteKey]
    sprite.animation:draw(sprite.image, player.x, player.y, 0, 1.5, 1.5, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
 
    -- Draw enemies
    for _, e in ipairs(enemies) do
        local flash = e.hitFlash / HIT_FLASH_TIME
        love.graphics.setColor(1, 1 - 0.8 * flash, 1 - 0.8 * flash, 1)
        e.animation:draw(cyborgImage, e.x, e.y, 0, 1.5, 1.5, 16, 16)
    end
    love.graphics.setColor(1, 1, 1, 1)
 
    -- Draw bullets (yellow)
    love.graphics.setColor(1, 1, 1, 1)
    for _, b in ipairs(bullets) do
        if b.kind == "bullet" then
            bulletAnimation:draw(bulletImage, b.x, b.y, b.angle, 1, 1, bulletW / 2, bulletH / 2)
        else
            fireballAnimation:draw(fireballImage, b.x, b.y, b.angle, 1, 1, fireballW / 2, fireballH / 2)
        end
    end
 
    -- Draw UI/text (black)
    love.graphics.setColor(0, 0, 0)
    love.graphics.print("HP: " .. math.floor(math.max(0, player.hp)) .. " / " .. fmt(player.maxHp), 10, 10)
    love.graphics.print("Score: " .. score, 10, 30)
 
    -- Dialogue UI is drawn last so it sits on top of everything
    love.graphics.setColor(1, 1, 1, 1)
    narrator:draw()

    --Draw pause menu if game is paused
    if love.update == love.paused then
        drawPauseMenu()
    end
end
 