anim8 = require 'libraries/anim8'
 
local function loadSheet(path, frameTime)
    local image = love.graphics.newImage(path)
    local grid = anim8.newGrid(32, 32, image:getWidth(), image:getHeight())
    local animation = anim8.newAnimation(grid('1-2', 1, '1-2', 2), frameTime)
    return image, animation
end
 
-- Helper function to find the distance between two points
local function getDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end
 
--
-- Upgrades -------------------------------------------------------------------
--
 
-- Add a new entry here and it automatically joins the random pool.
-- Avoid [ ] { } | characters in label/text, since they become ink source.
local upgradePool = {
    { id = "max_hp",
      label = "Vitality - +20 max HP",
      text = "Your body hardens against the wastes.",
      apply = function()
          player.maxHp = player.maxHp + 20
          player.hp = math.min(player.maxHp, player.hp + 20)
      end },
    { id = "regen",
      label = "Regeneration - +1 HP per second",
      text = "Your wounds begin to close on their own.",
      apply = function() player.regen = player.regen + 1 end },
    { id = "fire_rate",
      label = "Quickened Spells - faster fire rate",
      text = "Your staff hums with eager energy.",
      apply = function() shootRate = math.max(0.1, shootRate * 0.85) end },
    { id = "defense",
      label = "Warding - take less damage",
      text = "A faint barrier shimmers around you.",
      apply = function() player.defense = player.defense + 2 end },
    { id = "damage",
      label = "Overcharged Bolts - more bullet damage",
      text = "Your bolts crackle with raw power.",
      apply = function() bulletDamage = bulletDamage + 2 end },
    { id = "speed",
      label = "Fleet of Foot - move faster",
      text = "The ground slips away beneath your boots.",
      apply = function() player.speed = player.speed + 25 end },
}
 
local pendingUpgrade = nil  -- set by the ink observer, applied when the dialogue closes
local ignoreDash = false    -- stops a held space (used to close the dialogue) from dashing
 
local function pickUpgrades(n)
    local pool = {}
    for i, u in ipairs(upgradePool) do pool[i] = u end
 
    local picked = {}
    for _ = 1, math.min(n, #pool) do
        table.insert(picked, table.remove(pool, math.random(#pool)))
    end
    return picked
end
 
-- Builds ink source containing only the chosen upgrades
local function buildUpgradeScript(choices)
    local lines = {
        'VAR upgrade = ""',
        "",
        "Power surges through you. Choose your boon.",
        "",
    }
    for _, u in ipairs(choices) do
        table.insert(lines, "* [" .. u.label .. "]")
        table.insert(lines, "    " .. u.text)
        table.insert(lines, '    ~ upgrade = "' .. u.id .. '"')
        table.insert(lines, "    -> END")
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
 
local function startUpgrade()
    pendingUpgrade = nil
    local choices = pickUpgrades(3)
 
    local byId = {}
    for _, u in ipairs(choices) do byId[u.id] = u end
 
    narrator:startScript("upgrade", {
        content = buildUpgradeScript(choices),
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
    -- Restart after game over
    if player and player.hp <= 0 then
        if key == "return" or key == "kpenter" then
            love.load()
        end
        return
    end
 
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
 
    wizardImage, wizardAnimation = loadSheet("sprites/wizard.png", 0.2)
    cyborgImage, cyborgAnimation = loadSheet("sprites/cyborg.png", 0.2)
 
    narrator:init()
 
    -- Set up the player
    player = {
        x = screenWidth / 2,
        y = screenHeight / 2,
        rotation = 0,
        speed = 200,
        radius = 16,
        hp = 100,
        maxHp = 100,
        regen = 0,    -- HP per second
        defense = 0,  -- flat reduction to contact damage
 
        --upgrade variables
        lastupgradescore = 0,
 
        vx = 0, -- x velocity
        vy = 0, -- y velocity
 
        -- Dash variables
        dashForce = 1200, -- initial burst speed
        friction = 8,     -- how much the player is slowed down
        dashCooldown = 0, -- Timer for dashing
        dashDelay = 1.0,  -- Time between dashes (in seconds)
    }
 
    -- Lists to keep track of all active objects on screen
    enemies = {}
    bullets = {}
 
    -- Timers for enemies
    enemySpawnTimer = 0
    enemySpawnRate = 0.5 -- Spawn an enemy every x seconds
 
    shootTimer = 0
    shootRate = 0.5 -- Shoot a bullet every x seconds
    bulletDamage = 5
 
    score = 0
    pendingUpgrade = nil
    ignoreDash = false
 
    love.update = love.introDialogue
end
 
--
-- Update states --------------------------------------------------------------
--
 
function love.introDialogue(dt)
    if not narrator:isOpen() then
        narrator:startScript("intro")
    end
    narrator:update(dt)
end
 
function love.upgrade(dt)
    -- Input is handled in love.keypressed
    narrator:update(dt)
end
 
function love.gameplay(dt)
    if player.hp <= 0 then
        return -- Stop updating the game if the player is dead
    end
 
    wizardAnimation:update(dt)
 
    -- Player upgrade after every 20 score
    if score > 0 and score % 20 == 0 and score ~= player.lastupgradescore then
        player.lastupgradescore = score
        startUpgrade()
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
 
    -- Dash: uses the currently held movement keys
    if player.dashCooldown > 0 then
        player.dashCooldown = player.dashCooldown - dt
    end
    if not love.keyboard.isDown("space") then
        ignoreDash = false
    end
    if love.keyboard.isDown("space") and not ignoreDash and player.dashCooldown <= 0
        and (moveX ~= 0 or moveY ~= 0) then
        player.vx = moveX * player.dashForce
        player.vy = moveY * player.dashForce
        player.dashCooldown = player.dashDelay
    end
 
    -- Apply velocity, then friction
    player.x = player.x + (player.vx * dt)
    player.y = player.y + (player.vy * dt)
    player.vx = player.vx - (player.vx * player.friction * dt)
    player.vy = player.vy - (player.vy * player.friction * dt)
 
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
            enemy_hp = 10 + math.floor(score / 5), -- enemy hp grows with score
            speed = 150,
            radius = 16,
            animation = cyborgAnimation:clone()    -- each enemy gets its own animation clock
        }
        newEnemy.animation:gotoFrame(math.random(1, 4)) -- so they don't all animate in sync
        table.insert(enemies, newEnemy)
    end
 
    -- Enemy movement (loop backwards so removing entries is safe)
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        e.animation:update(dt)
 
        local angle = math.atan2(player.y - e.y, player.x - e.x)
        e.x = e.x + math.cos(angle) * e.speed * dt
        e.y = e.y + math.sin(angle) * e.speed * dt
 
        -- Check if enemy touched the player
        if getDistance(player.x, player.y, e.x, e.y) < player.radius + e.radius then
            player.hp = player.hp - math.max(1, 10 - player.defense)
            table.remove(enemies, i)
        end
    end
 
    -- Automatic shooting toward the mouse
    shootTimer = shootTimer + dt
    if shootTimer >= shootRate then
        shootTimer = 0
 
        local aimAngle = math.atan2(mouseY - player.y, mouseX - player.x)
        table.insert(bullets, {
            x = player.x,
            y = player.y,
            dx = math.cos(aimAngle),
            dy = math.sin(aimAngle),
            speed = 400,
            radius = 5
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
 
                if getDistance(b.x, b.y, e.x, e.y) < b.radius + e.radius then
                    e.enemy_hp = e.enemy_hp - bulletDamage
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
 
function love.draw()
    -- Game over screen: draw only this, nothing else
    if player.hp <= 0 then
        love.graphics.clear(0, 0, 0)
        love.graphics.setColor(1, 0, 0)
        love.graphics.printf("GAME OVER", 0, screenHeight / 2 - 30, screenWidth, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Score: " .. score, 0, screenHeight / 2, screenWidth, "center")
        love.graphics.printf("Press Enter to restart", 0, screenHeight / 2 + 30, screenWidth, "center")
        return
    end
 
    love.graphics.setColor(1, 1, 1, 1)
 
    cam:attach()
        gameMap:drawLayer(gameMap.layers["Ground"])
        gameMap:drawLayer(gameMap.layers["Trees"])
    cam:detach()
 
    -- Draw player
    love.graphics.setColor(1, 1, 1, 1)
    wizardAnimation:draw(wizardImage, player.x, player.y, 0, 1.5, 1.5, 16, 16)
 
    -- Draw enemies
    for _, e in ipairs(enemies) do
        e.animation:draw(cyborgImage, e.x, e.y, 0, 1.5, 1.5, 16, 16)
    end
 
    -- Draw bullets (yellow)
    love.graphics.setColor(1, 1, 0)
    for _, b in ipairs(bullets) do
        love.graphics.circle("fill", b.x, b.y, b.radius)
    end
 
    -- Draw UI/text (black)
    love.graphics.setColor(0, 0, 0)
    love.graphics.print("HP: " .. math.floor(player.hp) .. " / " .. player.maxHp, 10, 10)
    love.graphics.print("Score: " .. score, 10, 30)
 
    -- Dialogue UI is drawn last so it sits on top of everything
    love.graphics.setColor(1, 1, 1, 1)
    narrator:draw()
end
 