Modules = {
    sfx = "sfx",
    controls = "controls",
    ease = "ease",
    ui = "uikit",
    webquad = "github.com/aduermael/modzh/webquad:7fbc37d",
    niceleaderboard = "github.com/aduermael/modzh/niceleaderboard:d1d7c49",
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
local GROUND_MOTION_MULTIPLIER = 1/64  -- NEEDS UPDATED VALUE
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
local STAIRS_BOOST_MULTIPLIER = 1.5  -- Multiplier for stairs boost
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
local CROUCH_DURATION = 1.0  -- How long to stay crouched
local NORMAL_SCALE = 0.5  -- The player's normal scale
local CROUCH_SCALE = 0.25  -- How much to scale down when crouching (50% of normal size)
local wantsToCrouch = false  -- Track if player wants to crouch while in air
local scoreText = nil
local newHighScoreText = nil
local newHighScorePanel = nil
local currentState = STATES.LOADING
local assetsLoaded = 0
local totalAssets = 5  -- log, wall, flag, stairs, cliff
local startButton = nil
local restartButton = nil


local function createTopRightScore()
    -- Create score text in top-right corner
    scoreText = ui:createText("0",
        {
            size = "big",
            color = Color.White,
            bold = true,
            outline = 0.4,
            text
        }
    )
    scoreText.parentDidResize = function()
        scoreText.pos = {Screen.Width - 55 - scoreText.Width, Screen.Height - 55 - scoreText.Height}
    end
    scoreText:parentDidResize()
end

local function updateScoreDisplay(newScore)
    if scoreText then
        scoreText.Text = string.format("%.0f", newScore)
        scoreText:parentDidResize()  -- Reposition after text change
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
    end})
    isGameOver = true
    print("Game Over")
    currentState = STATES.GAME_OVER
    Player.Animations.Walk:Stop()
    Player.Velocity = Number3(0, 0, 0)
    -- stop all motions
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            obstacle.Motion.Z = 0
        end
    end
    updateCliffMotion(0)
    --clearSegments()
    
    -- Show leaderboard UI when game is over
    leaderboardUI:show()
    
    -- Hide the score text in top-right
    if scoreText then scoreText.IsHidden = true end
    
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
    
    if restartButton then restartButton:show() end
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
    currentState = STATES.RUNNING
    leaderboardUI:hide()
    Player.Animations.Walk:Play()
    for _, segment in ipairs(segments) do
        for _, obstacle in ipairs(segment.obstacles) do
            obstacle.Motion.Z = -gameSpeed
        end
    end
    updateCliffMotion(gameSpeed)
    if startButton then startButton:hide() end
    if restartButton then restartButton:hide() end
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
        -- Only allow movement/crouch/jump, not game start/restart
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
    score = score + (SCORE_PER_SECOND * dt)
end

-- Called when Pointer is "shown" (Pointer.IsHidden == false), which is the case by default.
Pointer.Drag = function(pe)
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
            triggerBox.Min.Y = triggerBox.Min.Y + 5  -- Start trigger a bit above ground
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

    -- load cliff slope asset
    HTTP:Get("https://files.blip.game/gltf/kenney/cliff-slope.glb", function(response)
        if response.StatusCode == 200 then
            local req = Object:Load(response.Body, function(o)
                cliffPart = wrapMesh(o, Number3(CLIFF_LENGTH, 45, 35), "cliff")
                o.Material = {
                    albedo = Color(120, 200, 120),
                }
                --print("Cliff part loaded.")
                assetsLoaded = assetsLoaded + 1
                
                -- Prepopulate the cliff pool after cliff asset is loaded
                prepopulateCliffPool(10)  -- Start with 20 cliffs in the pool
                
                if assetsLoaded == totalAssets then
                    currentState = STATES.MENU
                end
            end)
        end
    end)

    -- Create modern UI panels
    createTopRightScore()
    createNewHighScoreText()
    
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
            tree.LocalPosition = Number3(x, 16, 0)
            tree.Scale = Number3(1, 1, 0.7)
            tree.CollisionGroups = nil
            tree.CollidesWithGroups = nil
            tree.Physics = PhysicsMode.Disabled
            tree.Shadow = true
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

    -- Additional cleanup: remove any obstacles that are too far behind
    for obstacle, _ in pairs(obstaclesByRef) do
        if obstacle and obstacle.Parent and obstacle.Position.Z < -CLEANUP_DISTANCE then
            World:RemoveChild(obstacle)
            obstacle.IsHidden = true
            local type = obstaclesByRef[obstacle]
            if type and obstaclePools[type] then
                table.insert(obstaclePools[type], obstacle)
                if type == "cliff" then
                    --activeCliffCount -= 1  -- Decrement active count
                end
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
            return cliffPart:Copy({ includeChildren = true })
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
                tracker.lastSpawnZ = zPosition + ((trainLength - 1) * WALL_SPACING)
                tracker.minDistance = obstacleData.minDistance
                tracker.wallTrainCount = 0
            else
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
    -- set logs higher for now
    local y = groundLevel + GROUND_OFFSET
    if obstaclesByRef[obstacle] == "log" then
        y += 3
    end
    obstacle.Position = Number3(lane * LANE_WIDTH, y, zPosition)
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
    if not cliffPart then
        print("Cannot prepopulate cliff pool - cliffPart not loaded yet")
        return
    end
    
    --print("Prepopulating cliff pool with " .. poolSize .. " cliffs...")
    for i = 1, poolSize do
        local cliff = cliffPart:Copy({ includeChildren = true })
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

-- Add a helper to update all cliff motions
function updateCliffMotion(newSpeed)
    for obstacle, type in pairs(obstaclesByRef) do
        if type == "cliff" then
            obstacle.Motion.Z = -newSpeed
        end
    end
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
        leaderboardUI:hide()
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
        updateCliffMotion(gameSpeed)
        if slowDownTimer <= 0 then
            isSlowDownActive = false
            gameSpeed = NORMAL_GAME_SPEED * difficultyMultiplier  -- Use current difficulty multiplier
            Player.Animations.Walk.Speed = ANIMATION_SPEED
            Player.Animations.Walk:Play()  -- Ensure walk animation is playing
            updateObstacleSpeed(gameSpeed)
            updateCliffMotion(gameSpeed)
        end
    end

    updateSegments(gameProgress)
    groundMotionTracker.Motion.Z = -gameSpeed

    -- Calculate offset based on position delta
    local dz = groundMotionTracker.Position.Z - (groundMotionLastZ or 0)
    groundMotionLastZ = groundMotionTracker.Position.Z
    -- Use dz to update groundImage and yellow line offsets
    groundImage.Offset.Y = groundImage.Offset.Y + dz * GROUND_MOTION_MULTIPLIER
    yellowLineLeft.Offset.Y = yellowLineLeft.Offset.Y + dz * GROUND_MOTION_MULTIPLIER
    yellowLineMiddle.Offset.Y = yellowLineMiddle.Offset.Y + dz * GROUND_MOTION_MULTIPLIER
    yellowLineRight.Offset.Y = yellowLineRight.Offset.Y + dz * GROUND_MOTION_MULTIPLIER

    if isMoving then
        targetLane = math.max(-1, math.min(1, targetLane))
        targetPosition = lanePositions[targetLane + 2]
        Player.Velocity.X = (targetPosition.X - Player.Position.X) * LANE_MOVEMENT_SPEED * dt
        if math.abs(targetPosition.X - Player.Position.X) < LANE_MOVEMENT_THRESHOLD then
            currentLane = targetLane
            isMoving = false
        end
    end

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
    while count < MAX_ACTIVE_CLIFFS do
        local spawnZ = (count == 0 and 0) or (furthestZ + CLIFF_SPAWN_INTERVAL)
        local cliffRight = spawnObstacle("cliff", 2.1, spawnZ)
        local cliffLeft = spawnObstacle("cliff", -2.1, spawnZ)
        if cliffRight and cliffLeft then
            cliffRight.Rotation = Number3(0, math.pi/2, 0)
            cliffLeft.Rotation = Number3(0, -math.pi/2, 0)
            if currentState == STATES.RUNNING then
                cliffRight.Motion.Z = -gameSpeed
                cliffLeft.Motion.Z = -gameSpeed
            end
            spawnTreesOnCliff(cliffRight)
            spawnTreesOnCliff(cliffLeft)
            count = count + 2
            furthestZ = spawnZ
           --wned cliffs at Z: " .. spawnZ .. ", Pool size: " .. #obstaclePools.cliff .. ", Active cliffs: " .. count)
        else
            break
        end
    end
end






