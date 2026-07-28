--[[
	Pickups -- the glowing things that appear around the arena.

	One appears every few seconds up to a cap, hovers and spins, and is
	collected by walking into it. Which kind appears is a weighted roll from
	Abilities.luau, so making something rarer is a matter of changing one number
	in that file.

	Collection is a server-side distance check, exactly like passing the bomb in
	RoundManager -- not a .Touched event. Same two reasons: a client cannot fake
	it, and it stays reliable when players are moving fast.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Config = require(ReplicatedStorage.Shared.Config)

local AbilityService = require(script.Parent.AbilityService)
local Modifiers = require(script.Parent.Modifiers)

local Pickups = {}

type Active = {
	model: BasePart,
	definition: Abilities.Definition,
	base: Vector3, -- where it hovers; the bob is measured from here
	bornAt: number,
	phase: number, -- so they do not all bob in unison
}

local folder: Folder? = nil
local active: { Active } = {}
local enabled = false
local getAlive: () -> { Player } = function()
	return {}
end
local spawnThread: thread? = nil
local heartbeat: RBXScriptConnection? = nil
local nextCollectCheck = 0

--=============================================================================
-- BUILDING ONE
--=============================================================================

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local existing = workspace:FindFirstChild("Pickups")
	if existing and existing:IsA("Folder") then
		existing:Destroy()
	end
	local created = Instance.new("Folder")
	created.Name = "Pickups"
	created.Parent = workspace
	folder = created
	return created
end

--[[
	Finds somewhere sensible to put a pickup.

	The area comes from the map, not from this file: any part tagged
	Config.TAG_PICKUP_ZONE marks a volume where pickups may appear. We pick a
	random point inside one and ray straight down to find the ground under it.
	Several zones are fine -- use one per level on a multi-storey map.

	If a map has no zones tagged at all, we fall back to a flat square around
	ARENA_CENTER so nothing silently breaks.
]]
local function pickZone(): (Vector3?, Vector3?) -- returns (centre, size)
	local zones = CollectionService:GetTagged(Config.TAG_PICKUP_ZONE)
	local usable = {}
	for _, zone in zones do
		if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) then
			table.insert(usable, zone)
		end
	end
	if #usable == 0 then
		-- No zones in this map: assume a flat square, as the old code did.
		local size = Config.ARENA_SIZE - 24
		return Config.ARENA_CENTER + Vector3.new(0, 12, 0), Vector3.new(size, 24, size)
	end
	local chosen = usable[math.random(#usable)]
	return chosen.Position, chosen.Size
end

local function findSpawnPosition(): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getFolder() }

	for _ = 1, 12 do
		local centre, size = pickZone()
		if not centre or not size then
			return nil
		end

		-- A random spot on the ceiling of the zone, rayed downwards through it.
		local x = centre.X + (math.random() - 0.5) * size.X
		local z = centre.Z + (math.random() - 0.5) * size.Z
		local top = centre.Y + size.Y / 2

		local result = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -size.Y - 4, 0), params)
		if result then
			return result.Position + Vector3.new(0, Config.PICKUP_FLOAT_HEIGHT, 0)
		end
	end
	return nil
end

--[[
	Builds the glowing ball for one pickup. Exported so the Test Mode showcase
	range can use exactly the same visuals rather than a lookalike copy.
]]
function Pickups.buildVisual(definition: Abilities.Definition, position: Vector3, parent: Instance?): BasePart
	local part = Instance.new("Part")
	part.Name = "Pickup_" .. definition.id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.4, 2.4, 2.4)
	part.Color = definition.color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.25
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position)

	local light = Instance.new("PointLight")
	light.Color = definition.color
	light.Range = 12
	light.Brightness = 3
	light.Parent = part

	-- The icon floats above it so you can tell what it is from across the map.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(70, 70)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = definition.icon
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Parent = label

	part.Parent = parent or getFolder()
	return part
end

local function removeAt(index: number)
	local entry = active[index]
	if not entry then
		return
	end
	table.remove(active, index)
	if entry.model.Parent then
		entry.model:Destroy()
	end
end

--[[
	How many pickups the arena should be holding right now.

	Scaled by how many people are still playing: a flat number cannot suit both
	4 players and 10. Ten players sharing four pickups means most of them never
	touch one, which is what made the flow feel bad.
]]
local function activeCap(): number
	local target = math.round(#getAlive() * Config.PICKUP_PER_PLAYER)
	return math.clamp(target, Config.PICKUP_MIN_ACTIVE, Config.PICKUP_MAX_ACTIVE)
end

local function spawnOne()
	if #active >= activeCap() then
		return
	end
	local definition = Abilities.roll()
	if not definition then
		return
	end
	local position = findSpawnPosition()
	if not position then
		return -- arena was busy this tick; we will try again next interval
	end

	table.insert(active, {
		model = Pickups.buildVisual(definition, position),
		definition = definition,
		base = position,
		bornAt = os.clock(),
		phase = math.random() * math.pi * 2,
	})
end

--=============================================================================
-- COLLECTING
--=============================================================================

--[[
	Gives a player whatever this pickup was, and makes the collection noise.

	Exported so the Test Mode showcase range awards things through exactly the
	same path as a real pickup -- if it works on the range it works in a round.
]]
function Pickups.award(player: Player, definition: Abilities.Definition, atPosition: Vector3)
	if definition.kind == "Ability" then
		AbilityService.grant(player, definition.id)
	else
		-- Beacons are not carried -- they go off the moment you touch them,
		-- and they change the map for everyone, not just the collector.
		Modifiers.activate(definition.id, player)
	end

	-- A short-lived copy of the pickup's sound, so it is still audible after
	-- the pickup itself is gone.
	local speaker = Instance.new("Part")
	speaker.Anchored = true
	speaker.CanCollide = false
	speaker.CanQuery = false
	speaker.CanTouch = false
	speaker.Transparency = 1
	speaker.Size = Vector3.one
	speaker.CFrame = CFrame.new(atPosition)

	local sound = Instance.new("Sound")
	sound.SoundId = Config.SOUND_PICKUP
	sound.Volume = 0.8
	sound.PlaybackSpeed = 1.4
	sound.Parent = speaker

	speaker.Parent = workspace
	sound:Play()
	Debris:AddItem(speaker, 3)
end

local function collect(index: number, player: Player)
	local entry = active[index]
	if not entry then
		return
	end
	Pickups.award(player, entry.definition, entry.model.Position)
	removeAt(index)
end

local function checkCollection()
	local players = getAlive()
	if #players == 0 then
		return
	end

	for i = #active, 1, -1 do
		local entry = active[i]
		local position = entry.model.Position
		local claimed: Player? = nil
		local best = Config.PICKUP_COLLECT_RADIUS

		for _, player in players do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local distance = (root.Position - position).Magnitude
				if distance < best then
					claimed = player
					best = distance
				end
			end
		end

		if claimed then
			collect(i, claimed)
		elseif os.clock() - entry.bornAt > Config.PICKUP_LIFETIME then
			removeAt(i) -- nobody wanted it; make room for something else
		end
	end
end

--=============================================================================
-- RUNNING
--=============================================================================

local function onHeartbeat()
	local clock = os.clock()

	-- Spin and bob. One connection drives every pickup rather than one each.
	-- Always measured from the stored base position, never from where the part
	-- currently is, or the bob would creep further each frame.
	for _, entry in active do
		local bob = math.sin(clock * 2 + entry.phase) * 0.35
		entry.model.CFrame = CFrame.new(entry.base + Vector3.new(0, bob, 0))
			* CFrame.Angles(0, clock * 1.6, 0)
	end

	if clock >= nextCollectCheck then
		nextCollectCheck = clock + 0.1
		checkCollection()
	end
end

function Pickups.clear()
	for i = #active, 1, -1 do
		removeAt(i)
	end
end

--[[
	Turns spawning on or off. RoundManager calls this at the start and end of
	every round, handing in a function that answers "who is still playing?".
]]
function Pickups.setActive(isActive: boolean, aliveProvider: (() -> { Player })?)
	enabled = isActive
	getAlive = aliveProvider or function()
		return {}
	end

	if spawnThread then
		task.cancel(spawnThread)
		spawnThread = nil
	end

	if not isActive then
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		Pickups.clear()
		return
	end

	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
	end

	spawnThread = task.spawn(function()
		task.wait(1) -- let everyone finish spawning so the cap is sized right

		-- Fill the arena straight away rather than trickling up from one. At a
		-- 5.3s interval it would otherwise take most of a round to reach the
		-- cap, so the opening minute would feel as sparse as before.
		while enabled and #active < activeCap() do
			spawnOne()
			task.wait(0.15)
		end

		-- Then just top it up as they get taken.
		while enabled do
			task.wait(Config.PICKUP_SPAWN_INTERVAL)
			spawnOne()
		end
	end)
end

return Pickups
