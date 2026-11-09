-- Helper function to find the difference between two points
local function getDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function love.load()
    sti = require 'libraries/sti'
    narrator = require 'libraries/narrator'
    camera = require 'libraries/camera'

    cam = camera()

    -- Get the screen dimensions so we know where to spawn things
    screenWidth = love.graphics.getWidth()
    screenHeight = love.graphics.getHeight()

    gameMap = sti('maps/testMap.lua')
    gameMap:resize(love.graphics.getWidth()*2, love.graphics.getHeight())

    -- Set custom cursor
    local customCursor = love.mouse.newCursor("sprites/cursor.png", 16, 16)
    love.mouse.setCursor(customCursor)

    wizard = love.graphics.newImage("sprites/Wizard.png")
    cyborg = love.graphics.newImage("sprites/Cyborg.png")


    narrator:init()

    -- Set up the player
    player = {
        x = screenWidth / 2,
        y = screenHeight / 2,
        rotation = 0,
        speed = 200,
        radius = 16,
        hp = 100,

        --upgrade variables
        lastupgradescore = 0,

        vx = 0, -- x velocity
        vy = 0, -- y velocity

        -- Dash variables
        dashForce = 1200, -- initial burst speed
        friction = 8, -- how much the player is slowed down
        dashCooldown = 0, -- Timer for dashing
        dashDelay = 1.0, -- Time between dashes (in seconds)

    }

    -- Lists to keep track of all active objects on screen
    enemies = {}
    bullets = {}

    -- Timers for enemies
    enemySpawnTimer = 0
    enemySpawnRate = 0.5 -- Spawn an enemy every x seconds

    shootTimer = 0
    shootRate = 0.5 -- Shoot a bullet every x seconds

    score = 0

    love.update = love.introDialogue
    -- love.draw = love.draw2
    count = 0
    time = 0
    lastKeyTime = 0
end

function love.introDialogue(dt)
    time = time + dt

    if narrator:isOpen() then
        -- Inside a dialog: advance / pick options.
        if love.keyboard.isDown("space", "return")  and (time - lastKeyTime) > 1 then 
            lastKeyTime = time
            narrator:onAction()
            if not narrator:isOpen() then
                love.update = love.gameplay
            end
        elseif love.keyboard.isDown("up")  and (time - lastKeyTime) > 0.3 then 
            lastKeyTime = time
            narrator:prevOption()
        elseif love.keyboard.isDown("down")  and (time - lastKeyTime) > 0.3 then 
            lastKeyTime = time
            narrator:nextOption()
        end
    else
        narrator:startScript("intro")
    end

    narrator:update(dt)
end

function love.gameplay(dt)

    -- dt is delta time, the time passed since the last frame
    -- Multiply by dt to make sure that movement is smooth no matter the framerate

    if player.hp <= 0 then
        return -- Stop updating the game if the player is dead
    end
    -- Player Upgrade after every 10 score
    -- when score % 10 == 0, and has not upgraded last update, move to love.upgrade
    if score > 0 and score % 10 == 0 and score ~= player.lastupgradescore then
        -- change love.update to love.upgrade
        --NOT IMPLEMENTEDnarrator:startScript("upgrade")
        love.update = love.upgrade
        player.lastupgradescore = score
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

    -- Apply movement to player coordinates
    player.x = player.x + (moveX * player.speed * dt)
    player.y = player.y + (moveY * player.speed * dt)

    -- Dash cooldown
    if player.dashCooldown > 0 then
        player.dashCooldown = player.dashCooldown - dt
    end

    if love.keyboard.isDown("space") and player.dashCooldown <= 0 then
        player.vx = math.cos(player.rotation) * player.dashForce
        player.vy = math.sin(player.rotation) * player.dashForce

        -- Reset dash cooldown timer
        player.dashCooldown = player.dashDelay
    end

    -- Apply velocity to player movement by adding it
    player.x = player.x + (player.vx * dt)
    player.y = player.y + (player.vy * dt)

    -- Apply friction to player movement by subtracting it
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

        -- Top
        if side == 1 then
            spawnX = math.random(0, screenWidth)
            spawnY = -30

        -- Bottom
        elseif side == 2 then
            spawnX = math.random(0, screenWidth)
            spawnY = screenHeight + 30

        -- Left
        elseif side == 3 then
            spawnX = -30
            spawnY = math.random(0, screenHeight)

        -- Right
        elseif side == 4 then
            spawnX = screenWidth + 30
            spawnY = math.random(0, screenHeight)
        end
        
        -- Spawn enemy at a random location at the top of the screen for simplicity
        local newEnemy = {
            x = spawnX,
            y = spawnY,
            enemy_hp = 10 + math.floor(score / 5), -- the enemy hp will increase by 1 every 10 score
            speed = 150,
            radius = 16
        }
        table.insert(enemies, newEnemy)
    end

    -- Enemy movement
    -- Loop backwards through table to remove dead enemies
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        
        -- Calculate the angle between the enemy and the player
        local angle = math.atan2(player.y - e.y, player.x - e.x)
        
        -- Move the enemy toward the player using the angle
        e.x = e.x + math.cos(angle) * e.speed * dt
        e.y = e.y + math.sin(angle) * e.speed * dt

        -- Check if enemy touched the player
        if getDistance(player.x, player.y, e.x, e.y) < player.radius + e.radius then
            player.hp = player.hp - 10
            table.remove(enemies, i) -- Remove the enemy that hit the player
        end
    end

    -- Automatic shooting
    shootTimer = shootTimer + dt
    if shootTimer >= shootRate and #enemies > 0 then
        shootTimer = 0

        -- Find the closest enemy
        local closestEnemy = nil
        local shortestDistance = math.huge -- Start with an infinitely large distance

        for _, e in ipairs(enemies) do
            local dist = getDistance(player.x, player.y, e.x, e.y)
            if dist < shortestDistance then
                shortestDistance = dist
                closestEnemy = e
            end
        end

        -- If we found a target, then we create a bullet aiming at it
        if closestEnemy then
            local perfectAngle = math.atan2(closestEnemy.y - player.y, closestEnemy.x - player.x)
            local maxSpread = 0.5
            local finalAngle = perfectAngle + (math.random() - 0.5) * maxSpread
            
            local newBullet = {
                x = player.x,
                y = player.y,
                dx = math.cos(finalAngle),
                dy = math.sin(finalAngle),
                speed = 400,
                radius = 5
            }
            table.insert(bullets, newBullet)
        end
    end

    -- Movement of bullets + enemy collision
    for b_idx = #bullets, 1, -1 do
        local b = bullets[b_idx]
        
        -- Move the bullet
        b.x = b.x + b.dx * b.speed * dt
        b.y = b.y + b.dy * b.speed * dt

        -- Remove bullet if it goes off screen
        if b.x < 0 or b.x > screenWidth or b.y < 0 or b.y > screenHeight then
            table.remove(bullets, b_idx)
        else
            -- Check for collision with enemies
            local hit = false
            for e_idx = #enemies, 1, -1 do
                local e = enemies[e_idx]
                
                if getDistance(b.x, b.y, e.x, e.y) < b.radius + e.radius then
                    -- Bullet hit an enemy, decrease enemy HP by 5 and increase score
                    e.enemy_hp = e.enemy_hp - 5
                    if e.enemy_hp <= 0 then
                        table.remove(enemies, e_idx)
                    end
                    hit = true
                    score = score + 1
                    break -- Stop checking other enemies for this bullet
                end
            end

            -- If the bullet hit something, remove the bullet
            if hit then
                table.remove(bullets, b_idx)
            end
        end
    end
end

function love.upgrade(dt)
    --[[time = time + dt

    if narrator:isOpen() then
        if love.keyboard.isDown("space", "return") and (time - lastKeyTime) > 1 then
            lastKeyTime = time
            narrator:onAction()
        elseif love.keyboard.isDown("up") and (time - lastKeyTime) > 0.3 then
            lastKeyTime = time
            narrator:prevOption()
        elseif love.keyboard.isDown("down") and (time - lastKeyTime) > 0.3 then
            lastKeyTime = time
            narrator:nextOption()
        end
    else
        love.update = love.gameplay
    end
    narrator:update(dt)
    ]]
    love.update = love.gameplay
end

function love.draw()
    -- Draw background
    -- love.graphics.clear(0.1, 0.1, 0.15) -- Dark bluish-grey baackground


    cam:attach()
        gameMap:drawLayer(gameMap.layers["Ground"])
        -- player.anim:draw(player.spriteSheet, player.x, player.y, nil, 6, nil, 6, 9)
        -- myNPC:draw()
        -- drNPC:draw()
        gameMap:drawLayer(gameMap.layers["Trees"])

        -- if nearbyNPC then
        --     drawInteractPrompt(nearbyNPC)
        -- end
    cam:detach()

    love.graphics.print("x = " .. math.floor(player.x) .. " y = " .. math.floor(player.y), 10, 10)

    -- Dialogue UI is drawn last so it sits on top of everything.
    -- narrator:draw()

    if player.hp <= 0 then
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("GAME OVER! Score: " .. score, screenWidth/2 - 50, screenHeight/2)
        return
    end

    -- Draw player
    love.graphics.setColor(1, 1, 1, 1)
    -- love.graphics.circle("fill", player.x, player.y, player.radius)
    love.graphics.draw(wizard, player.x-player.radius, player.y-player.radius, 0, 1.5, 1.5)

    -- Draw enemies
    love.graphics.setColor(1, 1, 1, 1)
    for _, e in ipairs(enemies) do
        -- love.graphics.circle("fill", e.x, e.y, e.radius)
        love.graphics.draw(cyborg, e.x-e.radius, e.y-e.radius, 0, 1.5, 1.5)
    end

    -- Draw bullets (yellow)
    love.graphics.setColor(1, 1, 0)
    for _, b in ipairs(bullets) do
        love.graphics.circle("fill", b.x, b.y, b.radius)
    end

    -- Draw UI/text
    love.graphics.setColor(1, 1, 1) -- White
    love.graphics.print("HP: " .. player.hp, 10, 10)
    love.graphics.print("Score: " .. score, 10, 30)
    count = count + 1
    -- love.graphics.print("time:" .. time .. "count: " .. count, 50, 50)


    narrator:draw()
end