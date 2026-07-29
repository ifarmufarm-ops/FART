--!strict
--[[
	Queue -- who has asked to play.

	A pad in the middle of the lobby. Step on it and you are in the next round;
	step on it again and you are out. Membership is what RoundManager now asks
	for when it picks participants, so this file is the difference between
	"everyone in the server is dragged into every round" and "you play when you
	choose to".

	QUEUEING IS STICKY. You stay in round after round until you step off the
	pad, so nobody has to re-join between games.

	Detection is a distance check on a loop rather than a Touched event, for the
	same reason bomb passing is: Touched is unreliable at speed, fires many
	times, and can be provoked by a modified client. This is the pattern from
	RoundManager.findPassTarget.

	The toggle is EDGE-TRIGGERED -- it fires when you arrive, and will not fire
	again until you have left and come back. Standing on the pad therefore does
	nothing, rather than flickering you in and out several times a second.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Queue = {}

local COLOR_INFO = Color3.fromRGB(235, 238, 245)

-- Who has asked to play. Keyed by Player so leaving is a single delete.
local queued: { [Player]: boolean } = {}

-- Who was within the pad's radius last time we looked, so we can act on the
-- moment they arrive rather than every tick they stay.
local onPad: { [Player]: boolean } = {}

local pad: BasePart? = nil
local countLabel: TextLabel? = nil
local running = false

--=============================================================================
-- THE PAD
--=============================================================================

--[[
	Builds the pad in the middle of the lobby, on top of the plinth.

	Call after Lobby.build(), which creates the plinth it sits on.
]]
function Queue.build(): BasePart
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		error("Queue.build() needs the Lobby to exist -- call Lobby.build() first", 2)
	end

	local existing = lobby:FindFirstChild("QueuePad")
	if existing then
		existing:Destroy()
	end

	local plinth = lobby:FindFirstChild("Plinth") :: BasePart?
	local plinthTop = if plinth then plinth.Position.Y + plinth.Size.Y / 2 else Config.LOBBY_CENTER.Y

	local part = Instance.new("Part")
	part.Name = "QueuePad"
	part.Size = Vector3.new(12, 0.6, 12)
	part.CFrame = CFrame.new(Config.LOBBY_CENTER.X, plinthTop + 0.3, Config.LOBBY_CENTER.Z)
	part.Color = Config.QUEUE_COLOR_IDLE
	part.Material = Enum.Material.Neon
	part.Anchored = true
	-- Walk over it, not into it. A 0.6 stud step is enough to read as a pad
	-- without being something players have to climb.
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = lobby

	-- A sign, because a pad that does not say what it does is a pad nobody
	-- stands on. This is the whole of the queue's UI for now.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "QueueSign"
	billboard.Size = UDim2.new(0, 320, 0, 90)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Parent = part

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "STEP ON TO PLAY"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Parent = billboard

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Position = UDim2.new(0, 0, 0.55, 0)
	count.Size = UDim2.new(1, 0, 0.45, 0)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamMedium
	count.Text = "nobody waiting"
	count.TextColor3 = Config.QUEUE_COLOR_IDLE
	count.TextScaled = true
	count.Parent = billboard

	pad = part
	countLabel = count
	Queue.refreshSign()
	return part
end

--[[
	Keeps the sign honest. Called on every change rather than on a timer.
]]
function Queue.refreshSign()
	local label = countLabel
	local part = pad
	local n = #Queue.getQueued()

	if label then
		label.Text = if n == 0
			then "nobody waiting"
			elseif n == 1 then "1 player waiting"
			else ("%d players waiting"):format(n)
		label.TextColor3 = if n > 0 then Config.QUEUE_COLOR_ACTIVE else Config.QUEUE_COLOR_IDLE
	end
	if part then
		part.Color = if n > 0 then Config.QUEUE_COLOR_ACTIVE else Config.QUEUE_COLOR_IDLE
	end
end

--=============================================================================
-- MEMBERSHIP
--=============================================================================

--[[
	Everyone who has asked to play and is still connected.

	This is the provider RoundManager uses to choose participants. It returns a
	fresh list every call, so nobody can hold onto it and mutate the queue.
]]
function Queue.getQueued(): { Player }
	local list = {}
	for player in queued do
		-- A player who has left is still a key here until the disconnect
		-- handler runs, and the round must never try to spawn a ghost.
		if player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

function Queue.isQueued(player: Player): boolean
	return queued[player] == true
end

--[[
	Puts a player in or takes them out, and tells them which just happened.

	Returns the new state, so callers do not have to ask again.
]]
function Queue.setQueued(player: Player, wantsIn: boolean): boolean
	if queued[player] == wantsIn or (not wantsIn and queued[player] == nil) then
		return wantsIn
	end

	if wantsIn then
		queued[player] = true
		Remotes.Announce:FireClient(player, "You're in for the next round", Config.QUEUE_COLOR_ACTIVE, 2.5)
	else
		queued[player] = nil
		Remotes.Announce:FireClient(player, "You left the queue", COLOR_INFO, 2.5)
	end

	Queue.refreshSign()
	return wantsIn
end

--=============================================================================
-- THE LOOP
--=============================================================================

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--[[
	Starts watching the pad. Safe to call once.
]]
function Queue.start()
	if running then
		return
	end
	running = true

	Players.PlayerRemoving:Connect(function(player)
		queued[player] = nil
		onPad[player] = nil
		Queue.refreshSign()
	end)

	task.spawn(function()
		while true do
			task.wait(Config.QUEUE_CHECK_INTERVAL)

			local part = pad
			if not part then
				continue
			end

			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if not root then
					-- No body: forget where they were, so walking back on after
					-- a respawn counts as arriving rather than being ignored.
					onPad[player] = nil
					continue
				end

				local flat = Vector3.new(root.Position.X - part.Position.X, 0, root.Position.Z - part.Position.Z)
				local inside = flat.Magnitude <= Config.QUEUE_PAD_RADIUS
					-- Vertical check too, so somebody in the arena 600 studs
					-- away can never register, and neither can anyone who has
					-- been launched over the top of the pad.
					and math.abs(root.Position.Y - part.Position.Y) <= 12

				if inside and not onPad[player] then
					-- The moment of arrival: this is the only place the toggle
					-- fires.
					Queue.setQueued(player, not Queue.isQueued(player))
				end
				onPad[player] = inside
			end
		end
	end)
end

return Queue
