--!strict
--[[
	GhostClicker -- the thing ghosts punch while they wait.

	A meme-faced lump standing in the middle of the ghost platform. Hit it and
	it rocks back, thumps, and the counter above its head goes up. That is the
	whole feature: somewhere for a knocked-out player's hands to go so that
	being out of the round is not four minutes of standing still.

	ON ANIMATION. Roblox's proper animation system needs an uploaded animation
	asset tied to an account, which this project deliberately has none of -- the
	same reason the sounds and the face are placeholders. So the reaction is
	done with TweenService instead: the body is tweened backwards and squashed,
	and the head follows because it is welded on. That needs nothing uploaded,
	works on every platform, and can be swapped for a real animation later
	without changing anything else here.

	Only ghosts may punch it. The check is on the server, because a ClickDetector
	will happily fire for anybody who can reach it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local GhostClicker = {}

local COLOR_BODY = Color3.fromRGB(196, 108, 220)
local COLOR_HIT = Color3.fromRGB(255, 224, 120)

local model: Model? = nil
local body: BasePart? = nil
local head: BasePart? = nil
local countLabel: TextLabel? = nil
local thump: Sound? = nil

-- How many times it has been hit, in total and by each player. In memory only:
-- it resets when the server restarts. Saving it properly belongs with the rest
-- of the stats work, which is a later stage.
local totalPunches = 0
local punchesBy: { [Player]: number } = {}

-- Who is allowed to hit it. Wired from init.server.luau.
local canPunch: (Player) -> boolean = function()
	return false
end

function GhostClicker.setPunchCheck(check: (Player) -> boolean)
	canPunch = check
end

--=============================================================================
-- BUILDING IT
--=============================================================================

local function refreshLabel()
	local label = countLabel
	if not label then
		return
	end
	label.Text = if totalPunches == 1 then "1 punch" else ("%d punches"):format(totalPunches)
end

--[[
	Builds the punching bag in the middle of the ghost platform.

	Call after GhostArea.build(), which is what it stands on.
]]
function GhostClicker.build(): Model
	local existing = workspace:FindFirstChild("GhostClicker")
	if existing then
		existing:Destroy()
	end

	local centre = Config.ARENA_CENTER + Vector3.new(0, Config.GHOST_HEIGHT, 0)

	local rig = Instance.new("Model")
	rig.Name = "GhostClicker"

	-- The body is anchored and is the only thing that gets moved. The head is
	-- welded to it and unanchored, so it comes along for the ride -- that is
	-- what lets one tween animate the whole thing.
	local torso = Instance.new("Part")
	torso.Name = "Body"
	torso.Size = Vector3.new(5, 6, 3)
	torso.CFrame = CFrame.new(centre.X, centre.Y + 3, centre.Z)
	torso.Color = COLOR_BODY
	torso.Material = Enum.Material.SmoothPlastic
	torso.Anchored = true
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Parent = rig

	local noggin = Instance.new("Part")
	noggin.Name = "Head"
	noggin.Size = Vector3.new(4, 4, 4)
	noggin.CFrame = torso.CFrame * CFrame.new(0, 5, 0)
	noggin.Color = COLOR_BODY
	noggin.Material = Enum.Material.SmoothPlastic
	noggin.Anchored = false
	noggin.CanCollide = false
	noggin.TopSurface = Enum.SurfaceType.Smooth
	noggin.BottomSurface = Enum.SurfaceType.Smooth
	noggin.Parent = rig

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = noggin
	weld.Parent = torso

	-- PLACEHOLDER face, the same built-in one the Brain Rot NPC uses, so it has
	-- a face today without anything being uploaded.
	local face = Instance.new("Decal")
	face.Name = "Face"
	face.Texture = Config.BRAINROT_FACE
	face.Face = Enum.NormalId.Front
	face.Parent = noggin

	rig.PrimaryPart = torso

	--- THE SIGN ------------------------------------------------------------
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Counter"
	billboard.Size = UDim2.fromOffset(260, 70)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	billboard.Adornee = noggin
	billboard.Parent = noggin

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.5, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "PUNCH ME"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Parent = billboard

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Position = UDim2.new(0, 0, 0.5, 0)
	count.Size = UDim2.new(1, 0, 0.5, 0)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamMedium
	count.TextColor3 = COLOR_HIT
	count.TextScaled = true
	count.Parent = billboard

	--- THE THUMP -----------------------------------------------------------
	-- Parented to the body so it plays from where the thing is, and given a
	-- short range so the ghosts hear it and the arena below does not.
	local sound = Instance.new("Sound")
	sound.Name = "Thump"
	sound.SoundId = Config.CLICKER_SOUND
	sound.Volume = 0.6
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = Config.CLICKER_SOUND_RANGE
	sound.Parent = torso

	--- THE HIT -------------------------------------------------------------
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = Config.CLICKER_CLICK_DISTANCE
	detector.Parent = torso

	detector.MouseClick:Connect(function(player)
		GhostClicker.punch(player)
	end)

	-- The head is worth hitting too, and a ClickDetector only covers the part
	-- it is parented to.
	local headDetector = Instance.new("ClickDetector")
	headDetector.MaxActivationDistance = Config.CLICKER_CLICK_DISTANCE
	headDetector.Parent = noggin
	headDetector.MouseClick:Connect(function(player)
		GhostClicker.punch(player)
	end)

	rig.Parent = workspace

	model = rig
	body = torso
	head = noggin
	countLabel = count
	thump = sound
	refreshLabel()
	return rig
end

--=============================================================================
-- BEING PUNCHED
--=============================================================================

-- Bumped on every hit, so a rapid series of punches does not have several
-- recoils fighting each other over where the body should be.
local recoilToken = 0

local function playRecoil(fromDirection: Vector3)
	local torso = body
	if not torso then
		return
	end

	recoilToken += 1
	local myToken = recoilToken

	local resting = CFrame.new(torso.Position)

	-- Tip away from whoever hit it, so a punch from the front knocks it
	-- backwards and one from the side knocks it sideways.
	local flat = Vector3.new(fromDirection.X, 0, fromDirection.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, 1)
	end
	flat = flat.Unit
	local axis = Vector3.new(-flat.Z, 0, flat.X) -- perpendicular, so it tips over
	local knocked = resting * CFrame.fromAxisAngle(axis, math.rad(Config.CLICKER_RECOIL_ANGLE))

	local hit = TweenService:Create(
		torso,
		TweenInfo.new(Config.CLICKER_RECOIL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = knocked, Color = COLOR_HIT }
	)
	hit:Play()

	task.delay(Config.CLICKER_RECOIL_TIME, function()
		if recoilToken ~= myToken or not torso.Parent then
			return -- hit again since; that punch owns the body now
		end
		-- Springs back more slowly than it was knocked, which is what sells it.
		TweenService
			:Create(
				torso,
				TweenInfo.new(Config.CLICKER_RECOVER_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ CFrame = resting, Color = COLOR_BODY }
			)
			:Play()
	end)
end

--[[
	Registers a punch. Refused for anybody who is not a ghost.

	Returns the new total, or nil if it was refused.
]]
function GhostClicker.punch(player: Player): number?
	if not canPunch(player) then
		return nil
	end

	local torso = body
	if not torso then
		return nil
	end

	-- Has to actually be within reach. A ClickDetector enforces its own
	-- distance, but the server should not take a client's word for it.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local offset = root.Position - torso.Position
	if offset.Magnitude > Config.CLICKER_CLICK_DISTANCE + 6 then
		return nil
	end

	totalPunches += 1
	punchesBy[player] = (punchesBy[player] or 0) + 1
	refreshLabel()

	if thump then
		thump.TimePosition = 0
		thump:Play()
	end
	playRecoil(offset)

	return totalPunches
end

function GhostClicker.getTotal(): number
	return totalPunches
end

function GhostClicker.getPunchesBy(player: Player): number
	return punchesBy[player] or 0
end

Players.PlayerRemoving:Connect(function(player)
	punchesBy[player] = nil
end)

--=============================================================================
-- LOOKING AT IT IN STUDIO
--=============================================================================
--     require(game.ServerScriptService.Server.GhostClicker).preview()
-- Needs the ghost area to exist first, since it stands on it.

function GhostClicker.preview(): Model
	local rig = GhostClicker.build()
	rig.Archivable = false
	return rig
end

function GhostClicker.clearPreview()
	local existing = workspace:FindFirstChild("GhostClicker")
	if existing then
		existing:Destroy()
	end
	model = nil
end

return GhostClicker
