
Config = {
    Map = "caillef.empty",
	Items = { "caillef.empty", "aduermael.super_bike", "timaosimpson.stone_cube" }
}

--[[
-- TODO
[ ] Text showing winner, saying that you have to wait
[ ] Spawn boosts every X seconds, max 5 in the map
[X] Bonus ghost: become a ghost and remove collision for X seconds (activateGhost(p,duration))
[ ] Bonus boost: increse speed for 2 seconds
--]]

-- Named constants
local DEBUG_MODE = false -- start with a single player
local SOUND_MODE = false -- enable sound

-- Game states
local GAME_STATES = {
	WAITING = 0,
	STARTING = 1,
	RUNNING = 2,
	END = 3
}

-- Trail colors
local TRAIL_COLORS = { 31, 7, 136, 94, 52, 181, 160, 55 }

-- Map size
local MAP_SIZE = 100

-- Speed
local SPEED = 90

-- Directions
local DIRECTIONS = {
	FORWARD = 0,
	RIGHT = 1,
	BACKWARD = 2,
	LEFT = 3
}

cameraLocalRotation = Number3(0.5, 0, 0)

 _ParticleSpawner = {}

    function _ParticleSpawner:spawnparticle(n, color)

        for i = 1,n do

            local p = table.remove(self.recycled, 1)

			if p == nil then
				p = MutableShape()
				p:AddBlock(color,0,0,0)
				p.Scale = math.random() + 1
				self.count = self.count + 1
			else
				p.Palette[1].Color = color
            end

            p.Position = self.pos
            p.Physics = true
            p.CollidesWithGroups = Map.CollisionGroups
            p.Velocity = Number3(
                                (math.random() * 30 - 15) * 4,
                                self.spawnjump,
                                (math.random() * 30 - 15) * 4
                                )
            p.Rotation = Number3(math.random(0,360),math.random(0,360),math.random(0,360))
            Timer(self.lifetime, function()
                p:RemoveFromParent()
                table.insert(self.recycled, p)
            end)

            World:AddChild(p)

        end
    end
    
    function _ParticleSpawner:new(position)
        local spawner = {
        	count = 0,
            lifetime = 1.5,
            spawnjump = 70,
            recycled = {}, -- to recycle particules
			pos = position
        }
        setmetatable(spawner, self)
        self.__index = self
        return spawner
    end



-- Client functions
Client.OnStart = function()
	require("uikit.lua")
	if not ui then
		ui = require("uikit")
	end

	-- Spawn player function
	spawnPlayer = function(p)
		if not p.init then initPlayer(p) end
		resetTrailsOfPlayer(p)
		p.hasPlayed = true
		p.isDead = false
		p.spec = false
		p.avatar.IsHidden = false
		activateGhost(p, 1)

		-- Set position
		local pos
		if p.ID % 4 == 0 or (p.ID - 1) % 4 == 0 then
			pos = Number3((((p.ID % 8) - 1) % 4 == 0 and -1 or 1) * (p.ID % 8 < 4 and 0.6 or 0.8), 0, 0) * MAP_SIZE / 2
		else
			pos = Number3(0, 0, (((p.ID % 8) - 3) % 4 == 0 and -1 or 1) * (p.ID % 8 < 4 and 0.6 or 0.8)) * MAP_SIZE / 2
		end
		pos = Number3(pos.X, 0.5, pos.Z) * Map.LossyScale
		setPlayerPosition(p, pos)

		-- Set direction
		local dir = DIRECTIONS.FORWARD
		local id = p.ID % 8
		if id == 0 or id == 5 then dir = DIRECTIONS.FORWARD end
		if id == 1 or id == 4 then dir = DIRECTIONS.BACKWARD end
		if id == 2 or id == 7 then dir = DIRECTIONS.LEFT end
		if id == 3 or id == 6 then dir = DIRECTIONS.RIGHT end
		rotatePlayerAndSpawnTrail(p,dir)

		if not p == Player then
			-- p.avatar:TextBubble(p.Username,-1,0,Color.White,Color(0,0,0,0))
		end

		if cameraOrbit then
			cameraOrbit:AddChild(Camera)
			Camera.LocalPosition = Number3(0,30,-30)
			Camera.LocalRotation = cameraLocalRotation
		end
	end

	spawnPlayerVehicle = function(color)
		local avatar = MutableShape(Items.aduermael.super_bike)
		avatar.Palette[1].Color = color
		avatar.IsHidden = true
		avatar.Pivot.Z = 0.1
		avatar.CollisionGroups = { 5 }
		return avatar
	end

	initPlayer = function(p)
		if p.init then return end
		p.init = true
		p.hasPlayed = false -- set to true after first game
		p.Scale = 0.1
		p.color = DefaultColors[TRAIL_COLORS[math.floor(p.ID % #TRAIL_COLORS) + 1]]
		p.IsHidden = true
		p.Physics = false
	    World:AddChild(p, true) -- keep world
		p.spec = true

		p.avatar = spawnPlayerVehicle(p.color)
		World:AddChild(p.avatar)
		p.avatar.Position = p.Position + Number3(0, 4, 0)
		if p == Player then
			cameraOrbit = Object()
			p.avatar:AddChild(cameraOrbit)
			World:AddChild(Camera)
			Camera:SetModeFree()
			Camera.Position = Number3(0, 500, 0)
			Camera.Rotation.X = math.pi / 2 - 0.01
			-- Audio Listener
			Player.Head:AddChild(AudioListener)
		end

	    local asWhoosh = AudioSource()
 	   asWhoosh.Sound = "whooshes_small_1"
 	   asWhoosh.Spatialized = true
 	   World:AddChild(asWhoosh)
		p.asWhoosh = asWhoosh
	
	    local asExplode = AudioSource()
		asExplode.Sound = "thunder_3"
		asExplode.Spatialized = true
		asExplode.StartAt = 0.2
		asExplode.StopAt = 2
		World:AddChild(asExplode, true)
		p.asExplode = asExplode

		local l = Light()
		l.Type = LightType.Spot
		p.avatar:AddChild(l)
		l.Angle = 0.5
		l.Range = 100
		l.Hardness = 1
		l.Color = p.color
	end

	killPlayer = function(p)
		p.isDead = true
		updatePlayersList()
		-- p.avatar:TextBubble(p.Username.." ☠", -1)

		p.avatar.IsHidden = true
		local spawner = _ParticleSpawner:new(p.avatar.Position + Number3(0,3,0))
		spawner:spawnparticle(30, p.color)

		if _SOUND then
			p.asExplode.Position = p.avatar.Position
			p.asExplode:Stop()
			p.asExplode:Play()
		end

		require("ambience"):set({
			sky = {
				skyColor = p.color,
				horizonColor = p.color,
				abyssColor = p.color,
				lightColor = Color(153,153,153),
				lightIntensity = 0.310000,
			},
			fog = {
				color = Color(54,60,61),
				near = 300,
				far = 700,
				lightAbsorbtion = 0.400000,
			},
			sun = {
				color = Color(0,0,0),
				intensity = 1.000000,
				rotation = Number3(1.061161, 3.089219, 0.000000),
			},
			ambient = {
				skyLightFactor = 0.100000,
				dirLightFactor = 0.200000,
			}
		})
		Timer(0.5, function()
			require("ambience"):set({
				sky = {
					skyColor = Color(0,0,0),
					horizonColor = Color(0,0,0),
					abyssColor = Color(0,0,0),
					lightColor = Color(153,153,153),
					lightIntensity = 0.310000,
				},
				fog = {
					color = Color(54,60,61),
					near = 300,
					far = 700,
					lightAbsorbtion = 0.400000,
				},
				sun = {
					color = Color(0,0,0),
					intensity = 1.000000,
					rotation = Number3(1.061161, 3.089219, 0.000000),
				},
				ambient = {
					skyLightFactor = 0.100000,
					dirLightFactor = 0.200000,
				}
			})
		end)
	
		Timer(1, function()
			if gameState == gameStates.Running then
				p.spec = true
				if p == Player then
					World:AddChild(Camera)
					Camera.Position = Number3(0, 500, 0)
					Camera.Rotation.X = math.pi / 2
				end
			end
		end)
	end

	newTrail = function(p)
		if not p.init then return end
		if p.trail then
			local t = p.trail
			t.Scale[t.dir % 2 == 0 and "Z" or "X"] = (p.Position - t.Position).Length + 0.5
			table.insert(p.trails, t)
			if p.prevTrail then
				p.prevTrail.CollisionGroups = { 3 }
			end
			p.prevTrail = t
		end

		if _SOUND then
			p.asWhoosh.Position = p.avatar.Position
			p.asWhoosh:Stop()
			p.asWhoosh:Play()
		end

		local t = MutableShape()
		World:AddChild(t)
		p.trail = t

		t.Position = p.Position
		t.Scale.Y = 6
		t.dir = p.dir
		t.owner = p
		t.Pivot = Number3(t.dir % 2 == 0 and 0.5 or 0, 0, t.dir % 2 == 0 and 0 or 0.5)
		t.Forward = t.dir % 2 == 0 and p.Forward or p.Left

		t.CollisionGroups = p == Player and { 4 } or t.CollisionGroups
		t.CollisionBox = Box(Number3(0, 0, 0), Number3(1,1,1))

		t.color = DefaultColors[TRAIL_COLORS[math.floor(p.ID % #TRAIL_COLORS) + 1]]
		t:AddBlock(t.color,0,0,0)
		t.IsUnlit = true
	end

	updatePlayer = function(dt, p)
		if not p.init then return end
		if p.spec then return end

		local t = p.trail
		if p.isDead or not t then return end

		local forwardVec = p.Forward * speed * dt
		if p == Player and p.ghost ~= true then
			local impact = Ray(p.Position + { 0, 2, 0 }, p.Forward):Cast({ 3 })
			if impact.Shape ~= nil and impact.Distance <= forwardVec.Length * 4 then
				sendEventDied()
			end
		end
		setPlayerPosition(p, p.Position + forwardVec)
	end

	---------------
	-- BONUS
	---------------
	activateGhost = function(p,time)
		p.ghost = true
		Timer(time, function()
			p.ghost = false
		end)
	end

	---------------
	-- MOVEMENTS
	---------------
	setPlayerPosition = function(p, pos)
		p.Position = pos
		p.avatar.Forward = p.Forward
		p.avatar.Position = p.Position + Number3(0, 4, 0)
		local t = p.trail
		if t then
			t.Scale[t.dir % 2 == 0 and "Z" or "X"] = (p.Position - t.Position).Length
		end
	end

	rotatePlayerAndSpawnTrail = function(p, newDir)
		if gameState ~= gameStates.Starting and gameState ~= gameStates.Running then return end
		if not p.init or p.spec then return end

		p.dir = newDir
		local r = newDir * 0.5 * math.pi
		local delta = p.Rotation.Y - r
		p.Rotation.Y = r
		p.avatar.Forward = p.Forward
		if p == Player then
			cameraOrbit.LocalRotation.Y = cameraOrbit.LocalRotation.Y + delta
			sendEventRotate()
		end
		newTrail(p)
	end

	clearTexts = function()
		if waitingText then
			waitingText:remove()
			waitingText = nil
		end
		if textWinner then
			textWinner:remove()
			textWinner = nil
		end
		if titleScreen then
			titleScreen:remove()
			titleScreen = nil
		end
	end

	---------------
	-- GAME STATE
	---------------
	gameStateUpdate = function(dt)
		if gameState == gameStates.Running and Player.hasPlayed then
			for _,p in pairs(Players) do
				updatePlayer(dt,p)
			end
		end
	end

	setGameState = function(newState)
        prevState = gameState
		gameState = newState
		if newState == gameStates.Waiting then
			for _,p in pairs(Players) do
				resetTrailsOfPlayer(p)
				p.spec = true
			end
		elseif newState == gameStates.Starting and prevState ~= gameStates.Starting then
			clearTexts()
			for _,p in pairs(Players) do
				spawnPlayer(p)
			end
			updatePlayersList()
		elseif newState == gameStates.Running then
			-- nothing
		end
	end
	gameState = gameStates.Waiting
	
	---------------
	-- EVENTS
	---------------
	sendEventRotate = function()
		local e = Event()
		e.action = "rotate"
		e.dir = Player.dir
		e.pos = Player.Position
		e:SendTo(OtherPlayers)
	end

	sendEventDied = function()
		local e = Event()
		e.action = "died"
		killPlayer(Player)
		e:SendTo(OtherPlayers)
		e:SendTo(Server)
	end

	---------------
	-- MAP
	---------------
	initMap = function()
		m = MutableShape(Items.caillef.empty)
		m:GetBlock(0,0,0):Replace(DefaultColors[202])
		local c = DefaultColors[202]
		for y=-MAP_SIZE/2,MAP_SIZE/2-1 do
			for x=-MAP_SIZE/2,MAP_SIZE/2-1 do
				m:AddBlock(c,x,0,y)
			end
		end
		m.Scale = Map.LossyScale
		m.Position = Number3(Map.Width / 2, 0, Map.Depth / 2) * Map.LossyScale
		m.PrivateDrawMode = 8
		World:AddChild(m, true)
		Map.IsHidden = true
		
		-- Make map borders
		for i=0,3 do
			local p = (i < 2 and 0 or MAP_SIZE * 5) - MAP_SIZE / 2 * 5
			newWall(Number3(p,0,p), i, MAP_SIZE * 5, i < 2 and Number3(0,0,1) or Number3(0,0,-1))
		end
	end

	newWall = function(pos, dir, size, forward)
		local t = MutableShape(Items.caillef.empty)
		World:AddChild(t)
		t.Position = pos
		t.dir = dir
		t.owner = Map
		t.Pivot = Number3(t.dir % 2 == 0 and 0.5 or 0, 0, t.dir % 2 == 0 and 0 or 0.5)

		t.Forward = forward
		t.CollisionBox = Box(Number3(0, 0, 0), Number3(1,1,1))
		t.Scale.Y = 20
		t.color = DefaultColors[199]
		t:GetBlock(0,0,0):Replace(t.color)
		t.IsUnlit = true

		t.Scale[t.dir % 2 == 0 and "Z" or "X"] = size
	end

	resetTrailsOfPlayer = function(p)
		if p.trails then
			for _,t in ipairs(p.trails) do
				t:RemoveFromParent()
			end
		end
		if p.trail then
			p.trail:RemoveFromParent()
			p.trail = nil
		end
		p.trails = {}
	end

	updatePlayersList = function()
		if playersListTexts then
			for _,t in ipairs(playersListTexts) do
				t:remove()
			end
		end
		playersListTexts = {}
		local i = 0

		local startPos = Number3(5,Screen.Height - 5,0)

		for _,p in pairs(Players) do
			local color = Color.Grey
			if not p.spec and not p.isDead then
				color = p.color
			end

			local t = ui:createText(p.Username, color)
			--t:setParent(ui.rootFrame) -- BUG: comment this to fix bike transparency
			t.LocalPosition = startPos - {0, t.Height, 0}
			startPos = t.LocalPosition
			i = i + 1
			table.insert(playersListTexts, t)
		end
	end

	UI.Crosshair = false
	initMap()
	Fog.On = false
	Pointer:Hide()

	require("ambience"):set({
		sky = {
			skyColor = Color(0,0,0),
			horizonColor = Color(0,0,0),
			abyssColor = Color(0,0,0),
			lightColor = Color(153,153,153),
			lightIntensity = 0.310000,
		},
		fog = {
			color = Color(54,60,61),
			near = 300,
			far = 700,
			lightAbsorbtion = 0.400000,
		},
		sun = {
			color = Color(0,0,0),
			intensity = 1.000000,
			rotation = Number3(1.061161, 3.089219, 0.000000),
		},
		ambient = {
			skyLightFactor = 0.100000,
			dirLightFactor = 0.200000,
		}
	})

	Timer(1, updatePlayersList)
	
	titleScreen = ui:createText("Retro Motor Club", Color.White, "big")
	titleScreen.LocalPosition = Number2(Screen.Width / 2 - titleScreen.Width * 0.5, Screen.Height / 2 - titleScreen.Height * 0.5)
end

Client.OnPlayerLeave = function(p)
	local avatar = p.avatar
	resetTrailsOfPlayer(p)
	killPlayer(p)
	avatar:RemoveFromParent()
end

Client.AnalogPad = function(dx,dy)
	if not Player.init then initPlayer(Player) end
	cameraOrbit.LocalRotation.Y = cameraOrbit.LocalRotation.Y + dx * 0.01
end

Client.DirectionalPad = function(x,y)
	if gameState ~= gameStates.Running or Player.isDead or Player.init ~= true then return end
	if not (x == 1 or x == -1) then return end

	Player.dir = Player.dir + x
	if Player.dir > LEFT then Player.dir = FORWARD end
	if Player.dir < FORWARD then Player.dir = LEFT end

	rotatePlayerAndSpawnTrail(Player, Player.dir)
end

Client.OnPlayerJoin = function(p)
	print(p.Username.." just joined")
	initPlayer(p)

	Timer(1, function()
		local e = Event()
		e.action = "syncState"
		e:SendTo(Server)
	end)
end

Client.DidReceiveEvent = function(e)
	local p = e.Sender
	if e.action == "rotate" then
		setPlayerPosition(p, e.pos)
		rotatePlayerAndSpawnTrail(p, e.dir)
	end
	if e.action == "gs" then
		setGameState(e.state)
	end
	if e.action == "died" then
		killPlayer(p)
	end
	if e.action == "endGame" then
		textWinner = ui:createText(e.text, Color.White, "big")
		textWinner.LocalPosition = Number2(Screen.Width / 2 - textWinner.Width / 2, Screen.Height / 2 - textWinner.Height / 2)
	end
end

Client.Tick = function(dt)
	gameStateUpdate(dt)
end

--
-- Server code
--

Server.OnStart = function()
	nbPlayers = 0
	sgameState = gameStates.Waiting
	starting = false

	sgameStateUpdate = function(dt)
		if sgameState == gameStates.Waiting then
			if (_DEBUG or nbPlayers >= 2) and not starting then
				starting = true
				Timer(2, function() -- Timer to wait all players when restarting the server
					ssetGameState(gameStates.Starting)
				end)
				return
			end
		end
		if sgameState == gameStates.Starting or sgameState == gameStates.Running then
			starting = false
			if not _DEBUG and nbPlayers < 2 then
				print("All the other players left. Waiting for a new player...")
				ssetGameState(gameStates.Waiting)
				return
			end
		end
	end

	ssetGameState = function(newState)
		local e = Event()
		e.action = "gs"
		e.state = newState
		e:SendTo(Players)

		if newState == gameStates.Waiting then
			if nbPlayers < 2 then
				print("Waiting for another player to connect.")
			end
		elseif newState == gameStates.Starting and sgameState == gameStates.Waiting then
			for _,p in pairs(Players) do
				p.isDead = false
				p.spec = false
			end
			Timer(2, function()
				return ssetGameState(gameStates.Running)
			end)
		elseif newState == gameStates.End and sgameState == gameStates.Running then
			Timer(3, function()
				ssetGameState(gameStates.Waiting)
			end)
		end
		sgameState = newState
	end

	setGameState(gameStates.Waiting)
end

Server.OnPlayerJoin = function(p)
	nbPlayers = nbPlayers + 1
	p.spec = true

	if _DEBUG then
		ssetGameState(gameStates.Starting)
	end
end

Server.OnPlayerLeave = function(p)
	nbPlayers = nbPlayers - 1
	p.isDead = true
	p.spec = true
end

Server.DidReceiveEvent = function(e)
	if e.action == "syncState" then
		local e = Event()
		e.action = "gs"
		e.state = sgameState
		e:SendTo(e.Sender)
		return
	end
	if e.action == "died" and sgameState == gameStates.Running then
		if e.Sender.isDead then return end
		e.Sender.isDead = true
		e.Sender.spec = true
		local playersAlive = {}
		for _,p in pairs(Players) do
			if not p.isDead and not p.spec then
				table.insert(playersAlive,p)
			end
		end
		local nbPlayersAlive = #playersAlive
		if nbPlayersAlive == 0 then
			local e = Event()
			e.action = "endGame"
			e.text = "Tie"
			e:SendTo(Players)
			return ssetGameState(gameStates.End)
		end
		if nbPlayersAlive == 1 then
			local winner = playersAlive[1]
			local e = Event()
			e.action = "endGame"
			--e.winner = winner
			e.text = "Winner is "..winner.Username
			e:SendTo(Players)
			return ssetGameState(gameStates.End)
		end
	end
end

Server.Tick = function(dt)
	sgameStateUpdate(dt)
end
