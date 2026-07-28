--[[
	Bomb -- the physical bomb object and everything you can see or hear about it.

	The bomb is a single glowing ball that floats just above the holder's head.
	It is not welded on rigidly; it is pulled towards a point above the head by
	an AlignPosition, so it lags and bobs as the player runs. The holder also
	gets a red outline (a Highlight) so everyone can spot them across the arena.

	This file has no rules in it -- it just shows what RoundManager decides.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Bomb = {}

-- How far above the holder's head the bomb floats.
local HOLD_OFFSET = Vector3.new(0, 2.4, 0)

-- The visuals only need refreshing when the countdown has moved meaningfully.
-- Without this the bomb's colour is re-sent to every client 20 times a second.
local URGENCY_STEP = 0.02

local bombPart: BasePart? = nil
local holdAttachment: Attachment? = nil
local alignPosition: AlignPosition? = nil
local highlight: Highlight? = nil
local beepSound: Sound? = nil
local light: PointLight? = nil
local sparks: ParticleEmitter? = nil
local lastUrgency = -1

local function newHoldAttachment(): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "BombHoldPoint"
	attachment.Position = HOLD_OFFSET
	return attachment
end

--[[
	How tall this character currently is relative to normal. 1 usually, 0.6
	during Tiny Mode. R6 rigs have no scale values, so they read as 1.
]]
function Bomb.getHeightScale(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local value = humanoid and humanoid:FindFirstChild("BodyHeightScale")
	if value and value:IsA("NumberValue") and value.Value > 0 then
		return value.Value
	end
	return 1
end

--[[
	Re-seats the bomb at the current holder's height. Called when Tiny Mode
	starts or stops, since the holder changes size without changing hands.
]]
function Bomb.refreshHoldOffset()
	local hold = holdAttachment
	if not hold or not hold.Parent then
		return
	end
	local character = hold.Parent:FindFirstAncestorOfClass("Model")
	if character then
		hold.Position = HOLD_OFFSET * Bomb.getHeightScale(character)
	end
end

--[[
	Creates the bomb once, at server start. It sits parked out of sight until
	the first round assigns it to somebody.
]]
function Bomb.create()
	Bomb.destroy()

	local part = Instance.new("Part")
	part.Name = "Bomb"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.8, 1.8, 1.8)
	part.Color = Color3.fromRGB(28, 28, 32)
	part.Material = Enum.Material.Metal
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true

	local attachment = Instance.new("Attachment")
	attachment.Name = "BombAttachment"
	attachment.Parent = part

	light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 80, 40)
	light.Range = 14
	light.Brightness = 2
	light.Parent = part

	sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 60, 30))
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Transparency = NumberSequence.new(0.1, 1)
	sparks.Lifetime = NumberRange.new(0.25, 0.5)
	sparks.Rate = 18
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.Parent = part

	beepSound = Instance.new("Sound")
	beepSound.Name = "Beep"
	beepSound.SoundId = Config.SOUND_BEEP
	beepSound.Volume = 0.7
	beepSound.RollOffMaxDistance = 120
	beepSound.Parent = part

	local passSound = Instance.new("Sound")
	passSound.Name = "Pass"
	passSound.SoundId = Config.SOUND_PASS
	passSound.Volume = 0.6
	passSound.RollOffMaxDistance = 100
	passSound.Parent = part

	-- The invisible target the bomb is dragged towards. It gets parented to
	-- whichever head currently owns the bomb.
	holdAttachment = newHoldAttachment()

	alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "BombFollow"
	alignPosition.Attachment0 = attachment
	alignPosition.MaxForce = 1e6
	alignPosition.Responsiveness = 45 -- high = snappy, low = floaty and laggy
	alignPosition.Enabled = false
	alignPosition.Parent = part

	highlight = Instance.new("Highlight")
	highlight.Name = "BombHolderGlow"
	highlight.FillColor = Color3.fromRGB(255, 60, 40)
	highlight.FillTransparency = 0.72
	highlight.OutlineColor = Color3.fromRGB(255, 130, 90)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = part

	bombPart = part
	lastUrgency = -1
	Bomb.park()
end

--[[
	Puts the bomb out of the world while nobody is holding it.

	It is pulled out of Workspace entirely rather than hidden somewhere far
	away. An unanchored part left sitting below Workspace.FallenPartsDestroyHeight
	(-500 by default) gets deleted by Roblox, which silently destroyed the bomb
	the first time it was handed off.
]]
function Bomb.park()
	local part = bombPart
	if not part then
		return
	end
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Parent = nil
end

--[[
	Moves the bomb onto a character. Returns false if that character is not in
	a fit state to hold it (no head, already gone, etc).
]]
function Bomb.attachTo(character: Model): boolean
	local part, hold, align, glow = bombPart, holdAttachment, alignPosition, highlight
	if not (part and hold and align and glow) then
		return false
	end

	local head = character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return false
	end

	-- The hold point lives on the holder's head, so it dies with that character
	-- if a body is ever destroyed before the bomb was taken off it. Every path
	-- in RoundManager detaches first, but if that invariant is ever broken this
	-- would throw and leave the bomb permanently unusable -- so rebuild it
	-- rather than trusting it.
	if not pcall(function()
		hold.Parent = head
	end) then
		hold = newHoldAttachment()
		holdAttachment = hold
		hold.Parent = head
	end

	align.Attachment1 = hold
	align.Enabled = true

	-- Sit the bomb at the right height for the holder's actual size. Tiny Mode
	-- shrinks players to 60%, and a fixed offset would leave the bomb floating
	-- conspicuously above their head.
	hold.Position = HOLD_OFFSET * Bomb.getHeightScale(character)

	-- Place it before putting it back into the world, so it appears above the
	-- new holder's head rather than flying in from wherever it last was.
	part.CFrame = head.CFrame * CFrame.new(hold.Position)
	part.Parent = workspace
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.new(0, 6, 2) -- a lazy tumble

	-- Hand physics control to the holder's own machine. Otherwise Roblox may
	-- park ownership on some other player and the bomb visibly trails behind
	-- the head it is supposed to be glued to.
	pcall(function()
		part:SetNetworkOwner(Players:GetPlayerFromCharacter(character))
	end)

	glow.Adornee = character
	glow.Enabled = true

	local passSound = part:FindFirstChild("Pass")
	if passSound and passSound:IsA("Sound") then
		passSound:Play()
	end

	return true
end

--[[
	Takes the bomb off whoever has it and parks it out of sight.
]]
function Bomb.detach()
	local part, hold, align, glow = bombPart, holdAttachment, alignPosition, highlight
	if not (part and hold and align and glow) then
		return
	end

	align.Enabled = false
	align.Attachment1 = nil
	hold.Parent = nil

	glow.Enabled = false
	glow.Adornee = nil

	Bomb.stopBeep()
	Bomb.park()
end

--[[
	Called every check tick with how far through the countdown we are:
	1 means the timer just started, 0 means it is about to blow.
	Drives the light, the sparks and the colour of the bomb.
]]
function Bomb.setUrgency(fraction: number)
	local part = bombPart
	if not part then
		return
	end
	local urgency = 1 - math.clamp(fraction, 0, 1)

	-- Skip tiny changes. This is called on every rule-check tick (20 a second);
	-- without the guard each one re-replicates the bomb's colour to every
	-- client for a difference nobody can see.
	if math.abs(urgency - lastUrgency) < URGENCY_STEP then
		return
	end
	lastUrgency = urgency

	if light then
		light.Brightness = 2 + urgency * 8
		light.Range = 14 + urgency * 12
	end
	if sparks then
		sparks.Rate = 18 + urgency * 90
	end
	part.Color = Color3.fromRGB(28, 28, 32):Lerp(Color3.fromRGB(255, 70, 30), urgency)
	part.Material = if urgency > 0.6 then Enum.Material.Neon else Enum.Material.Metal
end

--[[
	One tick of the countdown beep. Pitch rises as the timer runs down.
]]
function Bomb.beep(fraction: number)
	local sound = beepSound
	if not sound then
		return
	end
	local urgency = 1 - math.clamp(fraction, 0, 1)
	sound.PlaybackSpeed = 1 + urgency * 1.1
	sound.Volume = 0.55 + urgency * 0.45
	sound:Play()
end

function Bomb.stopBeep()
	if beepSound then
		beepSound:Stop()
	end
	Bomb.setUrgency(1)
end

--[[
	Where the bomb is right now -- used as the centre of the explosion.
]]
function Bomb.getPosition(): Vector3?
	return if bombPart then bombPart.Position else nil
end

function Bomb.destroy()
	if bombPart then
		bombPart:Destroy()
	end
	if holdAttachment then
		holdAttachment:Destroy()
	end
	bombPart, holdAttachment, alignPosition, highlight, beepSound, light, sparks =
		nil, nil, nil, nil, nil, nil, nil
end

return Bomb
