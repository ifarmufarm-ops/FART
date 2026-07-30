--!strict
--[[
	Lobby -- where players stand when they are not in a round.

	Built from code at server start, exactly like Arena, and deliberately the
	same shape as that file: build / getShuffledSpawns / getModel / preview /
	clearPreview. If you learn one you know the other, and the map stage can
	replace either with a hand-built model the same way.

	It sits a long way from the arena in the same place, so moving between them
	is a PivotTo rather than a teleport -- no loading screen, and no second
	server.

	ONE RULE WORTH KNOWING: the lobby floor must never carry Config.TAG_FLOOR.
	That tag is what Ice Shoes freezes, and it does not know or care which
	building you are standing in. Tagging the lobby floor would ice the lobby
	every time somebody in the arena grabbed the beacon. See LOBBY_PLAN.md.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MovementGuard = require(script.Parent.MovementGuard)

local Lobby = {}

local respawnerRunning = false

local CENTER = Config.LOBBY_CENTER
local HALF = Config.LOBBY_SIZE / 2
local FLOOR_TOP = CENTER.Y

-- Warmer than the arena on purpose: the two places should never be mistaken
-- for each other at a glance, least of all by a player who has just respawned.
local COLOR_FLOOR = Color3.fromRGB(70, 66, 84)
local COLOR_WALL = Color3.fromRGB(48, 45, 60)
local COLOR_TRIM = Color3.fromRGB(126, 214, 255)
local COLOR_PLINTH = Color3.fromRGB(92, 88, 108)

local model: Model? = nil
local spawnPoints: { CFrame } = {}

-- Same one-line helper as Arena, for the same reason.
local function build(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	className: string?
): BasePart
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
	Creates the lobby in Workspace. Safe to call more than once.
]]
function Lobby.build(): Model
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end

	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"

	--- FLOOR ----------------------------------------------------------------
	-- NOT tagged. See the header, and LOBBY_PLAN.md.
	build(
		lobby,
		"Floor",
		Vector3.new(Config.LOBBY_SIZE, 2, Config.LOBBY_SIZE),
		CFrame.new(CENTER.X, FLOOR_TOP - 1, CENTER.Z),
		COLOR_FLOOR,
		Enum.Material.Marble
	)

	--- PERIMETER WALLS ------------------------------------------------------
	-- Low enough to see over towards the arena, high enough that a fart jump
	-- does not put anyone into the void.
	local wallY = FLOOR_TOP + Config.LOBBY_WALL_HEIGHT / 2
	local wallSpecs = {
		{ Vector3.new(Config.LOBBY_SIZE + 8, Config.LOBBY_WALL_HEIGHT, 4), Vector3.new(0, 0, -HALF - 2) },
		{ Vector3.new(Config.LOBBY_SIZE + 8, Config.LOBBY_WALL_HEIGHT, 4), Vector3.new(0, 0, HALF + 2) },
		{ Vector3.new(4, Config.LOBBY_WALL_HEIGHT, Config.LOBBY_SIZE + 8), Vector3.new(-HALF - 2, 0, 0) },
		{ Vector3.new(4, Config.LOBBY_WALL_HEIGHT, Config.LOBBY_SIZE + 8), Vector3.new(HALF + 2, 0, 0) },
	}
	for i, spec in wallSpecs do
		local offset = spec[2] :: Vector3
		local wall = build(
			lobby,
			"Wall" .. i,
			spec[1] :: Vector3,
			CFrame.new(CENTER.X + offset.X, wallY, CENTER.Z + offset.Z),
			COLOR_WALL,
			Enum.Material.Slate
		)
		local trimSize = if wall.Size.X > wall.Size.Z
			then Vector3.new(wall.Size.X, 0.6, wall.Size.Z + 0.4)
			else Vector3.new(wall.Size.X + 0.4, 0.6, wall.Size.Z)
		build(
			lobby,
			"Trim" .. i,
			trimSize,
			wall.CFrame * CFrame.new(0, Config.LOBBY_WALL_HEIGHT / 2, 0),
			COLOR_TRIM,
			Enum.Material.Neon
		).CanCollide = false
	end

	--- CENTRE PLINTH --------------------------------------------------------
	-- Somewhere for the eye to land, and the obvious spot for the queue pad to
	-- sit on in the next stage.
	build(
		lobby,
		"Plinth",
		Vector3.new(24, 1, 24),
		CFrame.new(CENTER.X, FLOOR_TOP + 0.5, CENTER.Z),
		COLOR_PLINTH,
		Enum.Material.Marble
	)

	--- SPAWN POINTS ---------------------------------------------------------
	-- Parented first so the clearance check below can query the geometry --
	-- the same ordering, and the same reason, as Arena.
	lobby.Parent = workspace

	spawnPoints = {}
	local SPAWN_RADIUS = HALF - 18
	local PAD_THICKNESS = 1
	local padTop = FLOOR_TOP + PAD_THICKNESS
	-- Players are placed by their ROOT, which sits about 3 studs above their
	-- feet. Getting this wrong is what had everyone spawning inside the arena
	-- floor -- see Config.SPAWN_ROOT_HEIGHT.
	local spawnY = padTop + Config.SPAWN_ROOT_HEIGHT + Config.SPAWN_CLEARANCE

	local STAND_SIZE = Vector3.new(2.5, 5.5, 2.5)
	local function hasRoomAt(x: number, z: number): boolean
		local centre = Vector3.new(x, padTop + STAND_SIZE.Y / 2, z)
		for _, part in workspace:GetPartBoundsInBox(CFrame.new(centre), STAND_SIZE) do
			if part.CanCollide and part:IsDescendantOf(lobby) and part.Name ~= "Floor" then
				return false
			end
		end
		return true
	end

	for i = 1, Config.LOBBY_SPAWN_COUNT do
		local baseAngle = (i / Config.LOBBY_SPAWN_COUNT) * math.pi * 2
		local angle = baseAngle
		for step = 0, 12 do
			local offset = math.rad(3 * math.ceil(step / 2)) * (if step % 2 == 0 then 1 else -1)
			local try = baseAngle + offset
			if
				hasRoomAt(CENTER.X + math.cos(try) * SPAWN_RADIUS, CENTER.Z + math.sin(try) * SPAWN_RADIUS)
			then
				angle = try
				break
			end
		end

		local pos = Vector3.new(
			CENTER.X + math.cos(angle) * SPAWN_RADIUS,
			spawnY,
			CENTER.Z + math.sin(angle) * SPAWN_RADIUS
		)
		local pad = build(
			lobby,
			"Spawn" .. i,
			Vector3.new(6, PAD_THICKNESS, 6),
			CFrame.new(pos.X, padTop - PAD_THICKNESS / 2, pos.Z),
			COLOR_TRIM,
			Enum.Material.Neon,
			"SpawnLocation"
		) :: SpawnLocation
		pad.Neutral = true
		pad.Duration = 0 -- no forcefield bubble on spawn
		-- These are the ONLY enabled SpawnLocations in the game. The arena's are
		-- disabled in Arena.build(), which is what guarantees that a player who
		-- joins, dies or resets always reappears here and never mid-round.
		pad.Enabled = true
		spawnPoints[i] = CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, CENTER.Z))
	end

	model = lobby
	return lobby
end

--[[
	Lobby spawn CFrames, shuffled, so players do not pile onto one pad.
]]
function Lobby.getShuffledSpawns(): { CFrame }
	local copy = table.clone(spawnPoints)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

function Lobby.getModel(): Model?
	return model
end

--[[
	Moves a player's existing body back to the lobby, without respawning them.

	Used when a round finishes: the winner is still standing in the arena and
	has nothing left to do there, and everybody else has already drifted back.
	Respawning them instead would take their body away and hand them a new one,
	which reads as being killed for winning.
]]
function Lobby.sendToLobby(player: Player): boolean
	local character = player.Character
	if not character or not character.PrimaryPart then
		return false
	end
	local spawns = Lobby.getShuffledSpawns()
	if #spawns == 0 then
		return false
	end

	local ok = pcall(function()
		character:PivotTo(spawns[1])
	end)
	-- Kill any leftover momentum, or somebody who was sprinting when the round
	-- ended arrives in the lobby still travelling and slides off the pad.
	if ok and character.PrimaryPart then
		character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
		character.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
	end

	-- The server just moved them 600 studs. Without this the movement guard
	-- would measure that as the fastest anyone has ever travelled.
	MovementGuard.forgive(player)
	return ok
end

--=============================================================================
-- KEEPING PEOPLE ON THEIR FEET
--=============================================================================
--[[
	Gives a body back to anybody in the lobby who has lost one.

	This exists because RoundManager sets Players.CharacterAutoLoads = false --
	the game hands out every single body itself, so that an eliminated player
	does not pop straight back into the middle of a live round.

	That was safe while every connected player was a participant, because the
	round's own spawnEveryone covered everyone. The moment rounds began taking
	only the queue, everybody else was left with nothing to respawn them: one
	press of Roblox's Reset button, one fall, and they were bodyless forever,
	staring at the spectator camera with no way out. That is a real bug this
	stage introduced, and this is the fix.

	`shouldWait(player)` returns true for somebody who is deliberately without a
	body right now -- eliminated, mid-round, watching the end of the game -- and
	who must be left alone rather than yanked back to the lobby.
]]
function Lobby.startRespawner(shouldWait: (Player) -> boolean)
	if respawnerRunning then
		return
	end
	respawnerRunning = true

	local function needsBody(player: Player): boolean
		local character = player.Character
		if not character or not character.Parent then
			return true
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		-- A corpse counts as no body. Without this, dying in the lobby leaves
		-- you lying on the floor permanently.
		return humanoid == nil or humanoid.Health <= 0
	end

	task.spawn(function()
		while true do
			task.wait(Config.LOBBY_RESPAWN_CHECK)
			for _, player in Players:GetPlayers() do
				if player.Parent ~= Players then
					continue
				end
				if not needsBody(player) or shouldWait(player) then
					continue
				end
				-- Only the lobby's SpawnLocations are enabled, so this always
				-- puts them in the lobby and never into a running round.
				pcall(function()
					player:LoadCharacter()
				end)
			end
		end
	end)
end

--=============================================================================
-- LOOKING AT THE LOBBY IN STUDIO
--=============================================================================
--[[
	Same as Arena. The lobby only exists while the game is running, so Edit mode
	shows an empty Workspace. To drop a real copy in and look at it, paste this
	into the command bar (View -> Command Bar):

		require(game.ServerScriptService.Server.Lobby).preview()

	and to take it away again:

		require(game.ServerScriptService.Server.Lobby).clearPreview()

	It is marked Archivable = false, so Roblox will never save or publish it.
]]
function Lobby.preview(): Model
	local lobby = Lobby.build()
	lobby.Archivable = false

	local note = Instance.new("StringValue")
	note.Name = "PREVIEW_ONLY"
	note.Value = "Built by Lobby.preview() for looking at in Studio. Not saved or published."
	note.Parent = lobby

	return lobby
end

function Lobby.clearPreview()
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	model = nil
end

return Lobby
