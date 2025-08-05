--
-- Cookie Clicker
--
-- original author: aduermael
--

Config = {
	Map = nil,
	Items = { "aduermael.cookie_no_chips", "aduermael.cookie_chip" },
}

-- -------------------------
-- global variables
-- -------------------------
cooldown_duration = 3 -- seconds
count = 0 -- counter of clicks (actual value)
coolingDown = false -- true if we are cooling down, so we don't update the score too often
dirty = false -- true if we need to update the score once the cooldown is over

Client.OnStart = function()
	Client.resetScene()

	-- AMBIANCE
	Sky.SkyColor = Color(59, 29, 103)
	Sky.HorizonColor = Color(143, 65, 181)
	Sky.AbyssColor = Color(59, 29, 103)

	container = Object()
	World:AddChild(container)

	cookie = MutableShape(Items.aduermael.cookie_no_chips)
	container:AddChild(cookie)

	bubbleHooks = {}
	nextBubbleHook = 1
	for _ = 1, 10 do
		local bubbleHook = Object()
		bubbleHook.Physics = true
		bubbleHook.CollidesWithMask = 0
		bubbleHook.CollisionGroupsMask = 0
		bubbleHook.Acceleration = -Config.ConstantAcceleration
		bubbleHook.Motion.Y = 10
		World:AddChild(bubbleHook)
		table.insert(bubbleHooks, bubbleHook)
	end

	function displayBubble(pos, msg)
		bubbleHooks[nextBubbleHook].Position = pos
		bubbleHooks[nextBubbleHook]:TextBubble(msg, 5, 0)

		nextBubbleHook = nextBubbleHook + 1
		if nextBubbleHook > #bubbleHooks then
			nextBubbleHook = 1
		end
	end

	chips = {}
	local max = cookie.BoundingBox.Max
	local margin = 2
	local marginTwice = margin * 2

	for _ = 1, 6 do
		local chip = MutableShape(Items.aduermael.cookie_chip)
		container:AddChild(chip)
		chip.Pivot = { 0.5, 0.5, 0.5 }
		chip.Position = {
			(0.5 - math.random()) * (max.X - marginTwice),
			max.Y * 0.5 - 0.5 + math.random() * 0.5,
			(0.5 - math.random()) * (max.Z - marginTwice),
		}
		chip.Scale = 1.5 + math.random() * 0.5
		chip.Rotation = { math.random() * math.pi * 2.0, math.random() * math.pi * 2.0, 0.0 }
		table.insert(chips, chip)
	end

	Camera:SetModeSatellite(container.Position, 20)
	cameraBaseRotation = Number3(0.8, 0, 0)
	Camera.Rotation = cameraBaseRotation

	Pointer:Show()

	totalDT = 0.0

	-- UI
	local ui = require("uikit")
	countLabel = ui:createText("" .. math.floor(count), Color.White, "big")

	bestCount = nil
	bestLabel = ui:createText("Best: …", Color(255, 255, 255, 0.5), "default")

	function layoutLabels()
		countLabel.pos = {
			Screen.Width - Screen.SafeArea.Right - countLabel.Width - 10,
			Screen.Height - Screen.SafeArea.Top - countLabel.Height - 10,
		}

		bestLabel.pos = {
			Screen.Width - Screen.SafeArea.Right - bestLabel.Width - 10,
			countLabel.pos.Y - bestLabel.Height - 10,
		}
	end

	countLabel.parentDidResize = function()
		layoutLabels()
	end
	layoutLabels()

	getPersonalBest(function(ok, count)
		if ok then
			bestCount = count
			bestLabel.Text = "Best: " .. math.floor(count)
		end
	end)
end

Pointer.Down = function(e)
	-- this can also be done using a Ray object:
	local ray = Ray(e.Position, e.Direction)

	local impacts = {}

	local impact = ray:Cast(cookie)
	if impact ~= nil then
		table.insert(impacts, { impact = impact, object = cookie, isChip = false })
	end

	for _, chip in ipairs(chips) do
		local impact = ray:Cast(chip)
		if impact ~= nil then
			-- print("chip")
			table.insert(impacts, { impact = impact, object = chip, isChip = true })
		end
	end

	local closestImpact = nil

	for _, impact in ipairs(impacts) do
		if closestImpact == nil then
			closestImpact = impact
		else
			if impact.impact.Distance < closestImpact.impact.Distance then
				closestImpact = impact
			end
		end
	end

	if closestImpact ~= nil then
		local pos = e.Position + e.Direction * closestImpact.impact.Distance

		local add
		if closestImpact.isChip then
			closestImpact.object.Physics = true
			closestImpact.object.Velocity = { (0.5 - math.random()) * 40, 50, (0.5 - math.random()) * 40 }
			closestImpact.object.CollidesWithGroups = {}
			closestImpact.object.CollisionGroups = {}

			add = 2
		else
			add = 1
		end

		displayBubble(pos, "+" .. add)

		count = count + add
		countLabel.Text = "" .. math.floor(count)

		if bestCount ~= nil and count > bestCount then
			bestCount = count
			bestLabel.Text = "Best: " .. math.floor(count) -- .. " (" .. Player.Username .. ")"
		end

		layoutLabels()

		print("-> updatePersonalBest: from pointer down")
		updatePersonalBest()
	end
end

Client.Tick = function(dt)
	totalDT = totalDT + dt
	container.Rotation = Number3(math.sin(totalDT), math.sin(totalDT * 1.3), 0) * 0.2
end

-- hide the directional pad
Client.DirectionalPad = nil

--
-- Utilities
--

Client.resetScene = function()
	-- reset scene
	World:Recurse(function(o)
		if o.Name == "aduermael.baseplate" then -- or typeof(o) == "Light" or typeof(o) == "Camera" and o ~= Camera
			o:RemoveFromParent()
		end
	end)
	-- Clouds.On = false
	-- Player:RemoveFromParent()
	-- Map:RemoveFromParent()
	-- Camera.Behavior = nil
	-- Config.ConstantAcceleration = { 0, 0, 0 }
end

--
-- Key-Value Store utilities
--

-- update personal best score in KV store
-- This can be called anywhere and anytime. It takes care of the cooldown and the dirty flags.
function updatePersonalBest()
	local userID = Player.UserID
	local newCount = count

	if coolingDown then -- already cooling down, so we need to wait for the cooldown to finish
		print("-> updatePersonalBest: already cooling down, setting dirty flag")
		dirty = true
		return
	else -- not cooling down, so we start the cooldown and update the score
		coolingDown = true
		print("-> updatePersonalBest: not cooling down, starting cooldown")
	end

	-- update KV store
	local store = KeyValueStore(userID)
	store:Get("count", function(ok, res)
		if not ok then
			error("failed to get count from KV store")
		end

		print("-> updatePersonalBest: got count from KV store", res.count, newCount)

		if res.count == nil or res.count < newCount then
			store:Set("count", newCount, function(ok)
				if ok then
					print("updatePersonalBest: set count to", newCount)
				else
					print("updatePersonalBest: failed to set count to", newCount)
				end

				-- reset dirty flag right now and cooldown flag in a few seconds
				dirty = false
				Timer(cooldown_duration, function()
					coolingDown = false
					if dirty then
						print("-> updatePersonalBest: from timer + dirty")
						updatePersonalBest()
					end
				end)
			end)
		else
			-- reset dirty flag right now and cooldown flag in a few seconds
			dirty = false
			Timer(cooldown_duration, function()
				coolingDown = false
				if dirty then
					print("-> updatePersonalBest: from timer + dirty")
					updatePersonalBest()
				end
			end)
		end
	end)
end

-- get personal best score from KV store
-- callback(ok, count)
function getPersonalBest(callback)
	local userID = Player.UserID
	local store = KeyValueStore(userID)
	store:Get("count", function(ok, res)
		callback(ok, res.count or 0)
	end)
end

-- -- also try to update the global best
-- function updateGlobalBest()
-- 	local userName = Player.Username
-- 	local newCount = count

-- 	local globalStore = KeyValueStore("global")
-- 	globalStore:Get("count", "name", function(success, res)
-- 		if success then
-- 			if res.count == nil or res.count < newCount then
-- 				globalStore:Set("count", newCount, "name", userName, function(ok)
-- 					if ok then
-- 						-- TODO: update UI
-- 					end
-- 				end)
-- 			end
-- 		end
-- 	end)
-- end

-- function getGlobalBest(callback)
-- 	local globalStore = KeyValueStore("global")
-- 	globalStore:Get("count", "name", function(success, res)
-- 		callback(success, res.count or 0, res.name or "Unknown")
-- 	end)
-- end
