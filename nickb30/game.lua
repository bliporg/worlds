Modules = {
    sfx = "sfx",
    controls = "controls",
    ease = "ease",
    ui = "uikit",
    webquad = "github.com/aduermael/modzh/webquad:cc6dda1",
    niceleaderboard = "github.com/aduermael/modzh/niceleaderboard:47c44c8",
}
    
Config.Items = {
    "littlecreator.lc_tree_01",
    "sansyozh.tree",
    "cawa2un.tree01",
    "cawa2un.tree04",
}

--Dev.DisplayColliders = true
Config.ConstantAcceleration *= 2

-- CONSTANTS
local GROUND_MOTION_MULTIPLIER = 4/384  -- NEEDS UPDATED VALUE
local JUMP_STRENGTH = 150
local SCORE_PER_SECOND = 100
local ANIMATION_SPEED = 1.5
local NORMAL_GAME_SPEED = 80
local SLOW_DOWN_MULTIPLIER = 0.80
local SLOW_DOWN_DURATION = 3.0
local LANE_WIDTH = 30
local BUILDING_FAR = 700
local DIFFICULTY_INCREASE_RATE = 0.02  -- How fast difficulty increases per second
local MAX_DIFFICULTY_MULTIPLIER = 3.0  -- Maximum difficulty multiplier
local SWIPE_THRESHOLD = 10  -- Minimum distance for swipe detection
local GROUND_OFFSET = 0.1  -- Height offset for obstacles above ground
local WALL_SPACING = 50  -- Distance between walls in a train
local SPAWN_DISTANCE = 200  -- Distance ahead of current progress to spawn obstacles
local MAX_SPAWN_DISTANCE = 400  -- Maximum distance to spawn obstacles ahead
local SPAWN_SPACING = 50  -- Spacing between spawn attempts
local MAX_SPAWNS_PER_FRAME = 10  -- Maximum obstacles to spawn per frame
local CLEANUP_DISTANCE = 80 -- Distance behind player to clean up obstacles
local STAIRS_BOOST_MULTIPLIER = 3.0  -- Multiplier for stairs boost (increased for high speeds)
local LANE_MOVEMENT_SPEED = 1000  -- Speed multiplier for lane movement
local LANE_MOVEMENT_THRESHOLD = 0.01  -- Threshold for lane movement completion

-- Tutorial constants
local TUTORIAL_ENABLED = true  -- Set to true to enable tutorial
local TUTORIAL_WALL_Z = 200  -- Z position for tutorial walls (increased from 50)
local TUTORIAL_LOG_Z = 500   -- Z position for tutorial logs (increased spacing)
local TUTORIAL_FLAG_Z = 700  -- Z position for tutorial flags (better spacing)
local TUTORIAL_COMPLETE_Z = 800  -- Z position where tutorial ends (increased from 350)

local TUTORIAL_END_BUFFER = 80  -- how far past the flags before tutorial ends

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

-- Debug function to print lane tracker values
local function printLaneTrackers()
    print("=== LANE TRACKERS ===")
    print("Left: lastSpawnZ=" .. laneTrackers.left.lastSpawnZ .. ", minDistance=" .. laneTrackers.left.minDistance)
    print("Center: lastSpawnZ=" .. laneTrackers.center.lastSpawnZ .. ", minDistance=" .. laneTrackers.center.minDistance)
    print("Right: lastSpawnZ=" .. laneTrackers.right.lastSpawnZ .. ", minDistance=" .. laneTrackers.right.minDistance)
    print("====================")
end

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
local cliffPart

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
local CROUCH_DURATION = 0.5  -- How long to stay crouched
local NORMAL_SCALE = 0.5  -- The player's normal scale
local CROUCH_SCALE = 0.25  -- How much to scale down when crouching (50% of normal size)
local wantsToCrouch = false  -- Track if player wants to crouch while in air
local scoreText = nil
local newHighScoreText = nil
local newHighScorePanel = nil
local currentState = STATES.LOADING
local assetsLoaded = 0
local totalAssets = 6  -- log, wall, flag, stairs, cliff, tutorial_completed
local startButton = nil
local restartButton = nil

-- Tutorial state variables
local tutorialState = 0  -- 0 = not started, 1 = walls, 2 = logs, 3 = flags, 4 = complete
local tutorialText = nil
local tutorialObstacles = {}  -- Track tutorial obstacles for cleanup
local tutorialStarted = false
local tutorialCompleted = false

-- Footstep sound variables
local footstepTimer = 0
local FOOTSTEP_INTERVAL = 0.33  -- Time between footsteps in seconds
local lastPlayerOnGround = false

-- Flashing effect variables
local flashTimer = 0
local FLASH_INTERVAL = 0.1  -- Time between flash toggles in seconds
local isFlashing = false
local showLeaderboardTimer = 0  -- Timer for showing leaderboard after game over

-- Track last ground collider for footsteps
local lastGroundCollider = nil

-- Track last ground obstacle type for footsteps
local lastGroundObstacleType = nil

local OBSTACLE_SPAWN_Z_OFFSET = 850

-- Table to track obstacles that are animating upwards
local obstacleAnimations = {}  -- { [obstacle] = { targetY = number, duration = number, elapsed = number, startY = number } }
local OBSTACLE_SPAWN_ANIMATION_OFFSET = 20  -- How far below ground to start
local OBSTACLE_SPAWN_ANIMATION_DURATION = 0.3  -- Animation duration in seconds

local function createTopRightScore()
    -- Create score text in top-right corner
    node = ui:frameTextBackground()
    scoreText = ui:createText("0",
        {
            size = "big",
            color = Color.White,
            bold = true,
            outline = 0.4,
            text
        }
    )
    scoreText:setParent(node)
    node.parentDidResize = function()
        node.pos = {Screen.Width - 55 - node.Width, Screen.Height - 55 - node.Height}
        node.size = {scoreText.Width + 12, scoreText.Height + 10}
        scoreText.pos = {5, 5}
    end
    node:parentDidResize()
end

local function updateScoreDisplay(newScore)
    if scoreText then
        scoreText.Text = string.format("%.0f", newScore)
        node.parentDidResize()  -- Reposition after text change
    end
end

local function createNewHighScoreText()
    -- Remove the background panel for the final score display
    -- Only create the text object
    newHighScoreText = ui:createText("", {
        size = "big",
        color = Color.White,
        bold = true,
        outline = 0.4,
    })
    newHighScoreText.parentDidResize = function()
        newHighScoreText.pos = { Screen.Width / 2 - newHighScoreText.Width / 2, Screen.Height * 0.8 - newHighScoreText.Height / 2}
    end
    newHighScoreText:parentDidResize()
    newHighScoreText.Text = ""  -- Start hidden
    newHighScorePanel = nil
end

local function createTutorialText()
    tutorialText = ui:createText("", {
        size = "medium",
        color = Color.White,
        bold = true,
        outline = 0.4,
    })
    tutorialText.parentDidResize = function()
        tutorialText.pos = { Screen.Width / 2 - tutorialText.Width / 2, Screen.Height * 0.15 - tutorialText.Height / 2}
        tutorialText.object.MaxWidth = Screen.Width * 0.8
    end
    tutorialText:parentDidResize()
    tutorialText.Text = ""
    tutorialText.IsHidden = true
end

local function showTutorialText(text)
    if tutorialText then
        tutorialText.Text = text
        tutorialText.IsHidden = false
        tutorialText:parentDidResize()
    end
end

local function hideTutorialText()
    if tutorialText then
        tutorialText.IsHidden = true
    end
end

-- At the top of your file, add:
-- length of a cliff
local CLIFF_LENGTH = 85
local CLIFF_SPAWN_INTERVAL = CLIFF_LENGTH - 15 -- match your cliff Z scale 
local nextCliffSpawnZ = 0

-- In dropPlayer, reset nextCliffSpawnZ to the player's Z position
function dropPlayer()
    Player.Position:Set(0, 40, 0)
    Player.Rotation:Set(0, 0, 0)
    Player.Velocity:Set(0, 0, 0)
    clearSegments()
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
    currentState = STATES.READY
    cliffSpawnZ = 0
    lastCliffSpawnZ = -math.huge
    
    -- Reset tutorial state for new game
    tutorialState = 0
    tutorialStarted = false
    -- tutorialCompleted should preserve the value from KeyValueStore
    cleanupTutorialObstacles()
    hideTutorialText()
    
    -- Reset footstep timer
    footstepTimer = 0
    
    -- Reset flashing state
    flashTimer = 0
    isFlashing = false
    Player.IsHidden = false

    -- Update UI displays
    updateScoreDisplay(score)
    if scoreText then scoreText.IsHidden = false end
    if newHighScoreText then newHighScoreText.Text = "" end
    if newHighScorePanel then newHighScorePanel.Color = Color(0, 0, 0, 0) end
    if leaderboardUI then leaderboardUI:show() end
    if startButton then startButton:show() end
    if restartButton then restartButton:hide() end
end

function gameOver()
    leaderboard:set({score = score, callback = function() 
        loadHighScore()
        -- Reload the leaderboard UI after the score is submitted
        leaderboardUI:reload()
    end})
    isGameOver = true
    sfx("death_scream_guy_4", { Volume = 0.5, Pitch = math.random() * 0.5 + 0.8, Spatialized = false })
    print("Game Over")
    currentState = STATES.GAME_OVER
    Player.Animations.Walk:Stop()
    Player.Velocity = Number3(0, 0, 0)
    -- Ensure player is visible when game ends
    Player.IsHidden = false
    -- stop all motions
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            obstacle.Motion.Z = 0
        end
    end
    updateCliffMotion(0)
    -- stop tutorial obstacles
    for _, obstacle in ipairs(tutorialObstacles) do
        if obstacle and obstacle.Parent then
            obstacle.Motion.Z = 0
        end
    end
    -- stop all cliffs
    for obstacle, type in pairs(obstaclesByRef) do
        if type == "cliff" and obstacle and obstacle.Parent then
            obstacle.Motion.Z = 0
        end
    end
    -- Show leaderboard UI and restart button after a delay
    showLeaderboardTimer = 2
    -- Hide the score text in top-right
    if scoreText then 
        scoreText.IsHidden = true 
        node.IsHidden = true
    end
    -- Show final score in the center panel
    if newHighScoreText and newHighScorePanel then
        newHighScoreText.Text = "FINAL SCORE: " .. string.format("%.0f", score)
        newHighScoreText.Color = Color.White
        newHighScoreText.FontSize = 48
        newHighScoreText.Font = "Bold"
        newHighScoreText.Outline = 0.4
        newHighScoreText.parentDidResize()
    end
    -- Check if this is a new high score (simplified - just show final score for now)
    if newHighScoreText then
        newHighScoreText.Text = "FINAL SCORE: " .. string.format("%.0f", score)
        newHighScoreText.parentDidResize()
    end
    if restartButton then restartButton:hide() end
    if startButton then startButton:hide() end
end

function restartGame()
    print("Restarting game...")
    currentState = STATES.RUNNING
    isGameOver = false
    dropPlayer()
    nextCliffSpawnZ = Player.Position.Z  -- Ensure cliff spawning resumes
end

function startGame()
    print("Starting game...")
    print("spawn offset: " .. OBSTACLE_SPAWN_Z_OFFSET)
    currentState = STATES.RUNNING
    leaderboardUI:hide()
    Player.Animations.Walk:Play()
    
    -- Set high speed for testing
    --gameSpeed = NORMAL_GAME_SPEED * 4.0  -- Start at 3x speed
    --gameTime = 80  -- Simulate 60 seconds of gameplay for high difficulty
    
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            obstacle.Motion.Z = -gameSpeed
        end
    end
    updateCliffMotion(gameSpeed)
    if startButton then startButton:hide() end
    if restartButton then restartButton:hide() end
    if scoreText then scoreText.IsHidden = false end
    if node then node.IsHidden = false end
    
    -- Start tutorial if enabled
    if TUTORIAL_ENABLED then
        startTutorial()
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
        
        -- Check for collisions when manually uncrouching
        checkForObstacleCollisions()
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
            
            -- Check for collisions when uncrouching
            checkForObstacleCollisions()
        end
    end
end

-- Add a function to check for obstacle collisions - for flag and crouching
function checkForObstacleCollisions()
    -- Check if player is colliding with any obstacles after uncrouching
    for obstacle, obstacleType in pairs(obstaclesByRef) do
        if obstacle and obstacle.Parent and obstacleType ~= "stairs" then
            -- Get the obstacle's collision box
            local obstacleBox = obstacle.CollisionBox
            if obstacleBox then
                -- Get player's collision box
                local playerBox = Player.CollisionBox
                if playerBox then
                    -- Check if the boxes overlap
                    local playerMin = Player.Position + playerBox.Min
                    local playerMax = Player.Position + playerBox.Max
                    local obstacleMin = obstacle.Position + obstacleBox.Min
                    local obstacleMax = obstacle.Position + obstacleBox.Max
                    
                    -- Check for overlap
                    if playerMin.X < obstacleMax.X and playerMax.X > obstacleMin.X and
                       playerMin.Y < obstacleMax.Y and playerMax.Y > obstacleMin.Y and
                       playerMin.Z < obstacleMax.Z and playerMax.Z > obstacleMin.Z then
                        -- Player is colliding with an obstacle, trigger game over
                        Player.Position.Y = 0
                        
                        -- Play collision sound based on obstacle type
                        if obstacleType == "log" then
                            sfx("wood_impact_5", { Volume = 0.6, Pitch = math.random(9000, 10000) / 10000, Spatialized = false })
                        else
                            sfx("metal_clanging_6", { Volume = 0.6, Pitch = math.random(9000, 10000) / 10000, Spatialized = false })
                        end
                        
                        gameOver()
                        return
                    end
                end
            end
        end
    end
end

if Client.IsMobile then
    Client.DirectionalPad = nil
    Client.Action1 = nil
else
    Client.DirectionalPad = function(x, y)
        -- Only allow controls when game is running
        if currentState ~= STATES.RUNNING then
            return
        end
        
        -- Only allow movement/crouch/jump, not game start/restart
        if x == 1 then
            targetLane += 1
            isMoving = true
            sfx("whooshes_small_1", { Volume = 0.5, Pitch = math.random(9000, 10000) / 10000, Spatialized = false })
        elseif x == -1 then
            targetLane -= 1
            isMoving = true
            sfx("whooshes_small_1", { Volume = 0.5, Pitch = math.random(9000, 10000) / 10000, Spatialized = false })
        end
        if y == 1 then
            if Player.IsOnGround then
                cancelCrouch()  -- Cancel crouch when jumping
                Player.Velocity.Y = JUMP_STRENGTH
            end
        elseif y == -1 then
            if not Player.IsOnGround then
                Player.Velocity.Y = -JUMP_STRENGTH * 1.8  -- Fall faster
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
    -- Score increases based on game speed multiplier for higher difficulty = higher rewards
    local scoreMultiplier = difficultyMultiplier or 1.0
    score = score + (SCORE_PER_SECOND * scoreMultiplier * dt)
end

function updateFootsteps(dt)
    -- Only play footsteps when game is running and player is on ground
    if currentState == STATES.RUNNING and Player.IsOnGround then
        footstepTimer = footstepTimer + dt
        
        -- Play footstep sound at regular intervals
        if footstepTimer >= FOOTSTEP_INTERVAL then
            if Player.Position.Y > 41 then
                -- Player is on top of a wall - use concrete sound for walking
                sfx("walk_concrete_1", { Volume = 0.3, Pitch = 2.3 + math.random() * 0.2, Spatialized = false })
            else
                -- Player is on ground - use grass sound for walking
                sfx("walk_grass_1", { Volume = 0.4, Pitch = 2.3 + math.random() * 0.2, Spatialized = false })
            end
            footstepTimer = footstepTimer % FOOTSTEP_INTERVAL  -- Use modulo instead of reset to 0
        end
    else
        -- Only reset timer when game is not running, not when player is in air
        if currentState ~= STATES.RUNNING then
            if footstepTimer > 0 then
                print("Footstep timer reset: currentState=" .. currentState .. ", IsOnGround=" .. tostring(Player.IsOnGround))
            end
            footstepTimer = 0
        end
    end
end

function updateFlashing(dt)
    if isSlowDownActive then
        flashTimer = flashTimer + dt
        
        -- Toggle player visibility for flashing effect
        if flashTimer >= FLASH_INTERVAL then
            Player.IsHidden = not Player.IsHidden
            flashTimer = 0
        end
    else
        -- Stop flashing and ensure player is visible when not slowed down
        Player.IsHidden = false
        flashTimer = 0
    end
end

-- Called when Pointer is "shown" (Pointer.IsHidden == false), which is the case by default.
Pointer.Drag = function(pe)
    -- Only allow controls when game is running
    if currentState ~= STATES.RUNNING then
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
            sfx("whooshes_small_1", { Volume = 0.5, Pitch = math.random(9000, 10000) / 10000, Spatialized = false })
        elseif Xdiff < -SWIPE_THRESHOLD and currentLane >= 0 then
            swipeTriggered = true
            targetLane -= 1
            isMoving = true
            sfx("whooshes_small_1", { Volume = 0.5, Pitch = math.random(9000, 10000) / 10000, Spatialized = false })
        elseif Ydiff > SWIPE_THRESHOLD then
            swipeTriggered = true
            if Player.IsOnGround then
                cancelCrouch()  -- Cancel crouch when jumping
                Player.Velocity.Y = JUMP_STRENGTH
            end
        elseif Ydiff < -SWIPE_THRESHOLD then
            swipeTriggered = true
            if not Player.IsOnGround then
                Player.Velocity.Y = -JUMP_STRENGTH * 1.8  -- Fall faster
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

    local store = KeyValueStore(Player.UserID)
    --store:Set("tutorial_completed", false, function(success) end)
    store:Get("tutorial_completed", function(success, results)
        if success then 
            tutorialCompleted = results.tutorial_completed
            assetsLoaded += 1
            if assetsLoaded == totalAssets then
                currentState = STATES.MENU
            end
            -- Move the tutorial completion check here, after everything is loaded
            --print("Tutorial completed: " .. tostring(tutorialCompleted))
            if tutorialCompleted then
                OBSTACLE_SPAWN_Z_OFFSET = 0
                TUTORIAL_ENABLED = false
                --print("Tutorial disabled due to previous completion")
            end
            --print("OBSTACLE_SPAWN_Z_OFFSET: " .. OBSTACLE_SPAWN_Z_OFFSET)
            --print("KeyValueStore: " .. tostring(results.tutorial_completed))
        end
    end)

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
    leaderboardUI = niceleaderboard({})
    leaderboardUI.Width = 200
    leaderboardUI.Height = 300
    leaderboardUI.Position = { Screen.Width / 2 - leaderboardUI.Width / 2, Screen.Height / 2 - leaderboardUI.Height / 2 }
    leaderboardUI:reload()

    -- ground texture
    -- 256 x 384
    groundImageMiddle = webquad:create({
        color = Color.White,
        url = "https://files.blip.game/textures/grass-with-path-2.jpg",
        filtering = false,
    })
    groundImageMiddle.Width = LANE_WIDTH * 5 * 4
    groundImageMiddle.Height = BUILDING_FAR * 2 * 4
    groundImageMiddle.Scale = 1/4
    tilingY = groundImageMiddle.Height / 384
    groundImageMiddle.Tiling = { 5, tilingY }
    groundImageMiddle.Anchor = { 0.5, 0.5 }
    groundImageMiddle.IsDoubleSided = false
    groundImageMiddle.Position = { 0, groundLevel, 0 }
    World:AddChild(groundImageMiddle)
    groundImageMiddle.Rotation = { math.pi * 0.5, 0, 0 }

    -- Create ground motion tracker object
    groundMotionTracker = Object()
    groundMotionTracker.Physics = PhysicsMode.Dynamic
    groundMotionTracker.Acceleration = -Config.ConstantAcceleration
    groundMotionTracker.Position = Number3(0, 0, 0)
    groundMotionTracker.Mass = 1
    groundMotionTracker.Motion.Z = -gameSpeed
    groundMotionTracker.CollisionGroups = nil
    groundMotionTracker.CollidesWithGroups = nil
    World:AddChild(groundMotionTracker)
    groundMotionLastZ = 0

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
            box.Max -= Number3(0, 5, 2)
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
            triggerBox.Min += Number3(0, 0, -8)
            triggerBox.Max += Number3(0, 3, 0)
            trigger.CollisionBox = triggerBox
            wrapper:AddChild(trigger)
            trigger.CollisionGroups = nil
            trigger.CollidesWithGroups = COLLISION_GROUPS.PLAYER

            
        elseif type == "cliff" then
            -- set scale and rotation for cliff
            local fixedRotation = Number3(0, 0, 0)
            scale:Rotate(fixedRotation)
            mesh.LocalRotation = fixedRotation
            mesh.Scale = scale
            wrapper.CollisionGroups = nil
        end

        wrapper:Recurse(function(o)
            if o.Shadow ~= nil then o.Shadow = true end
        end, { includeRoot = true })
        return wrapper
    end

    -- load log asset
    HTTP:Get("https://files.blip.game/gltf/kenney/tree-log.glb", function(response)
        if response.StatusCode == 200 then
            local req = Object:Load(response.Body, function(o)
                logPart = wrapMesh(o, Number3(30, 40, 40), "log")
                --print("Log part loaded.")
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
                --print("Wall part loaded.")
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
                --print("Flag part loaded.")
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
                stairsPart = wrapMesh(o, Number3(80, 55, 30), "stairs")
                o.Material = {
                    albedo = Color(180, 140, 90),
                    --metallic = 0.0,
                    --roughness = 0.2,
                }
                --print("Stairs part loaded.")
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

    -- function to create cliff part texture
    -- edit this function to put the webquad into an object, and return the object
    function createCliffPart()
        local cliffObj = Object()
        local quad = webquad:create({
            url = "https://files.blip.game/textures/grass-tile.jpg",
            filtering = false,
        })
        quad.Physics = PhysicsMode.Disabled
        --quad.CollisionGroups = nil
        --quad.CollidesWithGroups = nil
        quad.Width = CLIFF_LENGTH * 4
        quad.Height = 45 * 4
        quad.Scale = 1/4
        quad.Anchor = { 0.5, 0 }
       -- quad.Rotation = { math.rad(90), 0, 0}
        cliffObj:AddChild(quad)
        cliffObj.Physics = PhysicsMode.Dynamic
        cliffObj.Acceleration = -Config.ConstantAcceleration
        cliffObj.CollisionGroups = nil
        cliffObj.CollidesWithGroups = nil
        assetsLoaded = assetsLoaded + 1
        if assetsLoaded == totalAssets then
            currentState = STATES.MENU
        end
        return cliffObj
    end
    prepopulateCliffPool(20)

    -- Create modern UI panels
    createTopRightScore()
    createNewHighScoreText()
    createTutorialText()
    
    -- Load high score with callback
    function loadHighScore()
        leaderboard:get({
            mode = "best",
            friends = false,
            limit = 5,
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
                end
            end
        })
    end
    
    -- Load the high score initially
    loadHighScore()

    -- Debug: Print initial lane tracker values
   -- print("Initial lane tracker values:")
   -- printLaneTrackers()

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
        rotationTarget = Rotation(math.rad(20), 0, 0), -- camera rotates to that rotation (or rotation of given object)
        rigidity = 0.3, -- how fast the camera moves to the target (reduced for smoother movement)
        collidesWithGroups = nil, -- camera will not go through objects in these groups
    }

    Player.OnCollisionBegin = function(self, other, normal)
        -- Check for landing sound when player hits ground from above
        if normal.Y > 0.5 and currentState == STATES.RUNNING then
            local obstacleType = obstaclesByRef[other]
            if lastGroundObstacleType ~= obstacleType then
                footstepTimer = FOOTSTEP_INTERVAL
                lastGroundObstacleType = obstacleType
            end
        end
        
        if other.Physics == PhysicsMode.Trigger or other.Physics == PhysicsMode.Static then
            if other.Parent ~= nil then
                -- Check if this is a stairs trigger
                local parent = other.Parent
                if obstaclesByRef[parent] == "stairs" then
                    -- Give the player a boost up and forward, scaled by current game speed
                    -- At higher speeds, we need a stronger boost to clear obstacles
                    local boostStrength = gameSpeed * STAIRS_BOOST_MULTIPLIER
                    Player.Motion.Y = boostStrength  -- Upward boost
                    return
                end
                other = parent
            end
        end

        if not obstaclesByRef[other] then
            return
        end
        
        local obstacleType = obstaclesByRef[other]
        
        -- Don't kill player if they hit stairs (even from front)
        if obstacleType == "stairs" then
            return
        end
        
        -- Check for front collision (always fatal)
        if normal.Z < 0 then
            -- Play collision sound based on obstacle type
            if obstacleType == "log" then
                sfx("wood_impact_5", { Volume = 0.6, Pitch = math.random(9000, 11000) / 10000, Spatialized = false })
            else
                sfx("metal_clanging_6", { Volume = 0.6, Pitch = math.random(9000, 11000) / 10000, Spatialized = false })
            end
            gameOver()
            return
        end
        
        -- Check if player is already flashing and hits from side
        if isSlowDownActive and normal.Y == 0 then
            -- Play collision sound based on obstacle type
            if obstacleType == "log" then
                sfx("wood_impact_5", { Volume = 0.6, Pitch = math.random(9000, 11000) / 10000, Spatialized = false })
            else
                sfx("metal_clanging_6", { Volume = 0.6, Pitch = math.random(9000, 11000) / 10000, Spatialized = false })
            end
            gameOver()
            return
        end
        
        -- hit block from the side (first hit)
        if normal.Y == 0 then
            if normal.X < 0 then
                targetLane -= 1  
            -- hit block from the left
            elseif normal.X > 0 then
                targetLane += 1  
            end
            isSlowDownActive = true
            slowDownTimer = SLOW_DOWN_DURATION
            
            -- Play collision sound based on obstacle type
            if obstacleType == "log" then
                sfx("wood_impact_5", { Volume = 0.6, Pitch = math.random(9000, 11000) / 10000, Spatialized = false })
            else
                sfx("metal_clanging_6", { Volume = 0.6, Pitch = math.random(9000, 11000) / 10000, Spatialized = false })
            end
        end
    end

    Player.OnCollisionEnd = function(self, other, normal)
        local obstacleType = obstaclesByRef[other]
        if lastGroundObstacleType == obstacleType then
            lastGroundObstacleType = nil
        end
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

    -- Create start button
    startButton = ui:buttonPositive({content = "Start Game"})
    startButton.Width = 200
    startButton.Height = 50
    startButton.pos = { Screen.Width / 2 - startButton.Width / 2, Screen.Height / 2 - leaderboardUI.Height + 40 }
    startButton.onRelease = function()
        leaderboardUI:hide()
        startButton:hide()
        startGame()
    end
    startButton:show()

    -- Create restart button
    restartButton = ui:buttonPositive({content = "Restart Game"})
    restartButton.Width = 200
    restartButton.Height = 50
    restartButton.pos = { Screen.Width / 2 - restartButton.Width / 2, Screen.Height / 2 - leaderboardUI.Height + 40}
    restartButton.onRelease = function()
        leaderboardUI:hide()
        restartButton:hide()
        restartGame()
        startGame()
    end
    restartButton:hide()

    function spawnTreesOnCliff(cliff)
        -- Check if trees already exist by looking for tree children
        if cliff.hasTrees then
            return
        end        

        cliff.hasTrees = true
        -- Place two trees at 1/3 and 2/3 along the local X axis of the cliff
        local positions = {
            -CLIFF_LENGTH/2 + CLIFF_LENGTH * 0.3,
            -CLIFF_LENGTH/2 + CLIFF_LENGTH * 0.7,
            -- -CLIFF_LENGTH/2 + CLIFF_LENGTH * 0.25,
            -- -CLIFF_LENGTH/2 + CLIFF_LENGTH * 0.75
        }

        for _, x in ipairs(positions) do
            local treeAsset = Config.Items[math.random(1, #Config.Items)]
            local tree = Shape(treeAsset)
            cliff:AddChild(tree)
            tree.Name = "tree"  -- Give trees a name for identification
            tree.Pivot = {tree.Width * 0.5, 0, tree.Depth * 0.5}
            tree.Scale = Number3(1, 1, 0.7)
            tree.LocalPosition = Number3(x, 16, 5)
            tree.CollisionGroups = nil
            tree.CollidesWithGroups = nil
            tree.Physics = PhysicsMode.Disabled
            tree.Shadow = true
            -- Counter-rotate the tree to stand upright despite cliff rotation
            tree.LocalRotation = Number3(-math.pi/6, 0, 0)
        end
    end
end

function updateSegments(gameProgress)
    -- Don't spawn obstacles if assets aren't loaded yet
    if assetsLoaded < totalAssets then
        return
    end
    
    -- During tutorial, only clean up cliffs, let normal cleanup run for everything else
    if TUTORIAL_ENABLED and tutorialStarted and not tutorialCompleted then
        for obstacle, type in pairs(obstaclesByRef) do
            if type == "cliff" and obstacle and obstacle.Parent and obstacle.Position.Z < -CLEANUP_DISTANCE then
                World:RemoveChild(obstacle)
                obstacle.IsHidden = true
                if obstaclePools.cliff then
                    table.insert(obstaclePools.cliff, obstacle)
                end
                obstaclesByRef[obstacle] = nil
            end
        end
        -- Do NOT return here; let normal cleanup logic run for flags and other obstacles
    end
    
    -- Reset lane trackers if lastSpawnZ is too far behind the current progress
    --[[
    for _, tracker in pairs(laneTrackers) do
        if gameProgress - tracker.lastSpawnZ > MAX_SPAWN_DISTANCE then
            tracker.lastSpawnZ = gameProgress - MAX_SPAWN_DISTANCE + tracker.minDistance
        end
    end
    ]]
    -- get furthest Z position of cliffs
    local furthestCliffZ = 0
    for obstacle, type in pairs(obstaclesByRef) do
        if type == "cliff" and obstacle.Position.Z > furthestCliffZ then
            furthestCliffZ = obstacle.Position.Z
        end
    end
    -- Always spawn obstacles (with offset)
    local currentSpawnZ = gameProgress + SPAWN_DISTANCE + OBSTACLE_SPAWN_Z_OFFSET
    currentSpawnZ = math.min(currentSpawnZ, furthestCliffZ + OBSTACLE_SPAWN_Z_OFFSET - 30)
    
    -- Spawn obstacles at the current position (no loop needed since this runs every frame)
   --print("Attempting to spawn obstacles at Z: " .. currentSpawnZ)
    local newObstacles = spawnObstaclesAtPosition(currentSpawnZ)
    if newObstacles and #newObstacles > 0 then
        -- Create a segment entry for tracking
        local segment = {
            zPosition = currentSpawnZ,
            obstacles = newObstacles
        }
        table.insert(segments, segment)
    end

    -- Additional cleanup: remove any obstacles that are too far behind
    for obstacle, type in pairs(obstaclesByRef) do
        local cleanupZ = -CLEANUP_DISTANCE
        if type == "flag" then
            cleanupZ = -120
        elseif type == "cliff" then
            cleanupZ = -120  -- Keep cliffs visible longer
        end
        if obstacle and obstacle.Parent and obstacle.Position.Z < cleanupZ then
            World:RemoveChild(obstacle)
            obstacle.IsHidden = true
            if type and obstaclePools[type] then
                table.insert(obstaclePools[type], obstacle)
            end
            -- Remove from segments
            for _, segment in ipairs(segments) do
                for i = #segment.obstacles, 1, -1 do
                    if segment.obstacles[i] == obstacle then
                        table.remove(segment.obstacles, i)
                        break
                    end
                end
            end
            obstaclesByRef[obstacle] = nil
        end
    end

    -- Remove empty segments
    for i = #segments, 1, -1 do
        if #segments[i].obstacles == 0 then
            table.remove(segments, i)
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

-- Restore getPooledObstacle for pooling
function getPooledObstacle(obstacleType)
    local pool = obstaclePools[obstacleType]
    if pool and #pool > 0 then
        local obj = table.remove(pool)
        obj.IsHidden = false
        if obstacleType == "cliff" then
           -- print("Spawned cliff from pool (recycled)")
        end
        return obj
    else
        if obstacleType == "log" and logPart then
            return logPart:Copy({ includeChildren = true })
        elseif obstacleType == "wall" and wallPart then
            return wallPart:Copy({ includeChildren = true })
        elseif obstacleType == "flag" and flagPart then
            return flagPart:Copy({ includeChildren = true })
        elseif obstacleType == "stairs" and stairsPart then
            return stairsPart:Copy({ includeChildren = true })
        elseif obstacleType == "cliff" and cliffPart then
            --print("Spawned new cliff (not recycled)")
            return createCliffPart()
            -- cliffPart:Copy({ includeChildren = true })
        end
    end
    return nil
end

-- Restore spawnObstacle for lane obstacles
function spawnObstacle(obstacleType, lane, zPosition)
    local obstacle = getPooledObstacle(obstacleType)
    if not obstacle then
        return nil
    end
    obstaclesByRef[obstacle] = obstacleType
    if obstacleType == "cliff" then
        obstacle.Physics = PhysicsMode.Dynamic
        obstacle.Mass = 1000
        obstacle.Friction = 0
        obstacle.Acceleration = -Config.ConstantAcceleration
    end
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
    return obstacle
end

function spawnObstaclesAtPosition(zPosition)
    local spawnedObstacles = {}
    -- Lane obstacles
    for lane = -1, 1 do
        local tracker = getLaneTracker(lane)
        --print("Can spawn in lane: " .. tostring(canSpawnInLane(lane, zPosition)))
        if tracker and canSpawnInLane(lane, zPosition) then
            local obstacleData = selectObstacleType()
            if wouldCreateImpossibleSegment(lane, obstacleData.type, zPosition) then
                return spawnedObstacles
            end
            if obstacleData.type == "wall" and obstacleData.trainLength then
                local trainLength = math.random(obstacleData.trainLength[1], obstacleData.trainLength[2])
                tracker.wallTrainCount = trainLength
                tracker.stairsSpawned = false
                if math.random() <= 0.5 then
                    local stairsObstacle = spawnObstacle("stairs", lane, zPosition + 10)
                    if stairsObstacle then
                        table.insert(spawnedObstacles, stairsObstacle)
                        tracker.stairsSpawned = true
                    end
                end
                for i = 1, trainLength do
                    local wallZ = zPosition + (i * WALL_SPACING)
                    local wallObstacle = spawnObstacle("wall", lane, wallZ)
                    if wallObstacle then
                        table.insert(spawnedObstacles, wallObstacle)
                    end
                end
                tracker.lastSpawnZ = zPosition + ((trainLength) * WALL_SPACING)
                --print("Set lastSpawnZ to: " .. tracker.lastSpawnZ)
                tracker.minDistance = obstacleData.minDistance
                tracker.wallTrainCount = 0
            else
                local obstacle = spawnObstacle(obstacleData.type, lane, zPosition)
                if obstacle then
                    table.insert(spawnedObstacles, obstacle)
                    tracker.lastSpawnZ = zPosition
                    --print("Set lastSpawnZ to: " .. tracker.lastSpawnZ)
                    tracker.minDistance = obstacleData.minDistance
                end
            end
        end
    end
    return spawnedObstacles
end

function setObstaclePosition(obstacle, lane, zPosition)
    -- set logs higher for now
    local y = groundLevel + GROUND_OFFSET
    if obstaclesByRef[obstacle] == "log" then
        y += 3
    end
    -- Always animate from below ground, even for recycled obstacles
    local startY = y - OBSTACLE_SPAWN_ANIMATION_OFFSET
    obstacle.Position = Number3(lane * LANE_WIDTH, startY, zPosition)
    obstacleAnimations[obstacle] = {
        targetY = y,
        duration = OBSTACLE_SPAWN_ANIMATION_DURATION,
        elapsed = 0,
        startY = startY
    }
end

-- Add at the top with other obstacle variables
obstaclePools = {
    log = {},
    wall = {},
    flag = {},
    stairs = {},
    cliff = {},
}

-- Cliff management
local MAX_ACTIVE_CLIFFS = 20  -- Maximum number of active cliffs
local activeCliffCount = 0

-- Function to prepopulate the cliff pool
function prepopulateCliffPool(poolSize)
    if not createCliffPart() then
        print("Cannot prepopulate cliff pool - cliffPart not loaded yet")
        return
    end
    
    --print("Prepopulating cliff pool with " .. poolSize .. " cliffs...")
    for i = 1, poolSize do
        local cliff = createCliffPart()
        cliff.IsHidden = true
        table.insert(obstaclePools.cliff, cliff)
    end
    --print("Cliff pool prepopulated with " .. #obstaclePools.cliff .. " cliffs")
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

function updateLaneTrackerLastSpawnZ(lane)
    local tracker = getLaneTracker(lane)
    if not tracker then return end
    
    -- Find the furthest obstacle in this lane
    local furthestZ = -math.huge
    for obstacle, obstacleType in pairs(obstaclesByRef) do
        if obstacle and obstacle.Parent and obstacleType ~= "cliff" then
            -- Check if this obstacle is in the correct lane
            local obstacleLane = math.round(obstacle.Position.X / LANE_WIDTH)
            if obstacleLane == lane and obstacle.Position.Z > furthestZ then
                furthestZ = obstacle.Position.Z
            end
        end
    end
    
    -- If we found obstacles in this lane, update lastSpawnZ
    if furthestZ > -math.huge then
        tracker.lastSpawnZ = furthestZ
    end
end

function canSpawnInLane(lane, currentZ)
    local tracker = getLaneTracker(lane)
    if not tracker then return false end
    
    -- If we're in a wall train, continue spawning walls
    if tracker.wallTrainCount > 0 then
        return true
    end
    
    -- Update lastSpawnZ based on current obstacle positions
    updateLaneTrackerLastSpawnZ(lane)
    
    -- For non-wall train spawning, check minimum distance
    --print("Current Z: " .. currentZ .. ", Last Spawn Z: " .. tracker.lastSpawnZ .. ", Min Distance: " .. tracker.minDistance)
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

-- Update clearSegments and cleanup code to return obstacles to the pool
function clearSegments()
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            if obstacle and obstacle.Parent then
                World:RemoveChild(obstacle)
                obstacle.IsHidden = true
                local type = obstaclesByRef[obstacle]
                if type and obstaclePools[type] then
                    table.insert(obstaclePools[type], obstacle)
                end
                obstaclesByRef[obstacle] = nil
            end
        end
    end
    -- Also recycle any remaining cliffs in the world (not in segments)
    for obstacle, type in pairs(obstaclesByRef) do
        if type == "cliff" and obstacle.Parent then
            activeCliffCount -= 1
            World:RemoveChild(obstacle)
            obstacle.IsHidden = true
            table.insert(obstaclePools.cliff, obstacle)
            obstaclesByRef[obstacle] = nil
        end
    end
    segments = {}
    -- Reset lane trackers
   -- print("Resetting lane trackers in clearSegments()")
    laneTrackers.left.lastSpawnZ = 0
    laneTrackers.center.lastSpawnZ = 0
    laneTrackers.right.lastSpawnZ = 0
    laneTrackers.left.minDistance = 100
    laneTrackers.center.minDistance = 100
    laneTrackers.right.minDistance = 100
    --printLaneTrackers()
    laneTrackers.left.wallTrainCount = 0
    laneTrackers.center.wallTrainCount = 0
    laneTrackers.right.wallTrainCount = 0
    laneTrackers.left.stairsSpawned = false
    laneTrackers.center.stairsSpawned = false
    laneTrackers.right.stairsSpawned = false
end

-- Add a helper to update all cliff motions
function updateCliffMotion(newSpeed)
    local cliffCount = 0
    for obstacle, type in pairs(obstaclesByRef) do
        if type == "cliff" then
            obstacle.Motion.Z = -newSpeed
            cliffCount = cliffCount + 1
            if cliffCount == 1 then
               -- print("Cliff position: " .. obstacle.Position.Z .. ", Motion.Z: " .. obstacle.Motion.Z)
            end
        end
    end
    if cliffCount > 0 then
        --print("Updated " .. cliffCount .. " cliffs with speed: " .. newSpeed)
    end
end

-- Add this function after updateCliffMotion or near other update functions
function updateCliffs()
    local function getActiveCliffCountAndFurthestZ()
        local count = 0
        local maxZ = 0
        for obstacle, type in pairs(obstaclesByRef) do
            if type == "cliff" and obstacle.Parent then
                count = count + 1
                if obstacle.Position.Z > maxZ then
                    maxZ = obstacle.Position.Z
                end
            end
        end
        return count, maxZ
    end

    local count, furthestZ = getActiveCliffCountAndFurthestZ()
    if TUTORIAL_ENABLED and tutorialStarted and not tutorialCompleted then
        --print("Tutorial cliffs - count: " .. count .. ", furthestZ: " .. furthestZ .. ", MAX_ACTIVE_CLIFFS: " .. MAX_ACTIVE_CLIFFS)
    end
    while count < MAX_ACTIVE_CLIFFS do
        local spawnZ = (count == 0 and 0) or (furthestZ + CLIFF_SPAWN_INTERVAL)
        if TUTORIAL_ENABLED and tutorialStarted and not tutorialCompleted then
            --print("Attempting to spawn cliffs at Z: " .. spawnZ .. " (count: " .. count .. ")")
        end
        local cliffRight = spawnObstacle("cliff", 1.8, spawnZ)
        local cliffLeft = spawnObstacle("cliff", -1.8, spawnZ)
        if cliffRight and cliffLeft then
            cliffRight.Rotation = Number3(math.pi/6, math.pi/2, 0)
            cliffLeft.Rotation = Number3(math.pi/6, -math.pi/2, 0)
            if currentState == STATES.RUNNING then
                cliffRight.Motion.Z = -gameSpeed
                cliffLeft.Motion.Z = -gameSpeed
            else
                cliffRight.Motion.Z = 0
                cliffLeft.Motion.Z = 0
            end
            spawnTreesOnCliff(cliffRight)
            spawnTreesOnCliff(cliffLeft)
            count = count + 2
            furthestZ = spawnZ
            if TUTORIAL_ENABLED and tutorialStarted and not tutorialCompleted then
                --print("Successfully spawned tutorial cliffs at Z: " .. spawnZ)
            end
        else
            if TUTORIAL_ENABLED and tutorialStarted and not tutorialCompleted then
                --print("Failed to spawn cliffs at Z: " .. spawnZ)
            end
            break
        end
    end
end

-- Tutorial functions
function startTutorial()
    if not TUTORIAL_ENABLED then
        return
    end
    
    tutorialStarted = true
    tutorialState = 1
    
    -- Spawn all tutorial obstacles at once
    spawnTutorialWalls()
    spawnTutorialLogs()
    spawnTutorialFlags()
    if IsMobile then
        showTutorialText("Swipe left and right to switch lanes")
    else
        showTutorialText("Press the right or left key to switch lanes")
    end
end

function spawnTutorialWalls()
    -- Spawn 3 walls in the middle lane
    for i = 1, 3 do
        local wallZ = TUTORIAL_WALL_Z + (i - 1) * WALL_SPACING
        local wall = spawnObstacle("wall", 0, wallZ)  -- 0 = center lane
        if wall then
            table.insert(tutorialObstacles, wall)
            if currentState == STATES.RUNNING then
                wall.Motion.Z = -gameSpeed
            else
                wall.Motion.Z = 0
            end
        end
    end
end

function spawnTutorialLogs()
    -- Spawn logs in all three lanes
    for lane = -1, 1 do
        local log = spawnObstacle("log", lane, TUTORIAL_LOG_Z)
        if log then
            table.insert(tutorialObstacles, log)
            if currentState == STATES.RUNNING then
                log.Motion.Z = -gameSpeed
            else
                log.Motion.Z = 0
            end
        end
    end
end

function spawnTutorialFlags()
    -- Spawn flags in all three lanes
    for lane = -1, 1 do
        local flag = spawnObstacle("flag", lane, TUTORIAL_FLAG_Z)
        if flag then
            --print("Spawned flag in lane " .. lane .. " at Z: " .. flag.Position.Z)
            table.insert(tutorialObstacles, flag)
            if currentState == STATES.RUNNING then
                flag.Motion.Z = -gameSpeed
            else
                flag.Motion.Z = 0
            end
        else
            print("Failed to spawn flag in lane " .. lane)
        end
    end
end

function updateTutorial()
    if not TUTORIAL_ENABLED or not tutorialStarted or tutorialCompleted then
        return
    end
    
    -- Check if tutorial obstacles have moved behind the player (Z < 0)
    local wallsPassed = false
    local logsPassed = false
    local flagsPassed = false
    
    -- Check if walls have passed the player
    for _, obstacle in ipairs(tutorialObstacles) do
        if obstaclesByRef[obstacle] == "wall" and obstacle.Position.Z < 0 then
            wallsPassed = true
            break
        end
    end
    
    -- Check if logs have passed the player
    for _, obstacle in ipairs(tutorialObstacles) do
        if obstaclesByRef[obstacle] == "log" and obstacle.Position.Z < 0 then
            logsPassed = true
            break
        end
    end
    
    -- Check if flags have passed the player
    for _, obstacle in ipairs(tutorialObstacles) do
        if obstaclesByRef[obstacle] == "flag" and obstacle.Position.Z < 0 then
            flagsPassed = true
            --print("Flag passed player at Z: " .. obstacle.Position.Z)
            break
        end
    end
    
    if tutorialState == 1 then
        -- Check if player moved left or right from center lane
        if currentLane ~= 0 then
            -- Player moved left or right, but keep text until walls pass
            if wallsPassed then
                tutorialState = 2
                hideTutorialText()
                if IsMobile then
                    showTutorialText("Swipe up to jump")
                else
                    showTutorialText("Press the up key to jump")
                end
            end
        elseif wallsPassed then
            -- Player passed walls without moving, force them to move
            tutorialState = 2
            hideTutorialText()
            if IsMobile then
                showTutorialText("Swipe up to jump")
            else
                showTutorialText("Press the up key to jump")
            end
        end
    elseif tutorialState == 2 then
        if not Player.IsOnGround then
            if logsPassed then
                tutorialState = 3
                hideTutorialText()
                if IsMobile then
                    showTutorialText("Swipe down to crouch")
                else
                    showTutorialText("Press the down key to crouch")
                end
            end
        elseif logsPassed then
            tutorialState = 3
            hideTutorialText()
            if IsMobile then
                showTutorialText("Swipe down to crouch")
            else
                showTutorialText("Press the down key to crouch")
            end
        end
    elseif tutorialState == 3 then
        -- Check if player crouched
        local allFlagsBehind = true
        for _, obstacle in ipairs(tutorialObstacles) do
            if obstaclesByRef[obstacle] == "flag" and obstacle.Position.Z > -TUTORIAL_END_BUFFER then
                allFlagsBehind = false
                break
            end
        end
        --print("Tutorial State 3 - flagsPassed: " .. tostring(flagsPassed) .. ", allFlagsBehind: " .. tostring(allFlagsBehind) .. ", isCrouching: " .. tostring(isCrouching))
        if isCrouching then
            if flagsPassed and allFlagsBehind then
                --print("Tutorial completing - player crouched and flags passed!")
                tutorialState = 4
                hideTutorialText()
                tutorialCompleted = true
                cleanupTutorialObstacles()
            end
        elseif flagsPassed and allFlagsBehind then
            --print("Tutorial completing - flags passed without crouching!")
            tutorialState = 4
            hideTutorialText()
            tutorialCompleted = true
            TUTORIAL_ENABLED = false
            OBSTACLE_SPAWN_Z_OFFSET = 0
            print("Tutorial ended!")
            
                -- Reset lane trackers after tutorial ends so normal spawning can begin
            print("Resetting lane trackers after tutorial end")
            laneTrackers.left.lastSpawnZ = 0
            laneTrackers.center.lastSpawnZ = 0
            laneTrackers.right.lastSpawnZ = 0
            laneTrackers.left.minDistance = 100
            laneTrackers.center.minDistance = 100
            laneTrackers.right.minDistance = 100
            printLaneTrackers()
            
            local store = KeyValueStore(Player.UserID)
            store:Set("tutorial_completed", true, function(success) 
                if success then
                    --print("Tutorial completed saved")
                else
                    --print("Tutorial completed not saved")
                end
            end)
            cleanupTutorialObstacles()
        end
    end
end

function cleanupTutorialObstacles()
    for _, obstacle in ipairs(tutorialObstacles) do
        if obstacle and obstacle.Parent then
            World:RemoveChild(obstacle)
            obstacle.IsHidden = true
            local type = obstaclesByRef[obstacle]
            if type and obstaclePools[type] then
                table.insert(obstaclePools[type], obstacle)
            end
            obstaclesByRef[obstacle] = nil
        end
    end
    tutorialObstacles = {}
end

Client.Tick = function(dt)
    if currentState == STATES.LOADING then
        return
    end

    -- Animate obstacles rising from below ground
    for obstacle, anim in pairs(obstacleAnimations) do
        if obstacle and obstacle.Parent then
            anim.elapsed = anim.elapsed + dt
            local t = math.min(anim.elapsed / anim.duration, 1)
            -- Ease out cubic for smoothness
            local easeT = 1 - (1 - t) * (1 - t) * (1 - t)
            local newY = anim.startY + (anim.targetY - anim.startY) * easeT
            obstacle.Position.Y = newY
            if t >= 1 then
                obstacle.Position.Y = anim.targetY
                obstacleAnimations[obstacle] = nil
            end
        else
            obstacleAnimations[obstacle] = nil
        end
    end

    if currentState == STATES.MENU then
        -- In menu state, just update cliffs (no obstacle spawning)
        updateCliffs()
        return
    end

    if currentState == STATES.READY then
        -- Update UI in ready state
        updateScoreDisplay(score)
        -- Just update cliffs, don't spawn obstacles yet
        updateCliffs()
        return
    end

    if isGameOver then 
        -- Handle leaderboard timer even when game is over
        if showLeaderboardTimer > 0 then
            showLeaderboardTimer = showLeaderboardTimer - dt
            if showLeaderboardTimer <= 0 then
                leaderboardUI:show()
                if restartButton then restartButton:show() end
            end
        end
        return 
    end
    
    -- Update game progress based on time and game speed
    gameProgress = gameProgress + (gameSpeed * dt)
    
    -- Update difficulty over time (only when game is running)
    if currentState == STATES.RUNNING then
        leaderboardUI:hide()
        gameTime = gameTime + dt
        difficultyMultiplier = math.min(MAX_DIFFICULTY_MULTIPLIER, 1.0 + (DIFFICULTY_INCREASE_RATE * gameTime))
        gameSpeed = NORMAL_GAME_SPEED * difficultyMultiplier
    end
    
    updateScore(dt)
    updateScoreDisplay(score)
    updateCrouch(dt)  -- Update crouch timer
    updateFootsteps(dt)  -- Update footstep sounds
    updateFlashing(dt)  -- Update flashing effect

    if isSlowDownActive then
        slowDownTimer -= dt
        if slowDownTimer <= 0 then
            isSlowDownActive = false
        end
    end

    updateSegments(gameProgress)
    updateObstacleSpeed(gameSpeed)
    updateCliffMotion(gameSpeed)
    updateCliffs()
    groundMotionTracker.Motion.Z = -gameSpeed

    -- Update tutorial
    updateTutorial()
    
    -- Update tutorial obstacle speeds and cliff motion
    if TUTORIAL_ENABLED and tutorialStarted and not tutorialCompleted then
        for _, obstacle in ipairs(tutorialObstacles) do
            if obstacle and obstacle.Parent then
                obstacle.Motion.Z = -gameSpeed
            end
        end
        -- Also update cliff motion during tutorial
        updateCliffMotion(gameSpeed)
        --print("Tutorial active - updating cliff motion with speed: " .. gameSpeed)
    end

    -- Calculate offset based on position delta
    local dz = groundMotionTracker.Position.Z - (groundMotionLastZ or 0)
    groundMotionLastZ = groundMotionTracker.Position.Z
    -- Use dz to update groundImage
    groundImageMiddle.Offset.Y = groundImageMiddle.Offset.Y + dz * GROUND_MOTION_MULTIPLIER

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