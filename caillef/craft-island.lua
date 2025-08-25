Modules = {
	-- big bricks
	inventory_module = "github.com/caillef/cubzh-library/inventory:1037602",
	areas_module = "github.com/caillef/cubzh-library/areas:28e70ca",

	-- small bricks
	growth_module = "github.com/caillef/cubzh-library/growth:28e70ca",
	interaction_module = "github.com/caillef/cubzh-library/interaction:28e70ca",
	event_logger_module = "github.com/caillef/cubzh-library/event_logger:28e70ca",
	async_loader = "github.com/caillef/cubzh-library/async_loader:28e70ca",
	block_outline = "github.com/caillef/cubzh-library/block_outline:28e70ca",

	-- game specific
	resources = "github.com/caillef/cubzh-library/game_craft_island/resources:52f1992",
	islands_manager = "github.com/caillef/cubzh-library/game_craft_island/islands_manager:0fbb618",

	ui_blocks = "github.com/caillef/cubzh-library/ui_blocks:09941d5",
}

-- Config
local REACH_DIST = 30
local attackSpeed = 0.3
local SAVE_EVERY = 30 -- seconds

-- Tooltip
local time = 0
local holdLeftClick = false

-- Global
local currentArea

-- Islands
local mainIsland

-- Game
local map
local sneak = false
local selectedResource = nil

local blockMined
local blockKey
local blockStartedMiningAt
local blockSwingTimer

local assets = {}
local assetsByPos = {}

-- Constants
local resourcesByKey = {} -- generated from resources on load before onStart
local resourcesById = {} -- generated from resources on load before onStart

local blackLoadingBg

Client.OnStart = function()
	Map.IsHidden = true
	initAmbience()

	blackLoadingBg = require("uikit"):createFrame(Color.Black)
	blackLoadingBg.parentDidResize = function()
		blackLoadingBg.Width = Screen.Width
		blackLoadingBg.Height = Screen.Height
	end
	blackLoadingBg:parentDidResize()

	LocalEvent:Listen("areas.CurrentArea", function(newCurrentArea)
		currentArea = newCurrentArea
	end)

	LocalEvent:Listen(LocalEvent.Name.AvatarLoaded, function()
		initPlayer()
		if Player.Animations then
			-- remove view bobbing
			Player.Animations.Walk.Duration = 10000
			-- remove idle animation
			Player.Animations.Idle.Duration = 10000
		end
	end)
end

Client.OnWorldObjectLoad = function(obj)
	if not mainIsland then
		mainIsland = Object()
	end
	obj:SetParent(mainIsland)

	require("hierarchyactions"):applyToDescendants(obj, { includeRoot = true }, function(o)
		o.root = obj
	end)

	if obj.Name == "portal" then
		obj.OnCollisionBegin = function(o, p)
			if p ~= Player then return end
			LocalEvent:Send("areas.TeleportTo", "CurrentPlayerIsland")
		end
	elseif obj.Name == "shop_1" then
		interaction_module:addInteraction(obj, "Farmer", function()
			sellerUI = createFarmerUI()
			Pointer:Show()
		end)
	elseif obj.Name == "shop_2" then
		interaction_module:addInteraction(obj, "Merchant", function()
			furnitureUI = createFurnitureUI()
			Pointer:Show()
		end)
	elseif obj.Name == "invisiblewall" then
		obj.IsHidden = true
		obj.Physics = PhysicsMode.StaticPerBlock
	elseif obj.Name == "workbench" then
		interaction_module:addInteraction(obj, "Workbench", function()
			print("interact with workbench")
		end)
	end
end

Client.OnPlayerJoin = function(p)
	if p == Player then
		local listLoadCache = {}
		local texturesList = {}
		local URL = "https://api.voxdream.art/"

		for _,v in ipairs(resources) do
			resourcesByKey[v.key] = v
			resourcesById[v.id] = v

			if v.texture then
				table.insert(texturesList, { name = v.key, url = URL..v.texture })
			end
			if v.fullname then
				table.insert(listLoadCache, function(loadCacheDone)
					Object:Load(v.fullname, function(obj)
						if v.assetTransformer then
							obj = v.assetTransformer(obj)
						end
						v.cachedShape = obj
						resourcesByKey[v.key] = v
						resourcesById[v.id] = v
						loadCacheDone()
					end)
				end)
			end
		end
		
		table.insert(listLoadCache, function(loadCacheDone)
			textureLoader:load(texturesList, function(textures)				
				cachedTextures = textures
				loadCacheDone()
			end)
		end)

		async_loader:start(listLoadCache, function()
			islands_manager:loadIsland(resourcesByKey, resourcesById,
				function(_map, _playerIsland, savedAssets, texturedBlocksList)
					map = _map
					map.Shadow = true
					playerIsland = _playerIsland
					for _,asset in ipairs(savedAssets) do
						local key = resourcesById[asset.id].key
						local pos = Number3(asset.X, asset.Y, asset.Z)
						blockAssetPlacer:placeAsset(key, pos, { force = true })
					end
					for _,block in ipairs(texturedBlocksList) do
						local key = resourcesById[block.id].key
						local pos = Number3(block.X, block.Y, block.Z)
						texturedBlocks:placeBlock(key, pos)
					end
					onStart()
				end
			)
		end)
		return
	end
	p.IsHidden = true
	p.Scale = 0.4
end

function onStart()
	inventory_module:setResources(resourcesByKey, resourcesById)
	require("multi"):action("changeArea", { area = currentArea })

	-- init mandatory inventories
	inventory_module:create("cursor", { width = 1, height = 1, alwaysVisible = true })

	-- init other inventories
	inventory_module:create("mainInventory", { width = 9, height = 3 })
	inventory_module:create("hotbar", { width = 9, height = 1, alwaysVisible = true,
		selector = true,
		uiPos = function(node)
			return { Screen.Width * 0.5 - node.Width * 0.5, require("uitheme").current.padding }
		end
	})

	event_logger_module:log(Player, "sessionsLog", { v = 1, date = Time.Unix() }, function(logs)
		event_logger_module:get(Player, { "sessionsLog", "sessionsEndLog" }, function(data)
			local logs = data.sessionsLog
			local endLogs = data.sessionsEndLog
			if #logs == 1 then
				LocalEvent:Send("eventLoggerEvent", { type = "FirstConnection" })
			end

			if #logs > 1 then
				--print("Time since last connection", logs[#logs].date - endLogs[#endLogs].date)
			else
				print("Welcome on your Island! Ping @caillef on Discord to share your island screenshots")
			end
		end)
	end)

	if Client.IsMobile then
		local ui = require("uikit")
		local invBtn = ui:createButton("🎒")
		invBtn.parentDidResize = function()
			invBtn.pos = { Screen.Width - invBtn.Width - 4, Screen.Height - Screen.SafeArea.Top - invBtn.Height}
		end
		invBtn:parentDidResize()
		invBtn.onRelease = function()
			LocalEvent:Send("InvToggle", { key = "mainInventory" })
		end
	end

	-- Portal
	local asset = blockAssetPlacer:placeAsset("portal", Number3(0,1,8), { force = true })
	asset.skipSave = true
	asset.Scale = asset.Scale.X * 1.1
	asset.OnCollisionBegin = function(o,p)
		if p ~= Player then return end
		LocalEvent:Send("areas.TeleportTo", "MainIsland")
	end

	initAreas()
	initMulti()
	initKeyboardShortcuts()
	initPlayerHand()

	LocalEvent:Send("areas.TeleportTo", "CurrentPlayerIsland")

	LocalEvent:Listen("eventLoggerEvent", function(data)
		if data.type == "FirstConnection" then
			local baseInventory = {
				pickaxe = 1,
				shovel = 1,
				axe = 1,
				hoe = 1,
				wheat_seed = 8,
			}

			for k,v in pairs(baseInventory) do
				LocalEvent:Send("InvAdd", {
					key = "hotbar",
					rKey = k,
					amount = v
				})
			end
		end
	end)

	-- Dev debug because of KVS issue in dev mode
	Timer(2, function()
	if Player.Username == "caillef" then
		local baseInventory = {
			pickaxe = 1,
			shovel = 1,
			axe = 1,
			hoe = 1,
			wheat_seed = 8,
			oak_planks = 20,
		}

		for k,v in pairs(baseInventory) do
			LocalEvent:Send("InvAdd", {
				key = "hotbar",
				rKey = k,
				amount = v
			})
		end
	end
	end)

	-- moneyLeaderboard
	moneyLeaderboardUI = moneyLeaderboardUIModule:create("Money", 5, moneyLeaderboardUIModule.TOP_LEFT)
	Timer(10, true, function()
		moneyLeaderboardModule:sync()
	end)
	moneyLeaderboardModule:sync()
	moneyLeaderboardModule.onSyncLeaderboard = function(scores)
	    for _,v in ipairs(scores) do
	        v.score = math.floor(v.score)
	    end
	    moneyLeaderboardUI:update(scores)
	end

	-- Block outline
	LocalEvent:Listen("block_outline.update", function(data)
		local block = data.block
		if holdLeftClick and blockMined.Position ~= block.Position then
			startMineBlockInFront()
		end
	end)
	block_outline:setShape(map)
	block_outline:setMaxReachDist(REACH_DIST)

	-- Save island
	Timer(SAVE_EVERY, true, function()
		islands_manager:saveIsland(map, assets, texturedBlocks.list)
	end)

	-- End loading
	blackLoadingBg.pos.Z = -500
	Timer(1, function()
		require("crosshair"):show()
		blackLoadingBg:remove()
	end)
end

blockAssetPlacer = {}

blockAssetPlacer.placeAsset = function(_, key, pos, options)
	options = options or {}
	local resource = resourcesByKey[key]
	if not resource or not resource.asset then return false end
	if (not options.growth and not options.force) and resource.canBePlaced == false then return false end

	local asset = Shape(resource.cachedShape, { includeChildren = true })
	asset.Shadow = true

	table.insert(assets, asset)
	assetsByPos[pos.Z] = assetsByPos[pos.Z] or {}
	assetsByPos[pos.Z][pos.Y] = assetsByPos[pos.Z][pos.Y] or {}
	assetsByPos[pos.Z][pos.Y][pos.X] = asset

	asset:SetParent(playerIsland)
	asset.Scale = resource.asset.scale
	asset.Rotation = resource.asset.rotation or Rotation(0,0,0)
	local box = Box()
	box:Fit(asset, true)
	asset.Pivot = Number3(asset.Width / 2, box.Min.Y + asset.Pivot.Y, asset.Depth / 2)
	if resource.asset.pivot then
		asset.Pivot = resource.asset.pivot(asset)
	end
	local worldPos = map:BlockToWorld(pos)
	asset.Position = worldPos + Number3(map.Scale.X * 0.5, 0, map.Scale.Z * 0.5)

	require("hierarchyactions"):applyToDescendants(asset, { includeRoot = true }, function(o)
		o.root = asset
		if resource.asset.physics == false then
			o.Physics = PhysicsMode.TriggerPerBlock
		else
			o.Physics = PhysicsMode.StaticPerBlock
		end
	end)

	-- Custom properties
	asset.info = resource
	asset.mapPos = pos

	asset.hp = resource.asset.hp

	if resource.grow then
		local growthAfter = asset.info.grow.after()
		growth_module:add(asset, growthAfter, function(asset)
			for i=1,#assets do
				if assets[i] == asset then
					table.remove(assets, i)
					break
				end
			end
			local pos = asset.mapPos
			assetsByPos[pos.Z][pos.Y][pos.X] = nil

			asset:RemoveFromParent()
		end, function()
			blockAssetPlacer:placeAsset(resource.grow.asset, pos, { growth = true })
		end)
	end

	return asset
end

blockAssetPlacer.breakAsset = function(_, asset)
	local loot = asset.info.loot or { [asset.info.key] = 1 }

	for key,funcOrNb in pairs(loot) do
		local amount = type(funcOrNb) == "function" and funcOrNb() or funcOrNb
		LocalEvent:Send("InvAdd", { key = "hotbar", rKey = key, amount = amount,
			callback = function(success)
				if success then return end
				LocalEvent:Send("InvAdd", { key = "mainInventory", rKey = key, amount = amount,
					callback = function(success)
						if not success then print("fall on the ground") end
					end
				})
			end
		})
	end

	if asset.info.grow then
		growth_module:remove(asset)
		islands_manager:saveIsland(map, assets, texturedBlocks.list)
		return
	end

	for i=1,#assets do
		if assets[i] == asset then
			table.remove(assets, i)
			break
		end
	end
	local pos = asset.mapPos
	assetsByPos[pos.Z][pos.Y][pos.X] = nil

	asset:RemoveFromParent()

	islands_manager:saveIsland(map, assets, texturedBlocks.list)
end

blockAssetPlacer.canPlaceAssetAt = function(_, pos)
	return assetsByPos[pos.Z][pos.Y][pos.X] == nil
end

blockAssetPlacer.place = function()
	local impact = Camera:CastRay(nil, Player)
	if impact.Object and impact.Object == map then
		if selectedResource.block then
			local color = selectedResource.block.color
			LocalEvent:Send("InvRemove", { key = "hotbar", rKey = selectedResource.key, amount = 1,
				callback = function(success)
					if not success then return end
					local impactBlock = Camera:CastRay(impact.Object)
					impactBlock.Block:AddNeighbor(color, impactBlock.FaceTouched)
					LocalEvent:Send("SwingRight")
					require("sfx")("walk_gravel_"..math.random(5), { Spatialized = false, Volume = 0.3 })
				end
			})
			islands_manager:saveIsland(map, assets, texturedBlocks.list)
			return true
		elseif selectedResource.asset and selectedResource.canBePlaced ~= false then
			local rKey = selectedResource.key
			local impactBlock = Camera:CastRay(impact.Object)
			local pos = impactBlock.Block.Coords:Copy()
			if impact.FaceTouched == Face.Front then
				pos.Z = pos.Z + 1
			elseif impact.FaceTouched == Face.Back then
				pos.Z = pos.Z - 1
			elseif impact.FaceTouched == Face.Top then
				pos.Y = pos.Y + 1
			elseif impact.FaceTouched == Face.Bottom then
				pos.Y = pos.Y - 1
			elseif impact.FaceTouched == Face.Right then
				pos.X = pos.X + 1
			elseif impact.FaceTouched == Face.Left then
				pos.X = pos.X - 1
			end
			local blockUnderneath = resourcesByKey[selectedResource.asset.blockUnderneath]
			if blockUnderneath and blockUnderneath.block.color ~= impactBlock.Block.Color then
				return false
			end
			if not blockAssetPlacer:canPlaceAssetAt(pos) then return end
			LocalEvent:Send("InvRemove", { key = "hotbar", rKey = rKey, amount = 1,
				callback = function(success)
					if not success then return end
					blockAssetPlacer:placeAsset(rKey, pos)
					LocalEvent:Send("SwingRight")
					require("sfx")("walk_wood_"..math.random(5), { Spatialized = false, Volume = 0.3 })
				end
			})
			islands_manager:saveIsland(map, assets, texturedBlocks.list)
			return true
		elseif selectedResource.type == "texturedblock" then
			local rKey = selectedResource.key
			LocalEvent:Send("InvRemove", { key = "hotbar", rKey = selectedResource.key, amount = 1,
				callback = function(success)
					if not success then return end
					local impactBlock = Camera:CastRay(impact.Object)
					local pos = impactBlock.Block.Coords:Copy()
					if impact.FaceTouched == Face.Front then
						pos.Z = pos.Z + 1
					elseif impact.FaceTouched == Face.Back then
						pos.Z = pos.Z - 1
					elseif impact.FaceTouched == Face.Top then
						pos.Y = pos.Y + 1
					elseif impact.FaceTouched == Face.Bottom then
						pos.Y = pos.Y - 1
					elseif impact.FaceTouched == Face.Right then
						pos.X = pos.X + 1
					elseif impact.FaceTouched == Face.Left then
						pos.X = pos.X - 1
					end
					texturedBlocks:placeBlock(rKey, pos)
					islands_manager:saveIsland(map, assets, texturedBlocks.list)
				end
			})
			
		end
	end
end

-- handle left click loop to swing + call "onSwing"

mineModule = {}

local POINTER_INDEX_MOUSE_LEFT = 4

mineModule.init = function(_, actionCallback)
	mineModule.actionCallback = actionCallback
end

LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
	if not holdLeftClick and blockSwingTimer then
		blockSwingTimer:Cancel()
		blockSwingTimer = nil
	end
end)

LocalEvent:Listen(LocalEvent.Name.PointerDown, function(pointerEvent)
	if not Pointer.IsHidden then
		return
	end
	if pointerEvent.Index == POINTER_INDEX_MOUSE_LEFT then
		holdLeftClick = true
		if not mineModule.actionCallback() then
			LocalEvent:Send("SwingRight")
		end
	end
end)

LocalEvent:Listen(LocalEvent.Name.PointerUp, function(pointerEvent)
	if not Pointer.IsHidden then
		return
	end
	if pointerEvent.Index == POINTER_INDEX_MOUSE_LEFT then
		holdLeftClick = false
		blockMined = nil
		blockKey = nil
	end
end, { topPriority = true })

function startMineBlockInFront()
	if not holdLeftClick then return end
	blockMined = nil

	local impact = Camera:CastRay(nil, Player)
	if impact.Object.root and impact.Object.root.info and impact.Distance <= REACH_DIST then
		local obj = impact.Object.root

		if obj.info.canBeDestroyed == false then return end
		obj.hp = obj.hp - 3 -- todo: handle tool

		LocalEvent:Send("SwingRight")
		spawnBreakParticles(Camera.Position + Camera.Forward * impact.Distance, Color.Black)
		require("sfx")("walk_wood_"..math.random(5), { Spatialized = false, Volume = 0.3 })
		if blockSwingTimer then
			blockSwingTimer:Cancel()
		end
		blockSwingTimer = Timer(attackSpeed, true, function()
			local impact = Camera:CastRay(nil, Player)
			if not impact.Object.root.info or impact.Distance > REACH_DIST then return end
			local obj = impact.Object.root
			obj.hp = obj.hp - 3 -- todo: handle tool
			LocalEvent:Send("SwingRight")
			spawnBreakParticles(Camera.Position + Camera.Forward * impact.Distance, Color.Black)
			require("sfx")("walk_wood_"..math.random(5), { Spatialized = false, Volume = 0.3 })
			if obj.hp <= 0 then
				blockSwingTimer:Cancel()
				blockSwingTimer = nil
				blockAssetPlacer:breakAsset(obj)
			end
		end)

		if obj.hp <= 0 then
			blockSwingTimer:Cancel()
			blockSwingTimer = nil
			blockAssetPlacer:breakAsset(obj)
		end
		return
	end

	if not impact.Object or impact.Object ~= map or impact.Distance > REACH_DIST then
		-- cancelBlockMine
		if not blockMined then return end
		blockMined = nil
		blockKey = nil
		if blockSwingTimer then
			blockSwingTimer:Cancel()
			blockSwingTimer = nil
		end
		return
	end
	local impactBlock = Camera:CastRay(impact.Object)
	if not impactBlock or not impactBlock.Block.Color then
		return
	end

	local rKey = nil
	for _,v in ipairs(resources) do
		if v.block and v.block.color == impactBlock.Block.Color then
			rKey = v.key
		end
	end
	if not rKey then
		local b = texturedBlocks.list[impactBlock.Block.Coords.Z][impactBlock.Block.Coords.Y][impactBlock.Block.Coords.X]
		if b then
			rKey = b.rKey
		end
	end
	if not rKey then
		print("Can't find block of color", impactBlock.Block.Color)
		return
	end
	if blockMined and blockMined.Coords == impactBlock.Block.Coords then return end

	blockMined = impactBlock.Block
	blockKey = rKey
	blockStartedMiningAt = time

	if not blockSwingTimer then -- not restarted if holding click to break several blocks
		LocalEvent:Send("SwingRight")
		spawnBreakParticles(Camera.Position + Camera.Forward * impact.Distance, impactBlock.Block.Color)
		require("sfx")("walk_gravel_"..math.random(5), { Spatialized = false, Volume = 0.3 })
		blockSwingTimer = Timer(attackSpeed, true, function()
			local impact = Camera:CastRay(nil, Player)
			if not impact.Object or impact.Object ~= map or impact.Distance > REACH_DIST then return end
			local impactBlock = Camera:CastRay(impact.Object)
			if not impactBlock or not impactBlock.Block.Color then return end
			LocalEvent:Send("SwingRight")
			spawnBreakParticles(Camera.Position + Camera.Forward * impact.Distance, impactBlock.Block.Color)
			require("sfx")("walk_gravel_"..math.random(5), { Spatialized = false, Volume = 0.3 })
		end)
	end

	return true
end

-- Controls

Client.DirectionalPad = function(x,y)
	Player.Motion = (Player.Forward * y + Player.Right * x) * 50 * (sneak and 0.3 or 1)
end

Pointer.Drag = function(pointerEvent)
    local dx = pointerEvent.DX
    local dy = pointerEvent.DY

    Player.LocalRotation = Rotation(0, dx * 0.01, 0) * Player.LocalRotation
    Player.Head.LocalRotation = Rotation(-dy * 0.01, 0, 0) * Player.Head.LocalRotation

    local dpad = require("controls").DirectionalPadValues
    Player.Motion = (Player.Forward * dpad.Y + Player.Right * dpad.X) * 50 * (sneak and 0.3 or 1)
end

Client.AnalogPad = function(dx, dy)
    Player.LocalRotation = Rotation(0, dx * 0.01, 0) * Player.LocalRotation
    Player.Head.LocalRotation = Rotation(-dy * 0.01, 0, 0) * Player.Head.LocalRotation

    local dpad = require("controls").DirectionalPadValues
    Player.Motion = (Player.Forward * dpad.Y + Player.Right * dpad.X) * 50 * (sneak and 0.3 or 1)
end

Client.Action1 = function()
	if Player.IsOnGround then
		Player.Velocity.Y = 75
	end
end

function handleResourceRightClick()
	if selectedResource.key == "hoe" then
		local impact = Camera:CastRay(nil, Player)
		if not impact.Object or impact.Object ~= map then
			return
		end
		local impactBlock = Camera:CastRay(impact.Object)
		if impact.Block.Color ~= resourcesByKey.grass.block.color then
			return
		end
		impactBlock.Block:Replace(resourcesByKey.dirt.block.color)
		LocalEvent:Send("SwingRight")
		require("sfx")("walk_grass_" .. math.random(5), { Spatialized = false, Volume = 0.3 })
		islands_manager:saveIsland(map, assets, texturedBlocks.list)
		return true
	end
end

Client.Action3Release = function()
	if selectedResource.rightClick then
		if handleResourceRightClick() then return end
	end

	if blockAssetPlacer:place() then return end

	if impact.Object and impact.Object.root and impact.Object.root.isInteractable then
		local interactableObject = impact.Object.root -- all subshapes and root have a reference to root
		interactableObject:onInteract()
	end
end

-- Tick

function mine()
	if not blockMined then return end

	local defaultMiningTime = 1.5
	local toolType = Player.currentTool.tool.type
	local blockType = resourcesByKey[blockKey].miningType
	local multiplier = 1
	if toolType and toolType == blockType then
		multiplier = 0.5
	end
	local currentMiningTime = defaultMiningTime * multiplier
	if  time - blockStartedMiningAt >= currentMiningTime then
		blockMined:Remove()
		local texturedBlock = texturedBlocks.list[blockMined.Coords.Z][blockMined.Coords.Y][blockMined.Coords.X]
		if texturedBlock then
			texturedBlock:remove()
		end

		local rKey = blockKey
		LocalEvent:Send("InvAdd", { key = "hotbar", rKey = rKey, amount = 1,
			callback = function(success)
				if success then return end
				LocalEvent:Send("InvAdd", { key = "mainInventory", rKey = rKey, amount = 1,
					callback = function(success)
						if not success then print("fall on the ground") return end
					end
				})
			end
		})

		islands_manager:saveIsland(map, assets, texturedBlocks.list)
		startMineBlockInFront()
	end
end

Client.Tick = function(dt)
	if not map then return end
	time = time + dt

	if holdLeftClick then
		mine()
	end
end

-- Particles

function spawnBreakParticles(pos, color)
	local breakParticlesEmitter = require("particles"):newEmitter({
		velocity = function() return Number3((math.random() * 2 - 1) * 10, math.random(15), (math.random() * 2 - 1) * 10) end,
		position = pos,
		scale = 0.5,
		color = Color(math.floor(color.R * 0.8), math.floor(color.G * 0.8), math.floor(color.B * 0.8)),
		life = 2,
	})
	breakParticlesEmitter:spawn(10)
end

-- Server

Server.OnPlayerLeave = function(p)
	local eventLogger = {}
	eventLogger.log = function(_, player, eventName, eventData, callback)
		local store = KeyValueStore("eventlogger")
		store:Get(player.UserID, function(success, results)
			if not success then
				print("warning: Can't access event logger")
				return
			end
			local data = results[player.UserID] or {}
			data[eventName] = data[eventName] or {}
			table.insert(data[eventName], eventData)
			store:Set(player.UserID, data, function(success)
				if not success then
					error("Can't access event logger")
				end
				if not callback then
					return
				end
				callback(data[eventName])
			end)
		end)
	end
	eventLogger:log(p, "sessionsEndLog", { v = 1, date = Time.Unix() })
end

-- Init

function initAreas()
	LocalEvent:Send("areas.AddArea", {
		name = "MainIsland",
		getSpawnPosition = Number3(250,15,888),
		getSpawnRotation = 2.38,
		show = function()
			Map.IsHidden = false
			mainIsland:SetParent(World)
		end,
		hide = function()
			Map.IsHidden = true
			mainIsland:SetParent(nil)
		end,
		getName = function()
			return "MainIsland"
		end
	})

	LocalEvent:Send("areas.AddArea", {
		name = "CurrentPlayerIsland",
		getSpawnPosition = function() return map.Position + Number3(5,1,7 * map.Scale.Z) end,
		getSpawnRotation = math.pi,
		show = function()
			map:SetParent(World)
			playerIsland:SetParent(World)
		end,
		hide = function()
			map:SetParent(nil)
			playerIsland:SetParent(nil)
		end,
		getName = function()
			return "Player" .. Player.UserID .. Player.ID
		end
	})
end

function initPlayer()
	Player:SetParent(World)
	Camera.FOV = 80
	require("object_skills").addStepClimbing(Player, { mapScale = 6 })
	Camera:SetModeFirstPerson()
	if Player.EyeLidRight then
		Player.EyeLidRight:RemoveFromParent()
		Player.EyeLidLeft:RemoveFromParent()
	end

	mineModule:init(startMineBlockInFront)
end

function initMulti()
	multi = require("multi")
	multi:onAction("changeArea", function(sender, data)
		sender.IsHidden = data.area ~= currentArea
		sender.area = data.area
	end)
end

function initAmbience()
	require("ambience"):set({
		sky = {
			skyColor = Color(255,110,76),
			horizonColor = Color(255,174,102),
			abyssColor = Color(24,113,255),
			lightColor = Color(229,183,209),
			lightIntensity = 0.600000,
		},
		fog = {
			color = Color(229,129,90),
			near = 300,
			far = 700,
			lightAbsorbtion = 0.400000,
		},
		sun = {
			color = Color(255,163,127),
			intensity = 1.000000,
			rotation = Number3(0.624828, 2.111841, 0.000000),
		},
		ambient = {
			skyLightFactor = 0.100000,
			dirLightFactor = 0.200000,
		}
	})
end

function initPlayerHand()
	local handPreviewObj = Object()
	handPreviewObj:SetParent(Camera)
	handPreviewObj.LocalPosition = { 7, -7, 5 }
	handPreviewObj.LocalRotation = {math.pi * 0.4, 0, math.pi * 0.05}
	LocalEvent:Listen("SwingRight", function()
		handPreviewObj.LocalRotation = {math.pi * 0.4, 0, math.pi * 0.05}
		local ease = require("ease")
		ease:outBack(handPreviewObj.LocalRotation, 0.2).X = math.pi * 0.5
		Timer(0.2, function()
			ease:outBack(handPreviewObj.LocalRotation, 0.2).X = math.pi * 0.4
		end)
	end)

	local handPreview = MutableShape()
	handPreview.Physics = PhysicsMode.Disabled
	handPreview:AddBlock(Color(229,146,61),0,0,0)
	handPreview.Pivot = { 0.5, 0, 0.5 }
	handPreview:SetParent(handPreviewObj)
	handPreview.Scale = { 2, 4, 2 }

	LocalEvent:Listen("invSelect(hotbar)", function(slot)
		local resource = slot.key and resourcesByKey[slot.key] or nil

		if handPreviewObj.shape then
			handPreviewObj.shape:RemoveFromParent()
			handPreviewObj.shape = nil
		end

		Player.currentTool = nil

		selectedResource = resource
		if not resource then
			return
		end
		if resource.tool then
			local rTool = resource.tool
			Player.currentTool = resource
			local tool = Shape(resource.cachedShape, { includeChildren = true })
			tool:SetParent(handPreviewObj)
			require("hierarchyactions"):applyToDescendants(tool, { includeRoot = true }, function(o)
				o.Physics = PhysicsMode.Disabled
			end)
			tool.LocalPosition = rTool.hand.pos
			tool.LocalRotation = rTool.hand.rotation
			tool.Scale = tool.Scale * rTool.hand.scale
			handPreviewObj.shape = tool
		elseif resource.block then
			local b = MutableShape()
			b.Physics = PhysicsMode.Disabled
			b:AddBlock(resource.block.color,0,0,0)
			b:SetParent(handPreviewObj)
			b.Pivot = { 0.5,0.5,0.5 }
			b.Scale = 3
			b.LocalPosition = { 0, 4, 0 }
			b.LocalRotation = { math.pi * 0.1, math.pi * 0.25, 0 }
			handPreviewObj.shape = b
		end
	end)
end

function initKeyboardShortcuts()
	LocalEvent:Listen(LocalEvent.Name.KeyboardInput, function(char, keycode, modifiers, down)
		if keycode == 0 then
			if modifiers & 4 > 0 then -- shift
				if not inventory_module.uiOpened then
					Camera.LocalPosition.Y = down and -5 or 0
				end
				sneak = down
			end
		end
		if char == "e" and down then
			LocalEvent:Send("InvToggle", { key = "mainInventory" })
		end
	end)
end

-- Leaderboard


moneyLeaderboardModule = {}
moneyLeaderboardModuleMetatable = {
	__index = {
		sync = function(self)
			local store = KeyValueStore("mlb_leaderboard")
			store:Get("scores", function(success, results)
				local scores = results.scores or {}
				if self.onSyncLeaderboard then
					self.onSyncLeaderboard(self:_sortScores(scores))
				end
			end)
		end,
		onPlayerJoin = function(self)
			self:sync()
		end,
		setScore = function(self, score)
			local store = KeyValueStore("mlb_leaderboard")
			store:Get("scores", function(success, results)
			    if not success then print("Error: can't access leaderboard") return end
				local scores = results.scores or {}
				scores[Player.UserID] = { username = Player.Username, score = score }
				store:Set("scores", scores, function()
					if self.onSyncLeaderboard then
						self.onSyncLeaderboard(self:_sortScores(scores))
					end
				end)
			end)
		end,
		_sortScores = function(self, scores)
			local sortedScores = {}
			for _, info in pairs(scores) do
				table.insert(sortedScores, info)
			end
			table.sort(sortedScores, function(a, b)
				return a.score > b.score
			end)
			return sortedScores
		end,
	}
}
setmetatable(moneyLeaderboardModule, moneyLeaderboardModuleMetatable)

if type(Client.IsMobile) == "boolean" then -- only for client
	LocalEvent:Listen(LocalEvent.Name.OnPlayerJoin, function(p)
		moneyLeaderboardModule:onPlayerJoin(p)
	end)
end

moneyLeaderboardUIModule = {}
local moneyLeaderboardUIModuleMetatable = {
	__index = {
		TOP_LEFT = 1,
		TOP_RIGHT = 2,
		create = function(self, title, nbScores, anchor)
			local ui = require("uikit")
			local anchor = anchor or self.TOP_LEFT
			local nbScores = nbScores or 5

			local bg = ui:createFrame(Color(0.0,0.0,0.0,0.5))

			local title = ui:createText(title or "Money")
			title:setParent(bg)
			title.object.Color = Color.White
			title.object.Anchor = { 0.5, 0.5}
			title.LocalPosition.Z = -1

			local entries = {}
			for i=1,nbScores do
				local entry = ui:createFrame()
				entry:setParent(bg)
				table.insert(entries, entry)

				local name = ui:createText("")
				entry.name = name
				name:setParent(entry)
				name.object.Color = Color.White
				name.object.Anchor = { 0, 0.5 }
				name.LocalPosition.Z = -1

				local score = ui:createText("")
				entry.score = score
				score:setParent(entry)
				score.object.Color = Color.White
				score.object.Anchor = { 1, 0.5 }
				score.LocalPosition.Z = -1
			end

			bg.parentDidResize = function()
				local width = math.max(225, title.Width + 10)
				bg.Width = width

				local height = title.Height + 6
				for k,e in ipairs(entries) do
					e.Width = width
					e.Height = e.name.Height + 6
					height = height + e.Height

					e.LocalPosition.Y = (nbScores - k) * e.Height
					e.name.LocalPosition = Number3(5, e.Height / 2, 0)
					e.score.LocalPosition = Number3(e.Width - 5, e.Height / 2, 0)
				end
				bg.Height = height
				title.LocalPosition = Number3(width / 2, height - title.Height / 2 - 3, 0)

				local posX = 0
				if anchor == self.TOP_RIGHT then
					posX = Screen.Width - bg.Width
				end
				bg.LocalPosition = Number3(posX, Screen.Height - bg.Height - Screen.SafeArea.Top, 0)
			end
			bg:parentDidResize()

			bg.update = function(bg, list)
				for k,entry in ipairs(entries) do
					local data = list[k]
					local name = data.username or ""
					local score = data.score or ""
					if #name > 15 then
						name = string.sub(name,1,12).."..."
					end
					entry.name.object.Text = name
					entry.score.object.Text = tostring(score)
				end
			end

			return bg
		end
	}
}
setmetatable(moneyLeaderboardUIModule,moneyLeaderboardUIModuleMetatable)

cachedTextures = {}
--[[
	USAGE
	local texturesList = {
		{ name = "wall", url = "" },
		{ name = "ground", url = "" },
		{ name = "goblin_1", url = "" },
		{ name = "goblin_2", url = "" }
	}
	textureLoader:load(texturesList, function (listOfTextures) end)
--]]
textureLoader = {}
textureLoader.load = function(_, list, onDone)
	local nbList = #list
	local nbLoaded = 0
	local textures = {}
	for _,v in ipairs(list) do
		HTTP:Get(v.url, function(res)
			textures[v.name] = res.Body
			nbLoaded = nbLoaded + 1
			if nbLoaded >= nbList then
				onDone(textures)
			end
		end)
	end
end



money = {
	amount = 0,
	uiNode = nil
}

money.updateUI = function(self)
	if not self.uiNode then
		self.uiNode = require("uikit"):createText("0 💰", Color.White, "big")
		ui_blocks:anchorNode(self.uiNode, "right", "top", 15)
	end
	self.uiNode.Text = string.format("%d 💰", self.amount)
	self.uiNode:parentDidResize()
end

money.sync = function(self)
	local moneyStore = KeyValueStore("money")
	moneyStore:Get(Player.UserID, function(success, results)
		self.amount = results[Player.UserID] or 0
		self:updateUI()
	end)
end

LocalEvent:Listen(LocalEvent.Name.OnPlayerJoin, function(p)
	if p ~= Player then return end
	money:sync()
end)

local setMoneyKvsRequest
money.add = function(self, amount)
	if amount <= 0 then return end
	self.amount = self.amount + amount
	self:updateUI()

	moneyLeaderboardModule:setScore(self.amount)

	local moneyStore = KeyValueStore("money")
	if setMoneyKvsRequest then setMoneyKvsRequest:Cancel() end
	setMoneyKvsRequest = moneyStore:Set(Player.UserID, self.amount, function(success)
		setMoneyKvsRequest = nil
		if not success then return print("Can't save coins") end
	end)
end

money.remove = function(self, amount)
	if amount <= 0 then return end
	if amount > self.amount then return error("Not enough coins") end
	self.amount = self.amount - amount
	self:updateUI()

	moneyLeaderboardModule:setScore(self.amount)

	local moneyStore = KeyValueStore("money")
	if setMoneyKvsRequest then setMoneyKvsRequest:Cancel() end
	setMoneyKvsRequest = moneyStore:Set(Player.UserID, self.amount, function(success)
		setMoneyKvsRequest = nil
		if not success then return print("Can't save coins") end
	end)
end



createFarmerUI = function()
	local ui = require("uikit")

	local node

	local title = ui:createText("Merchant", Color.White, "small")
	local closeBtn = ui:createButton("X")
	closeBtn.onRelease = function()
		node:remove()
		Pointer:Show()
	end

	local topBar = ui_blocks:createBlock({
		height = function() return closeBtn.Height end,
		triptych = {
	        dir = "horizontal",
	        color = Color(0,0,0,0.5),
			center = title,
			right = closeBtn,
	    },
	    parentDidResize = function(node)
	        closeBtn.Width = closeBtn.Height
	    end,
	})

	local contentFrame = ui:createFrame()
	contentFrame.parentDidResize = function(node)
		node.Width = node.parent.Width - 8
		node.Height = node.parent.Height - topBar.Height - 8
	end

	local rows = {}
	local resourcesInfo = {
		{ name = "Wheat", price = 3, rKey = "wheat" },
		{ name = "Oak Log", price = 6, rKey = "oak_log" },
	}

	local imageFrame = ui:createFrame(Color(0,0,0,0.8))
	local name = ui:createText("Name", Color.White)

	local qty = ui:createText("You have 0 wheats", Color.White)
	local sellPrice = ui:createText("0 💰", Color.White)

	local selectedResource
	local selectResource

	local loadLine = function(index)
		local info = resourcesInfo[index]
		if not info then return end

		local icon = ui:createShape(Shape(resourcesByKey[info.rKey].cachedShape), { spherized = true })
		icon:setParent(node)
		icon.Size = 92
		icon.pivot.LocalRotation = resourcesByKey[info.rKey].icon.rotation

		local node = ui_blocks:createBlock({
			height = function() return 100 end,
			triptych = {
				color = Color.Grey,
				left = ui_blocks:createLineContainer({
					nodes = {
						{ type = "gap" },
						icon,
						{ type = "gap" },
						ui:createText(info.name)
					}
				}),
				right = ui:createText(string.format("%d 💰 ", info.price))
			}
		})
		node.onRelease = function()
			selectResource(info)
		end

		return node
	end

	local unloadLine = function(cell)
		cell:remove()
	end

	local config = {
		cellPadding = 4,
		loadCell = loadLine,
		unloadCell = unloadLine,
		uikit = uikit or require("uikit"),
	}

	local scrollArea = ui:createScrollArea(Color(0,0,0,0.5), config)
	scrollArea.parentDidResize = function()
		scrollArea.Width = scrollArea.parent.Width
		scrollArea.Height = scrollArea.parent.Height
	end

	local sell1Btn = ui:createButton("x1")
	sell1Btn.onRelease = function()
		LocalEvent:Send("InvRemoveGlobal", {
			keys = { "hotbar", "mainInventory" }, rKey = selectedResource.rKey, amount = 1, callback = function(success)
				if not success then return print("Not enough resources") end	
				print("Sold x1", selectedResource.rKey)
				money:add(selectedResource.price)
				selectResource(selectedResource)
			end
		})
	end
	local sell5Btn = ui:createButton("x5")
	sell5Btn.onRelease = function()
		LocalEvent:Send("InvRemoveGlobal", {
			keys = { "hotbar", "mainInventory" }, rKey = selectedResource.rKey, amount = 5, callback = function(success)
				if not success then return print("Not enough resources") end	
				print("Sold x5", selectedResource.rKey)
				money:add(selectedResource.price * 5)
				selectResource(selectedResource)
			end
		})
	end

	local sellAllBtn = ui:createButton("All")
	sellAllBtn.onRelease = function()
		LocalEvent:Send("InvGetQuantity", { rKey = selectedResource.rKey, keys = { "hotbar", "mainInventory" },
			callback = function(quantities)
				local amount = quantities.total
				if amount <= 0 then
					print("Not enough resources")
					return
				end
				LocalEvent:Send("InvRemoveGlobal", {
					keys = { "hotbar", "mainInventory" }, rKey = selectedResource.rKey, amount = amount, callback = function(success)
						if not success then return end
						money:add(selectedResource.price * amount)
						print(string.format("Sold x%d %s", amount, selectedResource.rKey))
						selectResource(selectedResource)
					end
				})
			end
		})
	end

	local topContainer = ui_blocks:createLineContainer({
		dir = "vertical",
		nodes = {
			imageFrame,
			{ type = "gap" },
			name
		}
	})

	local bottomContainer = ui_blocks:createLineContainer({
		dir = "vertical",
		nodes = {
			qty, { type = "gap" }, { type = "gap" },
			sellPrice, { type = "gap" }, { type = "gap" },
			ui_blocks:createBlock({
				width = function(node) return node.parent.Width end,
				height = function(node) return sell1Btn.Height end,
				triptych = {
					left = ui:createText("Sell", Color.White, "big"),
					right = ui_blocks:createLineContainer({
						dir = "horizontal",
						nodes = {
							sell1Btn, sell5Btn, sellAllBtn
						}
					})
				}
			}),
		},
	})

	local buyFrame = ui_blocks:createBlock({
		pos = function() return { 4, 0 } end,
		triptych = {
			color = Color(0,0,0,0.5),
			dir = "vertical",
			top = topContainer,
			bottom = bottomContainer
		},
		parentDidResize = function(node)
			imageFrame.Size = node.Width * 0.75
		end
	})

	selectResource = function(info)
		selectedResource = info
		name.Text = info.name
		name.pos.X = name.parent.Width * 0.5 - name.Width * 0.5
		sellPrice.Text = string.format("%d 💰", info.price)
		if imageFrame.imageIcon then imageFrame.imageIcon:remove() end
		imageFrame.imageIcon = ui:createShape(Shape(resourcesByKey[info.rKey].cachedShape), { spherized = true })
		imageFrame.imageIcon:setParent(imageFrame)
		imageFrame.imageIcon.pos = resourcesByKey[info.rKey].icon.pos
		imageFrame.imageIcon.Size = imageFrame.Width
		imageFrame.imageIcon.pivot.LocalRotation = resourcesByKey[info.rKey].icon.rotation
		LocalEvent:Send("InvGetQuantity", { rKey = info.rKey, keys = { "hotbar", "mainInventory" },
			callback = function(quantities)
				qty.Text = string.format("You have x%d %s%s", quantities.total, info.name, quantities.total > 1 and "s" or "")
				qty.pos.X = qty.parent.Width * 0.5 - qty.Width * 0.5
			end
		})
	end

	local content = ui_blocks:createBlock({
		width = function(node) return node.parent and node.parent.Width - 8 or 0 end,
		pos = function() return { 4, 4 } end,
		columns = {
			scrollArea,
			buyFrame
		}
	})
	content:setParent(contentFrame)

	node = ui_blocks:createBlock({
		width = function() return math.min(Screen.Width * 0.9,700) end,
		height = function() return math.min(Screen.Height * 0.8,500) end,
		pos = function(node)
			return {
				Screen.Width * 0.5 - node.Width * 0.5,
				Screen.Height * 0.5 - node.Height * 0.5
			}
		end,
		triptych = {
	        dir = "vertical",
	        color = Color(0,0,0,0.5),
			top = topBar,
			bottom = contentFrame
	    },
	})

	selectResource(resourcesInfo[1])

	return node
end

createFurnitureUI = function()
	local ui = require("uikit")

	local node

	local title = ui:createText("Furniture", Color.White, "small")
	local closeBtn = ui:createButton("X")
	closeBtn.onRelease = function()
		node:remove()
		Pointer:Show()
	end

	local topBar = ui_blocks:createBlock({
		height = function() return closeBtn.Height end,
		triptych = {
	        dir = "horizontal",
	        color = Color(0,0,0,0.5),
			center = title,
			right = closeBtn,
	    },
	    parentDidResize = function(node)
	        closeBtn.Width = closeBtn.Height
	    end,
	})

	local contentFrame = ui:createFrame()
	contentFrame.parentDidResize = function(node)
		node.Width = node.parent.Width - 8
		node.Height = node.parent.Height - topBar.Height - 8
	end

	local rows = {}
	local resourcesInfo = {
		{ name = "Wheat seed", price = 20, rKey = "wheat_seed" },
		{ name = "Sapling", price = 40, rKey = "oak_sapling" },
	}

	local imageFrame = ui:createFrame(Color(0,0,0,0.8))
	local name = ui:createText("Name", Color.White)

	local buyPrice = ui:createText("0 💰", Color.White)

	local selectedResource
	local selectResource

	local loading = true
	local loadLine = function(index)
		local info = resourcesInfo[index]
		if not info then return end

		local icon = ui:createShape(Shape(resourcesByKey[info.rKey].cachedShape, { includeChildren = true }), { spherized = true })
		icon:setParent(node)
		icon.Size = 92
		icon.pivot.LocalRotation = resourcesByKey[info.rKey].icon.rotation

		local node = ui_blocks:createBlock({
			height = function() return 100 end,
			triptych = {
				color = Color.Grey,
				left = ui_blocks:createLineContainer({
					nodes = {
						{ type = "gap" },
						icon,
						{ type = "gap" },
						ui:createText(info.name)
					}
				}),
				right = ui:createText(string.format("%d 💰 ", info.price))
			}
		})
		node.onRelease = function()
			selectResource(info)
		end

		return node
	end

	local unloadLine = function(cell)
		cell:remove()
	end

	local config = {
		cellPadding = 4,
		loadCell = loadLine,
		unloadCell = unloadLine,
		uikit = uikit or require("uikit"),
	}

	local scrollArea = ui:createScrollArea(Color(0,0,0,0.5), config)
	scrollArea.parentDidResize = function()
		scrollArea.Width = scrollArea.parent.Width
		scrollArea.Height = scrollArea.parent.Height
	end

	local buy1Btn = ui:createButton("x1")
	buy1Btn.onRelease = function()
		if money.amount < selectedResource.price then return end
		LocalEvent:Send("InvAddGlobal", {
			keys = { "hotbar", "mainInventory" }, rKey = selectedResource.rKey, amount = 1, callback = function(success)
				if not success then return end
				money:remove(selectedResource.price)
				print(string.format("Bought x1 %s", selectedResource.rKey))
				selectResource(selectedResource)
			end
		})
	end
	local buy5Btn = ui:createButton("x5")
	buy5Btn.onRelease = function()
		if money.amount < selectedResource.price * 5 then return end
		LocalEvent:Send("InvAddGlobal", {
			keys = { "hotbar", "mainInventory" }, rKey = selectedResource.rKey, amount = 5, callback = function(success)
				if not success then return end
				money:remove(selectedResource.price * 5)
				print(string.format("Bought x5 %s", selectedResource.rKey))
				selectResource(selectedResource)
			end
		})
	end

	local topContainer = ui_blocks:createLineContainer({
		dir = "vertical",
		nodes = {
			imageFrame,
			{ type = "gap" },
			name
		}
	})

	local bottomContainer = ui_blocks:createLineContainer({
		dir = "vertical",
		nodes = {
			buyPrice, { type = "gap" }, { type = "gap" },
			ui_blocks:createBlock({
				width = function(node) return node.parent.Width end,
				height = function(node) return sell1Btn.Height end,
				triptych = {
					dir = "horizontal",
					left = ui:createText("Buy", Color.White, "big"),
					right = ui_blocks:createLineContainer({
						dir = "horizontal",
						nodes = {
							sell1Btn, sell5Btn
						}
					})
				}
			}),
		},
	})

	local buyFrame = ui_blocks:createBlock({
		pos = function() return { 4, 4 } end,
		triptych = {
			color = Color(0,0,0,0.5),
			dir = "vertical",
			top = topContainer,
			bottom = bottomContainer
		},
		parentDidResize = function(node)
			imageFrame.Size = node.Width * 0.75
		end
	})

	selectResource = function(info)
		selectedResource = info
		name.Text = info.name
		name.pos.X = name.parent.Width * 0.5 - name.Width * 0.5
		buyPrice.Text = string.format("%d 💰", info.price)
		if imageFrame.imageIcon then imageFrame.imageIcon:remove() end
		imageFrame.imageIcon = ui:createShape(Shape(resourcesByKey[info.rKey].cachedShape, { includeChildren = true }), { spherized = true })
		imageFrame.imageIcon:setParent(imageFrame)
		imageFrame.imageIcon.pos = resourcesByKey[info.rKey].icon.pos
		imageFrame.imageIcon.Size = imageFrame.Width
		imageFrame.imageIcon.pivot.LocalRotation = resourcesByKey[info.rKey].icon.rotation
	end

	local content = ui_blocks:createBlock({
		width = function(node) return node.parent and node.parent.Width - 4 or 0 end,
		pos = function() return { 4, 4 } end,
		columns = {
			scrollArea,
			buyFrame
		}
	})
	content:setParent(contentFrame)

	node = ui_blocks:createBlock({
		width = function() return math.min(Screen.Width * 0.9,700) end,
		height = function() return math.min(Screen.Height * 0.8,500) end,
		pos = function(node)
			return {
				Screen.Width * 0.5 - node.Width * 0.5,
				Screen.Height * 0.5 - node.Height * 0.5
			}
		end,
		triptych = {
	        dir = "vertical",
	        color = Color(0,0,0,0.5),
			top = topBar,
			bottom = contentFrame
	    },
	})

	return node
end

texturedBlocks = {
	list = {},
	blocksCache = {} --TODO: save obj and duplicate them
}
texturedBlocks.placeBlock = function(self, rKey, pos)
	local obj = Object()
	local facesConfig = {
		{
			offset = Number3(1,0,0),
			rotation = Number3(0,0,0),
			anchor = { 1, 1 }
		},
		{
			offset = Number3(0,0,0),
			rotation = Number3(0,math.pi * 0.5,0),
			anchor = { 1, 1 }
		},
		{
			offset = Number3(1,0,1),
			rotation = Number3(0,-math.pi * 0.5,0),
			anchor = { 1, 1 }
		},
		{
			offset = Number3(0,0,1),
			rotation = Number3(0,math.pi,0),
			anchor = { 1, 1 }
		},
		{
			offset = Number3(0,0,0),
			rotation = Number3(math.pi * 0.5,0,0),
			anchor = { 0, 0 }
		},
		{
			offset = Number3(0,-1,0),
			rotation = Number3(-math.pi * 0.5,0,0),
			anchor = { 0, 1 }
		}
	}
	for _,faceConfig in ipairs(facesConfig) do
		local qleft = Quad()
		qleft.Image = cachedTextures[rKey]
		qleft:SetParent(obj)
		qleft.LocalPosition = faceConfig.offset
		qleft.Rotation = faceConfig.rotation
		qleft.IsDoubleSided = false
		qleft.Anchor = faceConfig.anchor
		qleft.Shadow = true
	end
	obj.CollisionBox = Box(Number3(0,-1,0), Number3(1,0,1))
	obj:SetParent(World)
	obj.Scale = map.Scale
	obj.Physics = PhysicsMode.Disabled
	obj.Position = pos * map.Scale.X
	obj.rKey = rKey
	self.list[pos.Z] = self.list[pos.Z] or {}
	self.list[pos.Z][pos.Y] = self.list[pos.Z][pos.Y] or {}
	self.list[pos.Z][pos.Y][pos.X] = obj

	obj.remove = function(obj)
		self.list[pos.Z][pos.Y][pos.X] = nil
		obj:RemoveFromParent()
	end

	map:AddBlock(Color(0,0,0,0), pos)

	return obj
end
