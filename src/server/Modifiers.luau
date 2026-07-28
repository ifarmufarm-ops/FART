--[[
	Modifiers -- the beacon events that change the map for everybody.

	Each one is a small table with an `apply` and a `revert`. Adding a new
	beacon means adding an entry here and one in Abilities.luau; nothing else
	needs to know it exists.

	Several can run at once (Config.MODIFIERS_STACK), each on its own timer.
	Grabbing a beacon that is already running refreshes its timer rather than
	starting a second copy of it.

	THE RULE THAT MATTERS: everything here must undo itself. Not just when the
	timer runs out, but when a round ends, and for a player who spawns halfway
	through. Gravity left at 60, or a player stuck at 60% height forever, would
	quietly poison every round that follows. That is why `revert` and
	`applyToCharacter` both exist for every modifier.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Bomb = require(script.Parent.Bomb)
local BrainRot = require(script.Parent.BrainRot)

local Modifiers = {}

type Running = {
	id: string,
	endsAt: number,
	token: number,
	activatorUserId: number?,
}

local running: { [string]: Running } = {}
local tokenCounter = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

--=============================================================================
-- TELLING THE CLIENTS
--=============================================================================

local function broadcast()
	local list = {}
	for _, entry in running do
		table.insert(list, {
			id = entry.id,
			endsAt = entry.endsAt,
			activatorUserId = entry.activatorUserId,
		})
	end
	Remotes.ModifierChanged:FireAllClients(list)
end

--=============================================================================
-- ICE SHOES
--=============================================================================
-- Every part tagged as floor loses its grip. Found by TAG, never by name, so a
-- hand-built map works untouched as long as its ground parts carry the tag.

local iceOriginals: { [BasePart]: { props: PhysicalProperties, color: Color3, material: Enum.Material } } = {}

local function floorParts(): { BasePart }
	local parts = {}
	for _, part in CollectionService:GetTagged(Config.TAG_FLOOR) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			table.insert(parts, part)
		end
	end
	return parts
end

local IceShoes = {
	apply = function()
		local slippery = PhysicalProperties.new(0.7, Config.ICE_FRICTION, 0.5, Config.ICE_FRICTION_WEIGHT, 1)
		for _, part in floorParts() do
			if not iceOriginals[part] then
				iceOriginals[part] = {
					props = part.CustomPhysicalProperties,
					color = part.Color,
					material = part.Material,
				}
			end
			part.CustomPhysicalProperties = slippery
			part.Color = part.Color:Lerp(Config.ICE_TINT, 0.65)
			part.Material = Enum.Material.Ice
		end
	end,

	revert = function()
		for part, original in iceOriginals do
			if part.Parent then
				part.CustomPhysicalProperties = original.props
				part.Color = original.color
				part.Material = original.material
			end
		end
		table.clear(iceOriginals)
	end,
}

--=============================================================================
-- LOW GRAVITY
--=============================================================================

local LowGravity = {
	apply = function()
		workspace.Gravity = Config.LOW_GRAVITY_VALUE
	end,

	revert = function()
		workspace.Gravity = Config.NORMAL_GRAVITY
	end,
}

--=============================================================================
-- TINY MODE
--=============================================================================
-- R15 characters carry their proportions as NumberValues inside the Humanoid.
-- Setting those is instant and reversible. R6 has no such values, so tiny mode
-- simply does nothing on an R6 rig rather than erroring.

local SCALE_VALUES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

local function setScale(character: Model, scale: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, name in SCALE_VALUES do
		local value = humanoid:FindFirstChild(name)
		if value and value:IsA("NumberValue") then
			value.Value = scale
		end
	end
end

local TinyMode = {
	apply = function()
		for _, player in Players:GetPlayers() do
			if player.Character then
				setScale(player.Character, Config.TINY_SCALE)
			end
		end
		-- The holder just changed size without the bomb changing hands, so the
		-- bomb needs re-seating or it floats above a shrunken head.
		Bomb.refreshHoldOffset()
	end,

	revert = function()
		for _, player in Players:GetPlayers() do
			if player.Character then
				setScale(player.Character, 1)
			end
		end
		Bomb.refreshHoldOffset()
	end,

	-- Someone who spawns mid-event has to be shrunk too, or they get a free
	-- advantage for the rest of it.
	onCharacter = function(character: Model)
		setScale(character, Config.TINY_SCALE)
	end,

	onCharacterEnd = function(character: Model)
		setScale(character, 1)
	end,
}

--=============================================================================
-- REVERSE CONTROLS
--=============================================================================
-- Purely a client-side effect: inverting movement means changing what the
-- player's own machine does with their input, which is not something the
-- server can do for them. The client is told to invert and does so.
--
-- That makes it the one modifier a cheater could ignore. Accepted: it is a
-- five-second comedy beat, not a rule that decides who wins.

local ReverseControls = {
	apply = function() end, -- entirely handled by the clients
	revert = function() end,
}

--=============================================================================
-- BRAIN ROT ALERT
--=============================================================================
-- All the work lives in BrainRot.luau; this just switches it on and off.

local BrainRotAlert = {
	apply = function()
		BrainRot.spawn()
	end,
	revert = function()
		BrainRot.despawn()
	end,
}

--=============================================================================
-- THE CATALOGUE
--=============================================================================

type Definition = {
	apply: () -> (),
	revert: () -> (),
	onCharacter: ((Model) -> ())?,
	onCharacterEnd: ((Model) -> ())?,
	duration: number,
}

local definitions: { [string]: Definition } = {
	IceShoes = { apply = IceShoes.apply, revert = IceShoes.revert, duration = Config.ICE_DURATION },
	LowGravity = { apply = LowGravity.apply, revert = LowGravity.revert, duration = Config.LOW_GRAVITY_DURATION },
	TinyMode = {
		apply = TinyMode.apply,
		revert = TinyMode.revert,
		onCharacter = TinyMode.onCharacter,
		onCharacterEnd = TinyMode.onCharacterEnd,
		duration = Config.TINY_DURATION,
	},
	ReverseControls = {
		apply = ReverseControls.apply,
		revert = ReverseControls.revert,
		duration = Config.REVERSE_DURATION,
	},
	BrainRot = {
		apply = BrainRotAlert.apply,
		revert = BrainRotAlert.revert,
		duration = Config.BRAINROT_DURATION,
	},
}

--=============================================================================
-- RUNNING THEM
--=============================================================================

local function stop(id: string)
	local entry = running[id]
	if not entry then
		return
	end
	running[id] = nil

	local definition = definitions[id]
	if definition then
		definition.revert()
		if definition.onCharacterEnd then
			for _, player in Players:GetPlayers() do
				if player.Character then
					definition.onCharacterEnd(player.Character)
				end
			end
		end
	end
	broadcast()
end

--[[
	Sets a beacon event going. `activator` is whoever touched it -- Reverse
	Controls uses it to spare them from their own beacon.
]]
function Modifiers.activate(id: string, activator: Player?)
	local definition = definitions[id]
	if not definition then
		warn("[Hot Potato] Unknown modifier: " .. tostring(id))
		return
	end

	-- You chose free stacking, so this is normally skipped. With stacking off,
	-- a new beacon clears whatever else was running first.
	if not Config.MODIFIERS_STACK then
		for otherId in running do
			if otherId ~= id then
				stop(otherId)
			end
		end
	end

	tokenCounter += 1
	local token = tokenCounter
	local alreadyRunning = running[id] ~= nil

	running[id] = {
		id = id,
		endsAt = now() + definition.duration,
		token = token,
		activatorUserId = if activator then activator.UserId else nil,
	}

	-- Grabbing the same beacon twice extends it rather than applying it twice.
	if not alreadyRunning then
		definition.apply()
	end
	broadcast()

	task.delay(definition.duration, function()
		local current = running[id]
		if current and current.token == token then
			stop(id) -- not refreshed since, so it really has expired
		end
	end)
end

--[[
	Cancels everything. Called at the start and end of every round, so no
	modifier can ever bleed from one round into the next.
]]
function Modifiers.clearAll()
	for id in running do
		stop(id)
	end
	-- Belt and braces: put the global values back even if nothing was running,
	-- in case a round ended mid-apply.
	workspace.Gravity = Config.NORMAL_GRAVITY
	IceShoes.revert()
	BrainRot.despawn()
	for _, player in Players:GetPlayers() do
		if player.Character then
			setScale(player.Character, 1)
		end
	end
	broadcast()
end

--[[
	Brings a freshly spawned character into line with whatever is running.
	Hooked into RoundManager's watchCharacters.
]]
function Modifiers.applyToCharacter(character: Model)
	for id in running do
		local definition = definitions[id]
		if definition and definition.onCharacter then
			definition.onCharacter(character)
		end
	end
end

function Modifiers.isRunning(id: string): boolean
	return running[id] ~= nil
end

--[[
	Re-sends the current state. Used when a player joins so their screen is not
	blank until the next beacon.
]]
function Modifiers.resync()
	broadcast()
end

return Modifiers
