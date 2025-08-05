Config = {
	Map = nil,
	Items = { "aduermael.cookie_no_chips", "aduermael.cookie_chip" },
}

Client.OnStart = function()
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

	count = 0

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
end

Client.ServerConnectionSuccess = function()
	-- print("ServerConnectionSuccess")
	-- PING THE SERVER
	Timer(0.5, function()
		local e = Event()
		e.action = "didStart"
		e:SendTo(Server)
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
			bestLabel.Text = "Best: " .. math.floor(count) .. " (" .. Player.Username .. ")"
		end

		layoutLabels()

		local e = Event()
		e.action = "add"
		e.count = add
		e:SendTo(Server)
	end
end

Client.Tick = function(dt)
	totalDT = totalDT + dt
	container.Rotation = Number3(math.sin(totalDT), math.sin(totalDT * 1.3), 0) * 0.2
end

Client.DidReceiveEvent = function(e)
	if e.info == "best" then
		bestCount = e.count
		bestLabel.Text = "Best: " .. math.floor(e.count) .. " (" .. e.name .. ")"
		layoutLabels()
	else
		if e.count ~= nil then
			count = count + e.count
			countLabel.Text = "" .. math.floor(count)
			layoutLabels()
		end
	end
end

Client.DirectionalPad = nil

--
-- Server code
--

Server.Tick = function(dt)
	-- Block executed once on first tick.
	-- It's a trick, waiting for Server.OnStart
	-- to be available.
	if didStart == nil then
		didStart = true

		playerCounts = {}

		function save()
			-- print("SAVE")

			for userID, playerData in pairs(playerCounts) do
				-- print("    userID:", userID)
				-- print("    playerData.name:", playerData.name)
				-- print("    playerData.diff:", playerData.diff)
				-- print("    playerData.count:", playerData.count)

				if playerData.diff > 0 and playerData.count ~= nil then
					playerData.count = playerData.count + playerData.diff
					playerData.diff = 0

					local store = KeyValueStore(userID)
					store:Set("count", playerData.count, function(success)
						-- print("SET SUCCESS:", success)
					end)

					if best.count ~= nil and playerData.count > best.count then
						updateBest(playerData.count, playerData.name)
					end
				end
			end
		end

		kTriggerDelta = 5.0 -- saves every 5 seconds
		trigger = kTriggerDelta

		best = {
			count = nil,
			name = nil,
		}

		local globalStore = KeyValueStore("global")
		globalStore:Get("count", "name", function(success, res)
			if success then
				if res.count ~= nil then
					best.count = res.count
				else
					best.count = 0
				end
				if res.name ~= nil then
					best.name = res.name
				else
					best.name = "TEST"
				end
			end
		end)

		function sendBest(recipient)
			-- print("sendBest:", best.count, best.name)
			if best.count ~= nil and best.name ~= nil then
				local e = Event()
				e.info = "best"
				e.count = best.count
				e.name = best.name
				e:SendTo(recipient)
			end
		end

		function updateBest(count, name)
			local globalStore = KeyValueStore("global")

			globalStore:Get("count", "name", function(success, res)
				if success then
					-- only update if the new count is higher
					if res.count == nil or res.count < count then
						globalStore:Set("count", count, "name", name, function(success)
							if success then
								best.count = count
								best.name = name
							end
						end)
					else
						best.count = res.count
						best.name = res.name
					end
				end
			end)
		end
	end

	trigger = trigger - dt
	if trigger <= 0 then
		trigger = kTriggerDelta
		save()
	end
end

Server.DidReceiveEvent = function(e)
	-- print("receiving event from", e.Sender.UserID)
	-- print("action:", e.action)

	local playerData = playerCounts[e.Sender.UserID]

	-- no matter the event, we need a table to store the count
	if playerData == nil then
		-- print("create player counts table")
		-- if this is the first event from this player,
		-- create the entry, store the diff, and get
		-- he actual count from the key/value store.
		playerCounts[e.Sender.UserID] = { diff = 0, count = 0, name = e.Sender.Username }
		playerData = playerCounts[e.Sender.UserID]
	end

	if e.action == "didStart" then
		-- set best score
		sendBest(e.Sender)

		local store = KeyValueStore(e.Sender.UserID)

		local callback = function(success, results)
			if success == true then
				if results.count == nil then
					-- print("COUNT IS NIL")
					playerData.count = 0
				else
					-- print("COUNT:", results.count)
					playerData.count = results.count
				end
			end

			local response = Event()
			response.count = playerData.count
			response:SendTo(e.Sender)
		end

		store:Get("count", callback)
	elseif e.action == "add" then
		playerData.diff = playerData.diff + e.count
	end
end
