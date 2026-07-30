--!strict
--[[
	GhostArea -- where you go when you are blown up.

	A glass-floored platform directly above the arena. Being knocked out used to
	mean losing your body and watching a camera drift around, which is a long
	time to spend doing nothing. Instead you keep a body, turn see-through, and
	stand on glass watching the rest of the round happen underneath you.

	Keeping a real body is the point, not decoration: it is what lets a ghost
	walk about, and what will let them punch things up here later.

	Same shape as Arena and Lobby -- build / getShuffledSpawns / preview -- so
	all three read the same way.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MovementGuard = require(script.Parent.MovementGuard)

local GhostArea = {}

local CENTER = Config.ARENA_CENTER + Vector3.new(0, Config.GHOST_HEIGHT, 0)
local HALF = Config.GHOST_SIZE / 2

local COLOR_GLASS = Color3.fromRGB(200, 226, 255)
local COLOR_RAIL = Color3.fromRGB(126, 214, 255)

local model: Model? = nil
local spawnPoints: { CFrame } = {}

-- Who is currently a ghost, so a body handed out later can be made see-through
-- again and so we know whose look to restore.
local ghosts: { [Player]: boolean } = {}

local function build(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function GhostArea.build(): Model
	local existing = workspace:FindFirstChild("GhostArea")
	if existing then
		existing:Destroy()
	end

	local area = Instance.new("Model")
	area.Name = "GhostArea"

	-- The glass floor. Deliberately NOT tagged as a game floor: Ice Shoes must
	-- never freeze it, and pickups must never try to spawn up here.
	build(
		area,
		"Glass",
		Vector3.new(Config.GHOST_SIZE, 1, Config.GHOST_SIZE),
		CFrame.new(CENTER.X, CENTER.Y - 0.5, CENTER.Z),
		COLOR_GLASS,
		Enum.Material.Glass,
		0.65
	)

	-- A rail all the way round. Ghosts can jump, and falling 130 studs back
	-- into a live round would be both confusing and unfair on the players in it.
	local railY = CENTER.Y + Config.GHOST_WALL_HEIGHT / 2
	local rails = {
		{ Vector3.new(Config.GHOST_SIZE, Config.GHOST_WALL_HEIGHT, 2), Vector3.new(0, 0, -HALF) },
		{ Vector3.new(Config.GHOST_SIZE, Config.GHOST_WALL_HEIGHT, 2), Vector3.new(0, 0, HALF) },
		{ Vector3.new(2, Config.GHOST_WALL_HEIGHT, Config.GHOST_SIZE), Vector3.new(-HALF, 0, 0) },
		{ Vector3.new(2, Config.GHOST_WALL_HEIGHT, Config.GHOST_SIZE), Vector3.new(HALF, 0, 0) },
	}
	for i, spec in rails do
		local offset = spec[2] :: Vector3
		build(
			area,
			"Rail" .. i,
			spec[1] :: Vector3,
			CFrame.new(CENTER.X + offset.X, railY, CENTER.Z + offset.Z),
			COLOR_RAIL,
			Enum.Material.Glass,
			0.7
		)
	end

	area.Parent = workspace

	-- Spawn points. These are plain CFrames rather than SpawnLocations: Roblox
	-- must never choose to respawn somebody up here on its own.
	spawnPoints = {}
	local radius = HALF - 14
	local standY = CENTER.Y + Config.SPAWN_ROOT_HEIGHT + Config.SPAWN_CLEARANCE
	for i = 1, Config.GHOST_SPAWN_COUNT do
		local angle = (i / Config.GHOST_SPAWN_COUNT) * math.pi * 2
		local pos = Vector3.new(CENTER.X + math.cos(angle) * radius, standY, CENTER.Z + math.sin(angle) * radius)
		-- Facing inwards, so a ghost arrives looking at the middle rather than
		-- at a rail.
		spawnPoints[i] = CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, CENTER.Z))
	end

	model = area
	return area
end

function GhostArea.getShuffledSpawns(): { CFrame }
	local copy = table.clone(spawnPoints)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--=============================================================================
-- BECOMING, AND UNBECOMING, A GHOST
--=============================================================================

--[[
	Fades a character out. Accessories included, or a solid hat floats above a
	see-through head.
]]
local function setGhostLook(character: Model, transparency: number)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Transparency = transparency
		elseif part:IsA("Decal") then
			part.Transparency = transparency
		end
	end
end

--[[
	Sends a player up to the ghost area with a fresh body, faded out.

	Called once their corpse has finished flying and been cleared away.
]]
function GhostArea.send(player: Player): boolean
	if #spawnPoints == 0 then
		return false
	end

	ghosts[player] = true

	local ok = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		return false
	end

	local character = player.Character
	if not character or not character.PrimaryPart then
		return false
	end

	local spawns = GhostArea.getShuffledSpawns()
	pcall(function()
		character:PivotTo(spawns[1])
	end)
	character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
	setGhostLook(character, Config.GHOST_TRANSPARENCY)

	-- Straight up 130 studs, by the server's hand. Not a speed cheat.
	MovementGuard.forgive(player)
	return true
end

--[[
	Is this player currently a ghost?
]]
function GhostArea.isGhost(player: Player): boolean
	return ghosts[player] == true
end

--[[
	Stops treating somebody as a ghost and makes their current body solid again.

	Called when a round ends and everybody comes back down to the arena, and
	when a ghost leaves for the lobby.

	Returns whether they actually were one, which tells the caller whether this
	player needs carrying back down to the arena or is already there.
]]
function GhostArea.restore(player: Player): boolean
	local wasGhost = ghosts[player] == true
	ghosts[player] = nil
	local character = player.Character
	if character then
		setGhostLook(character, 0)
	end
	return wasGhost
end

--[[
	A ghost who respawns for any reason must come back see-through, or they
	turn solid halfway through a round for no visible reason.
]]
function GhostArea.reapplyTo(character: Model)
	local owner = Players:GetPlayerFromCharacter(character)
	if owner and ghosts[owner] then
		setGhostLook(character, Config.GHOST_TRANSPARENCY)
	end
end

function GhostArea.clearAll()
	for player in ghosts do
		GhostArea.restore(player)
	end
	ghosts = {}
end

Players.PlayerRemoving:Connect(function(player)
	ghosts[player] = nil
end)

--=============================================================================
-- LOOKING AT IT IN STUDIO
--=============================================================================
-- Same as Arena and Lobby:
--     require(game.ServerScriptService.Server.GhostArea).preview()

function GhostArea.preview(): Model
	local area = GhostArea.build()
	area.Archivable = false
	local note = Instance.new("StringValue")
	note.Name = "PREVIEW_ONLY"
	note.Value = "Built by GhostArea.preview(). Not saved or published."
	note.Parent = area
	return area
end

function GhostArea.clearPreview()
	local existing = workspace:FindFirstChild("GhostArea")
	if existing then
		existing:Destroy()
	end
	model = nil
end

return GhostArea
