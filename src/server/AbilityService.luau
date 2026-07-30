--[[
	AbilityService -- who is carrying what, and whether they may use it.

	You carry ONE ability at a time. Collecting a new pickup replaces whatever
	was in your slot. Using it empties the slot.

	This file owns the only client -> server channel in the game, so it is the
	only place where anything a player's machine says is taken seriously -- and
	it is never taken at face value. A request says "I pressed the button"; the
	server decides whether that does anything.

	Why the movement itself is applied on the client: a player's own machine
	owns their character's physics. If the server set the dash velocity, the
	client would immediately overwrite it and the dash would look broken. So
	the server owns the thing worth protecting -- the charge -- and hands the
	client a one-shot "yes, go" once it is spent.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Products = require(ReplicatedStorage.Shared.Products)

local CosmeticVfx = require(script.Parent.CosmeticVfx)
local MovementGuard = require(script.Parent.MovementGuard)
local Purchases = require(script.Parent.Purchases)
local Ragdoll = require(script.Parent.Ragdoll)
local StatsService = require(script.Parent.StatsService)

local AbilityService = {}

-- What one player is carrying: which ability, and how many uses are left in it.
type Slot = { id: string, uses: number }

local slots: { [Player]: Slot } = {}
local lastRequestAt: { [Player]: number } = {}
local sneakersUntil: { [Player]: number } = {}
local sneakersToken: { [Player]: number } = {}

-- Who is currently carrying the bomb. Holding it makes you faster, and that has
-- to combine with Sneakers rather than fight it -- see applyToCharacter.
local bombHolders: { [Player]: boolean } = {}

-- Set by start(). Answers "is this player actually in the round right now?"
local isEligible: (Player) -> boolean = function()
	return false
end

--[[
	Answers "does this use belong on the leaderboard?", which is a different
	question from "is this use allowed".

	Wired from init.server.luau rather than required, because RoundManager
	already requires this file and the two cannot require each other.
]]
local shouldCount: (Player) -> boolean = function()
	return true
end

function AbilityService.setCountCheck(check: (Player) -> boolean)
	shouldCount = check
end

--=============================================================================
-- SLOTS
--=============================================================================

local function tellClient(player: Player)
	local slot = slots[player]
	Remotes.AbilityState:FireClient(player, slot and slot.id, slot and slot.uses or 0)
end

--[[
	Puts an ability in a player's slot, replacing anything already there and
	resetting the use count. Deliberately a replace and not a top-up: collecting
	a second Dash while still holding one gives you three uses, not six.
]]
function AbilityService.grant(player: Player, abilityId: string)
	-- Most abilities get the standard number of uses; one that is deliberately
	-- short and powerful can ask for fewer. See the `uses` field in
	-- Abilities.luau, and Config.SNEAKERS_USES for the case that motivated it.
	local definition = Abilities.get(abilityId)
	local uses = (definition and definition.uses) or Config.ABILITY_USES
	slots[player] = { id = abilityId, uses = uses }
	tellClient(player)
end

function AbilityService.getCarried(player: Player): (string?, number)
	local slot = slots[player]
	if not slot then
		return nil, 0
	end
	return slot.id, slot.uses
end

function AbilityService.clear(player: Player)
	slots[player] = nil
	tellClient(player)
end

--[[
	Wipes every slot and cancels every speed boost. Called at the start and end
	of each round so nothing leaks between rounds.
]]
function AbilityService.clearAll()
	for _, player in Players:GetPlayers() do
		slots[player] = nil
		sneakersUntil[player] = nil
		sneakersToken[player] = (sneakersToken[player] or 0) + 1 -- cancels pending expiry
		bombHolders[player] = nil
		AbilityService.applyToCharacter(player)
		tellClient(player)
	end
end

--=============================================================================
-- SNEAKERS
--=============================================================================
-- The one ability the server can apply directly: WalkSpeed is a Humanoid
-- property, so setting it here replicates and the client honours it.

local function setWalkSpeed(player: Player, speed: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

--[[
	Re-applies whatever speed a player should currently have. Called whenever a
	character spawns, so a boost is not silently lost to a respawn.

	Everything that changes walking speed goes through here rather than setting
	WalkSpeed itself. That matters: Sneakers and the bomb both change it, and if
	each set the number directly then whichever finished second would wipe the
	other -- a holder whose Sneakers ran out would silently lose their bomb speed
	as well.
]]
function AbilityService.applyToCharacter(player: Player)
	local speed = Config.BASE_WALK_SPEED

	local until_ = sneakersUntil[player]
	if until_ and os.clock() < until_ then
		speed *= Config.SNEAKERS_MULTIPLIER
	end

	if bombHolders[player] then
		speed *= Config.BOMB_HOLDER_SPEED
	end

	setWalkSpeed(player, speed)
end

--[[
	Tells the service somebody has picked up or lost the bomb, so their speed
	can be recalculated. Called by RoundManager on every pass.
]]
function AbilityService.setBombHolder(player: Player, holding: boolean)
	bombHolders[player] = if holding then true else nil
	AbilityService.applyToCharacter(player)
end

local function startSneakers(player: Player)
	-- The token means a second pair of sneakers refreshes the timer instead of
	-- the first pair's expiry cutting the second one short.
	local token = (sneakersToken[player] or 0) + 1
	sneakersToken[player] = token
	sneakersUntil[player] = os.clock() + Config.SNEAKERS_DURATION

	AbilityService.applyToCharacter(player)

	task.delay(Config.SNEAKERS_DURATION, function()
		if sneakersToken[player] ~= token then
			return -- refreshed or cleared since
		end
		sneakersUntil[player] = nil
		AbilityService.applyToCharacter(player)
	end)
end

--=============================================================================
-- WHAT USING ONE LOOKS AND SOUNDS LIKE
--=============================================================================
-- Deliberately created on the SERVER, not on the dashing player's machine, so
-- that everybody nearby hears the noise and sees the trail. Only the movement
-- itself happens client-side.

local function playSound(root: BasePart, soundId: string, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = 120
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, 5)
end

--[[
	The dash leaves a streak of smoke hanging in the air behind you.

	The trick that makes it a TRACE rather than a cloud stuck to your back is
	that particle emitters spawn into world space by default -- each puff stays
	exactly where it was born while you keep moving. Pouring them out for the
	length of the dash therefore paints a line along the path you took.

	This replaces the ribbon Trail that used to be here. A Trail is welded to
	the character and sweeps along with it; smoke is left behind.
]]
local function dashSmoke(root: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashSmoke"
	attachment.Position = Vector3.new(0, -0.7, 0.8) -- low, out of the back
	attachment.Parent = root

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "DashTrace"
	smoke.Texture = Config.PARTICLE_SMOKE

	-- Same purchased colour as the fart puff. One cosmetic covers everything you
	-- leave behind, so a colour somebody paid for is not half applied.
	local dashOwner = Players:GetPlayerFromCharacter(root.Parent)
	local dashFrom, dashTo = Products.DASH_DEFAULT_FROM, Products.DASH_DEFAULT_TO
	if dashOwner then
		dashFrom, dashTo = Purchases.getDashColors(dashOwner)
	end
	smoke.Color = ColorSequence.new(dashFrom, dashTo)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 5.2),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.55, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.6, 1.2)
	-- Barely any push of its own -- the streak comes from the player moving,
	-- not from the particles being fired anywhere.
	smoke.Speed = NumberRange.new(1, 4)
	smoke.Drag = 5
	smoke.SpreadAngle = Vector2.new(35, 35)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-60, 60)
	smoke.Acceleration = Vector3.new(0, 1.5, 0) -- drifts up as it thins out
	smoke.LightEmission = 0.1
	smoke.Rate = Config.DASH_SMOKE_RATE
	smoke.Parent = attachment

	-- Keep pouring for the whole journey, not just the burst: through the dash
	-- itself, through any airtime if it took you off a ledge, and for a moment
	-- after you touch down. Cutting it at the burst left the trail ending in
	-- mid-air while the player carried on without it.
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	task.spawn(function()
		task.wait(Config.DASH_DURATION)

		local stopBy = os.clock() + Config.DASH_TRAIL_MAX
		while humanoid and humanoid.Parent and os.clock() < stopBy do
			local state = humanoid:GetState()
			if
				state ~= Enum.HumanoidStateType.Freefall
				and state ~= Enum.HumanoidStateType.Jumping
			then
				break -- landed
			end
			task.wait(0.05)
		end

		task.wait(Config.DASH_TRAIL_LINGER)
		smoke.Rate = 0
	end)
	Debris:AddItem(attachment, Config.DASH_TRAIL_MAX + Config.DASH_TRAIL_LINGER + 2.5)

	if dashOwner then
		CosmeticVfx.apply("Dash", root, Purchases.getEquipped(dashOwner))
	end
end

--[[
	The fart jump's exhaust: a one-off puff of green gas out of the back and
	underside of the character, drifting downwards as they shoot upwards.

	Rate stays at 0 and the particles come from a single Emit() burst, so it is
	a puff rather than a permanent cloud. The particles start small and swell as
	they fade, which is what makes separate dots read as one cloud of smoke.
]]
local function fartPuff(root: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FartPuff"
	attachment.Position = Vector3.new(0, -1.1, 0.5) -- low, and behind
	attachment.Parent = root

	local puff = Instance.new("ParticleEmitter")
	puff.Name = "FartSmoke"
	puff.Texture = Config.PARTICLE_SMOKE

	-- The one thing a purchase changes. Anybody who has bought nothing gets the
	-- colours this has always used, so nothing looks different until it should.
	local owner = Players:GetPlayerFromCharacter(root.Parent)
	local from, to = Products.FART_DEFAULT_FROM, Products.FART_DEFAULT_TO
	if owner then
		from, to = Purchases.getFartColors(owner)
	end
	puff.Color = ColorSequence.new(from, to)
	puff.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 4.6),
	})
	puff.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	puff.Lifetime = NumberRange.new(0.7, 1.3)
	-- Gently, and then hanging there. Fired out hard it reads as a rocket
	-- exhaust; the drag makes the puffs stall almost immediately and billow,
	-- which is what actually looks like gas.
	puff.Speed = NumberRange.new(4, 9)
	puff.Drag = 4
	puff.SpreadAngle = Vector2.new(45, 45)
	puff.Rotation = NumberRange.new(0, 360)
	puff.RotSpeed = NumberRange.new(-70, 70)
	puff.Acceleration = Vector3.new(0, -3, 0) -- drifts down as you rise
	puff.EmissionDirection = Enum.NormalId.Bottom
	puff.LightEmission = 0.15
	puff.Rate = 0 -- burst only
	puff.Parent = attachment

	puff:Emit(Config.FART_PUFF_PARTICLES)
	Debris:AddItem(attachment, 3)

	-- A premium cosmetic gets more than a recolour. Does nothing for the others.
	if owner then
		CosmeticVfx.apply("Jump", root, Purchases.getEquipped(owner))
	end
end

local function playUseEffects(character: Model, abilityId: string)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	if abilityId == "Dash" then
		playSound(root, Config.SOUND_DASH, 0.85)
		dashSmoke(root)
	elseif abilityId == "FartJump" then
		playSound(root, Config.SOUND_FART_JUMP, 0.8)
		fartPuff(root)
	end
end

--=============================================================================
-- REQUESTS FROM THE CLIENT
--=============================================================================

--[[
	Everything a client sends arrives here. Every branch that returns is a
	rejected request -- deliberately silent, so a modified client learns nothing
	from probing.
]]
local function onRequest(player: Player, requestKind: any)
	-- 1. Is it even the right shape?
	if typeof(requestKind) ~= "string" then
		return
	end

	-- 2. Rate limit, before doing any real work.
	local clock = os.clock()
	if clock - (lastRequestAt[player] or 0) < Config.ABILITY_REQUEST_COOLDOWN then
		return
	end
	lastRequestAt[player] = clock

	-- 3. Do they actually have something with uses left in it, and does it
	--    match how they claim to be using it? This is what stops a Double Jump
	--    being fired off with the dash button, or vice versa.
	local slot = slots[player]
	if not slot or slot.uses <= 0 then
		return
	end
	local abilityId = slot.id
	local definition = Abilities.get(abilityId)
	if not definition or definition.activation ~= requestKind then
		return
	end

	-- 4. Are they in a fit state to use it?
	if not isEligible(player) then
		return
	end
	local character = player.Character
	if not character or not character.Parent or Ragdoll.isRagdolled(character) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Approved. Spend a use first, so a duplicate request in the same frame
	-- finds one fewer (or an empty slot).
	slot.uses -= 1
	if slot.uses <= 0 then
		slots[player] = nil
	end
	tellClient(player)

	-- Counted here because this is the approval point: every branch above is a
	-- rejection, and this runs before the effects, which could in principle
	-- error. One use spent, one use counted.
	--
	-- Gated, because the lobby practice range hands abilities out every couple of
	-- seconds forever -- counting those would let anybody top the board without
	-- ever entering a round. See Config.COUNT_PRACTICE_ABILITIES.
	if shouldCount(player) then
		StatsService.add(player, "AbilityUses", 1)
	end

	-- Tell the movement guard this player is about to move fast on purpose, or
	-- every legitimate dash reads as a speed cheat.
	--
	-- A dash's momentum outlives the dash itself, and by a lot. Jump straight
	-- after one and there is no friction to slow you, so you keep the full dash
	-- speed until you land -- longer still under Low Gravity -- and landing on
	-- Ice Shoes keeps most of it again while you slide.
	--
	-- So this grants FULL dash speed for a good while rather than the slower
	-- slide speed for a moment. See Config.MOVEMENT_MOMENTUM_SECONDS for why
	-- that trade is the right way round.
	if abilityId == "Dash" then
		MovementGuard.allow(
			player,
			Config.DASH_SPEED * Config.MOVEMENT_GRANT_HEADROOM,
			Config.MOVEMENT_MOMENTUM_SECONDS
		)
	end

	if abilityId == "Sneakers" then
		startSneakers(player)
	end

	playUseEffects(character, abilityId)

	-- Dash and Double Jump are movement, so the owner's machine plays them.
	Remotes.AbilityUsed:FireClient(player, abilityId)
end

--=============================================================================
-- START
--=============================================================================

function AbilityService.start(eligibilityCheck: (Player) -> boolean)
	isEligible = eligibilityCheck

	Remotes.AbilityRequest.OnServerEvent:Connect(onRequest)

	Players.PlayerRemoving:Connect(function(player)
		slots[player] = nil
		lastRequestAt[player] = nil
		sneakersUntil[player] = nil
		sneakersToken[player] = nil
		bombHolders[player] = nil
	end)
end

return AbilityService
