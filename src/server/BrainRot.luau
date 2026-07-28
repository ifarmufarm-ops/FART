--[[
	BrainRot -- the meme-faced NPC that turns up and hunts people.

	It chases the nearest player who is NOT holding the bomb, and re-picks its
	victim twice a second, so the moment the bomb changes hands it drops whoever
	it was after and turns on somebody new. The bomb holder is the one person it
	will never touch.

	Catching someone knocks them down for a moment and then they get up. It is
	deliberately not a second way of dying -- its job is to shove people towards
	the bomb, not to compete with it.

	Entirely server-side. There is no input, no client code and nothing to
	press, so it behaves identically on PC, console and phone.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Ragdoll = require(script.Parent.Ragdoll)

local BrainRot = {}

local model: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local loopThread: thread? = nil
local canCatchAt = 0

-- Supplied by RoundManager, which is the only place that knows both of these.
local getAlive: () -> { Player } = function()
	return {}
end
local getHolder: () -> Player? = function()
	return nil
end

--=============================================================================
-- THE RIG
--=============================================================================

local function weld(a: BasePart, b: BasePart)
	local joint = Instance.new("Weld")
	joint.Part0 = a
	joint.Part1 = b
	joint.C0 = a.CFrame:Inverse() * b.CFrame
	joint.Parent = a
end

--[[
	Builds the NPC out of plain parts rather than a real avatar, so it needs no
	uploaded assets and cannot be broken by an avatar failing to load.
]]
local function buildRig(position: Vector3): Model
	local rig = Instance.new("Model")
	rig.Name = "BrainRot"

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(2.6, 2.6, 1.6)
	body.Color = Color3.fromRGB(120, 40, 160)
	body.Material = Enum.Material.SmoothPlastic
	body.CFrame = CFrame.new(position)
	body.CanCollide = true
	body.Parent = rig

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2.2, 2.2, 2.2)
	head.Color = Color3.fromRGB(255, 232, 90)
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = body.CFrame * CFrame.new(0, 2.2, 0)
	head.CanCollide = false
	head.Parent = rig

	local face = Instance.new("Decal")
	face.Name = "Face"
	face.Texture = Config.BRAINROT_FACE
	face.Face = Enum.NormalId.Front
	face.Parent = head

	weld(body, head)

	-- Floating hands, purely so it reads as "coming for you" at a distance.
	for _, side in { -1, 1 } do
		local hand = Instance.new("Part")
		hand.Name = "Hand"
		hand.Shape = Enum.PartType.Ball
		hand.Size = Vector3.new(1, 1, 1)
		hand.Color = Color3.fromRGB(255, 232, 90)
		hand.Material = Enum.Material.SmoothPlastic
		hand.CFrame = body.CFrame * CFrame.new(side * 2, 0.4, -0.6)
		hand.CanCollide = false
		hand.Parent = rig
		weld(body, hand)
	end

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(220, 120, 255)
	glow.Range = 18
	glow.Brightness = 2
	glow.Parent = body

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(220, 40)
	tag.StudsOffset = Vector3.new(0, 3.4, 0)
	tag.AlwaysOnTop = true
	tag.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "BRAIN ROT"
	label.TextColor3 = Color3.fromRGB(230, 150, 255)
	label.TextScaled = true
	label.Parent = tag

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.3
	stroke.Parent = label

	local npcHumanoid = Instance.new("Humanoid")
	npcHumanoid.RigType = Enum.HumanoidRigType.R6
	npcHumanoid.WalkSpeed = Config.BRAINROT_WALK_SPEED
	npcHumanoid.HipHeight = 2
	-- Large and finite rather than math.huge. Nothing can hurt it either way,
	-- but infinities in Humanoid properties are a known source of odd engine
	-- behaviour and buy nothing here.
	npcHumanoid.MaxHealth = 1e6
	npcHumanoid.Health = 1e6
	npcHumanoid.BreakJointsOnDeath = false
	npcHumanoid.Parent = rig

	rig.PrimaryPart = body

	-- Cannot barge into players, still walks on the floor.
	Ragdoll.setCollisionGroup(rig, Ragdoll.NPC_GROUP)

	rig.Parent = workspace
	return rig
end

--=============================================================================
-- PICKING A VICTIM
--=============================================================================

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local part = character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

--[[
	The nearest player who is not holding the bomb.

	Re-run twice a second, so when the bomb is passed the NPC immediately loses
	interest in the new holder and turns on somebody else.
]]
local function pickTarget(): (Player?, BasePart?)
	local myRoot = root
	if not myRoot then
		return nil, nil
	end

	local holder = getHolder()
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = math.huge

	for _, player in getAlive() do
		if player == holder then
			continue -- never chase whoever has the bomb
		end
		local targetRoot = rootOf(player)
		if not targetRoot then
			continue
		end
		local distance = (targetRoot.Position - myRoot.Position).Magnitude
		if distance < bestDistance then
			best = player
			bestRoot = targetRoot
			bestDistance = distance
		end
	end

	return best, bestRoot
end

--=============================================================================
-- CHASING
--=============================================================================

local waypoints: { PathWaypoint } = {}
local waypointIndex = 1

--[[
	Works out a route to the target. Pathfinding rather than a straight line,
	because the arena has pillars and low walls that a naive "walk at them" NPC
	gets permanently wedged against.

	Only called occasionally -- planning is the expensive part, walking is not.
]]
local function replan(goal: Vector3)
	local npcRoot = root
	if not npcRoot then
		return
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 5,
		AgentCanJump = true,
	})

	local ok = pcall(function()
		path:ComputeAsync(npcRoot.Position, goal)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		waypoints = path:GetWaypoints()
		waypointIndex = 2 -- [1] is where we already are
	else
		-- No route (target on top of a crate, say). Walking straight at them is
		-- better than standing still.
		waypoints = {}
		waypointIndex = 1
	end
end

--[[
	Walks the route. Called EVERY tick, not just when re-planning.

	This distinction matters more than it looks. Issuing one MoveTo per re-plan
	meant the NPC walked to a waypoint about four studs away, stopped, and stood
	there until the next plan -- an effective speed of under four studs a second
	against a WalkSpeed of eighteen. Players run at sixteen, so it could be
	strolled away from indefinitely. Following the route continuously and only
	advancing a waypoint once it is reached keeps it at full speed.
]]
local function follow(goal: Vector3)
	local npc, npcRoot = humanoid, root
	if not (npc and npcRoot) then
		return
	end

	local current = waypoints[waypointIndex]
	if not current then
		npc:MoveTo(goal)
		return
	end

	-- Measured flat: the NPC hovers, so height differences would otherwise stop
	-- it ever counting a waypoint as reached.
	local here = Vector3.new(npcRoot.Position.X, 0, npcRoot.Position.Z)
	local there = Vector3.new(current.Position.X, 0, current.Position.Z)
	if (here - there).Magnitude < 4 then
		waypointIndex += 1
		current = waypoints[waypointIndex]
		if not current then
			npc:MoveTo(goal)
			return
		end
	end

	if current.Action == Enum.PathWaypointAction.Jump then
		npc.Jump = true
	end
	npc:MoveTo(current.Position)
end

--=============================================================================
-- CATCHING
--=============================================================================

local function tryCatch()
	local myRoot = root
	if not myRoot or os.clock() < canCatchAt then
		return
	end

	local holder = getHolder()
	for _, player in getAlive() do
		if player == holder then
			continue
		end
		local character = player.Character
		local targetRoot = rootOf(player)
		if not (character and targetRoot) then
			continue
		end
		if Ragdoll.isRagdolled(character) then
			continue -- already down, leave them alone
		end
		if (targetRoot.Position - myRoot.Position).Magnitude > Config.BRAINROT_CATCH_RADIUS then
			continue
		end

		-- Got them. Tackled off their feet, then back up.
		Ragdoll.apply(character)
		Ragdoll.shove(character, targetRoot.Position - myRoot.Position, Config.BRAINROT_SHOVE)
		canCatchAt = os.clock() + Config.BRAINROT_CATCH_COOLDOWN

		task.delay(Config.BRAINROT_KNOCKDOWN, function()
			if character and character.Parent then
				Ragdoll.recover(character)
			end
		end)
		return
	end
end

--=============================================================================
-- LIFECYCLE
--=============================================================================

--[[
	Called by RoundManager, which is the only place that knows both who is still
	in the round and who currently holds the bomb.
]]
function BrainRot.setContext(aliveProvider: () -> { Player }, holderProvider: () -> Player?)
	getAlive = aliveProvider
	getHolder = holderProvider
end

function BrainRot.isActive(): boolean
	return model ~= nil and model.Parent ~= nil
end

function BrainRot.spawn()
	BrainRot.despawn()

	-- Comes in from a random point around the edge of the arena, so it is never
	-- suddenly on top of somebody.
	local angle = math.random() * math.pi * 2
	local radius = Config.ARENA_SIZE / 2 - 14
	local position = Vector3.new(math.cos(angle) * radius, Config.FLOOR_Y + 4, math.sin(angle) * radius)

	local rig = buildRig(position)
	model = rig
	humanoid = rig:FindFirstChildOfClass("Humanoid")
	root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	canCatchAt = 0
	waypoints = {}
	waypointIndex = 1

	loopThread = task.spawn(function()
		local lastTarget = 0
		local lastPath = 0
		local goal: Vector3? = nil

		while BrainRot.isActive() do
			local clock = os.clock()

			if clock - lastTarget >= Config.BRAINROT_RETARGET_INTERVAL then
				lastTarget = clock
				local _, targetRoot = pickTarget()
				goal = if targetRoot then targetRoot.Position else nil
			end

			if goal then
				if clock - lastPath >= Config.BRAINROT_REPATH_INTERVAL then
					lastPath = clock
					replan(goal)
				end
				follow(goal) -- every tick, so it never stalls between plans
			end

			tryCatch()
			task.wait(0.1)
		end
	end)
end

function BrainRot.despawn()
	if loopThread then
		task.cancel(loopThread)
		loopThread = nil
	end
	if model then
		model:Destroy()
	end
	model, humanoid, root = nil, nil, nil
end

return BrainRot
