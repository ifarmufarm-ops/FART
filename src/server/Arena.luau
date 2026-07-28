--[[
	Arena -- builds the closed play area out of code when the server starts.

	Nothing needs to exist in Studio beforehand. If you later want to build the
	arena by hand instead, delete the Arena.build() call in init.server.luau and
	this whole file becomes unused.

	Layout, from the middle outwards:
	  - a flat floor
	  - low walls you can vault over
	  - tall pillars you can hide behind and break line of sight
	  - scattered crates
	  - solid perimeter walls so nobody escapes
	  - a ring of spawn points
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Arena = {}

local HALF = Config.ARENA_SIZE / 2
local FLOOR_TOP = Config.FLOOR_Y

-- Colours, kept together so the whole arena is easy to re-theme.
local COLOR_FLOOR = Color3.fromRGB(56, 58, 64)
local COLOR_WALL = Color3.fromRGB(38, 40, 46)
local COLOR_TRIM = Color3.fromRGB(255, 94, 58)
local COLOR_OBSTACLE = Color3.fromRGB(88, 92, 100)
local COLOR_CRATE = Color3.fromRGB(126, 100, 72)

local model: Model? = nil
local spawnPoints: { CFrame } = {}

-- Small helper so every part below is one readable line instead of eight.
local function build(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, className: string?): BasePart
	local part = Instance.new(className or "Part") :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.Concrete
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	Creates the arena in Workspace. Safe to call more than once -- the previous
	arena is cleared out first, so a Rojo re-sync never leaves two behind.
]]
function Arena.build(): Model
	local existing = workspace:FindFirstChild("Arena")
	if existing then
		existing:Destroy()
	end

	local arena = Instance.new("Model")
	arena.Name = "Arena"

	--- FLOOR ----------------------------------------------------------------
	-- Tagged rather than found by name, so a hand-built map only has to tick
	-- the same tag in Studio's Tag Editor for Ice Shoes to work on it.
	CollectionService:AddTag(
		build(
			arena,
			"Floor",
			Vector3.new(Config.ARENA_SIZE, 2, Config.ARENA_SIZE),
			CFrame.new(0, FLOOR_TOP - 1, 0),
			COLOR_FLOOR,
			Enum.Material.Slate
		),
		Config.TAG_FLOOR
	)

	--- PERIMETER WALLS ------------------------------------------------------
	local wallY = FLOOR_TOP + Config.WALL_HEIGHT / 2
	local wallSpecs = {
		{ Vector3.new(Config.ARENA_SIZE + 8, Config.WALL_HEIGHT, 4), Vector3.new(0, wallY, -HALF - 2) },
		{ Vector3.new(Config.ARENA_SIZE + 8, Config.WALL_HEIGHT, 4), Vector3.new(0, wallY, HALF + 2) },
		{ Vector3.new(4, Config.WALL_HEIGHT, Config.ARENA_SIZE + 8), Vector3.new(-HALF - 2, wallY, 0) },
		{ Vector3.new(4, Config.WALL_HEIGHT, Config.ARENA_SIZE + 8), Vector3.new(HALF + 2, wallY, 0) },
	}
	for i, spec in wallSpecs do
		local wall = build(arena, "Wall" .. i, spec[1], CFrame.new(spec[2]), COLOR_WALL, Enum.Material.Metal)
		-- A glowing strip along the top edge, purely so the arena reads well.
		local trimSize = if wall.Size.X > wall.Size.Z
			then Vector3.new(wall.Size.X, 0.6, wall.Size.Z + 0.4)
			else Vector3.new(wall.Size.X + 0.4, 0.6, wall.Size.Z)
		build(
			arena,
			"Trim" .. i,
			trimSize,
			CFrame.new(spec[2] + Vector3.new(0, Config.WALL_HEIGHT / 2, 0)),
			COLOR_TRIM,
			Enum.Material.Neon
		).CanCollide = false
	end

	--- LOW WALLS TO VAULT ---------------------------------------------------
	-- 4 studs tall. A default Roblox jump clears about 7 studs, so these are
	-- hoppable but they still slow a chase down.
	local vaultY = FLOOR_TOP + 2
	local vaultSpecs = {
		{ Vector3.new(38, 4, 3), CFrame.new(-34, vaultY, -34) },
		{ Vector3.new(3, 4, 38), CFrame.new(34, vaultY, -34) },
		{ Vector3.new(38, 4, 3), CFrame.new(34, vaultY, 34) },
		{ Vector3.new(3, 4, 38), CFrame.new(-34, vaultY, 34) },
		{ Vector3.new(30, 4, 3), CFrame.new(0, vaultY, 0) },
	}
	for i, spec in vaultSpecs do
		-- Also walkable, so also iceable.
		CollectionService:AddTag(
			build(arena, "LowWall" .. i, spec[1], spec[2], COLOR_OBSTACLE, Enum.Material.Concrete),
			Config.TAG_FLOOR
		)
	end

	--- PILLARS --------------------------------------------------------------
	-- Tall enough to break line of sight, so the holder can lose you.
	local PILLAR_COUNT = 8
	local PILLAR_RADIUS = 58
	local PILLAR_HEIGHT = 16
	for i = 1, PILLAR_COUNT do
		local angle = (i / PILLAR_COUNT) * math.pi * 2
		local pos = Vector3.new(
			math.cos(angle) * PILLAR_RADIUS,
			FLOOR_TOP + PILLAR_HEIGHT / 2,
			math.sin(angle) * PILLAR_RADIUS
		)
		build(arena, "Pillar" .. i, Vector3.new(7, PILLAR_HEIGHT, 7), CFrame.new(pos), COLOR_WALL, Enum.Material.Metal)
	end

	--- SCATTERED CRATES -----------------------------------------------------
	-- Seeded so the layout is identical every time you press Play. Change the
	-- number 2024 to get a different but still repeatable scatter.
	local rng = Random.new(2024)
	for i = 1, 14 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(18, HALF - 18)
		local height = rng:NextNumber(3, 5)
		local width = rng:NextNumber(4, 8)
		local pos = Vector3.new(math.cos(angle) * dist, FLOOR_TOP + height / 2, math.sin(angle) * dist)
		local crate = build(
			arena,
			"Crate" .. i,
			Vector3.new(width, height, width),
			CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			COLOR_CRATE,
			Enum.Material.WoodPlanks
		)
		crate.TopSurface = Enum.SurfaceType.Smooth
		CollectionService:AddTag(crate, Config.TAG_FLOOR)
	end

	--- PICKUP ZONE ----------------------------------------------------------
	-- An invisible box saying "pickups may appear anywhere in here". Pickups
	-- pick a random spot inside it and ray straight down to find the ground.
	--
	-- A hand-built map just needs one or more parts carrying this tag -- use
	-- several to cover separate floors of a multi-level map.
	local zone = build(
		arena,
		"PickupZone",
		Vector3.new(Config.ARENA_SIZE - 24, 24, Config.ARENA_SIZE - 24),
		CFrame.new(0, FLOOR_TOP + 12, 0),
		COLOR_TRIM,
		Enum.Material.Neon
	)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	CollectionService:AddTag(zone, Config.TAG_PICKUP_ZONE)

	--- SPAWN POINTS ---------------------------------------------------------
	-- Ten evenly spaced points in a ring, all facing the middle. These are real
	-- SpawnLocations so the arena still works if you strip out the game logic,
	-- but the round manager also places players on them explicitly.
	spawnPoints = {}
	local SPAWN_RADIUS = HALF - 22
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * SPAWN_RADIUS, FLOOR_TOP + 3, math.sin(angle) * SPAWN_RADIUS)
		local pad = build(
			arena,
			"Spawn" .. i,
			Vector3.new(6, 1, 6),
			CFrame.new(pos - Vector3.new(0, 2.5, 0)),
			COLOR_TRIM,
			Enum.Material.Neon,
			"SpawnLocation"
		) :: SpawnLocation
		pad.Neutral = true
		pad.Duration = 0 -- no forcefield bubble on spawn
		spawnPoints[i] = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
	end

	arena.Parent = workspace
	model = arena
	return arena
end

--[[
	Returns spawn CFrames, shuffled, so players are spread around the ring
	rather than piling onto the same pad every round.
]]
function Arena.getShuffledSpawns(): { CFrame }
	local copy = table.clone(spawnPoints)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

function Arena.getModel(): Model?
	return model
end

--=============================================================================
-- LOOKING AT THE MAP IN STUDIO
--=============================================================================
--[[
	The arena only exists while the game is running, because it is built from
	scratch every time the server starts. That is what makes Config able to
	drive the layout -- but it also means Edit mode shows you an empty
	Workspace, with nothing to click on or measure.

	preview() drops a real copy into Edit mode so you can look at it.

	Paste this into the Studio command bar (View -> Command Bar):

		require(game.ServerScriptService.Server.Arena).preview()

	and to take it away again:

		require(game.ServerScriptService.Server.Arena).clearPreview()

	The preview is marked Archivable = false, which means Roblox will not save
	or publish it with the place. So you can leave it lying there, poke at it,
	and it will never end up in the live game by accident. Pressing Play also
	replaces it with a freshly built one, so it can never go stale.
]]
function Arena.preview(): Model
	local arena = Arena.build()

	-- The property you found: excluded from saving, publishing and Clone().
	arena.Archivable = false

	local note = Instance.new("StringValue")
	note.Name = "PREVIEW_ONLY"
	note.Value = "Built by Arena.preview() for looking at in Studio. Not saved or published."
	note.Parent = arena

	return arena
end

function Arena.clearPreview()
	local existing = workspace:FindFirstChild("Arena")
	if existing then
		existing:Destroy()
	end
	model = nil
end

return Arena
