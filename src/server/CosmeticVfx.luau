--!strict
--[[
	CosmeticVfx -- the extra flourish a premium cosmetic gets.

	Most cosmetics are a recolour and nothing more. A product can name a `vfx`
	style in shared/Products.luau and get something built on TOP of the ordinary
	cloud, without every other entry needing code of its own.

	Only "Bubblegum" has one today.

	EVERYTHING IS BUILT FROM WHAT ROBLOX SHIPS. No uploaded textures, meshes or
	sounds, the same constraint the rest of this project works under, so it all
	appears for every player with nothing to publish. That means the interesting
	work is in layering: a single emitter reads as "some smoke", but four of them
	with different sizes, speeds, lifetimes and drag read as one thing happening.

	CREATED ON THE SERVER, like the rest of the game's effects, so everybody
	nearby sees the same thing rather than only the player who set it off.

	Everything is handed to Debris with a lifetime. An effect that forgets to
	clean up is a memory leak that only shows itself an hour into a session.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Products = require(ReplicatedStorage.Shared.Products)

local CosmeticVfx = {}

-- Roblox's own textures. The sparkle is a small bright star, which is what makes
-- glitter read as glitter rather than as more smoke.
local TEXTURE_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEXTURE_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function attachmentOn(root: BasePart, name: string, offset: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = offset
	attachment.Parent = root
	Debris:AddItem(attachment, lifetime)
	return attachment
end

--=============================================================================
-- BUBBLEGUM
--=============================================================================
--[[
	Four layers, each doing one job:

	  1. BUBBLES -- big, slow, nearly transparent, drifting upwards. Round and
	     high transparency is what sells "bubble" rather than "smoke": they hang
	     about and rise instead of billowing.
	  2. GLITTER -- tiny, bright, fast, short-lived, thrown outwards. This is the
	     layer that makes it look expensive; it catches the eye for a fraction of
	     a second and is gone.
	  3. A SHOCKWAVE RING -- one sphere scaled up hard and faded out over a
	     quarter of a second. Reads as the moment of the pop.
	  4. A PINK FLASH -- a light that blooms and dies, so the whole thing lights
	     its own surroundings for an instant instead of being a flat sticker.
]]

local function bubbleEmitter(parent: Attachment, product: Products.Product, rate: number): ParticleEmitter
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "GumBubbles"
	bubbles.Texture = TEXTURE_SMOKE
	bubbles.Color = ColorSequence.new(product.colorFrom, product.colorTo)
	-- Start small, swell, then hold. A bubble does not billow like smoke.
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.35, Config.GUM_BUBBLE_SIZE),
		NumberSequenceKeypoint.new(1, Config.GUM_BUBBLE_SIZE * 0.9),
	})
	-- Never fully solid: you should be able to see through a bubble.
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.45),
		NumberSequenceKeypoint.new(0.8, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.Lifetime = NumberRange.new(1.1, Config.GUM_BUBBLE_LIFETIME)
	bubbles.Speed = NumberRange.new(2, 6)
	bubbles.SpreadAngle = Vector2.new(50, 50)
	bubbles.Drag = 3.5
	-- Rising, not falling. This is the single property that stops it reading as
	-- exhaust and starts it reading as bubbles.
	bubbles.Acceleration = Vector3.new(0, Config.GUM_BUBBLE_RISE, 0)
	bubbles.Rotation = NumberRange.new(0, 360)
	bubbles.RotSpeed = NumberRange.new(-40, 40)
	bubbles.LightEmission = 0.4
	bubbles.LightInfluence = 0.2
	bubbles.Rate = rate
	bubbles.Parent = parent
	return bubbles
end

local function glitterEmitter(parent: Attachment, rate: number): ParticleEmitter
	local glitter = Instance.new("ParticleEmitter")
	glitter.Name = "GumGlitter"
	glitter.Texture = TEXTURE_SPARKLE
	glitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 200, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 200)),
	})
	glitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.GUM_GLITTER_SIZE),
		NumberSequenceKeypoint.new(1, 0),
	})
	glitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	glitter.Lifetime = NumberRange.new(0.35, 0.7)
	glitter.Speed = NumberRange.new(9, 20)
	glitter.SpreadAngle = Vector2.new(180, 180)
	glitter.Drag = 6
	glitter.Acceleration = Vector3.new(0, -14, 0)
	glitter.Rotation = NumberRange.new(0, 360)
	glitter.RotSpeed = NumberRange.new(-260, 260)
	-- Glowing, and ignoring the world's lighting, so it reads as a spark rather
	-- than a pale grey fleck in a shadow.
	glitter.LightEmission = 1
	glitter.LightInfluence = 0
	glitter.Rate = rate
	glitter.Parent = parent
	return glitter
end

--[[
	The pop: one sphere blown outwards and faded away.
]]
local function shockwave(root: BasePart, product: Products.Product)
	local ring = Instance.new("Part")
	ring.Name = "GumShockwave"
	ring.Shape = Enum.PartType.Ball
	ring.Size = Vector3.new(1, 1, 1)
	ring.CFrame = CFrame.new(root.Position)
	ring.Color = product.colorFrom
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = workspace
	Debris:AddItem(ring, Config.GUM_RING_TIME + 0.5)

	local info = TweenInfo.new(Config.GUM_RING_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, {
		Size = Vector3.one * Config.GUM_RING_SIZE,
		Transparency = 1,
	}):Play()
end

--[[
	A light that blooms and dies, so the burst lights what is around it.
]]
local function flash(root: BasePart, product: Products.Product)
	local light = Instance.new("PointLight")
	light.Name = "GumFlash"
	light.Color = product.colorFrom
	light.Brightness = 0
	light.Range = Config.GUM_FLASH_RANGE
	light.Shadows = false
	light.Parent = root
	Debris:AddItem(light, Config.GUM_FLASH_TIME + 0.4)

	-- Up fast, down slow. The other way round reads as a fault rather than a pop.
	TweenService:Create(light, TweenInfo.new(0.06, Enum.EasingStyle.Quad), {
		Brightness = Config.GUM_FLASH_BRIGHTNESS,
	}):Play()
	task.delay(0.08, function()
		if light.Parent then
			TweenService:Create(light, TweenInfo.new(Config.GUM_FLASH_TIME, Enum.EasingStyle.Quad), {
				Brightness = 0,
			}):Play()
		end
	end)
end

--=============================================================================
-- "???" -- THE GLITCH
--=============================================================================
--[[
	The showpiece technique here is a FROZEN COPY OF THE PLAYER.

	There is no built-in way to leave an afterimage, so the body is copied part by
	part into an anchored model, every child that could move, weld, emit or make a
	noise is stripped out, and what is left is faded away. Several of those,
	staggered a few hundredths of a second apart, read as a body smeared through
	time.

	Copies are always CanCollide false and CanQuery false. That is not a limit on
	the spectacle -- a solid copy would physically block other players, which would
	make a cosmetic change the game.
]]

local RED = Color3.fromRGB(255, 40, 40)
local GREEN = Color3.fromRGB(40, 255, 40)
local BLUE = Color3.fromRGB(60, 90, 255)

--[[
	One frozen copy of a character, fading out where it stood.

	`tint` nil keeps the body's own colours; a colour makes it a flat neon
	silhouette, which is what the channel-split uses.
]]
local function freezeCopy(
	character: Model,
	tint: Color3?,
	offset: Vector3,
	fade: number,
	startTransparency: number
): Model?
	local ghost = Instance.new("Model")
	ghost.Name = "GlitchGhost"

	local copied = 0
	for _, part in character:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end

		local ok, copy = pcall(function()
			return part:Clone()
		end)
		if not ok or not copy then
			continue
		end

		-- Keep only what makes it LOOK like a body. Everything else -- joints,
		-- welds, emitters, sounds, scripts -- would either error, move it, or make
		-- a noise from something that is meant to be a still image.
		for _, child in copy:GetChildren() do
			if not (child:IsA("SpecialMesh") or child:IsA("Decal")) then
				child:Destroy()
			end
		end

		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Massless = true
		copy.Transparency = startTransparency
		if tint then
			copy.Color = tint
			copy.Material = Enum.Material.Neon
		end
		copy.CFrame = part.CFrame + offset
		copy.Parent = ghost
		copied += 1
	end

	if copied == 0 then
		ghost:Destroy()
		return nil
	end

	ghost.Parent = workspace
	Debris:AddItem(ghost, fade + 0.4)

	local info = TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in ghost:GetChildren() do
		if part:IsA("BasePart") then
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		end
	end
	return ghost
end

--[[
	The colour tear: the same instant rendered three times, pulled apart.
]]
local function channelSplit(character: Model)
	local spread = Config.GLITCH_SPLIT_OFFSET
	freezeCopy(character, RED, Vector3.new(-spread, 0, 0), Config.GLITCH_SPLIT_FADE, 0.55)
	freezeCopy(character, GREEN, Vector3.new(0, spread * 0.35, 0), Config.GLITCH_SPLIT_FADE, 0.55)
	freezeCopy(character, BLUE, Vector3.new(spread, 0, 0), Config.GLITCH_SPLIT_FADE, 0.55)
end

--[[
	A trail of frozen bodies, one every few hundredths of a second.
]]
local function ghostTrail(character: Model)
	task.spawn(function()
		for index = 1, Config.GLITCH_GHOSTS do
			if not character.Parent then
				return
			end
			-- Later copies start fainter, so the trail reads as a direction rather
			-- than a row of equal clones.
			local faintness = Config.GLITCH_GHOST_START + (index - 1) * 0.12
			freezeCopy(character, nil, Vector3.zero, Config.GLITCH_GHOST_FADE, math.min(faintness, 0.85))
			task.wait(Config.GLITCH_GHOST_GAP)
		end
	end)
end

--[[
	Shards that snap in and out at random angles. Deliberately not particles:
	hard-edged parts appearing and vanishing look like something broken, whereas
	particles always look like smoke.
]]
local function shardBurst(root: BasePart, product: Products.Product)
	for _ = 1, Config.GLITCH_SHARDS do
		local shard = Instance.new("Part")
		shard.Name = "GlitchShard"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		-- Thin and flat, at a random angle: reads as a fragment, not a brick.
		shard.Size = Vector3.new(
			Config.GLITCH_SHARD_SIZE * (0.3 + math.random() * 1.4),
			Config.GLITCH_SHARD_SIZE * (0.05 + math.random() * 0.25),
			Config.GLITCH_SHARD_SIZE * (0.3 + math.random() * 1.4)
		)
		shard.Color = if math.random() < 0.5 then product.colorFrom else product.colorTo
		shard.Material = Enum.Material.Neon
		shard.Transparency = 0.1

		local spread = Config.GLITCH_SHARD_SPREAD
		shard.CFrame = CFrame.new(
			root.Position
				+ Vector3.new(
					(math.random() - 0.5) * spread * 2,
					(math.random() - 0.5) * spread,
					(math.random() - 0.5) * spread * 2
				)
		) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		shard.Parent = workspace

		-- Each one lives a slightly different sliver of time, so they pop in and
		-- out raggedly rather than blinking together.
		Debris:AddItem(shard, Config.GLITCH_SHARD_LIFE * (0.4 + math.random()))
	end
end

--[[
	Flat bars sweeping through the body, like a screen refreshing.
]]
local function scanLines(root: BasePart, product: Products.Product)
	for index = 1, Config.GLITCH_SCANLINES do
		local bar = Instance.new("Part")
		bar.Name = "GlitchScan"
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CanTouch = false
		bar.CastShadow = false
		bar.Size = Vector3.new(7, 0.12, 7)
		bar.Color = product.colorFrom
		bar.Material = Enum.Material.Neon
		bar.Transparency = 0.35
		bar.CFrame = CFrame.new(root.Position + Vector3.new(0, -3.5, 0))
		bar.Parent = workspace
		Debris:AddItem(bar, Config.GLITCH_SCAN_TIME + 0.3)

		-- Staggered, so they chase each other upwards.
		task.delay(index * 0.045, function()
			if not bar.Parent then
				return
			end
			TweenService
				:Create(bar, TweenInfo.new(Config.GLITCH_SCAN_TIME, Enum.EasingStyle.Linear), {
					CFrame = bar.CFrame + Vector3.new(0, 7, 0),
					Transparency = 1,
				})
				:Play()
		end)
	end
end

local function glitchBurst(root: BasePart, product: Products.Product, withTrail: boolean)
	local character = root.Parent
	if character and character:IsA("Model") then
		channelSplit(character)
		if withTrail then
			ghostTrail(character)
		end
	end
	shardBurst(root, product)
	scanLines(root, product)
	flash(root, product)
end

--=============================================================================
-- "!!!" -- PRISMATIC
--=============================================================================
--[[
	The technique here is that NOTHING HOLDS A COLOUR. One loop drives every part
	of the effect off a single sweeping hue, so the orbiters, their ribbons, the
	beams and the light are all different colours at the same instant and all
	changing together. That coherence is what stops it looking like a bag of
	random bright objects.
]]

local function hue(offset: number): Color3
	local h = (os.clock() * Config.PRISM_CYCLE_SPEED + offset) % 1
	return Color3.fromHSV(h, 0.85, 1)
end

--[[
	Rings fired one after another, each a different colour.
]]
local function ringPulse(root: BasePart)
	local origin = root.Position
	for index = 1, Config.PRISM_RINGS do
		task.delay((index - 1) * Config.PRISM_RING_GAP, function()
			local ring = Instance.new("Part")
			ring.Name = "PrismRing"
			ring.Shape = Enum.PartType.Ball
			ring.Size = Vector3.one
			ring.CFrame = CFrame.new(origin)
			ring.Color = hue(index * 0.17)
			ring.Material = Enum.Material.Neon
			ring.Transparency = 0.45
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Parent = workspace
			Debris:AddItem(ring, Config.PRISM_RING_TIME + 0.4)

			TweenService
				:Create(ring, TweenInfo.new(Config.PRISM_RING_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Size = Vector3.one * Config.PRISM_RING_SIZE,
					Transparency = 1,
				})
				:Play()
		end)
	end
end

--[[
	Prisms orbiting the player, each on a ribbon, each strung back to them with a
	beam, all spiralling outwards and cycling colour.

	Driven by ONE Heartbeat connection for all of them rather than one each, and
	it follows the player, so the whole thing travels with a dash instead of being
	left behind at the launch point.
]]
local function orbiters(root: BasePart)
	local hub = Instance.new("Attachment")
	hub.Name = "PrismHub"
	hub.Parent = root

	local prisms: { { part: BasePart, phase: number, tip: Attachment } } = {}

	for index = 1, Config.PRISM_ORBITERS do
		local prism = Instance.new("Part")
		prism.Name = "PrismOrbiter"
		prism.Size = Vector3.one * Config.PRISM_ORBIT_SIZE
		prism.Material = Enum.Material.Neon
		prism.Anchored = true
		prism.CanCollide = false
		prism.CanQuery = false
		prism.CanTouch = false
		prism.CastShadow = false
		prism.Transparency = 0.05
		prism.CFrame = CFrame.new(root.Position)
		prism.Parent = workspace

		-- Two attachments and a Trail gives each one a ribbon following its path.
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, Config.PRISM_ORBIT_SIZE * 0.5, 0)
		top.Parent = prism
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -Config.PRISM_ORBIT_SIZE * 0.5, 0)
		bottom.Parent = prism

		local ribbon = Instance.new("Trail")
		ribbon.Attachment0 = top
		ribbon.Attachment1 = bottom
		ribbon.Lifetime = 0.5
		ribbon.MinLength = 0
		ribbon.LightEmission = 1
		ribbon.LightInfluence = 0
		ribbon.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		ribbon.Parent = prism

		-- A beam from the player to the prism, so it is strung to them by light.
		local link = Instance.new("Attachment")
		link.Parent = prism
		local beam = Instance.new("Beam")
		beam.Attachment0 = hub
		beam.Attachment1 = link
		beam.Width0 = Config.PRISM_BEAM_WIDTH
		beam.Width1 = Config.PRISM_BEAM_WIDTH * 0.2
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0.75),
		})
		beam.Parent = prism

		table.insert(prisms, {
			part = prism,
			phase = (index / Config.PRISM_ORBITERS) * math.pi * 2,
			tip = link,
		})

		Debris:AddItem(prism, Config.PRISM_ORBIT_TIME + 0.8)
	end

	local light = Instance.new("PointLight")
	light.Name = "PrismLight"
	light.Brightness = Config.PRISM_FLASH_BRIGHTNESS
	light.Range = Config.PRISM_FLASH_RANGE
	light.Shadows = false
	light.Parent = root

	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		local progress = elapsed / Config.PRISM_ORBIT_TIME

		if progress >= 1 or not root.Parent then
			if connection then
				connection:Disconnect()
			end
			if light.Parent then
				light:Destroy()
			end
			if hub.Parent then
				hub:Destroy()
			end
			return
		end

		-- Spiral outwards and fade as they go.
		local radius = Config.PRISM_ORBIT_RADIUS + Config.PRISM_ORBIT_GROWTH * progress
		local lift = math.sin(progress * math.pi) * 3
		local spin = elapsed * Config.PRISM_ORBIT_SPEED

		light.Color = hue(0)
		light.Brightness = Config.PRISM_FLASH_BRIGHTNESS * (1 - progress)

		for index, entry in prisms do
			local part = entry.part
			if not part.Parent then
				continue
			end
			local angle = entry.phase + spin
			local shade = hue(index * 0.13)
			part.Color = shade
			part.Transparency = 0.05 + progress * 0.9
			part.CFrame = CFrame.new(
				root.Position + Vector3.new(math.cos(angle) * radius, lift, math.sin(angle) * radius)
			) * CFrame.Angles(spin * 2, spin * 1.5, 0)

			local ribbon = part:FindFirstChildOfClass("Trail")
			if ribbon then
				ribbon.Color = ColorSequence.new(shade)
			end
			local beam = part:FindFirstChildOfClass("Beam")
			if beam then
				beam.Color = ColorSequence.new(hue(index * 0.13 + 0.5), shade)
			end
		end
	end)
end

local function prismBurst(root: BasePart)
	ringPulse(root)
	orbiters(root)
end

--=============================================================================
-- THE TWO THINGS THAT CALL IN
--=============================================================================

--[[
	Layered onto the fart jump's puff: everything at once, as a burst.
]]
local function bubblegumJump(root: BasePart, product: Products.Product)
	local lifetime = Config.GUM_BUBBLE_LIFETIME + 2

	local low = attachmentOn(root, "GumBurst", Vector3.new(0, -1.1, 0.5), lifetime)
	local bubbles = bubbleEmitter(low, product, 0)
	local glitter = glitterEmitter(low, 0)

	bubbles:Emit(Config.GUM_BUBBLE_BURST)
	glitter:Emit(Config.GUM_GLITTER_BURST)

	shockwave(root, product)
	flash(root, product)
end

--[[
	Layered onto the dash's trail: a continuous stream instead of a burst, so it
	paints the path rather than marking one spot.
]]
local function bubblegumDash(root: BasePart, product: Products.Product)
	local lifetime = Config.DASH_TRAIL_MAX + Config.GUM_BUBBLE_LIFETIME + 2

	local back = attachmentOn(root, "GumTrail", Vector3.new(0, -0.7, 0.8), lifetime)
	local bubbles = bubbleEmitter(back, product, Config.GUM_BUBBLE_TRAIL_RATE)
	local glitter = glitterEmitter(back, Config.GUM_GLITTER_TRAIL_RATE)

	-- A small kick at the moment of launch, so the dash has a definite start.
	glitter:Emit(math.floor(Config.GUM_GLITTER_BURST / 2))
	flash(root, product)

	-- Pour for the dash and a moment past it, then stop and let what is already
	-- in the air finish on its own.
	task.delay(Config.DASH_DURATION + Config.DASH_GLIDE_DURATION + 0.2, function()
		bubbles.Rate = 0
		glitter.Rate = 0
	end)
end

--[[
	Called after the ordinary cloud has been built. Does nothing at all unless the
	cosmetic asks for a style, which is what keeps the other four unchanged.
]]
function CosmeticVfx.apply(kind: "Jump" | "Dash", root: BasePart, cosmeticId: string?)
	if not Config.COSMETIC_VFX_ENABLED or not cosmeticId then
		return
	end
	local product = Products.get(cosmeticId)
	if not product or product.vfx == nil then
		return
	end

	if product.vfx == "Bubblegum" then
		if kind == "Jump" then
			bubblegumJump(root, product)
		else
			bubblegumDash(root, product)
		end
	elseif product.vfx == "Glitch" then
		-- The frozen-copy trail is saved for the dash, where there is actual
		-- movement for it to smear along. On a jump it would just stack copies in
		-- one spot.
		glitchBurst(root, product, kind == "Dash")
	elseif product.vfx == "Prism" then
		prismBurst(root)
	end
end

return CosmeticVfx
