--
-- New year's fireworks
--
-- original author: buche
--

Config = {
	Items = {
		"voxels.explosion_1",
		"voxels.explosion_2",
		"voxels.explosion_3",
		"voxels.explosion_4",
		"voxels.explosion_5",
		"voxels.explosion_6",
		"voxels.sparkle_1",
		"voxels.sparkle_2",
		"voxels.sparkle_3",
		"voxels.sparkle_4",
		"voxels.sparkle_5",
		"voxels.sparkle_6",
		"voxels.firework",
	},
}

Client.OnStart = function()
	multi = require("multi")
	walkSFX = require("walk_sfx")
	skills = require("object_skills")
	bundle = require("bundle")
	particles = require("particles")
	ease = require("ease")
	sfx = require("sfx")
	require("textbubbles").displayPlayerChatBubbles = true

	Clouds.Altitude = 75

	multi:onAction("launchFirework", function(_, data)
		_launchFirework(Players[data.id], data.fireworkType, data.speed, data.scale)
	end)

	Timer(2, function()
		_afterLoad()
	end)
end

Client.Action1 = function()
	if Player.launchDelay <= 0 then
		local fireworkType = math.random(1, 6)
		local speed = math.random(kMinVelocity, kMaxVelocity)
		local scale = math.random(5, 10)
		Player:SwingRight()
		multi:action("launchFirework", { id = Player.ID, fireworkType = fireworkType, speed = speed, scale = scale })
		_launchFirework(Player, fireworkType, speed, scale)
		Player.launchDelay = kLaunchDelay
		return
	end
	print("You must wait 1s before launching another firework")
end

Client.Tick = function(dt)
	if Player.launchDelay and Player.launchDelay > 0 then
		Player.launchDelay = Player.launchDelay - dt
	end
end

Client.OnPlayerJoin = function(p)
	print("Happy new year", p.Username, ":)")
	if p == Player then
		initPlayer(p)
	end
	dropPlayer(p)
end

initPlayer = function(p)
	World:AddChild(p) -- Adding the player to the world
	p.Head:AddChild(AudioListener) -- Adding an audio listener to the player
	p.Physics = true -- Enabling player physics
	skills.addStepClimbing(Player, { mapScale = Map.Scale.Y, velocityImpulse = 30 }) -- Giving the skill to auto climb blocks
	walkSFX:register(p) -- Adding step sounds
	p.launchDelay = 0

	local input = "[Space]"
	if Client.IsMobile then
		input = "✨"
		require("controls"):setButtonIcon("action1", input)
	end

	ctaToast = require("ui_toast"):create({
		message = "Press " .. input .. " to launch a firework",
		center = false,
		iconShape = Shape(Items.voxels.firework),
		duration = -1, -- negative duration means infinite
	})
end

Client.OnPlayerLeave = function(p)
	skills.removeStepClimbing(p)
	walkSFX:unregister(p)
	p:RemoveFromParent()
end

dropPlayer = function(p)
	local spawnPoint = Number3(15, 100, 64)
	local spawnRotation = Number3(0, -math.pi / 2, 0)
	p.Position = spawnPoint + Number3(math.random(-8, 8), 0, math.random(-8, 8))
	p.Rotation = spawnRotation + Number3(0, math.random(-1, 1) * math.pi / 8, 0)
end

_afterLoad = function()
	-- Invisible boundaries
	local createInvisibleWall = function(box)
		local o = Object()
		o:SetParent(World)
		o.CollidesWithGroups = { 2 }
		o.Physics = PhysicsMode.Static
		o.CollisionBox = box
		o.CollisionGroups = nil
		return o
	end

	local wallMapBorders = function()
		local yOffset = 20
		local width = 1
		w1 = createInvisibleWall(
			Box(Number3(0, 0, 0), Number3(Map.Width * Map.Scale.X, (Map.Height + yOffset) * Map.Scale.Y, -width))
		)
		w2 = createInvisibleWall(
			Box(Number3(0, 0, 0), Number3(-width, (Map.Height + yOffset) * Map.Scale.Y, Map.Depth * Map.Scale.Z))
		)
		w3 = createInvisibleWall(
			Box(
				Number3(Map.Width * Map.Scale.X, 0, 0),
				Number3(Map.Width * Map.Scale.X + width, (Map.Height + yOffset) * Map.Scale.Y, Map.Depth * Map.Scale.Z)
			)
		)
		w4 = createInvisibleWall(
			Box(
				Number3(0, 0, Map.Depth * Map.Scale.Z),
				Number3(Map.Width * Map.Scale.X, (Map.Height + yOffset) * Map.Scale.Y, Map.Depth * Map.Scale.Z + width)
			)
		)
	end
	wallMapBorders()

	local lights = World:FindObjectsByName("petroglyph.lantern")
	for k, v in pairs(lights) do
		v.IsUnlit = true
		local l = Light()
		l:SetParent(v)
	end
end

kLaunchDelay = 1
kSparkles = 24
kMinVelocity, kMaxVelocity = 400, 500
kExplodeDelay = 1.5
kSparklesDelay = 1.75
kSparklesDuration = 1
kRemoveDelay = 4

_launchFirework = function(p, fireworkType, speed, scale)
	local fireworkContainer = Object()
	fireworkContainer:SetParent(World)
	fireworkContainer.Physics = true
	fireworkContainer.CollisionGroups = nil
	fireworkContainer.CollidesWithGroups = nil
	fireworkContainer.Position = { p.Position.X, p.Position.Y + 20, p.Position.Z }
	fireworkContainer.Forward = { p.Forward.X, 2, p.Forward.Z }
	fireworkContainer.Velocity = fireworkContainer.Forward * speed

	local firework = Shape(Items.voxels.firework)
	firework:SetParent(fireworkContainer)
	firework.IsUnlit = true
	firework.Forward = { -Camera.Forward.X, Camera.Forward.Y, -Camera.Forward.Z }

	local fireworkLight = Light()
	fireworkLight:SetParent(fireworkContainer)

	local mainExplosion = Shape(Items.voxels["explosion_" .. fireworkType])
	mainExplosion:SetParent(fireworkContainer)
	mainExplosion.Pivot = mainExplosion.Center
	mainExplosion:RotateLocal(0, 0, math.random() * math.pi)
	mainExplosion.IsUnlit = true
	mainExplosion.CollisionGroups = nil
	mainExplosion.Scale = 0
	mainExplosion.InnerTransparentFaces = false

	local mainLight = Light()
	mainLight:SetParent(mainExplosion)
	mainLight.Color = mainExplosion.Palette[1].Color
	mainLight.Radius = 200

	local sparkles = {}
	for i = 0, kSparkles do
		local s = Shape(Items.voxels["sparkle_" .. math.random(1, 6)])
		s.IsUnlit = true
		s:SetParent(fireworkContainer)
		s.Scale = 0
		s.Pivot = s.Center
		s.LocalPosition = Number3(
			math.random(-mainExplosion.Width, mainExplosion.Width),
			math.random(-mainExplosion.Height, mainExplosion.Height),
			math.random(-mainExplosion.Depth, mainExplosion.Depth)
		) * scale * 0.5
		s.IsHidden = true
		table.insert(sparkles, s)
	end

	sfx("fireworks_fireworks_child_" .. math.random(1, 3))

	Timer(kExplodeDelay, function()
		ease:inSine(mainExplosion, 0.2).Scale = { scale, scale, scale }
		firework.IsHidden = true
		fireworkContainer.Physics = false
	end)

	Timer(kSparklesDelay, function()
		local dirX, dirY, dirZ = math.random(-1, 1), math.random(-1, 1), math.random(-1, 1)
		mainExplosion.Tick = function(self, dt)
			for i = 1, #self.Palette do
				self.Palette[i].Color.A = self.Palette[i].Color.A - 2
			end
			self:RotateLocal(dirX * dt * 0.1, dirY * dt * 0.1, dirZ * dt * 0.1)
			self:RefreshModel()
		end
		Timer(kSparklesDuration, function()
			mainExplosion.Tick = nil
			mainExplosion:RemoveFromParent()
			mainExplosion = nil
		end)

		for k, v in ipairs(sparkles) do
			local spawn = math.random() * kSparklesDuration
			Timer(spawn, function()
				ease:inSine(v, 0.3, {
					onDone = function(self)
						ease:inSine(self, 0.3, {
							onDone = function(self)
								self:RemoveFromParent()
								self = nil
							end,
						}).Scale =
							{ 0, 0, 0 }
					end,
				}).Scale =
					{ 1, 1, 1 }
				v.IsHidden = false
				sfx("small_explosion_" .. math.random(1, 3), { Pitch = 1.5, Volume = 0.4 })
			end)
		end
	end)

	Timer(kRemoveDelay, function()
		ease:inSine(fireworkContainer, 0.2, {
			onDone = function(self)
				self:RemoveFromParent()
				self = nil
			end,
		}).Scale =
			{ 0, 0, 0 }
	end)
end
