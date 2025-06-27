Modules = {
    sfx = "sfx",
    controls = "controls",
    ease = "ease",
    ui = "uikit",
    webquad = "github.com/aduermael/modzh/webquad:7fbc37d",
}
    
Config.Items = {
    --grass = "s12.grass_cubzh",
}

--Dev.DisplayColliders = true

-- CONSTANTS
local JUMP_STRENGTH = 100
local SCORE_PER_SECOND = 100
local ANIMATION_SPEED = 1.5
local NORMAL_GAME_SPEED = 80
local SLOW_DOWN_MULTIPLIER = 0.65
local SLOW_DOWN_DURATION = 3.0
local LANE_WIDTH = 30
local BUILDING_FAR = 700
local DIFFICULTY_INCREASE_RATE = 0.02  -- How fast difficulty increases per second
local MAX_DIFFICULTY_MULTIPLIER = 2.5  -- Maximum difficulty multiplier
local SWIPE_THRESHOLD = 10  -- Minimum distance for swipe detection
local GROUND_OFFSET = 0.1  -- Height offset for obstacles above ground
local WALL_SPACING = 50  -- Distance between walls in a train
local SPAWN_DISTANCE = 200  -- Distance ahead of current progress to spawn obstacles
local MAX_SPAWN_DISTANCE = 400  -- Maximum distance to spawn obstacles ahead
local SPAWN_SPACING = 50  -- Spacing between spawn attempts
local MAX_SPAWNS_PER_FRAME = 10  -- Maximum obstacles to spawn per frame
local CLEANUP_DISTANCE = 200  -- Distance behind player to clean up obstacles
local STAIRS_BOOST_MULTIPLIER = 1.5  -- Multiplier for stairs boost
local GROUND_MOTION_MULTIPLIER = 0.015  -- Multiplier for ground motion speed
local LANE_MOVEMENT_SPEED = 1000  -- Speed multiplier for lane movement
local LANE_MOVEMENT_THRESHOLD = 0.01  -- Threshold for lane movement completion
local STATES = {
    LOADING = 1,
    MENU = 2,
    READY = 3,  -- New state: waiting for player input to start
    RUNNING = 4,
    GAME_OVER = 5,
}

-- COLLISION GROUPS
local COLLISION_GROUPS = {
    GROUND = CollisionGroups(1),
    MOTION = CollisionGroups(2), -- for all objects in motion
    COLLIDERS = CollisionGroups(3),
    COLLECTIBLES = CollisionGroups(4),
    PLAYER = CollisionGroups(5),
}

-- Lane-based obstacle spawning system
local laneTrackers = {
    left = { lastSpawnZ = 0, minDistance = 100, wallTrainCount = 0, stairsSpawned = false },   -- Left lane (-1)
    center = { lastSpawnZ = 0, minDistance = 100, wallTrainCount = 0, stairsSpawned = false }, -- Center lane (0)
    right = { lastSpawnZ = 0, minDistance = 100, wallTrainCount = 0, stairsSpawned = false }   -- Right lane (1)
}

-- Obstacle spawning probabilities and types
local obstacleTypes = {
    { type = "log", probability = 0.4, minDistance = 80 },
    { type = "wall", probability = 0.25, minDistance = 120, trainLength = {1, 5} },
    { type = "flag", probability = 0.2, minDistance = 100 },
    --{ type = "stairs", probability = 0.15, minDistance = 120 }
}

-- obstacle parts
local wallPart
local flagPart
local logPart
local stairsPart

-- Simple segment manager
local segments = {}           -- Active segments

-- GAME STATE VARIABLES
local downPos
local isMoving = false
local targetLane = 0
local targetPosition = nil
local swipeTriggered = false
local currentLane = 0
local obstaclesByRef = {}
local gameSpeed = 80
local isGameOver = false
local lanePositions = {Number3(-30, 0, 0), Number3(0, 0, 0), Number3(30, 0, 0)} -- left, center, right
local isSlowDownActive = false
local slowDownTimer = 0
local score = 0
local gameProgress = 0  -- Track game progress for spawning
local difficultyMultiplier = 1.0  -- Current difficulty multiplier
local gameTime = 0  -- Total time the game has been running
local isCrouching = false
local crouchTimer = 0
local CROUCH_DURATION = 1.0  -- How long to stay crouched
local NORMAL_SCALE = 0.5  -- The player's normal scale
local CROUCH_SCALE = 0.25  -- How much to scale down when crouching (50% of normal size)
local wantsToCrouch = false  -- Track if player wants to crouch while in air
local scoreText = nil
local scoreValueText = nil
local highScoreText = nil
local highScoreValueText = nil
local newHighScoreText = nil
local newHighScorePanel = nil
local restartText = nil
local currentState = STATES.LOADING
local assetsLoaded = 0
local totalAssets = 4  -- log, wall, flag, stairs

-- UI STYLING CONSTANTS
local UI_COLORS = {
    primary = Color(255, 255, 255),      -- White
    secondary = Color(200, 200, 200),    -- Light gray
    accent = Color(255, 215, 0),         -- Gold
    background = Color(0, 0, 0, 0.8),   -- Semi-transparent black
    border = Color(255, 255, 255, 0.4),  -- Semi-transparent white
    shadow = Color(0, 0, 0, 0.3)        -- Shadow color
}

local UI_POSITIONS = {
    scorePanel = {x = 20, y = 20},
    highScorePanel = {x = 20, y = 80}
}

-- UI Helper Functions
local function createStyledText(text, fontSize, color, isBold)
    local textObj = ui:createText(text)
    textObj.FontSize = fontSize or 16
    textObj.Color = color or UI_COLORS.primary
    if isBold then
        textObj.Font = "Bold"
    end
    return textObj
end

local function createScorePanel()
    -- Score Panel Background
    local scorePanel = ui:createFrame()
    scorePanel.Size = {200, 65}
    scorePanel.Color = UI_COLORS.background
    scorePanel.BorderRadius = 12
    scorePanel.BorderColor = UI_COLORS.border
    scorePanel.BorderWidth = 2
    
    -- Score Label
    scoreText = createStyledText("SCORE", 12, UI_COLORS.secondary, true)
    scoreText.parentDidResize = function()
        scoreText.pos = {UI_POSITIONS.scorePanel.x + 15, UI_POSITIONS.scorePanel.y + 40}
    end
    
    -- Score Value
    scoreValueText = createStyledText("0", 24, UI_COLORS.primary, true)
    scoreValueText.parentDidResize = function()
        scoreValueText.pos = {UI_POSITIONS.scorePanel.x + 15, UI_POSITIONS.scorePanel.y + 10}
    end
    
    -- Position panel background
    scorePanel.parentDidResize = function()
        scorePanel.pos = {UI_POSITIONS.scorePanel.x, UI_POSITIONS.scorePanel.y}
    end
    
    scorePanel:parentDidResize()
    scoreText:parentDidResize()
    scoreValueText:parentDidResize()
end

local function createHighScorePanel()
    -- High Score Panel Background
    local highScorePanel = ui:createFrame()
    highScorePanel.Size = {200, 65}
    highScorePanel.Color = UI_COLORS.background
    highScorePanel.BorderRadius = 12
    highScorePanel.BorderColor = UI_COLORS.border
    highScorePanel.BorderWidth = 2
    
    -- High Score Label
    highScoreText = createStyledText("BEST", 12, UI_COLORS.secondary, true)
    highScoreText.parentDidResize = function()
        highScoreText.pos = {UI_POSITIONS.highScorePanel.x + 15, UI_POSITIONS.highScorePanel.y + 40}
    end
    
    -- High Score Value
    highScoreValueText = createStyledText("0", 24, UI_COLORS.accent, true)
    highScoreValueText.parentDidResize = function()
        highScoreValueText.pos = {UI_POSITIONS.highScorePanel.x + 15, UI_POSITIONS.highScorePanel.y + 10}
    end
    
    -- Position panel background
    highScorePanel.parentDidResize = function()
        highScorePanel.pos = {UI_POSITIONS.highScorePanel.x, UI_POSITIONS.highScorePanel.y}
    end
    
    highScorePanel:parentDidResize()
    highScoreText:parentDidResize()
    highScoreValueText:parentDidResize()
end

local function createRestartText()
    restartText = createStyledText("", 20, UI_COLORS.primary, true)
    restartText.parentDidResize = function()
        restartText.pos = { Screen.Width / 2 - restartText.Width / 2, Screen.Height / 2 - restartText.Height / 2}
    end
    restartText:parentDidResize()
end

local function createNewHighScoreText()
    -- New High Score Background Panel
    newHighScorePanel = ui:createFrame()
    newHighScorePanel.Size = {400, 60}
    newHighScorePanel.Color = Color(0, 0, 0, 0)  -- Start transparent
    newHighScorePanel.BorderRadius = 12
    newHighScorePanel.BorderColor = UI_COLORS.accent
    newHighScorePanel.BorderWidth = 3
    
    newHighScoreText = createStyledText("", 32, UI_COLORS.accent, true)
    newHighScoreText.parentDidResize = function()
        newHighScoreText.pos = { Screen.Width / 2 - newHighScoreText.Width / 2, Screen.Height * 0.666 - newHighScoreText.Height / 2}
    end
    
    -- Position background panel
    newHighScorePanel.parentDidResize = function()
        newHighScorePanel.pos = { Screen.Width / 2 - newHighScorePanel.Size.Width / 2, Screen.Height * 0.666 - newHighScorePanel.Size.Height / 2}
    end
    
    newHighScorePanel:parentDidResize()
    newHighScoreText:parentDidResize()
    newHighScoreText.Text = ""  -- Start hidden
end

local function updateScoreDisplay(newScore)
    if scoreValueText then
        scoreValueText.Text = string.format("%.0f", newScore)
    end
end

local function updateHighScoreDisplay(newHighScore)
    if highScoreValueText then
        highScoreValueText.Text = string.format("%.0f", newHighScore)
    end
end

-- ============================================================================
-- GAME STATE MANAGEMENT FUNCTIONS
-- ============================================================================

function dropPlayer()
    Player.Position:Set(0, 40, 0)
    Player.Rotation:Set(0, 0, 0)
    Player.Velocity:Set(0, 0, 0)
    
    -- Clear segments using the new system
    clearSegments()
    
    -- Reset game state
    targetLane = 0
    currentLane = 0
    isGameOver = false
    isSlowDownActive = false
    slowDownTimer = 0
    gameSpeed = NORMAL_GAME_SPEED
    gameProgress = 0  -- Reset game progress
    difficultyMultiplier = 1.0  -- Reset difficulty
    gameTime = 0  -- Reset game time
    isCrouching = false  -- Reset crouch state
    crouchTimer = 0
    wantsToCrouch = false  -- Reset air crouch state
    Player.Scale.Y = NORMAL_SCALE  -- Reset player scale
    Player.Animations.Walk.Speed = ANIMATION_SPEED
    Player.Animations.Walk:Stop()
    Player.Motion.Y = 0
    score = 0
    currentState = STATES.READY  -- Start in READY state instead of RUNNING

    -- Update UI displays
    updateScoreDisplay(score)
    
    -- Hide new high score text
    if newHighScoreText then
        newHighScoreText.Text = ""
    end
    if newHighScorePanel then
        newHighScorePanel.Color = Color(0, 0, 0, 0)  -- Make transparent
    end
    
    -- Hide restart text and show start instruction
    if restartText then
        restartText.Text = "Press W or swipe to start"
        restartText.parentDidResize()
    end
end

function gameOver()
    leaderboard:set({score = score, callback = function() 
        loadHighScore()
    end})
    isGameOver = true
    print("Game Over")
    currentState = STATES.GAME_OVER
    Player.Animations.Walk:Stop()
    clearSegments()
    
    -- Check if this is a new high score
    local currentHighScore = tonumber(highScoreValueText.Text) or 0
    if score > currentHighScore then
        if newHighScoreText and newHighScorePanel then
            newHighScoreText.Text = "NEW HIGH SCORE: " .. string.format("%.0f", score)
            newHighScoreText.parentDidResize()
            newHighScorePanel.Color = UI_COLORS.background
        end
    end
    
    -- Show restart instruction
    if restartText then
        restartText.Text = "Tap to restart"
        restartText.parentDidResize()
    end
end

function restartGame()
    print("Restarting game...")
    currentState = STATES.RUNNING
    isGameOver = false
    
    -- Hide restart instruction
    if restartText then
        restartText.Text = ""
    end
    
    -- Call dropPlayer to reset everything
    dropPlayer()
end

function startGame()
    print("Starting game...")
    currentState = STATES.RUNNING
    
    -- Start player animation
    Player.Animations.Walk:Play()
    
    -- Start motion on all existing obstacles
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            obstacle.Motion.Z = -gameSpeed
        end
    end
    
    -- Hide start instruction
    if restartText then
        restartText.Text = ""
    end
end

-- ============================================================================
-- PLAYER MOVEMENT AND CONTROLS
-- ============================================================================

function startCrouch()
    if not isCrouching then
        if Player.IsOnGround then
            -- Player is on ground, crouch immediately
            isCrouching = true
            crouchTimer = CROUCH_DURATION
            Player.Scale.Y = CROUCH_SCALE  -- Shrink to 0.25
        else
            -- Player is in air, mark that they want to crouch when they land
            wantsToCrouch = true
        end
    end
end

function cancelCrouch()
    if isCrouching then
        isCrouching = false
        crouchTimer = 0
        Player.Scale.Y = NORMAL_SCALE  -- Return to normal size
    end
    wantsToCrouch = false  -- Also cancel any pending air crouch
end

function updateCrouch(dt)
    -- Check if player wanted to crouch and just landed
    if wantsToCrouch and Player.IsOnGround then
        wantsToCrouch = false
        isCrouching = true
        crouchTimer = CROUCH_DURATION
        Player.Scale.Y = CROUCH_SCALE  -- Apply crouch scale now that they're on ground
    end
    
    if isCrouching then
        crouchTimer = crouchTimer - dt
        if crouchTimer <= 0 then
            isCrouching = false
            Player.Scale.Y = NORMAL_SCALE  -- Return to normal size
        end
    end
end

if Client.IsMobile then
    Client.DirectionalPad = nil
    Client.Action1 = nil
else
    Client.DirectionalPad = function(x, y)
        if currentState == STATES.GAME_OVER then
            restartGame()
            return
        end
        
        if currentState == STATES.MENU then
            -- Transition from MENU to READY
            currentState = STATES.READY
            if restartText then
                restartText.Text = "Press W or swipe to start"
                restartText.parentDidResize()
            end
            return
        end
        
        if currentState == STATES.READY then
            startGame()
            return
        end
        
        if x == 1 then
            targetLane += 1
            isMoving = true
        elseif x == -1 then
            targetLane -= 1
            isMoving = true
        end
        if y == 1 then
            if Player.IsOnGround then
                cancelCrouch()  -- Cancel crouch when jumping
                Player.Velocity.Y = JUMP_STRENGTH
            end
        elseif y == -1 then
            if not Player.IsOnGround then
                Player.Velocity.Y = -JUMP_STRENGTH  -- Fall faster
                startCrouch()  -- Mark that player wants to crouch when landing
            else
                startCrouch()
            end
        end
    end
end

Pointer.Down = function(pe)
    downPos = Number2(pe.X, pe.Y) * Screen.Size
end

Pointer.Up = function(pe)
    swipeTriggered = false
end

Pointer.Cancel = function(pe)
    swipeTriggered = false
end

function updateScore(dt)
    score = score + (SCORE_PER_SECOND * dt)
end

-- Called when Pointer is "shown" (Pointer.IsHidden == false), which is the case by default.
Pointer.Drag = function(pe)
    if currentState == STATES.GAME_OVER then
        restartGame()
        return
    end
    
    if currentState == STATES.MENU then
        -- Transition from MENU to READY
        currentState = STATES.READY
        if restartText then
            restartText.Text = "Swipe or jump to start"
            restartText.parentDidResize()
        end
        return
    end

    if currentState == STATES.READY then
        startGame()
        return
    end
    
    local pos = Number2(pe.X, pe.Y) * Screen.Size
    local Xdiff = pos.X - downPos.X
    local Ydiff = pos.Y - downPos.Y

    if swipeTriggered == false then
        -- Swipe Right
        if Xdiff > SWIPE_THRESHOLD and currentLane <= 0 then
            swipeTriggered = true
            targetLane += 1
            isMoving = true
        elseif Xdiff < -SWIPE_THRESHOLD and currentLane >= 0 then
            swipeTriggered = true
            targetLane -= 1
            isMoving = true
        elseif Ydiff > SWIPE_THRESHOLD then
            swipeTriggered = true
            if Player.IsOnGround then
                cancelCrouch()  -- Cancel crouch when jumping
                Player.Velocity.Y = JUMP_STRENGTH
            end
        elseif Ydiff < -SWIPE_THRESHOLD then
            swipeTriggered = true
            if not Player.IsOnGround then
                Player.Velocity.Y = -JUMP_STRENGTH  -- Fall faster
                startCrouch()  -- Mark that player wants to crouch when landing
            else
                startCrouch()
            end
        end
    end
 end

Client.OnWorldObjectLoad = function(o)
    if o.Name == "ground" then
        o.IsHidden = true
        -- print("ground height: " .. o.Position.Y)
        -- print(o.Height)
        -- print("pivot: " .. o.Pivot.Y)
        groundLevel = o.Position.Y + o.Height * o.Scale.Y
        o.CollisionGroups = COLLISION_GROUPS.GROUND
        o.CollidesWithGroups = COLLISION_GROUPS.PLAYER 
    end
end

-- function executed when the game starts
Client.OnStart = function()
    Player.CollisionGroups = COLLISION_GROUPS.PLAYER
    Player.CollidesWithGroups = COLLISION_GROUPS.GROUND + COLLISION_GROUPS.COLLIDERS

    -- skybox
    HTTP:Get("https://files.blip.game/skyboxes/sunny-sky-with-clouds.ktx", function(response)
        if response.StatusCode == 200 then
            Sky.Image = response.Body
            Sky.SkyColor = Color.White
            Sky.HorizonColor = Color.White
            Sky.AbyssColor = Color.White
        end
    end)
    -- Collision Groups
    -- Leaderboard
    leaderboard = Leaderboard("default")

    -- ground texture
    groundImage = webquad:create({
        color = Color.White,
        url = "https://files.cu.bzh/textures/asphalt.png",
    })
    local tiling = BUILDING_FAR / 32
    groundImage.Width = BUILDING_FAR * 2
    groundImage.Height = BUILDING_FAR * 2
    groundImage.Tiling = { tiling, tiling }
    groundImage.Anchor = { 0.5, 0.5 }
    groundImage.IsDoubleSided = false
    groundImage.Position.Y = groundLevel
    World:AddChild(groundImage)
    groundImage.Rotation = { math.pi * 0.5, 0, 0 }

    -- yellow lines (placeoholder for lanes)
    yellowLineLeft = webquad:create({
        color = Color.White,
        url = "https://files.cu.bzh/textures/asphalt-yellow-lines.png",
    })
    yellowLineLeft.Width = 3
    yellowLineLeft.Height = BUILDING_FAR * 2
    yellowLineLeft.Tiling = { 1, tiling }
    yellowLineLeft.Anchor = { 0.5, 0.5 }
    yellowLineLeft.IsDoubleSided = false
    yellowLineLeft.Position = groundImage.Position + { -LANE_WIDTH, 0.1, 0 }
    World:AddChild(yellowLineLeft)
    yellowLineLeft.Rotation = { math.pi * 0.5, 0, 0 }

    yellowLineMiddle = webquad:create({
        color = Color.White,
        url = "https://files.cu.bzh/textures/asphalt-yellow-lines.png",
    })
    yellowLineMiddle.Width = 3
    yellowLineMiddle.Height = BUILDING_FAR * 2
    yellowLineMiddle.Tiling = { 1, tiling }
    yellowLineMiddle.Anchor = { 0.5, 0.5 }
    yellowLineMiddle.IsDoubleSided = false
    yellowLineMiddle.Position = groundImage.Position + { 0, 0.1, 0 }
    World:AddChild(yellowLineMiddle)
    yellowLineMiddle.Rotation = { math.pi * 0.5, 0, 0 }

    yellowLineRight = webquad:create({
        color = Color.White,
        url = "https://files.cu.bzh/textures/asphalt-yellow-lines.png",
    })
    yellowLineRight.Width = 3
    yellowLineRight.Height = BUILDING_FAR * 2
    yellowLineRight.Tiling = { 1, tiling }
    yellowLineRight.Anchor = { 0.5, 0.5 }
    yellowLineRight.IsDoubleSided = false
    yellowLineRight.Position = groundImage.Position + { LANE_WIDTH, 0.1, 0 }
    World:AddChild(yellowLineRight)
    yellowLineRight.Rotation = { math.pi * 0.5, 0, 0 }

    local function wrapMesh(mesh, scale, type)
        local wrapper = Object()
        wrapper:AddChild(mesh)
        wrapper.Physics = PhysicsMode.Dynamic
        mesh.Physics = PhysicsMode.Disabled
        mesh.Scale = scale

        if type == "log" then
            -- set scale and rotation
            local fixedRotation = Number3(0, math.rad(90), 0)
            scale:Rotate(fixedRotation)
            mesh.LocalRotation = fixedRotation
            mesh.Scale = scale
            local box = Box()
            box:Fit(wrapper, { recurse = true, localBox = true})
            wrapper.CollisionBox = box
            wrapper.CollisionGroups = COLLISION_GROUPS.COLLIDERS + COLLISION_GROUPS.MOTION
            wrapper.CollidesWithGroups = COLLISION_GROUPS.PLAYER
        elseif type == "wall" then
            -- set scale and rotation
            local fixedRotation = Number3(math.rad(90), 0, 0)
            scale:Rotate(fixedRotation)
            mesh.LocalRotation = fixedRotation
            mesh.Scale = scale

            -- set collision box and groups
            local box = Box()
            box:Fit(wrapper, { recurse = true, localBox = true})
            box.Max += Number3(5, -4, 0)
            box.Min -= Number3(5, 0, 0)
            wrapper.CollisionBox = box
            wrapper.CollisionGroups = COLLISION_GROUPS.COLLIDERS + COLLISION_GROUPS.MOTION
            wrapper.CollidesWithGroups = COLLISION_GROUPS.PLAYER
        elseif type == "flag" then
            -- set scale and rotation
            local fixedRotation = Number3(0, math.rad(90), 0)
            scale:Rotate(fixedRotation)
            mesh.LocalRotation = fixedRotation
            mesh.Scale = scale

            -- set collision box and groups
            local box = Box()
            box:Fit(wrapper, { recurse = true, localBox = true})
            box.Min += Number3(0, 10, 0)
            wrapper.CollisionBox = box
            wrapper.CollisionGroups = COLLISION_GROUPS.MOTION
            wrapper.CollidesWithGroups = COLLISION_GROUPS.PLAYER

        elseif type == "stairs" then
            -- set scale and rotation
            local fixedRotation = Number3(0, 0, 0)
            scale:Rotate(fixedRotation)
            mesh.LocalRotation = fixedRotation
            mesh.Scale = scale

            -- set collision box and groups - make it a trigger for boost
            local box = Box()
            box:Fit(wrapper, { recurse = true, localBox = true})
            wrapper.CollisionBox = box
            wrapper.CollisionGroups = COLLISION_GROUPS.MOTION
            wrapper.CollidesWithGroups = nil

            -- Create a trigger for player interaction
            local trigger = Object()
            trigger.Physics = PhysicsMode.Trigger
            local triggerBox = Box()
            triggerBox:Fit(wrapper, { recurse = true, localBox = true})
            triggerBox.Min.Y = triggerBox.Min.Y + 5  -- Start trigger a bit above ground
            trigger.CollisionBox = triggerBox
            wrapper:AddChild(trigger)
            trigger.CollisionGroups = nil
            trigger.CollidesWithGroups = COLLISION_GROUPS.PLAYER
        end
        return wrapper
    end

    -- load log asset
    HTTP:Get("https://files.blip.game/gltf/kenney/tree-log.glb", function(response)
        if response.StatusCode == 200 then
            local req = Object:Load(response.Body, function(o)
                logPart = wrapMesh(o, Number3(30, 40, 40), "log")
                print("Log part loaded.")
                assetsLoaded = assetsLoaded + 1
                if assetsLoaded == totalAssets then
                    currentState = STATES.MENU
                end
            end)
        end
    end)
    -- load wall asset
    HTTP:Get("https://files.blip.game/gltf/kenney/castle-wall-4.glb", function(response)
        if response.StatusCode == 200 then
            local req = Object:Load(response.Body, function(o)
                wallPart = wrapMesh(o, Number3(20, 30, 50), "wall")
                print("Wall part loaded.")
                assetsLoaded = assetsLoaded + 1
                if assetsLoaded == totalAssets then
                    currentState = STATES.MENU
                end
            end)
        end
    end)

    -- load flag asset
    HTTP:Get("https://files.blip.game/gltf/kenney/flag-wide.glb", function(response)
        if response.StatusCode == 200 then
            local req = Object:Load(response.Body, function(o)
                flagPart = wrapMesh(o, Number3(35, 35, 30), "flag")
                print("Flag part loaded.")
                assetsLoaded = assetsLoaded + 1
                if assetsLoaded == totalAssets then
                    currentState = STATES.MENU
                end
            end)
        end
    end)

    -- load stairs asset
    HTTP:Get("https://files.blip.game/gltf/kenney/stairs.glb", function(response)
        if response.StatusCode == 200 then
            local req = Object:Load(response.Body, function(o)
                stairsPart = wrapMesh(o, Number3(100, 60, 30), "stairs")
                print("Stairs part loaded.")
                assetsLoaded = assetsLoaded + 1
                if assetsLoaded == totalAssets then
                    currentState = STATES.MENU
                end
            end)
        else
            print("Failed to load stairs asset, status: " .. response.StatusCode)
            -- Continue without stairs if loading fails
            assetsLoaded = assetsLoaded + 1
            if assetsLoaded == totalAssets then
                currentState = STATES.MENU
            end
        end
    end)

    -- Create modern UI panels
    createScorePanel()
    createHighScorePanel()
    createRestartText()
    createNewHighScoreText()
    
    -- Load high score with callback
    function loadHighScore()
        leaderboard:get({
            mode = "best",
            friends = true,
            limit = 10,
            callback = function(scores, err)
                if err == nil and scores then
                    local playerHighScore = 0
                    -- Loop through scores to find the current player's score
                    for _, scoreData in ipairs(scores) do
                        if scoreData.userID == Player.UserID then
                            playerHighScore = scoreData.score or 0
                            break
                        end
                    end
                    updateHighScoreDisplay(playerHighScore)
                    -- print("Player's high score: " .. playerHighScore)
                else
                    updateHighScoreDisplay(0)
                    -- print("No high score data available")
                end
            end
        })
    end
    
    -- Load the high score initially
    loadHighScore()

    Player.Animations.Walk.Speed = ANIMATION_SPEED
    Player.Animations.Walk:Play()
    -- print("Initial Player.Scale.Y:", Player.Scale.Y)
    Player.Scale.Y = NORMAL_SCALE  -- Ensure player starts at normal scale
    World:AddChild(Player)
    dropPlayer()

    Camera.Behavior = {
        positionTarget = Player, -- camera goes to that position (or position of given object)
        positionTargetOffset = { 0, 25, 0 }, -- applying offset to the target position (increased Y offset)
        positionTargetBackoffDistance = 60, -- camera then tries to backoff that distance, considering collision (increased from 40)
        positionTargetMinBackoffDistance = 30, -- minimum backoff distance (increased from 20)
        positionTargetMaxBackoffDistance = 120, -- maximum backoff distance (increased from 100)
        rotationTarget = Player.Head, -- camera rotates to that rotation (or rotation of given object)
        rigidity = 0.3, -- how fast the camera moves to the target (reduced for smoother movement)
        collidesWithGroups = nil, -- camera will not go through objects in these groups
    }

    Player.OnCollisionBegin = function(self, other, normal)
        -- ignore collisions with the ground
        
        if other.Physics == PhysicsMode.Trigger or other.Physics == PhysicsMode.Static then
            if other.Parent ~= nil then
                -- Check if this is a stairs trigger
                local parent = other.Parent
                if obstaclesByRef[parent] == "stairs" then
                    -- Give the player a boost up and forward
                    Player.Motion.Y = gameSpeed * STAIRS_BOOST_MULTIPLIER  -- Upward boost
                    return
                end
                other = parent
            end
        end

        if not obstaclesByRef[other] then
            return
        end
        
        local obstacleType = obstaclesByRef[other]
        
        -- For all obstacles, use the original logic
        if isSlowDownActive and normal.Y == 0 or normal.Z < 0 then
            gameOver()
            return
        end
        -- hit block from the right
        if normal.Y == 0 then
            if normal.X < 0 then
                targetLane -= 1  
            -- hit block from the left
            elseif normal.X > 0 then
                targetLane += 1  
            end
            isSlowDownActive = true
            slowDownTimer = SLOW_DOWN_DURATION
        end
    end

    Player.OnCollisionEnd = function(self, other, normal)
        if other.Physics == PhysicsMode.Trigger or other.Physics == PhysicsMode.Static then
            if other.Parent ~= nil then
                -- Check if this is a stairs trigger
                local parent = other.Parent
                if obstaclesByRef[parent] == "stairs" then
                    Player.Motion.Y = 0
                    return
                end
                other = parent
            end
        end
    end
end

function updateSegments(gameProgress)
    -- Don't spawn obstacles if assets aren't loaded yet
    if logPart == nil or wallPart == nil or flagPart == nil or stairsPart == nil then
        return
    end
    
    -- Reset lane trackers if lastSpawnZ is too far behind the current progress
    for _, tracker in pairs(laneTrackers) do
        if gameProgress - tracker.lastSpawnZ > MAX_SPAWN_DISTANCE then
            tracker.lastSpawnZ = gameProgress - MAX_SPAWN_DISTANCE + tracker.minDistance
        end
    end
    
    -- Check if we need to spawn new obstacles
    local currentSpawnZ = gameProgress + SPAWN_DISTANCE
    local spawnCount = 0  -- Limit spawning to prevent memory issues
    
    while currentSpawnZ < gameProgress + MAX_SPAWN_DISTANCE and spawnCount < MAX_SPAWNS_PER_FRAME do
        local newObstacles = spawnObstaclesAtPosition(currentSpawnZ)
        
        if newObstacles and #newObstacles > 0 then
            -- Create a segment entry for tracking
            local segment = {
                zPosition = currentSpawnZ,
                obstacles = newObstacles
            }
            table.insert(segments, segment)
            spawnCount = spawnCount + #newObstacles
        end
        
        currentSpawnZ = currentSpawnZ + SPAWN_SPACING  -- Increased spacing to reduce spawn frequency
    end

    -- Remove old segments whose obstacles are all behind the player
    for i = #segments, 1, -1 do
        local segment = segments[i]
        local allBehind = true
        for _, obstacle in ipairs(segment.obstacles) do
            if obstacle.Position.Z >= Player.Position.Z - 50 then
                allBehind = false
                break
            end
        end
        if allBehind then
            for _, obstacle in ipairs(segment.obstacles) do
                if obstacle and obstacle.Parent then  -- Check if obstacle still exists
                    World:RemoveChild(obstacle)
                    obstaclesByRef[obstacle] = nil
                end
            end
            table.remove(segments, i)
        end
    end
    
    -- Additional cleanup: remove any obstacles that are too far behind
    for obstacle, _ in pairs(obstaclesByRef) do
        if obstacle and obstacle.Parent and obstacle.Position.Z < Player.Position.Z - CLEANUP_DISTANCE then
            World:RemoveChild(obstacle)
            obstaclesByRef[obstacle] = nil
        end
    end
end

function wouldCreateImpossibleSegment(lane, obstacleType, zPosition)
    -- If this isn't a wall, it won't create an impossible segment
    if obstacleType ~= "wall" then
        return false
    end
    
    -- Check if there are wall trains in other lanes that would overlap with this position
    local wallsInOtherLanes = 0
    for checkLane = -1, 1 do
        if checkLane ~= lane then
            local tracker = getLaneTracker(checkLane)
            if tracker and tracker.wallTrainCount > 0 then
                -- This lane is in a wall train, check if it overlaps with our target position
                -- Wall trains span multiple Z positions, so we need to check the range
                local wallTrainStartZ = tracker.lastSpawnZ - ((tracker.wallTrainCount - 1) * WALL_SPACING)
                local wallTrainEndZ = tracker.lastSpawnZ
                
                -- Check if our target position overlaps with this wall train
                if zPosition >= wallTrainStartZ and zPosition <= wallTrainEndZ then
                    wallsInOtherLanes = wallsInOtherLanes + 1
                end
            end
        end
    end
    
    -- Also check existing obstacles in the world for walls at this Z position
    for obstacle, obstacleType in pairs(obstaclesByRef) do
        if obstacleType == "wall" and obstacle.Parent then
            local obstacleLane = math.round(obstacle.Position.X / LANE_WIDTH)
            if obstacleLane ~= lane then
                -- Check if this wall is at or near our target Z position
                local distance = math.abs(obstacle.Position.Z - zPosition)
                if distance <= WALL_SPACING then
                    wallsInOtherLanes = wallsInOtherLanes + 1
                end
            end
        end
    end
    
    -- If there are already walls in both other lanes at this Z position, adding a wall here would block all lanes
    return wallsInOtherLanes >= 2
end

function spawnObstaclesAtPosition(zPosition)
    local spawnedObstacles = {}
    
    -- Check each lane for spawning
    for lane = -1, 1 do
        local tracker = getLaneTracker(lane)
        if tracker and canSpawnInLane(lane, zPosition) then
            local obstacleData = selectObstacleType()
            
            -- Check if spawning this obstacle would create an impossible segment
            if wouldCreateImpossibleSegment(lane, obstacleData.type, zPosition) then
                return
            end
            
            -- If it's a wall, start a wall train
            if obstacleData.type == "wall" and obstacleData.trainLength then
                    local trainLength = math.random(obstacleData.trainLength[1], obstacleData.trainLength[2])
                    tracker.wallTrainCount = trainLength
                    tracker.stairsSpawned = false
                    
                    -- 50% chance to spawn stairs at the start of the wall train
                    if math.random() <= 0.5 then
                        local stairsObstacle = spawnObstacle("stairs", lane, zPosition)
                        if stairsObstacle then
                            table.insert(spawnedObstacles, stairsObstacle)
                            tracker.stairsSpawned = true
                        end
                    end
                    
                    -- Spawn all walls in the train at once with Z offsets
                    for i = 1, trainLength do
                        local wallZ = zPosition + (i * WALL_SPACING)
                        local wallObstacle = spawnObstacle("wall", lane, wallZ)
                        if wallObstacle then
                            table.insert(spawnedObstacles, wallObstacle)
                        end
                    end
                    
                    -- Update the lane tracker - mark that this wall train is complete
                    tracker.lastSpawnZ = zPosition + ((trainLength - 1) * WALL_SPACING)
                    tracker.minDistance = obstacleData.minDistance
                    tracker.wallTrainCount = 0  -- Reset wall train count after spawning
            else
                 -- For non-wall obstacles, spawn normally
                local obstacle = spawnObstacle(obstacleData.type, lane, zPosition)
                if obstacle then
                    table.insert(spawnedObstacles, obstacle)
                    tracker.lastSpawnZ = zPosition
                    tracker.minDistance = obstacleData.minDistance
                end
            end
        end
    end
    return spawnedObstacles
end

function setObstaclePosition(obstacle, lane, zPosition)
    obstacle.Position = Number3(lane * LANE_WIDTH, groundLevel + GROUND_OFFSET, zPosition)
end

function spawnObstacle(obstacleType, lane, zPosition)
    local obstacle
    
    -- Check if required assets are loaded
    if obstacleType == "log" and logPart == nil then
        return nil
    elseif obstacleType == "wall" and wallPart == nil then
        return nil
    elseif obstacleType == "flag" and flagPart == nil then
        return nil
    elseif obstacleType == "stairs" and stairsPart == nil then
        return nil
    end
    
    if obstacleType == "log" then
        obstacle = logPart:Copy({ includeChildren = true })
    elseif obstacleType == "wall" then
        obstacle = wallPart:Copy({ includeChildren = true })
    elseif obstacleType == "flag" then
        obstacle = flagPart:Copy({ includeChildren = true })
    elseif obstacleType == "stairs" then
        obstacle = stairsPart:Copy({ includeChildren = true })
    end
    
    if obstacle then
        setObstaclePosition(obstacle, lane, zPosition)
        obstacle.Mass = 1000
        if currentState == STATES.RUNNING then
            obstacle.Motion.Z = -gameSpeed
        else
            obstacle.Motion.Z = 0
        end
        obstacle.Friction = 0
        obstacle.Acceleration = -Config.ConstantAcceleration
        obstacle.Velocity = Number3(0, 0, 0)
        
        World:AddChild(obstacle)
        obstaclesByRef[obstacle] = obstacleType
        
        return obstacle
    end
    
    return nil
end

function getLaneTracker(lane)
    if lane == -1 then
        return laneTrackers.left
    elseif lane == 0 then
        return laneTrackers.center
    elseif lane == 1 then
        return laneTrackers.right
    end
    return nil
end

function canSpawnInLane(lane, currentZ)
    local tracker = getLaneTracker(lane)
    if not tracker then return false end
    
    -- If we're in a wall train, continue spawning walls
    if tracker.wallTrainCount > 0 then
        return true
    end
    
    -- For non-wall train spawning, check minimum distance
    return (currentZ - tracker.lastSpawnZ) >= tracker.minDistance
end

function selectObstacleType()
    local rand = math.random()
    local cumulative = 0
    
    -- Use all available obstacles including stairs
    local totalProb = 0
    for _, obstacle in ipairs(obstacleTypes) do
        totalProb = totalProb + obstacle.probability
    end
    
    -- Select from all obstacles
    rand = rand * totalProb
    for _, obstacle in ipairs(obstacleTypes) do
        cumulative = cumulative + obstacle.probability
        if rand <= cumulative then
            return obstacle
        end
    end
    
    -- Fallback to log if something goes wrong
    return obstacleTypes[1]
end

function updateObstacleSpeed(newSpeed)
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            obstacle.Motion.Z = -newSpeed
        end
    end
end

function clearSegments()
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            World:RemoveChild(obstacle)
            obstaclesByRef[obstacle] = nil
        end
    end
    segments = {}
    
    -- Reset lane trackers
    laneTrackers.left.lastSpawnZ = 0
    laneTrackers.center.lastSpawnZ = 0
    laneTrackers.right.lastSpawnZ = 0
    laneTrackers.left.minDistance = 100
    laneTrackers.center.minDistance = 100
    laneTrackers.right.minDistance = 100
    laneTrackers.left.wallTrainCount = 0
    laneTrackers.center.wallTrainCount = 0
    laneTrackers.right.wallTrainCount = 0
    laneTrackers.left.stairsSpawned = false
    laneTrackers.center.stairsSpawned = false
    laneTrackers.right.stairsSpawned = false
end

Client.Tick = function(dt)
    if currentState == STATES.LOADING then
        return
    end

    if currentState == STATES.MENU then
        -- In menu state, just spawn initial segments
        updateSegments(gameProgress)
        return
    end

    if currentState == STATES.READY then
        -- Update UI in ready state
        updateScoreDisplay(score)
        
        -- Spawn segments but don't update score or move obstacles
        updateSegments(gameProgress)
        return
    end

    if isGameOver then return end
    
    -- Update game progress based on time and game speed
    gameProgress = gameProgress + (gameSpeed * dt)
    
    -- Update difficulty over time (only when game is running)
    if currentState == STATES.RUNNING then
        gameTime = gameTime + dt
        difficultyMultiplier = math.min(MAX_DIFFICULTY_MULTIPLIER, 1.0 + (DIFFICULTY_INCREASE_RATE * gameTime))
        gameSpeed = NORMAL_GAME_SPEED * difficultyMultiplier
    end
    
    updateScore(dt)
    updateScoreDisplay(score)
    updateCrouch(dt)  -- Update crouch timer

    if isSlowDownActive then
        slowDownTimer -= dt
        Player.Animations.Walk.Speed = ANIMATION_SPEED * SLOW_DOWN_MULTIPLIER
        gameSpeed = NORMAL_GAME_SPEED * SLOW_DOWN_MULTIPLIER
        updateObstacleSpeed(gameSpeed)
        if slowDownTimer <= 0 then
            isSlowDownActive = false
            gameSpeed = NORMAL_GAME_SPEED * difficultyMultiplier  -- Use current difficulty multiplier
            Player.Animations.Walk.Speed = ANIMATION_SPEED
            Player.Animations.Walk:Play()  -- Ensure walk animation is playing
            updateObstacleSpeed(gameSpeed)
        end
    end

    updateSegments(gameProgress)
    groundImage.Offset.Y = groundImage.Offset.Y - dt * gameSpeed * GROUND_MOTION_MULTIPLIER
    yellowLineLeft.Offset.Y = yellowLineLeft.Offset.Y - dt * gameSpeed * GROUND_MOTION_MULTIPLIER
    yellowLineMiddle.Offset.Y = yellowLineMiddle.Offset.Y - dt * gameSpeed * GROUND_MOTION_MULTIPLIER
    yellowLineRight.Offset.Y = yellowLineRight.Offset.Y - dt * gameSpeed * GROUND_MOTION_MULTIPLIER


    if isMoving then
        targetLane = math.max(-1, math.min(1, targetLane))
        targetPosition = lanePositions[targetLane + 2]
        Player.Velocity.X = (targetPosition.X - Player.Position.X) * LANE_MOVEMENT_SPEED * dt
        if math.abs(targetPosition.X - Player.Position.X) < LANE_MOVEMENT_THRESHOLD then
            currentLane = targetLane
            isMoving = false
        end
    end
end





