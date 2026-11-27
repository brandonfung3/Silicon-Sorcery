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

-- 2x2 sheet where only the first 3 slots hold frames (top row, then bottom left)
local function loadThreeFrameSheet(path, frameTime)
    local image = love.graphics.newImage(path)
    local iw, ih = image:getDimensions()
    local fw, fh = iw / 2, ih / 2
    local grid = anim8.newGrid(fw, fh, iw, ih)
    return image, anim8.newAnimation(grid('1-2', 1, 1, 2), frameTime), fw, fh
end

local HIT_FLASH_TIME = 0.1          -- seconds to flash red when player, enemy is hit
local PLAYER_INVULN_TIME = 0.5      -- seconds of invulnerability after being hit
local MAX_DASH_DISTANCE = 150
local BASE_SHOOT_RATE = 0.5         -- seconds between shots
local BASE_SPEED = 200

local UPGRADE_INTERVAL_START = 5        -- score per upgrade at the start
local UPGRADE_INTERVAL_MAX = 50         -- the interval never grows past this
local UPGRADE_INTERVAL_STEP = 5         -- how much the interval grows each time
local UPGRADES_PER_STEP = 4             -- upgrades taken before the interval grows
local DOUBLE_UPGRADE_CHANCE = 0.05   -- chance per offered minor upgrade to be doubled

local MAX_MAJOR = 4
local MAJOR_UPGRADE_SCORES = { 50, 150, 300, 500 } --score for major upgrades 1, 2, and 3
local GIANT_FIREBALL_SCALE = 2.5
local GIANT_FIREBALL_RADIUS = 40
local GIANT_FIREBALL_INTERVAL = 10       -- seconds between casts
local CLOAK_REDUCTION = 0.5          -- extra damage reduction while the cloak is active
local CLOAK_DAMAGE_PCT = 0.25        -- aura damage per second, as a fraction of magic power
local CLOAK_RADIUS = 90              -- how far the aura reaches (pixels)
local CLOAK_EXPIRE_DELAY = 1         -- seconds the cloak lasts after the player is hit
local CLOAK_RECAST_INTERVAL = 10     -- seconds until it returns after expiring
local CLOAK_TINT = { 0.6, 0.85, 1 }  -- light blue
local ORBIT_COUNT = 3
local ORBIT_RADIUS = 120            -- distance from the player (pixels)
local ORBIT_SPEED = 2              -- radians per second
local ORBIT_ORB_RADIUS = 24        -- hitbox size of each orb
local ORBIT_SPRITE_SCALE = 1.5    -- placeholder sprite scale
local ORBIT_DAMAGE_PCT = 2.0       -- 2x magic damage
local ORBIT_HIT_COOLDOWN = 0.5     -- seconds before the same orb can hit the same enemy again
local FROSTBITE_INTERVAL = 5       -- seconds between casts
local ICICLE_COUNT = 7
local ICICLE_CONE = math.rad(60)   -- total width of the cone
local ICICLE_SPEED = 450
local ICICLE_SCALE = 0.8
local ICICLE_RADIUS = 12           -- hitbox
local FROST_SLOW_MULT = 0.7        -- 30% slower
local FROST_SLOW_DURATION = 2      -- seconds
local ORBITAL_STRIKE_COUNT = 3     -- strikes per cast
local ORBITAL_INTERVAL = 15        -- seconds between strikes at 100% attack speed
local ORBITAL_FALL_TIME = 1.0      -- seconds from cast to impact
local ORBITAL_RADIUS = 75          -- blast radius (pixels)
local ORBITAL_DAMAGE_PCT = 3.0     -- 3x attack power
local ORBITAL_SPRITE_SCALE = 2     -- sprite scale
local ORBITAL_BLAST_TIME = 0.2     -- how long the blast flash stays on screen

-- Enemies
local BASE_SPAWNS_PER_SECOND = 2         -- same as the old 1 enemy per 0.5s
local SPAWN_RAMP_START_SCORE = 50        -- enemy spawn rate stays flat until 50 score
local SPAWN_RATE_GROWTH = 0.01           -- extra spawns per second, gained every second
local MAX_SPAWNS_PER_SECOND = 8          -- cap so it can't flood the screen
local DAMAGE_NUMBER_TIME = 0.7     -- seconds a damage number stays on screen
local DAMAGE_NUMBER_RISE = 40      -- pixels per second it floats upward
local MAGIC_NUMBER_COLOR = { 0.4, 0.6, 1 }
local PHYSICAL_NUMBER_COLOR = { 1, 0.3, 0.3 }

-- Each projectile type: whcih power stat it scales with, and what % of player power it deals
local PROJECTILES = {
    fireball = { stat = "magic", pct = 1.0 },
    bullet   = { stat = "attack", pct = 1.0 },

    giant_fireball = { stat = "magic", pct = 2.0},
    icicle = { stat = "magic", pct = 1.5 },
}

-- Power stat * its own multiplier
local function getPower(stat)
    if stat == "magic" then
        return player.magicPower * player.magicMult
    end
    return player.attackPower * player.attackMult
end
--What a given projectile's damage deals right now
local function getProjectileDamage(kind)
    return getPower(kind.stat) * kind.damagePct
end
 
-- Helper function to find the distance between two points
local function getDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Every enemy hit goes through here: damage, red flash, a floating number, and a kill removes them and scores.
-- stat is "magic" or "physical" and decides the number's colour.
local function damageEnemy(index, amount, stat)
    local e = enemies[index]
    e.enemy_hp = e.enemy_hp - amount
    e.hitFlash = HIT_FLASH_TIME

    table.insert(damageNumbers, {
        x = e.x + math.random(-10, 10),
        y = e.y - e.radius,
        text = tostring(math.floor(amount)),
        stat = stat,
        timer = 0,
    })

    if e.enemy_hp <= 0 then
        table.remove(enemies, index)
        score = score + 1
    end
end

local function updateDamageNumbers(dt)
    for i = #damageNumbers, 1, -1 do
        local n = damageNumbers[i]
        n.timer = n.timer + dt
        n.y = n.y - DAMAGE_NUMBER_RISE * dt
        if n.timer >= DAMAGE_NUMBER_TIME then table.remove(damageNumbers, i) end
    end
end

-- Total damage reduction, including the cloak, capped at 95%
local function getDamageReduction()
    local r = player.damageReduction
    if player.cloakActive then r = r + CLOAK_REDUCTION end
    return math.min(0.95, r)
end

-- Score needed for the next minor upgrade, based on how many have been taken
local function getUpgradeInterval(upgradesTaken)
    local steps = math.floor(upgradesTaken / UPGRADES_PER_STEP)
    return math.min(UPGRADE_INTERVAL_MAX, UPGRADE_INTERVAL_START + UPGRADE_INTERVAL_STEP * steps)
end

-- Seconds between enemy spawns, shrinking as the game goes on. Capped at a minimum spawn interval.
local function getSpawnInterval()
    local rate = math.min(MAX_SPAWNS_PER_SECOND, BASE_SPAWNS_PER_SECOND + SPAWN_RATE_GROWTH * spawnRampTime)
    return 1 / rate
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

-- Upgrade for Pulse Cannon. When a bullet hits an enemy, split into 2 fireballs
local function spawnPulseFireballs(b, hitEnemy)
    for _, offset in ipairs({ -math.pi / 3, math.pi / 3 }) do  -- +/- 60 degrees
        local a = b.angle + offset
        table.insert(bullets, {
            kind = "fireball",
            x = b.x,
            y = b.y,
            dx = math.cos(a),
            dy = math.sin(a),
            angle = a,
            speed = 400,
            radius = 5,
            stat = PROJECTILES.fireball.stat,
            damagePct = PROJECTILES.fireball.pct,
            ignoreEnemy = hitEnemy,  -- so they don't instantly hit the enemy they came from
        })
    end
end

-- Fires the giant fireball toward a point; it bursts when it gets there
local function castGiantFireball(aimX, aimY)
    local dx, dy = aimX - player.x, aimY - player.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local angle = math.atan2(dy, dx)

    table.insert(bullets, {
        kind = "giant_fireball",
        x = player.x,
        y = player.y,
        dx = math.cos(angle),
        dy = math.sin(angle),
        angle = angle,
        speed = 300,
        radius = GIANT_FIREBALL_RADIUS,
        stat = PROJECTILES.giant_fireball.stat,
        damagePct = PROJECTILES.giant_fireball.pct,
        travelRemaining = dist,  -- distance to where the mouse was
        hitEnemies = {},         -- enemies already damaged, so each is hit only once
    })
end

-- On impact, release 8 regular fireballs in a ring
local function spawnFireballRing(b, hitEnemy)
    for i = 0, 7 do
        local a = i * (math.pi / 4)  -- 8 directions
        table.insert(bullets, {
            kind = "fireball",
            x = b.x,
            y = b.y,
            dx = math.cos(a),
            dy = math.sin(a),
            angle = a,
            speed = 400,
            radius = 5,
            stat = PROJECTILES.fireball.stat,
            damagePct = PROJECTILES.fireball.pct,
            ignoreEnemy = hitEnemy,  -- so they don't instantly hit the enemy they came from
        })
    end
end

-- Celestial Cloak: aura damage, expiry after a hit, and recasting
local function updateCloak(dt)
    if not player.hasCloak then return end

    if player.cloakActive then
        -- Once per second, hit every enemy in range
        player.cloakAuraTimer = player.cloakAuraTimer + dt
        if player.cloakAuraTimer >= 1 then
            player.cloakAuraTimer = player.cloakAuraTimer - 1
            local damage = getPower("magic") * CLOAK_DAMAGE_PCT
            for i = #enemies, 1, -1 do
                local e = enemies[i]
                if getDistance(player.x, player.y, e.x, e.y) < CLOAK_RADIUS then
                    damageEnemy(i, damage, "magic")
                end
            end
        end

        -- After the player is hit, the cloak fades once the delay runs out
        if player.cloakExpiring then
            player.cloakExpireTimer = player.cloakExpireTimer - dt
            if player.cloakExpireTimer <= 0 then
                player.cloakActive = false
                player.cloakExpiring = false
                player.cloakRecastTimer = 0
            end
        end
    else
        -- Recharging. The interval is checked every frame, so cooldown reduction
        -- picked up mid-recharge applies right away.
        player.cloakRecastTimer = player.cloakRecastTimer + dt
        if player.cloakRecastTimer >= CLOAK_RECAST_INTERVAL / player.castSpeed then
            player.cloakActive = true
            player.cloakAuraTimer = 0
        end
    end
end

-- Current position of each orb
local function getOrbPositions()
    local list = {}
    for i = 0, ORBIT_COUNT - 1 do
        local a = player.orbitAngle + i * (2 * math.pi / ORBIT_COUNT)
        list[i + 1] = {
            x = player.x + math.cos(a) * ORBIT_RADIUS,
            y = player.y + math.sin(a) * ORBIT_RADIUS,
        }
    end
    return list
end

-- Arcane Orbit: spin the orbs and damage enemies they touch
local function updateOrbit(dt)
    if not player.hasOrbit then return end

    player.orbitAngle = player.orbitAngle + ORBIT_SPEED * player.castSpeed * dt

    -- Tick down each orb's per-enemy hit cooldowns
    for i = 1, ORBIT_COUNT do
        for enemy, t in pairs(player.orbitHits[i]) do
            t = t - dt
            player.orbitHits[i][enemy] = (t > 0) and t or nil
        end
    end

    local damage = getPower("magic") * ORBIT_DAMAGE_PCT
    for i, orb in ipairs(getOrbPositions()) do
        for e_idx = #enemies, 1, -1 do
            local e = enemies[e_idx]
            if not player.orbitHits[i][e]
                and getDistance(orb.x, orb.y, e.x, e.y) < ORBIT_ORB_RADIUS + e.radius then
                player.orbitHits[i][e] = ORBIT_HIT_COOLDOWN
                damageEnemy(e_idx, damage, "magic")
            end
        end
    end
end

-- Sprays a cone of icicles centered on the aim point
local function castIcicles(aimX, aimY)
    local center = math.atan2(aimY - player.y, aimX - player.x)
    local step = ICICLE_CONE / (ICICLE_COUNT - 1)

    for i = 0, ICICLE_COUNT - 1 do
        local a = center + (i - (ICICLE_COUNT - 1) / 2) * step
        table.insert(bullets, {
            kind = "icicle",
            x = player.x,
            y = player.y,
            dx = math.cos(a),
            dy = math.sin(a),
            angle = a,
            speed = ICICLE_SPEED,
            radius = ICICLE_RADIUS,
            stat = PROJECTILES.icicle.stat,
            damagePct = PROJECTILES.icicle.pct,
        })
    end
end

-- Orbital Strike: mark random spots; each strike lands after ORBITAL_FALL_TIME.
-- No strike's center may sit inside another strike's radius (the radii can overlap).
-- Casts one extra strike for every full 100% of attack speed above the base.
local function castOrbitalStrike()
    local extra = math.floor(math.max(0, player.attackSpeed - 1) + 1e-6)
    local count = ORBITAL_STRIKE_COUNT + extra

    local margin = ORBITAL_RADIUS   -- keeps the blast circle mostly on screen
    local centers = {}

    for _ = 1, count do
        for _ = 1, 50 do   -- retry a limited number of times so it can never loop forever
            local x = margin + math.random() * (screenWidth - 2 * margin)
            local y = margin + math.random() * (screenHeight - 2 * margin)

            local ok = true
            for _, c in ipairs(centers) do
                if getDistance(x, y, c.x, c.y) < ORBITAL_RADIUS then
                    ok = false
                    break
                end
            end

            if ok then
                table.insert(centers, { x = x, y = y })
                table.insert(strikes, { x = x, y = y, timer = 0, landed = false, blastTimer = 0 })
                break
            end
        end
    end
end

local function updateStrikes(dt)
    for i = #strikes, 1, -1 do
        local s = strikes[i]
        if not s.landed then
            s.timer = s.timer + dt
            if s.timer >= ORBITAL_FALL_TIME then
                -- Impact: damage everything in the blast radius
                s.landed = true
                s.blastTimer = ORBITAL_BLAST_TIME
                local damage = getPower("attack") * ORBITAL_DAMAGE_PCT
                for e_idx = #enemies, 1, -1 do
                    local e = enemies[e_idx]
                    if getDistance(s.x, s.y, e.x, e.y) < ORBITAL_RADIUS + e.radius then
                        damageEnemy(e_idx, damage, "physical")
                    end
                end
            end
        else
            s.blastTimer = s.blastTimer - dt
            if s.blastTimer <= 0 then table.remove(strikes, i) end
        end
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

-- Raises both multipliers (for upgrades that boost all damage)
local function addDamageMult(amount)
    player.attackMult = roundTo(player.attackMult + amount, 3)
    player.magicMult = roundTo(player.magicMult + amount, 3)
end

local pendingEnding = false  -- true after the final major pick, until the ending screen is shown
local inEnding = false       -- true while the ending screen is open

-- Adds to attack or magic power.
local function addPower(stat, amount)
    if stat == "magic" then
        player.magicPower = roundTo(player.magicPower + amount, 1)
    else
        player.attackPower = roundTo(player.attackPower + amount, 1)
    end
end

--Formats a number with at most 1 decimal
local function fmt(n)
    local s = string.format("%.1f", n)
    return (s:gsub("%.0$", ""))  -- remove trailing .0
end

-- Add a new entry here and it automatically joins the random pool.
-- Avoid [ ] { } | characters in label/text, since they become ink source.
local upgradePool = {
    { id = "max_hp", base = 30, decimals = 0,
      label = function(v) return "Vitality - +" .. fmt(v) .. " max HP" end,
      text = "Your body hardens against the wastes.",
      apply = function(v)
          player.maxHp = player.maxHp + v
          player.hp = math.min(player.maxHp, player.hp + v)
      end },
    { id = "regen", base = 1.5,
      label = function(v) return "Regeneration - +" .. fmt(v) .. " HP per second" end,
      text = "Your wounds begin to close on their own.",
      apply = function(v) player.regen = roundTo(player.regen + v, 1) end },
    { id = "fire_rate", base = 15, decimals = 0,   -- percent
      label = function(v) return "Firing rate - +" .. fmt(v) .. "% attack speed" end,
      text = "Your staff hums with eager energy.",
      apply = function(v) player.attackSpeed = roundTo(player.attackSpeed + v / 100, 2) end },
    { id = "defense", base = 3,
      label = function(v) return "Warding - +" .. fmt(v) .. " armor" end,
      text = "A faint barrier shimmers around you.",
      apply = function(v) player.defense = roundTo(player.defense + v, 1) end },
    { id = "attack_power", base = 3,
      label = function(v) return "Hardened Rounds - +" .. fmt(v) .. " physical power" end,
      text = "Your ammunition hits like a hammer.",
      apply = function(v) addPower("attack", v) end },    
    { id = "magic_power", base = 3,
      label = function(v) return "Arcane Might - +" .. fmt(v) .. " magic power" end,
      text = "Raw magic surges through you.",
      apply = function(v) addPower("magic", v) end },    
    { id = "all_power", base = 2.25,
      label = function(v) return "Balanced Might - +" .. fmt(v) .. " physical and magic power" end,
      text = "Steel and sorcery rise together.",
      apply = function(v)
        addPower("attack", v)
        addPower("magic", v)
    end },
    { id = "speed", base = 15, decimals = 0,       -- percent
      label = function(v) return "Fleet of Foot - +" .. fmt(v) .. "% move speed" end,
      text = "The ground slips away beneath your boots.",
      apply = function(v) player.speed = player.speed + v / 100 * BASE_SPEED end },
    --rare 3% chance upgrades
      { id = "damage_mult", base = 7, rare = 0.03,
      label = function(v) return "Overwhelming Force - +" .. fmt(v) .. "% damage multiplier" end,
      text = "Every strike lands harder than it should.",
      apply = function(v) addDamageMult(v / 100) end },
    { id = "damage_reduction", base = 7, rare = 0.03,
      label = function(v) return "Aegis - +" .. fmt(v) .. "% damage reduction" end,
      text = "Blows seem to glance off you.",
      apply = function(v) player.damageReduction = math.min(0.95, roundTo(player.damageReduction + v / 100, 3)) end },
    { id = "cast_speed", base = 15, decimals = 0, rare = 0.03,   -- percent
      label = function(v) return "Arcane Tempo - +" .. fmt(v) .. "% cast speed" end,
      text = "Your spells come faster than thought.",
      apply = function(v) player.castSpeed = roundTo(player.castSpeed + v / 100, 2) end },
}

-- The effects aren't implemented yet; the text lines are placeholder flavor.
local majorPools = {
    { name = "Wizard", upgrades = {
        { id = "frostbite",      name = "Frostbite Staff",        
          text = "Cold creeps along your staff.", 
          desc = "Every 5 seconds, cast a cone of icicles that deal damage and slow enemies"},
        { id = "giant_fireball", name = "Giant fireball",   
          text = "Your flames swell beyond reason.",
          desc = "Every 10 seconds, cast a giant fireball that pierces enemies and bursts into a ring of fireballs" },
        { id = "celestial_cloak", name = "Celestial Cloak",
          text = "Starlight settles over your shoulders.",
          desc = "Conjure a cloak that reduces damage and deals magic damage to nearby enemies, lingering for 1 second after you take damage. Replenishes after 10 seconds." },
        { id = "mana_siphon", name = "Mana Siphon",
          text = "The magic around you begins to flow into you.",
          desc = "Increase the rate at which you cast spells. Upgrades now also grant 2 magic power." },
        { id = "arcane_orbit", name = "Arcane Orbit",
          text = "Orbs of power circle you.",
          desc = "Conjure three orbs around you, dealing magic damage to enemies they touch." },
    }},
    { name = "Cybernetic", upgrades = {
        { id = "pulse_cannon",   name = "Pulse Cannon arm",  
          text = "Your arm whirs and splits into a cannon.",
          desc = "Deal 25% reduced damage. Bullets that hit an enemy split into 2 fireballs. Swap your primary weapon is now the blaster" },
        { id = "titanium_bio",   name = "Titanium Bioskeleton", 
          text = "Metal laces through your bones.",
          desc = "Take less damage and gain health and physical power." },
        { id = "orbital_strike", name = "Orbital Strike Uplink",
          text = "Somewhere above, a satellite wakes.",
          desc = "Periodically calls down random strikes, dealing large physical damage to enemies in the blasts. Attack speed increases the rate and number of strikes." },        
        { id = "overclocked_servos", name = "Overclocked Servos",
          text = "Your joints whine as the limiters come off.",
          desc = "Dramatically increase your attack and movement speed." },
        { id = "rapid_boots", name = "Rapid-fire Boots",
          text = "Your boots hum with restless energy.",
          desc = "Dash more often, and fire 2 bullets at the closest enemy when you dash." },
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
    pulse_cannon = function()
        addDamageMult(-0.25)
        player.weapon = "bullet" -- basic attack becomes bullets
    end,
    titanium_bio = function(order)
        -- +30% damage reduction, capped at 95%
        player.damageReduction = math.min(0.95, roundTo(player.damageReduction + 0.30, 3))
        -- +25 max HP
        player.maxHp = player.maxHp + 25
        player.hp = math.min(player.maxHp, player.hp + 25)
        -- Attack power scales with when the upgrade was picked
        addPower("attack", 10 * order)
    end,
    overclocked_servos = function()
        player.attackSpeed = player.attackSpeed + 1.0            -- +100% attack speed
        player.speed = player.speed + BASE_SPEED                 -- +100% movement speed
    end,
    giant_fireball = function()
        player.giantFireballTimer = GIANT_FIREBALL_INTERVAL
    end,
    mana_siphon = function()
        player.castSpeed = player.castSpeed + 1.0                -- + 100% cast speed
    end,
    celestial_cloak = function()
        player.hasCloak = true
        player.cloakActive = true
        player.cloakAuraTimer = 0
        player.cloakExpiring = false
    end,
    arcane_orbit = function()
        player.hasOrbit = true
        player.orbitAngle = 0
        player.orbitHits = {}
        for i = 1, ORBIT_COUNT do
            -- weak keys, so dead enemies don't pile up in the table
            player.orbitHits[i] = setmetatable({}, { __mode = "k" })
        end
    end,
    frostbite = function()
        player.frostbiteTimer = FROSTBITE_INTERVAL
    end,
    orbital_strike = function()
        player.orbitalTimer = ORBITAL_INTERVAL
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
                label = u.name .. (u.desc and (" - " .. u.desc) or ""),
                text = u.text,
                apply = function()
                    table.insert(player.majorUpgrades, { id = u.id, name = u.name, pool = pool.name })
                    -- The first major upgrade decides the player's look
                    if #player.majorUpgrades == 1 then
                        player.spriteKey = pool.name
                    end
                    -- Every major upgrade also grants 5% to its pool's multiplier
                    if pool.name == "Cybernetic" then
                        player.attackMult = roundTo(player.attackMult + 0.05, 3)
                    elseif pool.name == "Wizard" then
                        player.magicMult = roundTo(player.magicMult + 0.05, 3)
                    end
                    if majorEffects[u.id] then majorEffects[u.id](#player.majorUpgrades) end
                    -- After the final major upgrade, show the ending text
                    if #player.majorUpgrades >= MAX_MAJOR then
                        pendingEnding = true
                    end
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

        -- 1% chance to double the upgrade
        local doubled = math.random() < DOUBLE_UPGRADE_CHANCE
        if doubled then value = roundTo(value * 2, u.decimals or 1) end

        -- golden wins over light blue, even for a rare upgrade
        local color = nil
        if doubled then
            color = { 1, 0.82, 0.2 }
        elseif u.rare then
            color = { 0.55, 0.8, 1 }
        end

        table.insert(picked, {
            id = u.id,
            label = u.label(value),
            text = u.text,
            color = color,
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

    local byId, colors = {}, {}
    for _, u in ipairs(choices) do
        byId[u.id] = u
        if u.color then colors[u.label] = u.color end
    end

    narrator:startScript("upgrade", {
        content = buildUpgradeScript(choices, intro),
        colors = colors,
        observe = {
            upgrade = function(value)
                if value and value ~= "" then pendingUpgrade = byId[value] end
            end,
        },
    })
    love.update = love.upgrade
end

-- Shown after the final major upgrade; the text depends on which pools the player chose from
local function startEndingScript()
    local wizards, cybers = 0, 0
    for _, m in ipairs(player.majorUpgrades) do
        if m.pool == "Wizard" then wizards = wizards + 1 else cybers = cybers + 1 end
    end

    local text
    if wizards >= MAX_MAJOR then
        text = {
            "TEXT FOR FOUR WIZARDRY UPGRADES",
            "You walked the old path to its end, and the magic answered every time.",
            "The machines have never seen anything like you.",
        }
    elseif cybers >= MAX_MAJOR then
        text = {
            "TEXT FOR FOUR CYBERNETIC UPGRADES",
            "You gave yourself to the machines piece by piece, and they took everything you offered.",
            "There is very little left of the wizard.",
        }
    else
        text = {
            "TEXT FOR A MIX OF WIZARDRY AND CYBERNETICS",
            "Spell and circuit, ritual and code. You belong to neither world and both.",
            "Perhaps that is the power you were looking for.",
        }
    end

    inEnding = true
    startUpgrade({
        { id = "continue", label = "Continue", text = "You press on, changed.", apply = function() end },
    }, table.concat(text, "\n"))
end
 
--
-- Input ----------------------------------------------------------------------
--
 
function love.keypressed(key)
    --Game over: Enter returns to the main menu
    if love.update == love.gameover then
        if key == "return" or key == "kpenter" then
            startGame()
        end
        return
    end

    -- Tutorial: close it and return to the main menu
    if love.update == love.tutorial then
        if key == "escape" or key == "return" or key == "kpenter" or key == "t" then
            love.update = love.menu
        end
        return
    end

    -- Main menu: Enter starts the game, T opens the tutorial
    if love.update == love.menu then
        if key == "return" or key == "kpenter" then
            startGame()
        elseif key == "t" then
            love.update = love.tutorial
        end
        return
    end

    --Pause / resume 
    if key == "escape" or key == "e" then
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
                    -- checked first, and skipped on the conversion screen, so neither pays out Mana Siphon
                    local siphon = hasMajor("mana_siphon") and not inEnding
                    pendingUpgrade.apply()
                    pendingUpgrade = nil
                    if siphon then addPower("magic", 2) end
                end
                ignoreDash = true

                -- The last major upgrade was just picked: show the ending text before returning to the game
                if pendingEnding and not inEnding then
                    pendingEnding = false
                    startEndingScript()
                    return
                end
                inEnding = false
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
    giantFireballImage, giantFireballAnimation, giantFireballW, giantFireballH = loadFireball("sprites/giant_fireball.png", 0.1)
    bigHurtyImage, bigHurtyAnimation, bigHurtyW, bigHurtyH = loadThreeFrameSheet("sprites/big_hurty.png", 0.1)
    background = love.graphics.newImage("sprites/background.png")

    defaultFont = love.graphics.getFont()
    menuFont = love.graphics.newFont(24)
    hudFont = love.graphics.newFont(24)
    damageFont = love.graphics.newFont(14)
    tutorialFont = love.graphics.newFont(14)

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
        hp = 150,                   -- current HP
        maxHp = 150,
        regen = 0,                  -- HP per second
        defense = 0,                -- flat reduction from upgrades
        attackPower = 10,            -- flat attack added from upgrades
        magicPower = 10,             -- flat magic added from upgrades
        attackMult = 1.0,  -- 1.0 = 100%; scales attack power (bullets)
        magicMult = 1.0,   -- 1.0 = 100%; scales magic power (fireballs, cloak) and magic power
        damageReduction = 0,        -- 0 = 0% damage reduction
        attackSpeed = 1.0,          -- 1.0 = 100% attack speed
        castSpeed = 1.0,             -- 1.0 = 100% cast speed; 2.0 casts spells twice as often

        hitFlashTimer = 0,          -- Time left for hit flash effect
        invulnTimer = 0,            -- Time left before player can be hit again (after taking damage)
        -- EXP BAR
        barStart = 0,               -- score at which the last upgrade happened

        --Upgrade variables
        minorUpgradeCount = 0,
        nextUpgradeScore = UPGRADE_INTERVAL_START,  -- score needed for the next minor upgrade
        nextMajorIndex = 1,         -- which entry of MAJOR_UPGRADE_SCORES comes next
        majorUpgrades = {},         -- list of major upgrades the player has chosen
        giantFireballTimer = 0,     -- timer for casting giant fireball if the player has that major upgrade
        frostbiteTimer = 0,         -- timer for casting frostbite 
        -- Celestial Cloak
        hasCloak = false,
        cloakActive = false,
        cloakAuraTimer = 0,
        cloakExpiring = false,      -- true once the player has been hit while it was active
        cloakExpireTimer = 0,
        cloakRecastTimer = 0,
        -- Arcane Orbit
        hasOrbit = false,
        orbitAngle = 0,
        orbitHits = {},   -- one table per orb, filled when the upgrade is picked
        -- Orbital Strike
        orbitalTimer = 0,

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
    strikes = {}
    damageNumbers = {}
 
    -- Timers for enemies
    enemySpawnTimer = 0
    spawnRampTime = 0 -- seconds spent at or above SPAWN_RAMP_START_SCORE
 
    shootTimer = 0
 
    score = 0
    pendingUpgrade = nil
    pendingEnding = false
    inEnding = false
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

function love.tutorial(dt)
    -- Tutorial input is handled in love.keypressed
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
 
    if score >= SPAWN_RAMP_START_SCORE then
        spawnRampTime = spawnRampTime + dt
    end
    playerSprites[player.spriteKey].animation:update(dt)
    fireballAnimation:update(dt)
    bulletAnimation:update(dt)
    giantFireballAnimation:update(dt)
    bigHurtyAnimation:update(dt)

    -- Update the hit flash timer
    if player.hitFlashTimer > 0 then
        player.hitFlashTimer = player.hitFlashTimer - dt
    end

    -- Update the invulnerability timer
    if player.invulnTimer > 0 then
        player.invulnTimer = player.invulnTimer - dt
    end

    updateCloak(dt)
    updateOrbit(dt)
    updateStrikes(dt)
    updateDamageNumbers(dt)
    
    -- Major upgrades at the scores in MAJOR_UPGRADE_SCORES (>= so a score jump can't skip one)
    local majorScore = MAJOR_UPGRADE_SCORES[player.nextMajorIndex]
    if majorScore and score >= majorScore then
        player.nextMajorIndex = player.nextMajorIndex + 1

        if #player.majorUpgrades < MAX_MAJOR then
            local majorChoices = pickMajorUpgrades()
            if #majorChoices > 0 then
                startUpgrade(majorChoices, "A greater power calls to you. Choose your path.")
                return
            end
        end
    end

    --minor upgrades
    if score >= player.nextUpgradeScore then
        player.minorUpgradeCount = player.minorUpgradeCount + 1
        player.nextUpgradeScore = score + getUpgradeInterval(player.minorUpgradeCount)
        player.barStart = score
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
    if enemySpawnTimer >= getSpawnInterval() then
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
            enemy_hp = 15 + math.max(0, math.floor((score - 25) / 10)),  -- enemy hp grows with score
            damage = 10 + math.max(0, math.floor((score - 50) / 25)),   -- enemy damage grows with score
            speed = 150,
            radius = 16,

            slowTimer = 0,                          -- time left on the frostbite slow
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
 
        local speedMult = 1
        if e.slowTimer > 0 then
            e.slowTimer = e.slowTimer - dt
            speedMult = FROST_SLOW_MULT
        end

        local angle = math.atan2(player.y - e.y, player.x - e.x)
        e.x = e.x + math.cos(angle) * e.speed * speedMult * dt
        e.y = e.y + math.sin(angle) * e.speed * speedMult * dt

        -- Check if enemy touched the player (only if the player isn't locked out)
        if player.invulnTimer <= 0
            and getDistance(player.x, player.y, e.x, e.y) < player.radius + e.radius then
            -- percent reduction first, then flat defense (minimum 1)
            local damage = math.max(1, e.damage * (1 - getDamageReduction()) - player.defense)
            player.hp = player.hp - damage
            player.hitFlashTimer = HIT_FLASH_TIME
            player.invulnTimer = PLAYER_INVULN_TIME

            -- The hit that breaks the cloak is still reduced; the cloak fades 1 second later
            if player.cloakActive and not player.cloakExpiring then
                player.cloakExpiring = true
                player.cloakExpireTimer = CLOAK_EXPIRE_DELAY
            end
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

    -- Giant fireball cast automatically every 10 seconds
    if hasMajor("giant_fireball") then
        player.giantFireballTimer = player.giantFireballTimer + dt
        if player.giantFireballTimer >= GIANT_FIREBALL_INTERVAL / player.castSpeed then
            player.giantFireballTimer = 0
            castGiantFireball(mouseX, mouseY)
        end
    end

    -- Frostbite Staff: spray icicles every 5 seconds
    if hasMajor("frostbite") then
        player.frostbiteTimer = player.frostbiteTimer + dt
        if player.frostbiteTimer >= FROSTBITE_INTERVAL / player.castSpeed then
            player.frostbiteTimer = 0
            castIcicles(mouseX, mouseY)
        end
    end

    -- Orbital Strike: call down a strike every 15 seconds (sooner with attack speed)
    if hasMajor("orbital_strike") then
        player.orbitalTimer = player.orbitalTimer + dt
        if player.orbitalTimer >= ORBITAL_INTERVAL / player.attackSpeed then
            player.orbitalTimer = 0
            castOrbitalStrike()
        end
    end
 
    -- Movement of bullets + enemy collision
    for b_idx = #bullets, 1, -1 do
        local b = bullets[b_idx]

        if b.kind == "giant_fireball" then
            -- Move, but never past the point the mouse was at
            local step = math.min(b.speed * dt, b.travelRemaining)
            b.x = b.x + b.dx * step
            b.y = b.y + b.dy * step
            b.travelRemaining = b.travelRemaining - step

            -- Damage every enemy it passes through, once each
            for e_idx = #enemies, 1, -1 do
                local e = enemies[e_idx]
                if not b.hitEnemies[e]
                    and getDistance(b.x, b.y, e.x, e.y) < b.radius + e.radius then
                    b.hitEnemies[e] = true
                    damageEnemy(e_idx, getProjectileDamage(b), b.stat)
                end
            end

            -- Burst when it reaches the target point or the edge of the screen
            local atEdge = b.x <= 0 or b.x >= screenWidth or b.y <= 0 or b.y >= screenHeight
            if b.travelRemaining <= 0 or atEdge then
                b.x = math.max(0, math.min(screenWidth, b.x))   -- keep the ring on screen
                b.y = math.max(0, math.min(screenHeight, b.y))
                spawnFireballRing(b, nil)
                table.remove(bullets, b_idx)
            end
        else
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
                    if e ~= b.ignoreEnemy
                        and getDistance(b.x, b.y, e.x, e.y) < b.radius + e.radius then
                        -- Pulse Cannon: bullets split into 2 fireballs on impact
                        if b.kind == "bullet" and hasMajor("pulse_cannon") then
                            spawnPulseFireballs(b, e)
                        end

                        -- Frostbite: icicles slow the enemy they hit
                        if b.kind == "icicle" then
                            e.slowTimer = FROST_SLOW_DURATION
                        end

                        damageEnemy(e_idx, getProjectileDamage(b), b.stat)
                        hit = true
                        break
                    end
                end
                if hit then
                    table.remove(bullets, b_idx)
                end
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
    love.graphics.setFont(menuFont)
    printShadowed("Press Enter to start", screenHeight - 70)
    printShadowed("Press T for tutorial", screenHeight - 35)
    love.graphics.setFont(defaultFont)
end

local function drawTutorial()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(background, 0, 0, 0,
        screenWidth / background:getWidth(),
        screenHeight / background:getHeight())
    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", 30, 20, screenWidth - 60, screenHeight - 40, 8, 8)

    local x, w = 55, screenWidth - 110
    local y = 25

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(menuFont)
    love.graphics.printf("TUTORIAL", 0, y, screenWidth, "center")
    y = y + 42
    love.graphics.setFont(tutorialFont)

    local function heading(text)
        love.graphics.setColor(0.6, 0.85, 1, 1)
        love.graphics.print(text, x, y)
        y = y + tutorialFont:getHeight() + 4
    end

    local function entry(name, desc)
        local _, lines = tutorialFont:getWrap(name .. ": " .. desc, w)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf({ { 1, 0.85, 0.4 }, name .. ": ", { 1, 1, 1 }, desc }, x, y, w, "left")
        y = y + tutorialFont:getHeight() * #lines + 4
    end

    heading("CONTROLS")
    entry("Move", "WASD or the arrow keys.")
    entry("Aim and attack", "Aim with the mouse. You attack automatically toward your cursor.")
    entry("Dash", "Space dashes toward your cursor, stopping there if it is close. It has a short cooldown.")
    entry("Pause", "Escape or E pauses the game and shows your stats and major upgrades.")
    entry("Dialogue", "Space or Enter continues. Up and Down to change selection.")

    y = y + 8
    heading("UPGRADES")
    entry("Experience bar", "The green bar at the bottom fills as you defeat enemies. When it fills, you gain a choice of 3 upgrades.")
    entry("Ascensions", "After defeating enough enemies, ascend - choosing between a Wizard and a Cybernetic upgrade that changes how you fight.")

    y = y + 8
    heading("STATS")
    entry("Health", "How much damage you can take. You lose when it reaches 0.")
    entry("Health regen", "Restore health every second.")
    entry("Speed", "How fast you move.")
    entry("Armor", "Flat damage removed from every hit you take, after applying damage reduction. Cannot reduce damage below 1.")
    entry("Damage reduction", "Percent of incoming damage ignored, before applying armor. Damage reduction cannot exceed 95%.")
    entry("Physical power", "The base damage of physical attacks, such as bullets and many other cybernetic weapons.")
    entry("Magic power", "The base damage of magic attacks, such as fireballs and many other wizard spells.")
    entry("Physical and magic multipliers", "A percent bonus applied to that type of power.")
    entry("Attack speed", "How fast you fire your basic attack.")
    entry("Cast speed", "How fast your timed spells recharge.")

    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf("Press Escape to return", 0, screenHeight - 40, screenWidth, "center")

    love.graphics.setFont(defaultFont)
    love.graphics.setColor(1, 1, 1, 1)
end

function drawPauseMenu()
    -- Dim the frozen game underneath
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)

    local boxW, boxH = 380, 560
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
        "    Damage reduction: " .. pct(getDamageReduction()),
        "",
        "Damage",     
        "    Physical power: " .. fmt(player.attackPower),
        "    Magic power: " .. fmt(player.magicPower),
        "    Physical multiplier: " .. pct(player.attackMult),
        "    Magic multiplier: " .. pct(player.magicMult),
        "    Attack speed: " .. pct(player.attackSpeed),
        "    Cast speed: " .. pct(player.castSpeed), 
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
    love.graphics.setFont(defaultFont)

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
    -- draw tutorial if in tutorial state
    if love.update == love.tutorial then
        drawTutorial()
        return
    end
 
    love.graphics.setColor(1, 1, 1, 1)
 
    cam:attach()
        gameMap:drawLayer(gameMap.layers["Ground"])
        gameMap:drawLayer(gameMap.layers["Trees"])
    cam:detach()

    -- Orbital Strike warning circles
    for _, s in ipairs(strikes) do
        if not s.landed then
            local p = s.timer / ORBITAL_FALL_TIME
            love.graphics.setColor(0, 0, 0, 0.25 + 0.3 * p)   -- gets darker as the strike nears
            love.graphics.circle("fill", s.x, s.y, ORBITAL_RADIUS)
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.circle("line", s.x, s.y, ORBITAL_RADIUS)
        end
    end
 
    -- Celestial Cloak damage radius
    if player.cloakActive then
        love.graphics.setColor(CLOAK_TINT[1], CLOAK_TINT[2], CLOAK_TINT[3], 0.15)
        love.graphics.circle("fill", player.x, player.y, CLOAK_RADIUS)
        love.graphics.setColor(CLOAK_TINT[1], CLOAK_TINT[2], CLOAK_TINT[3], 0.6)
        love.graphics.circle("line", player.x, player.y, CLOAK_RADIUS)
    end

    -- Draw player (light blue while the cloak is active, red flash on top when hit)
    local flash = player.hitFlashTimer / HIT_FLASH_TIME
    local tr, tg, tb = 1, 1, 1
    if player.cloakActive then tr, tg, tb = CLOAK_TINT[1], CLOAK_TINT[2], CLOAK_TINT[3] end
    love.graphics.setColor(tr, tg * (1 - 0.8 * flash), tb * (1 - 0.8 * flash), 1)
    local sprite = playerSprites[player.spriteKey]
    sprite.animation:draw(sprite.image, player.x, player.y, 0, 1.5, 1.5, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
 
    -- Arcane Orbit orbs (giant fireball sprite as a placeholder)
    if player.hasOrbit then
        love.graphics.setColor(1, 1, 1, 1)
        for _, orb in ipairs(getOrbPositions()) do
            giantFireballAnimation:draw(giantFireballImage, orb.x, orb.y, 0,
                ORBIT_SPRITE_SCALE, ORBIT_SPRITE_SCALE, giantFireballW / 2, giantFireballH / 2)
        end
    end

    -- Draw enemies (light blue while slowed, red flash on top when hit)
    for _, e in ipairs(enemies) do
        local flash = e.hitFlash / HIT_FLASH_TIME
        local r, g, b = 1, 1, 1
        if e.slowTimer > 0 then r, g, b = 0.35, 0.6, 1 end
        love.graphics.setColor(r, g * (1 - 0.8 * flash), b * (1 - 0.8 * flash), 1)
        e.animation:draw(cyborgImage, e.x, e.y, 0, 1.5, 1.5, 16, 16)
    end
    love.graphics.setColor(1, 1, 1, 1)
 
    -- Draw bullets (yellow)
    love.graphics.setColor(1, 1, 1, 1)
    for _, b in ipairs(bullets) do
        if b.kind == "bullet" then
            bulletAnimation:draw(bulletImage, b.x, b.y, b.angle, 1, 1, bulletW / 2, bulletH / 2)
        elseif b.kind == "giant_fireball" then
            giantFireballAnimation:draw(giantFireballImage, b.x, b.y, b.angle, GIANT_FIREBALL_SCALE, GIANT_FIREBALL_SCALE, giantFireballW / 2, giantFireballH / 2)
        elseif b.kind == "icicle" then
            love.graphics.setColor(0.35, 0.6, 1, 1)  -- light blue, so they read as ice
            giantFireballAnimation:draw(giantFireballImage, b.x, b.y, b.angle, ICICLE_SCALE, ICICLE_SCALE, giantFireballW / 2, giantFireballH / 2)
            love.graphics.setColor(1, 1, 1, 1)
        else
            fireballAnimation:draw(fireballImage, b.x, b.y, b.angle, 1, 1, fireballW / 2, fireballH / 2)
        end
    end

    -- Orbital Strike: falling sprite, then the blast flash
    for _, s in ipairs(strikes) do
        if s.landed then
            local a = s.blastTimer / ORBITAL_BLAST_TIME
            love.graphics.setColor(1, 0.7, 0.2, 0.6 * a)
            love.graphics.circle("fill", s.x, s.y, ORBITAL_RADIUS)
        else
            local p = s.timer / ORBITAL_FALL_TIME
            local startY = -bigHurtyW * ORBITAL_SPRITE_SCALE   -- once rotated, its width is the vertical length
            local y = startY + (s.y - startY) * p * p
            love.graphics.setColor(1, 1, 1, 1)
            bigHurtyAnimation:draw(bigHurtyImage, s.x, y, math.pi / 2, ORBITAL_SPRITE_SCALE, ORBITAL_SPRITE_SCALE, bigHurtyW / 2, bigHurtyH / 2)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)

    -- Floating damage numbers (blue for magic, red for physical)
    love.graphics.setFont(damageFont)
    for _, n in ipairs(damageNumbers) do
        local alpha = 1 - (n.timer / DAMAGE_NUMBER_TIME)
        local c = (n.stat == "magic") and MAGIC_NUMBER_COLOR or PHYSICAL_NUMBER_COLOR
        love.graphics.setColor(0, 0, 0, alpha * 0.8)              -- shadow, so the number reads on any background
        love.graphics.print(n.text, n.x + 1, n.y + 1)
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        love.graphics.print(n.text, n.x, n.y)
    end
    love.graphics.setFont(defaultFont)
    love.graphics.setColor(1, 1, 1, 1)
 
    -- Draw UI/text (black)
    love.graphics.setFont(hudFont)
    love.graphics.setColor(0, 0, 0)
    love.graphics.print("HP: " .. math.floor(math.max(0, player.hp)) .. " / " .. fmt(player.maxHp), 10, 10)
    love.graphics.print("Kills: " .. score, 10, 42)
    love.graphics.setFont(defaultFont)

    -- Experience bar along the bottom of the screen (fills toward the next minor upgrade)
    do
        local barX, barH = 10, 18
        local barW = screenWidth - 20
        local barY = screenHeight - barH - 10

        local from = player.barStart
        local to = player.nextUpgradeScore
        local frac = (to > from) and math.max(0, math.min(1, (score - from) / (to - from))) or 0

        love.graphics.setColor(0, 0, 0, 0.6)                  -- background
        love.graphics.rectangle("fill", barX, barY, barW, barH, 4, 4)
        love.graphics.setColor(0.3, 0.85, 0.35, 1)            -- green fill
        love.graphics.rectangle("fill", barX, barY, barW * frac, barH, 4, 4)
        love.graphics.setColor(1, 1, 1, 0.8)                  -- outline
        love.graphics.rectangle("line", barX, barY, barW, barH, 4, 4)
    end
    love.graphics.setColor(1, 1, 1, 1)
 
    -- Dialogue UI is drawn last so it sits on top of everything
    love.graphics.setColor(1, 1, 1, 1)
    narrator:draw()

    --Draw pause menu if game is paused
    if love.update == love.paused then
        drawPauseMenu()
    end
end
 