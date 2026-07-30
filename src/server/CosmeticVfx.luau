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
	end
end

return CosmeticVfx
