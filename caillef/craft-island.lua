Modules = {
	interaction_module = "github.com/caillef/cubzh-library/interaction:c5ef4cb",
	inventory_module = "github.com/caillef/cubzh-library/inventory:c5ef4cb",
	event_logger_module = "github.com/caillef/cubzh-library/event_logger:b9fbc36",
	areas_module = "github.com/caillef/cubzh-library/areas:320eb91",
	growth_module = "github.com/caillef/cubzh-library/growth:fdee71d",
	resources = "github.com/caillef/cubzh-library/craft_island_resources:828e343",
	bit_writer = "github.com/caillef/cubzh-library/bitwriter:76e9b17",
	async_loader = "github.com/caillef/cubzh-library/async_loader:73435e4",
	block_outline = "github.com/caillef/cubzh-library/block_outline:3d85927",
}

-- Config
local REACH_DIST = 30
local attackSpeed = 0.3
local CANCEL_SAVE_SECONDS_INTERVAL = 3
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

Client.OnStart = function()
	Map.IsHidden = true
	initAmbience()

	LocalEvent:Listen("areas.CurrentArea", function(newCurrentArea)
		currentArea = newCurrentArea
	end)

	LocalEvent:Listen(LocalEvent.Name.AvatarLoaded, function()
		initPlayer()
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
			print("interact with farmer")
		end)
	elseif obj.Name == "shop_2" then
		interaction_module:addInteraction(obj, "Baker", function()
			print("interact with baker")
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
		for _,v in ipairs(resources) do
			resourcesByKey[v.key] = v
			resourcesById[v.id] = v

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
		async_loader:start(listLoadCache, function()
			loadIsland(onStart)
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
		invBtn.onRelease = function()
			LocalEvent:Send("InvToggle", { key = "mainInventory" })
		end
	end


	-- Portal
	local asset = blockAssetPlacer:placeAsset("portal", Number3(0,1,8), { force = true })
	asset.skipSave = true
	asset.OnCollisionBegin = function(o,p)
		if p ~= Player then return end
		LocalEvent:Send("areas.TeleportTo", "MainIsland")
	end

	--[[
	blockAssetPlacer:placeAsset("oak_tree",Number3(5,1,5), { force = true })
	blockAssetPlacer:placeAsset("oak_sapling",Number3(-5,1,5))

	map:GetBlock(-5,0,-4):Replace(resourcesByKey.dirt.block.color)
	blockAssetPlacer:placeAsset("wheat_seed",Number3(-5,1,-4))
	map:GetBlock(-5,0,-5):Replace(resourcesByKey.dirt.block.color)
	blockAssetPlacer:placeAsset("wheat_seed",Number3(-5,1,-5))
	map:GetBlock(-5,0,-6):Replace(resourcesByKey.dirt.block.color)
	blockAssetPlacer:placeAsset("wheat_seed",Number3(-5,1,-6))
	map:GetBlock(-4,0,-4):Replace(resourcesByKey.dirt.block.color)
	blockAssetPlacer:placeAsset("wheat_seed",Number3(-4,1,-4))
	map:GetBlock(-4,0,-5):Replace(resourcesByKey.dirt.block.color)
	blockAssetPlacer:placeAsset("wheat_seed",Number3(-4,1,-5))
	map:GetBlock(-4,0,-6):Replace(resourcesByKey.dirt.block.color)
	map:GetBlock(-3,0,-4):Replace(resourcesByKey.dirt.block.color)
	map:GetBlock(-3,0,-5):Replace(resourcesByKey.dirt.block.color)
	map:GetBlock(-3,0,-6):Replace(resourcesByKey.dirt.block.color)
	--]]

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

	LocalEvent:Listen("block_outline.update", function(data)
		local block = data.block
		if holdLeftClick and blockMined.Position ~= block.Position then
			startMineBlockInFront()
		end
	end)
	block_outline:setShape(map)
	block_outline:setMaxReachDist(REACH_DIST)

	Timer(SAVE_EVERY, true, function()
		craftIslandSave:saveIsland()
	end)
end

blockAssetPlacer = {}

blockAssetPlacer.placeAsset = function(_, key, pos, options)
	options = options or {}
	local resource = resourcesByKey[key]
	if not resource or not resource.asset then return false end
	if (not options.growth and not options.force) and resource.canBePlaced == false then return false end

	local asset = Shape(resource.cachedShape, { includeChildren = true })

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
		craftIslandSave:saveIsland()
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

	craftIslandSave:saveIsland()
end

blockAssetPlacer.canPlaceAssetAt = function(_, pos)
	return assetsByPos[pos.Z][pos.Y][pos.X] == nil
end

-- handle left click loop to swing + call "onSwing"

mineModule = {}

local POINTER_INDEX_MOUSE_LEFT = 4

mineModule.init = function(_, actionCallback)
	mineModule.actionCallback = actionCallback
end

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
		if blockSwingTimer then
			blockSwingTimer:Cancel()
			blockSwingTimer = nil
		end
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
	if not rKey then print("Can't find block of color", impactBlock.Block.Color) return end
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
		craftIslandSave:saveIsland()
		return true
	end
end

Client.Action3Release = function()
	if selectedResource.rightClick then
		if handleResourceRightClick() then return end
	end
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
			craftIslandSave:saveIsland()
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
				return
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
			craftIslandSave:saveIsland()
		end
	end

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

		craftIslandSave:saveIsland()
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

-- Map

craftIslandSave = {}

local islandsKey = "islands"

local saveTimer = nil
craftIslandSave.saveIsland = function()
	if saveTimer then saveTimer:Cancel() end
	saveTimer = Timer(CANCEL_SAVE_SECONDS_INTERVAL, function()
		--print("saving island...")
		local data = craftIslandSave:serialize(map, assets)
		local store = KeyValueStore(islandsKey)
		store:Set(Player.UserID, data, function(success, results)
			--print("save", success and "success" or "failed")
		end)
	end)
end

craftIslandSave.getIsland = function(_, player, callback)
	local store = KeyValueStore(islandsKey)
	store:Get(player.UserID, function(success, results)
		if not success then error("Can't retrieve island") callback() end
		callback(results[player.UserID])
	end)
end

function colorToStr(color)
	return string.format("%d-%d-%d", color.R, color.G, color.B)
end

craftIslandSave.serialize = function(_, map, assets)
	local blockIdByColors = {}
	for _,v in ipairs(resources) do
		if v.type == "block" then
			blockIdByColors[colorToStr(v.block.color)] = v.id
		end
	end

	local d = Data()
	d:WriteUInt8(1) -- version
	local nbBlocksAssetsCursor = d.Cursor
	d:WriteUInt32(0) -- nb blocks and assets
	local nbBlocksAssets = 0

	local offset = 0

	for z=map.Min.Z,map.Max.Z do
		for y=map.Min.Y,map.Max.Y do
			for x=map.Min.X,map.Max.X do
				local b = map:GetBlock(x,y,z)
				if b then
					local id = blockIdByColors[colorToStr(b.Color)]
					if not id then error("block not recognized") end

					local pos = b.Coords
					if offset > 0 then
						d.Cursor = d.Cursor - 1
					end
					local rest = bit_writer:writeNumbers(d, {
						{ value = math.floor(pos.X + 500), size = 10 }, -- x
						{ value = math.floor(pos.Y + 500), size = 10 }, -- y
						{ value = math.floor(pos.Z + 500), size = 10 }, -- z
						{ value = 0, size = 3 }, -- ry
						{ value = id, size = 11 }, -- id
						{ value = 0, size = 1 }, -- extra length
					}, { offset = offset })
					--offset = 8 - rest
					nbBlocksAssets = nbBlocksAssets + 1
				end
			end
		end
	end

	for _,v in ipairs(assets) do
		if v ~= nil and not v.skipSave then
			local pos = v.mapPos
			local id = v.info.id
			bit_writer:writeNumbers(d, {
				{ value = math.floor(pos.X + 500), size = 10 }, -- x
				{ value = math.floor(pos.Y + 500), size = 10 }, -- y
				{ value = math.floor(pos.Z + 500), size = 10 }, -- z
				{ value = 0, size = 3 }, -- ry
				{ value = id, size = 11 }, -- id
				{ value = 0, size = 1 }, -- extra length
			})
			nbBlocksAssets = nbBlocksAssets + 1
		end
	end

	d.Cursor = nbBlocksAssetsCursor
	d:WriteUInt32(nbBlocksAssets)
	d.Cursor = d.Length

	return d
end

craftIslandSave.deserialize = function(_, data, callback)
	local islandInfo = {
		blocks = {},
		assets = {}
	}
	local version = data:ReadUInt8()
	if version == 1 then
		local nbBlocks = data:ReadUInt32()
		local byteOffset = 0
		function loadNextBlocksAssets(offset, limit)
			for i=offset, offset + limit - 1 do
				if i >= nbBlocks then return callback(islandInfo) end
				if byteOffset > 0 then
					data.Cursor = data.Cursor - 1
				end
				local blockOrAsset = bit_writer:readNumbers(data, {
					{ key = "X", size = 10 }, -- x
					{ key = "Y", size = 10 }, -- y
					{ key = "Z", size = 10 }, -- z
					{ key = "ry", size = 3 }, -- ry
					{ key = "id", size = 11 }, -- id
					{ key = "extraLength", size = 1 }, -- extra length
				}, { offset = byteOffset })

				blockOrAsset.X = blockOrAsset.X - 500
				blockOrAsset.Y = blockOrAsset.Y - 500
				blockOrAsset.Z = blockOrAsset.Z - 500

				if resources[blockOrAsset.id].block then
					table.insert(islandInfo.blocks, blockOrAsset)
				else
					table.insert(islandInfo.assets, blockOrAsset)
				end
			end
			Timer(0.02, function() loadNextBlocksAssets(offset + limit, limit) end)
		end
		loadNextBlocksAssets(0, 500)
	else
		error(string.format("version %d not valid", version))
	end
end

function loadIsland(callback)
	playerIsland = Object()

	map = MutableShape()
	map.Shadow = true
	map:SetParent(World)
	map.Physics = PhysicsMode.StaticPerBlock
	map.Scale = 7.5
	map.Pivot.Y = 1

	craftIslandSave:getIsland(Player, function(islandData)
		if not islandData then
			for z=-10,10 do
				for y=-10,0 do
					for x=-10,10 do
						map:AddBlock(resourcesByKey[y == 0 and "grass" or (y < -3 and "stone" or "dirt")].block.color,x,y,z)
					end
				end
			end

			blockAssetPlacer:placeAsset("oak_tree",Number3(5,1,5), { force = true })
			blockAssetPlacer:placeAsset("oak_sapling",Number3(-5,1,5))

			map:GetBlock(-5,0,-4):Replace(resourcesByKey.dirt.block.color)
			blockAssetPlacer:placeAsset("wheat_seed",Number3(-5,1,-4))
			map:GetBlock(-5,0,-5):Replace(resourcesByKey.dirt.block.color)
			blockAssetPlacer:placeAsset("wheat_seed",Number3(-5,1,-5))
			map:GetBlock(-5,0,-6):Replace(resourcesByKey.dirt.block.color)
			blockAssetPlacer:placeAsset("wheat_seed",Number3(-5,1,-6))
			map:GetBlock(-4,0,-4):Replace(resourcesByKey.dirt.block.color)
			blockAssetPlacer:placeAsset("wheat_seed",Number3(-4,1,-4))
			map:GetBlock(-4,0,-5):Replace(resourcesByKey.dirt.block.color)
			blockAssetPlacer:placeAsset("wheat_seed",Number3(-4,1,-5))
			map:GetBlock(-4,0,-6):Replace(resourcesByKey.dirt.block.color)
			map:GetBlock(-3,0,-4):Replace(resourcesByKey.dirt.block.color)
			map:GetBlock(-3,0,-5):Replace(resourcesByKey.dirt.block.color)
			map:GetBlock(-3,0,-6):Replace(resourcesByKey.dirt.block.color)
			return callback(map)
		end
		craftIslandSave:deserialize(islandData, function(islandInfo)
			for _,b in ipairs(islandInfo.blocks) do
				map:AddBlock(resourcesById[b.id].block.color, b.X, b.Y, b.Z)
			end
			for _,a in ipairs(islandInfo.assets) do
				blockAssetPlacer:placeAsset(resourcesById[a.id].key, Number3(a.X, a.Y, a.Z), { force = true })
			end
			callback(map)
		end)
	end)
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
				error("Can't access event logger")
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
	require("crosshair"):show()
	Camera:SetModeFirstPerson()

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
