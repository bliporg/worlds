 local REACH_DIST = 30

local map
local sneak = false
local selectedResource = nil
local isClient = type(Client.IsMobile) == "boolean"

local time = 0

local holdLeftClick = false
local blockTargeted
local blockKey
local blockStartedMiningAt
local blockSwingTimer

resourcesByKey = {} -- generated from resources on load before onStart

loadingList = {
	-- init player
	function(done)
		LocalEvent:Listen(LocalEvent.Name.AvatarLoaded, function()
			Player:SetParent(World)
			Camera.FOV = 80
			Player.Position = map.Position + Number3(5,10,5)
			require("object_skills").addStepClimbing(Player, { mapScale = 6 })
			require("crosshair"):show()
			Camera:SetModeFirstPerson()
			done()
		end)
	end,
	-- init shape cache
	function(done)
		local listLoadCache = {}
		for _,v in ipairs(resources) do
			resourcesByKey[v.key] = v

			if v.fullname then
				table.insert(listLoadCache, function(loadCacheDone)
					Object:Load(v.fullname, function(obj)
						v.cachedShape = obj
						resourcesByKey[v.key] = v
						loadCacheDone()
					end)
				end)
			end
		end
		asyncLoader:start(listLoadCache, done)
	end,
	-- load island
	function(done)
		loadIsland(function(loadedIsland)
			map = loadedIsland
			done()
		end)
	end
}

Client.OnStart = function()
	setAmbience()
	asyncLoader:start(loadingList, onStart)
end

function onStart()
	initKeyboardShortcuts()

	initPlayerHand()

	-- init mandatory inventories
	inventoryModule:create("cursor", { width = 1, height = 1, alwaysVisible = true })
	-- init inventories
	inventoryModule:create("mainInventory", { width = 9, height = 3 })
	inventoryModule:create("hotbar", { width = 9, height = 1, alwaysVisible = true,
		selector = true,
		uiPos = function(node)
			return { Screen.Width * 0.5 - node.Width * 0.5, require("uitheme").current.padding }
		end
	})

	--[[
	inventoryModule:create("chest1", { width = 4, height = 2, uiPos = function(node)
		return { Screen.Width - node.Width, Screen.Height * 0.5 - node.Height * 0.5 }
	end, onOpen = function()
		LocalEvent:Send("InvShow", { key = "mainInventory" })
	end })
	--]]

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

	-- Init island

	placeAsset("oak_tree",Number3(5,1,5))
	placeAsset("oak_sapling",Number3(-5,1,5))

	placeAsset("wheat_seed",Number3(-5,1,-4))
	placeAsset("wheat_seed",Number3(-5,1,-5))
	placeAsset("wheat_seed",Number3(-5,1,-6))
	placeAsset("wheat_seed",Number3(-4,1,-4))
	placeAsset("wheat_seed",Number3(-4,1,-5))

	-- Init inventory

	LocalEvent:Send("InvAdd", { key = "hotbar", rKey = "pickaxe", amount = 1, callback = function(success) end })
	LocalEvent:Send("InvAdd", { key = "hotbar", rKey = "shovel", amount = 1, callback = function(success) end })
	LocalEvent:Send("InvAdd", { key = "hotbar", rKey = "axe", amount = 1, callback = function(success) end })
	LocalEvent:Send("InvAdd", { key = "hotbar", rKey = "wheat_seed", amount = 16, callback = function(success) end })
end

function initKeyboardShortcuts()
	LocalEvent:Listen(LocalEvent.Name.KeyboardInput, function(char, keycode, modifiers, down)
		if keycode == 0 then
			if modifiers & 4 > 0 then -- shift
				if not inventoryModule.uiOpened then
					Camera.LocalPosition.Y = down and -5 or 0
				end
				sneak = down
			end
		end
		if char == "e" and down then
			LocalEvent:Send("InvToggle", { key = "mainInventory" })
			LocalEvent:Send("InvHide", { key = "chest1" })
		end
	end)
end

function placeAsset(key, pos)
	local resource = resourcesByKey[key]
	if not resource or not resource.asset then error(string.format("can't place %s", key)) return end
	local asset = Shape(resource.cachedShape, { includeChildren = true })
	asset:SetParent(World)
	asset.Scale = resource.asset.scale
	local box = Box()
	box:Fit(asset, true)
	asset.Pivot = Number3(asset.Width / 2, box.Min.Y + asset.Pivot.Y, asset.Depth / 2)
	if resource.asset.pivot then
		asset.Pivot = resource.asset.pivot(asset)
	end
	local worldPos = map:BlockToWorld(pos)
	asset.Position = worldPos + Number3(map.Scale.X * 0.5, 0, map.Scale.Z * 0.5)

	require("hierarchyactions"):applyToDescendants(asset, { includeRoot = true }, function(o)
		o.root = obj
		if resource.asset.physics == false then
			o.Physics = PhysicsMode.Disabled
		else
			o.Physics = PhysicsMode.StaticPerBlock
		end
	end)

	-- Custom properties
	asset.info = resource
	asset.mapPos = pos

	if resource.asset.onInteract then
		asset.onInteract = resource.asset.onInteract
		require("hierarchyactions"):applyToDescendants(asset, { includeRoot = true }, function(o)
			o.isInteractable = true
		end)
	end

	if resource.grow then
		growthAssets:add(asset)
	end
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

function cancelBlockMine()
	if not blockMined then return end
	blockMined = nil
	blockKey = nil
	if blockSwingTimer then
		blockSwingTimer:Cancel()
		blockSwingTimer = nil
	end
end

function startMineBlockInFront()
	if not holdLeftClick then return end
	blockMined = nil

	local impact = Camera:CastRay(nil, Player)
	if not impact.Object or impact.Object ~= map or impact.Distance > REACH_DIST then
		cancelBlockMine()
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
		blockSwingTimer = Timer(0.3, true, function()
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

Client.Action2 = function()
	holdLeftClick = true
	if not startMineBlockInFront() then
		LocalEvent:Send("SwingRight")
	end
end

Client.Action2Release = function()
	holdLeftClick = false
	blockMined = nil
	blockKey = nil
	if blockSwingTimer then
		blockSwingTimer:Cancel()
		blockSwingTimer = nil
	end
end

Client.Action3Release = function()
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
		elseif selectedResource.asset then
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
					placeAsset(selectedResource.key, pos)
					LocalEvent:Send("SwingRight")
					require("sfx")("walk_wood_"..math.random(5), { Spatialized = false, Volume = 0.3 })
				end
			})
		end
	end

	if impact.Object and impact.Object.isInteractable then
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

		startMineBlockInFront()
	end
end

function displayBlackLines()
	local impact = Camera:CastRay(nil, Player)
	if not impact.Object or impact.Object ~= map or impact.Distance > REACH_DIST then
		setBlockBlackLines()
		return
	end
	local impactBlock = Camera:CastRay(impact.Object)
	setBlockBlackLines(impact.Object, impactBlock.Block)
	if holdLeftClick and blockMined.Position ~= impactBlock.Block.Position then
		startMineBlockInFront()
	end
end

Client.Tick = function(dt)
	if not map then return end

	time = time + dt
	if holdLeftClick then
		mine()
	end
	displayBlackLines()
end

-- Map

local blackLinesBlock
function setBlockBlackLines(shape, block)
	if not shape or not block or shape ~= map then
		if blackLinesBlock then
			blackLinesBlock:SetParent(nil)
		end
		return
	end
	if not blackLinesBlock then
		blackLinesBlock = MutableShape()
		blackLinesBlock:AddBlock(Color(0,0,0,0),0,0,0)
		blackLinesBlock.PrivateDrawMode = 8
		blackLinesBlock.Pivot = { 0.5, 0.5, 0.5 }
		blackLinesBlock.Scale = shape.Scale + 0.01
		blackLinesBlock.Physics = PhysicsMode.Disabled
	end
	blackLinesBlock:SetParent(World)
	blackLinesBlock.Position = shape:BlockToWorld(block) + shape.Scale * 0.5
end

function loadIsland(callback)
	local map = MutableShape()
	map.Shadow = true
	map:SetParent(World)
	map.Physics = PhysicsMode.StaticPerBlock
	for z=-10,10 do
		for y=-10,0 do
			for x=-10,10 do
				map:AddBlock(resourcesByKey[y == 0 and "grass" or (y < -3 and "stone" or "dirt")].block.color,x,y,z)
			end
		end
	end
	map.Scale = 7.5
	map.Pivot.Y = 1
	callback(map)
end



-- Inventory

inventoryModule = {
	inventories = {},
	uiOpened = false,
	nbUIOpen = 0,
	listUIOpened = {},

	-- private
	nbAlwaysVisible = 0,
}

if isClient then

function getSlotIndexFromVisibleInventories(x,y)
	for key,inventory in pairs(inventoryModule.listUIOpened) do
		if inventory and key ~= "cursor" then
			local inventoryUi = inventory.ui
			if inventoryUi.pos.X <= x and x <= inventoryUi.pos.X + inventoryUi.Width and
				inventoryUi.pos.Y <= y and y <= inventoryUi.pos.Y + inventoryUi.Height then
				return key, inventoryUi:getSlotIndex(x - inventoryUi.pos.X, y - inventoryUi.pos.Y)
			end
		end
	end
end

LocalEvent:Listen(LocalEvent.Name.PointerUp, function(pe)
	local cursorSlot = inventoryModule.inventories.cursor.slots[1]
	if not cursorSlot.key then return end
	local inventoryKey,slotIndex = getSlotIndexFromVisibleInventories(pe.X * Screen.Width, pe.Y * Screen.Height)
	if not inventoryKey or not slotIndex or slotIndex < 1 then return end
	local inventory = inventoryModule.inventories[inventoryKey]
	LocalEvent:Send("InvClearSlot", { key = "cursor", slotIndex = 1,
		callback = function()
			inventory:tryAddElement(cursorSlot.key, cursorSlot.amount, slotIndex)
		end
	})
end, { topPriority = true })

end -- end is client

inventoryModule.create = function(_, iKey, config)
	if not config.width or not config.height then return error("inventory: missing width or height in config", 2) end
	local nbSlots = config.width * config.height
	local alwaysVisible = config.alwaysVisible
	local selector = config.selector

	local inventory = {}
	inventoryModule.inventories[iKey] = inventory

	inventory.onOpen = config.onOpen
	
	local slots = {}
	for i=1, nbSlots do
		slots[i] = { index = i }
	end
	inventory.slots = slots

	local function inventoryGetSlotIndexMatchingKey(key)
		for i=1, nbSlots do
			if slots[i] and slots[i].key == key then return i end
		end
	end

	inventory.tryAddElement = function(_, rKey, amount, optionalSlot)
		if rKey == nil or amount == nil then return end
		local slotIndex = optionalSlot
		if slotIndex then
			if slots[slotIndex].key and slots[slotIndex].key ~= rKey then
				-- todo: call popContent on this after replacing value
			end
		else
			slotIndex = inventoryGetSlotIndexMatchingKey(rKey)
		end
		if not slotIndex then
			-- try add to first empty slot
			for i=1,nbSlots do
				if slots[i].key == nil then
					slotIndex = i
					break
				end
			end
		end
		if not slotIndex then
			LocalEvent:Send("invFailAdd("..iKey..")", { key = rKey, amount = amount })
			return false
		end

		slots[slotIndex] = { index = slotIndex, key = rKey, amount = (slots[slotIndex].amount or 0) + amount }
		LocalEvent:Send("invUpdateSlot("..iKey..")", slots[slotIndex])

		return true
	end

	inventory.tryRemoveElement = function(_, rKey, amount, optionalSlot)
		if rKey == nil or amount == nil then return end

		local slotIndex = optionalSlot
		if not slotIndex then
			slotIndex = inventoryGetSlotIndexMatchingKey(rKey)
		end
		if not slotIndex or amount > slots[slotIndex].amount then
			LocalEvent:Send("invFailRemove("..iKey..")", { key = rKey, amount = amount })
			return false
		end

		slots[slotIndex].amount = slots[slotIndex].amount - amount
		if slots[slotIndex].amount == 0 then
			slots[slotIndex] = { index = slotIndex }
		end
		LocalEvent:Send("invUpdateSlot("..iKey..")", slots[slotIndex])

		return true
	end

	inventory.clearSlotContent = function(_, slotIndex)
		if slotIndex == nil then return end
		local contentToClear = slots[slotIndex]
		slots[slotIndex] = { index = slotIndex }
		LocalEvent:Send("invUpdateSlot("..iKey..")", slots[slotIndex])
		return contentToClear
	end

	local bg
	local uiSlots = {}

	if iKey == "cursor" then
		local latestPointerPos
		LocalEvent:Listen(LocalEvent.Name.Tick, function()			
			if not latestPointerPos or not inventory.slots[1].key then return end
			local pe = latestPointerPos
			inventory.ui.pos = { pe.X * Screen.Width - 20, pe.Y * Screen.Height - 20 }
			inventory.ui.pos.Z = -300
		end, { topPriority = true })
		LocalEvent:Listen(LocalEvent.Name.PointerMove, function(pe)
			latestPointerPos = pe
		end, { topPriority = true })
		LocalEvent:Listen(LocalEvent.Name.PointerDrag, function(pe)
			latestPointerPos = pe
		end, { topPriority = true })
	end

	inventory.show = function(_)
		local ui = require("uikit")
		local padding = require("uitheme").current.padding

		bg = ui:createFrame(iKey == "cursor" and Color(0,0,0,0) or Color(198,198,198))
		inventory.ui = bg

		local nbRows = config.height
		local nbColumns = config.width

		local cellSize = Screen.Width < 1000 and 40 or 60

		for j=1,nbRows do
			for i=1,nbColumns do
				local slotBg = ui:createFrame(iKey == "cursor" and Color(0,0,0,0) or Color(85,85,85))
				local slot = ui:createFrame(iKey == "cursor" and Color(0,0,0,0) or Color(139,139,139))
				slot:setParent(slotBg)
				local slotIndex = (j - 1) * nbColumns + i
				uiSlots[slotIndex] = slotBg
				slotBg.slot = slot
				slotBg.parentDidResize = function()
					slotBg.Size = cellSize
					slot.Size = slotBg.Size - padding
					slotBg.pos = { padding + (i - 1) * cellSize, padding + (nbRows - j) * cellSize }
					slot.pos = { padding * 0.5, padding * 0.5 }
				end
				slotBg:setParent(bg)
				if iKey ~= "cursor" then
					local cursorSlotOnPress
					slotBg.onPress = function()
						local content = slots[slotIndex]
						cursorSlotOnPress = inventoryModule.inventories.cursor.slots[1]
						if not content.key then return end
						if sneak then
							LocalEvent:Send("InvAdd", { key = iKey == "hotbar" and "mainInventory" or "hotbar", rKey = content.key, amount = content.amount,
								callback = function()
									inventory:clearSlotContent(slotIndex)
								end
							})
							return
						end
					end
					slotBg.onDrag = function()
						local cursorSlot = inventoryModule.inventories.cursor.slots[1]
						if cursorSlot.key then return end
						local content = slots[slotIndex]
						if not content.key then return end
						LocalEvent:Send("InvAdd", { key = "cursor", rKey = content.key, amount = content.amount,
							callback = function()
								inventory:clearSlotContent(slotIndex)
							end
						})
					end
					slotBg.onRelease = function()
						local cursorSlot = inventoryModule.inventories.cursor.slots[1]
						if not cursorSlot.key and slots[slotIndex].key then
							local content = slots[slotIndex]
							LocalEvent:Send("InvAdd", { key = "cursor",
								rKey = content.key, amount = content.amount,
								callback = function()
									inventory:clearSlotContent(slotIndex)
								end
							})
							return
						end
						if not cursorSlotOnPress.key then return end
						local key, amount = cursorSlot.key, cursorSlot.amount
						LocalEvent:Send("InvClearSlot", { key = "cursor", slotIndex = 1,
							callback = function()
								inventory:tryAddElement(key, amount, slotIndex)
							end
						})
					end
				end
				LocalEvent:Send("invUpdateSlot("..iKey..")", slots[slotIndex])
			end
		end

		bg.getSlotIndex = function(_,x,y)
			x = x - padding + cellSize * 0.5
			y = y - padding + cellSize * 0.5
			return math.floor(x / (cellSize + padding)) + 1 + (nbRows - 1 - (math.floor(y / (cellSize + padding)))) * nbColumns
		end

		bg.parentDidResize = function()
			bg.Width = nbColumns * cellSize + 2 * padding
			bg.Height = nbRows * cellSize + 2 * padding

			bg.pos = config.uiPos and config.uiPos(bg) or { Screen.Width * 0.5 - bg.Width * 0.5, Screen.Height * 0.5 - bg.Height * 0.5 }
		end
		bg:parentDidResize()

		if not alwaysVisible then
			require("crosshair"):hide()
			Pointer:Show()
			require("controls"):turnOff()
			Player.Motion = {0,0,0}
		end
		inventory.isVisible = true

		if selector then
			inventory:selectSlot(1)
		end

		return bg
	end

	local prevSelectedSlotIndex
	inventory.selectSlot = function(_, index)
		index = index or prevSelectedSlotIndex
		if prevSelectedSlotIndex then
			uiSlots[prevSelectedSlotIndex]:setColor(Color(85,85,85))
		end
		if not uiSlots[index] then return end
		uiSlots[index]:setColor(Color.White)
		prevSelectedSlotIndex = index
		LocalEvent:Send("invSelect("..iKey..")", slots[index])
	end

	local ui = require("uikit")
	LocalEvent:Listen("invUpdateSlot("..iKey..")", function(slot)
		if not uiSlots or not slot.index then return end

		if selector then
			inventory:selectSlot() -- remove item in hand if reached 0 or add it if at least 1
		end

		if uiSlots[slot.index].key == slot.key and slot.amount and slot.amount > 1 and uiSlots[slot.index].content.amountText then
			uiSlots[slot.index].content.amountText.Text = string.format("%d", slot.amount)
			uiSlots[slot.index].content.amountText:show()
			uiSlots[slot.index].content:parentDidResize()
			return
		end

		if uiSlots[slot.index].content then
			uiSlots[slot.index].content:remove()
			uiSlots[slot.index].content = nil
		end

		if slot.key == nil then return end

		uiSlots[slot.index].key = slot.key
		local uiSlot = uiSlots[slot.index].slot

		local content = ui:createFrame()

		local amountText = ui:createText(string.format("%d", slot.amount), Color.White, "small")
		content.amountText = amountText
		amountText.pos.Z = -500
		amountText:setParent(content)
		if slot.amount == 1 then amountText:hide() end

		local resource = resourcesByKey[slot.key]
		if resource.block then
			local b = MutableShape()
			b:AddBlock(resourcesByKey[slot.key].block.color,0,0,0)

			local shape = ui:createShape(b)
			shape.pivot.Rotation = { math.pi * 0.1, math.pi * 0.25, 0 }
			shape:setParent(content)

			shape.parentDidResize = function()
				shape.Size = uiSlot.Width * 0.5
				shape.pos = { uiSlot.Width * 0.25, uiSlot.Height * 0.25 }
			end
		elseif (resource.tool or resource.asset) and resource.cachedShape then
			local obj = Shape(resource.cachedShape, { includeChildren = true })
			local shape = ui:createShape(obj, { spherized = true })
			shape:setParent(content)
			shape.pivot.Rotation = resource.icon.rotation
			shape.pivot.Scale = shape.pivot.Scale * resource.icon.scale
			--obj.Pivot = { obj.Width * 0.5, obj.Height * 0.5, obj.Depth * 0.5 }

			shape.parentDidResize = function()
				shape.Size = math.min(uiSlot.Width * 0.5, uiSlot.Height * 0.5)
				shape.pos = Number3(uiSlot.Width * 0.25, uiSlot.Height * 0.25, 0) + { resource.icon.pos[1] * uiSlot.Width, resource.icon.pos[2] * uiSlot.Height, 0 }
			end
		else -- unknown, red block
			local b = MutableShape()
			b:AddBlock(Color.Red,0,0,0)

			local shape = ui:createShape(b)
			shape:setParent(content)

			shape.parentDidResize = function()
				shape.Size = uiSlot.Width * 0.5
				shape.pos = { uiSlot.Width * 0.25, uiSlot.Height * 0.25 }
			end
		end

		if slot.amount == 1 then amountText:hide() end
		content.parentDidResize = function()
			content.Size = uiSlot.Width
			amountText.pos = { content.Width - amountText.Width, 0 }
			amountText.pos.Z = -500
		end
		content:setParent(uiSlot)
		uiSlots[slot.index].content = content
	end)

	if selector then -- Hotbar
		LocalEvent:Listen(LocalEvent.Name.PointerWheel, function(delta)
			local newSlot = prevSelectedSlotIndex + (delta > 0 and 1 or -1)
			if newSlot <= 0 then newSlot = nbSlots end
			if newSlot > nbSlots then newSlot = 1 end
			inventory:selectSlot(newSlot)
		end)
		LocalEvent:Listen(LocalEvent.Name.KeyboardInput, function(char, keycode, modifiers, down)
			if not down then return end
			local keys = { 82, 83, 84, 85, 86, 87, 88, 89, 81 }
			for i=1,math.min(#keys, nbSlots) do
				if keycode == keys[i] then
					inventory:selectSlot(i)
					return
				end
			end
		end)
	end

	inventory.hide = function(_)
		if not bg then return end
		if alwaysVisible then return end
		inventory.isVisible = false
		bg:remove()
		bg = nil
		inventory.ui = nil

		Pointer:Hide()
		require("crosshair"):show()
		require("controls"):turnOn()
	end

	inventory.isVisible = false
	inventory.alwaysVisible = alwaysVisible
	if alwaysVisible then
		inventory:show()
		inventoryModule.listUIOpened[iKey] = inventory
		inventoryModule.nbUIOpen = inventoryModule.nbUIOpen + 1
		inventoryModule.nbAlwaysVisible = inventoryModule.nbAlwaysVisible + 1
	end

	return inventory
end

LocalEvent:Listen("InvAdd", function(data)
	local key = data.key
	local rKey = data.rKey
	local amount = data.amount
	local inventory = inventoryModule.inventories[key]
	if not inventory then error("Inventory: can't find "..key, 2) end
	local success = inventory:tryAddElement(rKey, amount)
	if not data.callback then return end
	data.callback(success)
end)

LocalEvent:Listen("InvRemove", function(data)
	local key = data.key
	local rKey = data.rKey
	local amount = data.amount
	local inventory = inventoryModule.inventories[key]
	if not inventory then error("Inventory: can't find "..key, 2) end
	local success = inventory:tryRemoveElement(rKey, amount)
	if not data.callback then return end
	data.callback(success)
end)

LocalEvent:Listen("InvClearSlot", function(data)
	local key = data.key
	local index = data.slotIndex
	local inventory = inventoryModule.inventories[key]
	if not inventory then error("Inventory: can't find "..key, 2) end
	local success = inventory:clearSlotContent(index)
	if not data.callback then return end
	data.callback(success)
end)

LocalEvent:Listen("InvShow", function(data)
	local key = data.key
	local inventory = inventoryModule.inventories[key]
	if not inventory then error("Inventory: can't open "..key, 2) end
	if inventory.alwaysVisible or inventory.isVisible then return end
	inventory:show()
	if inventory.onOpen then
		inventory:onOpen()
	end
	inventoryModule.listUIOpened[key] = inventory
	inventoryModule.nbUIOpen = inventoryModule.nbUIOpen + 1
	inventoryModule.uiOpened = true
end)

LocalEvent:Listen("InvHide", function(data)
	local key = data.key
	local inventory = inventoryModule.inventories[key]
	if not inventory then error("Inventory: can't close "..key, 2) end
	if inventory.alwaysVisible or inventory.isVisible == false then return end
	inventory:hide()
	inventoryModule.nbUIOpen = inventoryModule.nbUIOpen - 1
	inventoryModule.listUIOpened[key] = nil
	if inventoryModule.nbUIOpen <= inventoryModule.nbAlwaysVisible then
		inventoryModule.uiOpened = false
	end
end)

LocalEvent:Listen("InvToggle", function(data)
	local key = data.key
	local inventory = inventoryModule.inventories[key]
	if not inventory then error("Inventory: can't close "..key, 2) end
	if inventory.isVisible then
		LocalEvent:Send("InvHide", data)
	else
		LocalEvent:Send("InvShow", data)
	end
end)

-- Async Loader
asyncLoader = {}
asyncLoader.start = function(_, list, callback)
	local nbWaiting = #list
	local currentWaiting = 0

	local function loadedOneMore()
		currentWaiting = currentWaiting + 1
		if currentWaiting == nbWaiting then callback() end
	end

	for _,func in ipairs(list) do
		func(loadedOneMore)
	end
end

-- Growth
growthAssets = {
	list = {}
}

function growthAssets:add(asset)
	asset.growthAt = time + asset.info.grow.after()
	table.insert(self.list, asset)
end

function growthAssets:remove(asset)
	for k,v in ipairs(self.list) do
		if v == asset then
			table.remove(self.list, k)
			asset:RemoveFromParent()
		end
	end
end

LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
	for i=1,#growthAssets.list do
		local asset = growthAssets.list[i]
		if not asset then return end
		if time >= asset.growthAt then
			placeAsset(asset.info.grow.asset, asset.mapPos)
			growthAssets:remove(asset)
			i = i - 1
		end
	end
end)

-- Particles

function spawnBreakParticles(pos, color)
	local breakParticlesEmitter = require("particles"):newEmitter({
		velocity = function() return Number3((math.random() * 2 - 1) * 10, math.random(15), (math.random() * 2 - 1) * 10) end,
		physics = true,
		position = pos,
		scale = 0.5,
		color = Color(math.floor(color.R * 0.8), math.floor(color.G * 0.8), math.floor(color.B * 0.8)),
		life = 2,
		collidesWithGroups = Map.CollisionGroups,
		collisionGroups = { 6 },
	})
	breakParticlesEmitter:spawn(10)
end

-- Ambience

function setAmbience()
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

-- Resources

resources = {
	{ id = 1, key = "grass", name = "Grass", type = "block", miningType = "shovel", block = { color = Color(32,122,41) } },
	{ id = 2, key = "dirt", name = "Dirt", type = "block", miningType = "shovel", block = { color = Color(155,118,83) } },
	{ id = 3, key = "stone", name = "Stone", type = "block", miningType = "pickaxe", block = { color = Color(153,153,153) } },
	{ id = 256, key = "pickaxe", name = "Pickaxe", type = "tool", fullname = "caillef.pickaxe",
		icon = {
			rotation = { math.pi * 0.25, math.pi * 0.5, 0 },
			pos = { 0, -0.05 }, scale = 2
		},
		tool = {
			type = "pickaxe",
			
			hand = {
				pos = { 0, 3, -2 }, rotation = { math.pi * -0.5, 0, 0 }, scale = 0.8
			}
		}
	},
	{ id = 257, key = "shovel", name = "Shovel", type = "tool", fullname = "caillef.shovel",
		icon = {
			rotation = { math.pi * 0.25, math.pi, math.pi * 0.25 },
			pos = { 0, -0.05 }, scale = 2
		},
		tool = {
			type = "shovel",			
			hand = {
				pos = { 0, 3.5, -2 }, rotation = { math.pi * -0.5, 0, 0 }, scale = 0.6
			}
		}
	},
	{ id = 258, key = "axe", name = "Axe", type = "tool", fullname = "littlecreator.lc_stone_axe",
		icon = {
			rotation = { math.pi * 0.25, math.pi * 0.5, 0 },
			pos = { -0.04, -0.05 }, scale = 2
		},
		tool = {
			type = "axe",
			hand = {
				pos = { 0, 3, 0 }, rotation = { math.pi * -0.5, 0, 0 }, scale = 0.6
			}
		}
	},
	{ id = 512, key = "oak_tree", name = "Oak Tree", type = "asset",
		fullname = "voxels.oak_tree",
		miningType = "axe",
		asset = {
			scale = 0.6,
			hp = 4,
			drop = { i_oak_log = { 4, 6 }, i_wooden_stick = { 0, 2 } },
		}
	},
	{ id = 513, key = "oak_sapling", name = "Oak Sapling", type = "asset",
		fullname = "voxels.oak_tree",
		asset = {
			physics = false,
			scale = 0.1,
			hp = 1,
		},
		icon = {
			rotation = { 0, 0, 0},
			pos = { 0, 0 }, scale = 0.65
		},
		grow = {
			asset = "oak_tree",
			after = function() return 5 end
		}
	},
	{ id = 514, key = "oak_log", name = "Oak Log", type = "item", fullname = "voxels.oak", item = {} },
	{ id = 515, key = "wooden_stick", name = "Wooden Stick", type = "item", fullname = "mutt.stick", item = {} },
	{ id = 516, key = "wheat_seed", name = "Wheat Seed", type = "asset",
		fullname = "voxels.barley_chunk",
		asset = {
			scale = 0.5,
			physics = false,
			pivot = function(asset) return asset.Pivot + Number3(0,6,0) end,
			hp = 1,
		},
		icon = {
			rotation = { 0, 0, 0},
			pos = { 0, 0 }, scale = 0.65
		},
		grow = {
			asset = "wheat_step_1",
			after = function() return 5 + math.random(5) end
		}
	},
	{ id = 517, key = "wheat_step_1", name = "Wheat Step 1", type = "asset",
		fullname = "voxels.barley_chunk",
		asset = {
			scale = 0.5,
			physics = false,
			pivot = function(asset) return asset.Pivot + Number3(0,4,0) end,
			hp = 1,
		},
		grow = {
			asset = "wheat_step_2",
			after = function() return 5 + math.random(5) end
		}
	},
	{ id = 518, key = "wheat_step_2", name = "Wheat Step 2", type = "asset",
		fullname = "voxels.barley_chunk",
		asset = {
			scale = 0.5,
			physics = false,
			pivot = function(asset) return asset.Pivot + Number3(0,2,0) end,
			hp = 1,
		},
		grow = {
			asset = "wheat",
			after = function() return 5 + math.random(5) end
		}
	},
	{ id = 519, key = "wheat", name = "Wheat", type = "asset",
		fullname = "voxels.wheat_chunk",
		asset = {
			physics = false,
			scale = 0.5,
			hp = 1,
		},
		icon = {
			rotation = { 0, 0, 0},
			pos = { 0, 0 }, scale = 0.65
		},
	},
}
