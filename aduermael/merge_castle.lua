--[[
	MERGE CASTLE

	2048-style game with medieval theme
]]

Config = {
	Items = {
		"voxels.ground_tile",
		"voxels.metal_panel_2",
	},
	UsePBR = true,
}

Modules = {
	ui = "uikit",
	ease = "ease", -- contains ease:linear, ease:outElastic, ease:outBack, ease:outSine, ease:inOutSine
	niceleaderboard = "github.com/aduermael/modzh/niceleaderboard:d1d7c49",
	music = "github.com/aduermael/modzh/music:c996473",
}

-- CONSTANTS

local TILES_GAMESTART = 2
local TILES_INITIAL_MAX_POW = 2
local MODEL_SCALE = 23

local MIN_DRAG_DISTANCE = 40
local DRAG_SPEED = 200

local BOARD_SIZE = 4 -- number of rows and columns
local BOARD_MARGIN = 0.06
local TILES_MARGIN = 0.02 -- percentage of board size
local BOARD_TILE_SPACE = 1 - BOARD_MARGIN * 2 - TILES_MARGIN * (BOARD_SIZE - 1) -- percentage of board size
local TILES_SCALE_RATIO = BOARD_TILE_SPACE / BOARD_SIZE

local UI_MARGIN_SMALL = 6
local UI_MARGIN = 12

-- UI and scene elements

local title
local score
local bestScore
local restartButton
local loadingMessage
local gameOverMessage
local gameOverRestartButton
local board

local leaderboard
local leaderboardUI

local dragDistance = nil
local direction = nil
local toMove = nil
local toMerge = nil
local newTiles = nil -- new tiles if move committed

-- VARIABLES

local currentScore = 0
local highScore = 0

local tileBaseConfig = { asset = Items.voxels.ground_tile }
local tilesConfig = {
	{ pow = 2, model = nil, rotation = Rotation(0, math.rad(-135), 0), sound = nil, audioSource = nil },
	{
		pow = 4,
		model = nil,
		rotation = Rotation(0, math.rad(45), 0),
		sound = "shield-impact-1.wav",
		pitch = 1,
		audioSource = nil,
	},
	{
		pow = 8,
		model = nil,
		rotation = Rotation(0, math.rad(90), 0),
		sound = "black-smith-hammer-1.wav",
		pitch = 1,
		audioSource = nil,
	}, -- well
	{
		pow = 16,
		model = nil,
		rotation = Rotation(0, math.rad(180), 0),
		sound = "unequip-item-1.wav",
		pitch = 1,
		audioSource = nil,
	}, -- home 1
	{
		pow = 32,
		model = nil,
		rotation = Rotation(0, math.rad(180), 0),
		sound = "unequip-item-1.wav",
		pitch = 0.8,
		audioSource = nil,
	}, -- home 2
	{
		pow = 64,
		model = nil,
		rotation = Rotation(0, math.rad(90), 0),
		sound = "unequip-item-1.wav",
		pitch = 0.6,
		audioSource = nil,
	}, -- town hall
	{ pow = 128, model = nil, sound = "equip-metal-weapon-1.wav", pitch = 1, audioSource = nil },
	{ pow = 256, model = nil, sound = "equip-metal-weapon-1.wav", pitch = 0.8, audioSource = nil },
	{ pow = 512, model = nil, sound = "equip-metal-weapon-1.wav", pitch = 0.6, audioSource = nil },
	{ pow = 1024, model = nil, sound = "ballista-shoot-1.wav", pitch = 1, audioSource = nil },
	{ pow = 2048, model = nil, sound = "equip-amulet-1.wav", pitch = 1, audioSource = nil },
}

local contains = function(t, v)
	for idx, value in ipairs(t) do
		if value == v then
			return idx
		end
	end
	return false
end

-- It's not yet possible in Blip to upload sounds.
-- Loading them here with HTTP:Get is a temporary solution.
local sounds = {}
function loadSounds()
	for _, s in tilesConfig do
		if s.sound ~= nil and sounds[s.sound] == nil then
			sounds[s.sound] = {
				req = HTTP:Get("https://files.blip.game/sfx/" .. s.sound, function(response)
					if response.StatusCode == 200 then
						sounds[s.sound].data = response.Body
						for _, tile in tilesConfig do
							if tile.sound == s.sound then
								tile.audioSource = AudioSource()
								tile.audioSource.Sound = response.Body
								if tile.pitch ~= nil then
									tile.audioSource.Pitch = tile.pitch
								end
								tile.audioSource.Spatialized = false
							end
						end
					end
				end),
			}
		end
	end
end

-- Blip doesn't yet support uploading / loading non-voxel 3D models from the library.
-- Loading them here with HTTP:Get is a temporary solution,
-- it will be much better to just add them to the scene with the world editor.
function load3DModels(onDone)
	local models = {
		"https://files.blip.game/gltf/wheelbarrow.glb",
		"https://files.blip.game/gltf/building-stage-1.glb",
		"https://files.blip.game/gltf/well.glb",
		"https://files.blip.game/gltf/home-1.glb",
		"https://files.blip.game/gltf/home-2.glb",
		"https://files.blip.game/gltf/townhall.glb",
		"https://files.blip.game/gltf/tower-1.glb",
		"https://files.blip.game/gltf/tower-2.glb",
		"https://files.blip.game/gltf/tower-3.glb",
		"https://files.blip.game/gltf/barracks.glb",
		"https://files.blip.game/gltf/castle.glb",
	}
	local nbModelsToLoad = #models
	local function modelLoaded(i, model)
		model.Scale = MODEL_SCALE
		model:Recurse(function(o)
			o.Shadow = true
		end, { includeRoot = true })
		tilesConfig[i].model = model
		nbModelsToLoad -= 1
		if nbModelsToLoad == 0 then
			if onDone then
				onDone()
			end
		end
	end
	for i = 1, nbModelsToLoad do
		HTTP:Get(models[i], function(response)
			if response.StatusCode == 200 then
				Object:Load(response.Body, function(o)
					modelLoaded(i, o)
				end)
			end
		end)
	end
end

Client.OnStart = function()
	Screen.Orientation = "portrait" -- force portrait

	music:play({ track = "medieval-puzzle" })

	board = Shape(Items.voxels.metal_panel_2)
	board.IsHiddenSelf = true
	board.Physics = PhysicsMode.Disabled
	board:SetParent(World)

	title = ui:createText("⚔️ Medieval 2048 ⚔️", { color = Color.White, size = "big" })
	loadingMessage = ui:createText("Loading...", { color = Color.White })
	gameOverMessage = ui:createText(
		"Game Over!",
		{ color = Color.White, outline = 0.6, outlineColor = Color(255, 56, 55), size = "big" }
	)

	score = ui:createText("⭐️ 0", { color = Color.White, outline = 0.4, outlineColor = Color(100, 100, 100) })
	bestScore = ui:createText(
		"🏆 0",
		{ color = Color(255, 255, 129), outline = 0.4, outlineColor = Color(251, 165, 0), size = "small" }
	)
	restartButton = ui:buttonSecondary({ content = "Restart", textSize = "small" })
	gameOverRestartButton = ui:buttonNeutral({ content = "Restart", textSize = "default", padding = UI_MARGIN_SMALL })
	gameOverMessage:hide()
	gameOverRestartButton:hide()

	leaderboard = Leaderboard("default")
	leaderboardUI = niceleaderboard({})
	leaderboardUI.Width = 200
	leaderboardUI.Height = 200
	leaderboardUI:hide()

	HTTP:Get("https://files.blip.game/gltf/mountain-1.glb", function(response)
		if response.StatusCode == 200 then
			local model = Object:Load(response.Body, function(o)
				mountain = o
				o.Shadow = true
				o.Pivot = o.Size * { 0, 1, 0 }
				o.Scale = 10 -- 45
				o:SetParent(board)
				o.LocalPosition = board.Size * 0.5 + { 0, -1.6, 23 }
				o.Rotation:Set(0, math.rad(270), math.rad(-20))
				-- models were flipped along X axis in previous versions
				-- it's been fixed so the rotation has to be changed accordingly
				if Client.BuildNumber >= 223 then
					o.Rotation:Set(0, math.rad(90), math.rad(20))
				end
			end)
		end
	end)

	HTTP:Get("https://files.blip.game/skyboxes/blue-sky-with-generous-clouds.ktx", function(response)
		if response.StatusCode == 200 then
			Sky.Image = response.Body
			Sky.SkyColor = Color.White
			Sky.HorizonColor = Color.White
			Sky.AbyssColor = Color.White
		end
	end)

	layout()
	loading()
end

if Client.IsMobile then
	Client.DirectionalPad = nil
else
	Client.DirectionalPad = function(x, z)
		inputMove(x, z)
	end
end

Pointer.Drag = function(pointerEvent)
	if dragDistance == nil then
		return
	end
	dragDistance.X += pointerEvent.DX
	dragDistance.Y += pointerEvent.DY

	if math.abs(dragDistance.X) > MIN_DRAG_DISTANCE then
		if dragDistance.X > 0 then
			inputMove(1, 0)
		else
			inputMove(-1, 0)
		end
		dragDistance = nil
		return
	end

	if math.abs(dragDistance.Y) > MIN_DRAG_DISTANCE then
		if dragDistance.Y > 0 then
			inputMove(0, 1)
		else
			inputMove(0, -1)
		end
		dragDistance = nil
		return
	end
end

Pointer.DragBegin = function(_)
	dragDistance = Number2(0, 0)
end
Pointer.DragEnd = function(_)
	dragDistance = nil
end

function layout()
	score.pos = {
		Screen.Width - Screen.SafeArea.Right - score.Width - UI_MARGIN,
		Screen.Height - Screen.SafeArea.Top - score.Height - UI_MARGIN,
	}
	bestScore.pos = {
		Screen.Width - Screen.SafeArea.Right - bestScore.Width - UI_MARGIN,
		score.pos.Y - bestScore.Height - UI_MARGIN_SMALL,
	}
	restartButton.pos = {
		Screen.Width - Screen.SafeArea.Right - restartButton.Width - UI_MARGIN,
		bestScore.pos.Y - restartButton.Height - UI_MARGIN,
	}

	local h = title.Height + loadingMessage.Height + UI_MARGIN
	title.pos = {
		Screen.Width * 0.5 - title.Width * 0.5,
		Screen.Height * 0.5 + h * 0.5 - title.Height,
	}
	loadingMessage.pos = {
		Screen.Width * 0.5 - loadingMessage.Width * 0.5,
		Screen.Height * 0.5 - h * 0.5,
	}

	h = gameOverMessage.Height + leaderboardUI.Height + gameOverRestartButton.Height + UI_MARGIN_SMALL * 2
	gameOverMessage.pos = {
		Screen.Width * 0.5 - gameOverMessage.Width * 0.5,
		Screen.Height * 0.5 + h * 0.5 - gameOverMessage.Height,
	}
	leaderboardUI.pos = {
		Screen.Width * 0.5 - leaderboardUI.Width * 0.5,
		gameOverMessage.pos.Y - leaderboardUI.Height - UI_MARGIN_SMALL,
	}
	gameOverRestartButton.pos = {
		Screen.Width * 0.5 - gameOverRestartButton.Width * 0.5,
		leaderboardUI.pos.Y - gameOverRestartButton.Height - UI_MARGIN_SMALL,
	}

	Camera:FitToScreen(board, { coverage = 1.3, orientation = "horizontal" })
	local d = (Camera.Position - board.Position).SquaredLength
	local p = Camera.Position:Copy()
	Camera:FitToScreen(board, { coverage = 1.1, orientation = "vertical" })
	local d2 = (Camera.Position - board.Position).SquaredLength
	if d > d2 then
		Camera.Position = p
	end
end

local t = 0
Client.Tick = function(dt)
	t = t + dt
	if loadingMessage:isVisible() then
		loadingMessage.Color:Lerp(Color.White, Color(255, 255, 255, 40), 1 + math.sin(t * 5))
	end
end

Screen.DidResize = function()
	layout()
end

function loading()
	leaderboard:get({
		userID = "self",
		callback = function(res, err)
			if err == nil then
				highScore = res.score
			end
			updateScore()
			loadSounds()
			load3DModels(function()
				startGame()
				Camera:SetModeFree()
				Camera.FOV = 30
				Camera.Rotation:Set(math.rad(60), 0, 0)
				layout()

				restartButton.onRelease = startGame
				gameOverRestartButton.onRelease = startGame
			end)
		end,
	})
end

function updateScore()
	if score ~= nil then
		score.Text = string.format("%d", currentScore)
	end
	if bestScore ~= nil then
		bestScore.Text = string.format("🏆 %d", highScore)
	end
	layout()
end

-- Game states
function startGame()
	title:hide()
	gameOverMessage:hide()
	gameOverRestartButton:hide()
	leaderboardUI:hide()
	restartButton:show()
	loadingMessage:hide()
	newGame()
end

function newGame()
	clearBoard()
	tiles = createInitialTiles()
	currentScore = 0
	updateScore()
end

function endGame()
	gameOverMessage:show()
	gameOverRestartButton:show()
	leaderboardUI:show()
	restartButton:hide()
	if currentScore > highScore then
		leaderboard:set({
			score = currentScore,
			callback = function(_) -- success
				-- success == true when request is successful
				-- but score is replaced only if bigger than currently stored value.
				leaderboardUI:reload()
			end,
		})
		highScore = currentScore
		updateScore()
	else
		leaderboardUI:reload()
	end
end

function clearBoard()
	clearCheckMoveCache()
	tileMap = resetTileMap()
	if not tiles then
		return
	end
	for _, v in ipairs(tiles) do
		v:RemoveFromParent()
	end
	tiles = {}
end

function resetTileMap()
	local map = {}
	for i = 1, BOARD_SIZE do
		map[i] = {}
		for j = 1, BOARD_SIZE do
			map[i][j] = 0
		end
	end
	return map
end

function createInitialTiles()
	local t = {}
	for _ = 1, TILES_GAMESTART do
		local tile = addRandomTile()
		table.insert(t, tile)
	end
	return t
end

function addRandomTile()
	local tile = false
	while not tile do
		tile = createTile(math.random(BOARD_SIZE), math.random(BOARD_SIZE), math.random(TILES_INITIAL_MAX_POW))
	end
	return tile
end

function createTile(x, z, pow)
	if tileMap[x][z] ~= 0 then
		return false
	end

	local tile = Shape(tileBaseConfig.asset)
	tile.IsHiddenSelf = true
	tile.LocalPosition = Number3(
		board.Width * (BOARD_MARGIN + (TILES_SCALE_RATIO + TILES_MARGIN) * (x - 1 + 0.4)),
		board.Height,
		board.Depth * (BOARD_MARGIN + (TILES_SCALE_RATIO + TILES_MARGIN) * (z - 1 + 0.4))
	)
	tile.Pivot = { 0.5 * tile.Width, 0, 0.5 * tile.Depth }
	tile.Scale = board.Width / tile.Width * TILES_SCALE_RATIO
	tile:SetParent(board)

	tile.pow = pow
	tile.x = x
	tile.z = z

	tile.clear = function(self)
		local idx = contains(tiles, self)
		if idx then
			table.remove(tiles, idx)
		end
		self:RemoveFromParent()
	end

	tile.setModel = function(self)
		if self.model ~= nil then
			self.model:RemoveFromParent()
			self.model = nil
		end
		if tilesConfig[self.pow].model == nil then
			return
		end

		local model = tilesConfig[self.pow].model:Copy({ recurse = true })
		model.LocalPosition.Y = self.Height + 1
		if tilesConfig[self.pow].rotation ~= nil then
			model.LocalRotation:Set(tilesConfig[self.pow].rotation)
		else
			model.LocalRotation:Set(0, math.rad(90), 0)
		end
		model:SetParent(self)

		self.model = model
		self.model:SetParent(self)

		-- Adding a pop-in animation for new models
		ease:cancel(self.model)
		self.model.Scale = Number3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE) * 0.5
		ease:outElastic(self.model, 0.5).Scale = Number3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	end

	tile.update = function(self)
		self.pow = self.pow + 1
		self:setModel()
		if self.model == nil then
			return
		end
		-- Adding a bounce animation on update (merge)
		ease:cancel(self.model)
		self.model.Scale = Number3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE) * 1.2
		ease:outBack(self.model, 0.4).Scale = Number3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	end

	tile.getModelScreenPosition = function(self)
		if self.model == nil then
			return nil
		end
		local coords = Camera:WorldToScreen(self.model.Position)
		if coords == nil then
			return nil
		end
		return coords * Screen.Size
	end

	tile:setModel()
	tileMap[x][z] = pow

	return tile
end

-- Move management
function moveTile(tile, x, z, flagToRemove)
	-- Adding a smooth and bouncy movement animation for tiles
	ease:outBack(tile, 0.3).LocalPosition = Number3(
		board.Width * (BOARD_MARGIN + (TILES_SCALE_RATIO + TILES_MARGIN) * (x - 1 + 0.4)),
		board.Height,
		board.Depth * (BOARD_MARGIN + (TILES_SCALE_RATIO + TILES_MARGIN) * (z - 1 + 0.4))
	)
	tile.x = x
	tile.z = z
	tile.flagToRemove = flagToRemove
end

function clearCheckMoveCache()
	toMove = nil
	toMerge = nil
	newTiles = nil
	direction = nil
end

-- returns true if tiles can move in this direction,
-- setting toMove, toMerge & newTiles variables
function checkMove(x, z)
	local d = Number2(x, z)
	if direction ~= nil and direction == d then
		return newTiles ~= nil
	end
	direction = d

	toMove = {}
	toMerge = {}
	newTiles = {}

	local isLegal = false
	local startIdx, endIdx = 1, BOARD_SIZE
	local step = 1

	if x == 1 or z == 1 then -- invert X scan direction when moving right
		startIdx, endIdx = BOARD_SIZE, 1
		step = -1
	end

	for i = startIdx, endIdx, step do -- Deep copy
		newTiles[i] = {}
		for j = startIdx, endIdx, step do
			newTiles[i][j] = tileMap[i][j] or 0
		end
	end

	local stepX = x and x ~= 0 and step or 0
	local stepZ = z and z ~= 0 and step or 0

	for i = startIdx, endIdx, step do
		for j = startIdx, endIdx, step do
			if newTiles[i][j] and newTiles[i][j] ~= 0 then
				local wasMoved = false
				local wasMerged = false

				for k = 1, 3 do -- checking recursively if can be moved towards the end point
					if newTiles[i - stepX * k][j - stepZ * k] and newTiles[i - stepX * k][j - stepZ * k] == 0 then
						newTiles[i - stepX * k][j - stepZ * k] = newTiles[i - stepX * (k - 1)][j - stepZ * (k - 1)]
						newTiles[i - stepX * (k - 1)][j - stepZ * (k - 1)] = 0
						wasMoved = { x = i, z = j, xNew = i - stepX * k, zNew = j - stepZ * k, savePos = true }
						isLegal = true
					end
				end
				if wasMoved then
					table.insert(toMove, wasMoved)
				end

				for k = 1, 3 do
					if
						i + stepX * k > BOARD_SIZE
						or i + stepX * k < 1
						or j + stepZ * k > BOARD_SIZE
						or j + stepZ * k < 1
					then
						break
					end

					local x = wasMoved and wasMoved.xNew or i
					local z = wasMoved and wasMoved.zNew or j
					local isSamePow = newTiles[i + stepX * k][j + stepZ * k] == newTiles[x][z]
					local neighbourTileExists = newTiles[i + stepX * k][j + stepZ * k] ~= 0

					if neighbourTileExists and isSamePow then
						newTiles[x][z] = newTiles[x][z] + 1
						newTiles[i + stepX * k][j + stepZ * k] = 0
						wasMerged = { x = x, z = z }
						wasMoved = {
							x = i + stepX * k,
							z = j + stepZ * k,
							xNew = x,
							zNew = z,
							flagToRemove = true,
						}
						isLegal = true
						break
					elseif neighbourTileExists then
						break
					end
				end
				if wasMerged then
					table.insert(toMove, wasMoved)
					table.insert(toMerge, wasMerged)
				end
			end
		end
	end

	if not isLegal then
		newTiles = nil
	end
	return isLegal
end

function inputMove(x, z)
	if blockInput then
		return
	end
	if x == 0 and z == 0 or x ~= 0 and z ~= 0 then
		return
	end

	blockInput = true

	if checkMove(x, z) == false then
		blockInput = false
		return
	end

	tileMap = newTiles ~= nil and newTiles or tileMap

	local toMove = toMove
	local toMerge = toMerge

	for _, tile in ipairs(tiles) do
		for _, data in ipairs(toMove) do
			if tile.x == data.x and tile.z == data.z then
				moveTile(tile, data.xNew, data.zNew, data.flagToRemove)
			end
		end
		Timer(0.3, function()
			local highestPow = -1
			for _, data in ipairs(toMerge) do
				if tile.x == data.x and tile.z == data.z then
					if tile.flagToRemove then
						tile:clear()
					else
						tile:update()
						highestPow = math.max(highestPow, tile.pow)
						currentScore = math.floor(currentScore + 2 ^ tile.pow)
						updateScore()
						-- Show score increase indicator at merge position with upward animation
						local scoreIncrease = 2 ^ tile.pow
						local screenPos = tile:getModelScreenPosition()
						if screenPos then
							local indicator = ui:createText("+" .. scoreIncrease, {
								color = Color(100, 255, 100),
								size = "default",
								outline = 0.4,
								outlineColor = Color(50, 100, 50),
							})
							indicator.pos = {
								screenPos.X - indicator.Width * 0.5,
								screenPos.Y - indicator.Height * 0.5,
							}
							Timer(0.2, function()
								ease:outSine(indicator, 1.0).pos = {
									screenPos.X - indicator.Width * 0.5,
									screenPos.Y + indicator.Height * 1.5,
								}
								Timer(0.8, function()
									ease:linear(indicator, 0.5).Color = Color(100, 255, 100, 0)
									Timer(0.5, function()
										indicator:remove()
									end)
								end)
							end)
						end
					end
				end
			end
			if highestPow > 0 then
				if tilesConfig[highestPow].audioSource ~= nil then
					tilesConfig[highestPow].audioSource:Play()
					Client:HapticFeedback()
				end
			end
		end)
	end

	clearCheckMoveCache()

	Timer(0.3, function()
		table.insert(tiles, addRandomTile())
		blockInput = false
		if not checkMove(-1, 0) and not checkMove(1, 0) and not checkMove(0, -1) and not checkMove(0, 1) then
			endGame()
		end
	end)
end
