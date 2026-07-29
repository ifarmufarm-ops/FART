--[[
	Hot Potato Bomb -- client display.

	This file draws things on your screen and nothing else. It never decides
	anything about the game: it is told the state by the server and shows it.
	The countdown you see is worked out locally between updates purely so the
	numbers tick smoothly -- the server's clock is the one that counts.

	On screen:
		- big countdown at the top, going green -> amber -> red
		- who currently has the bomb
		- how many players are left
		- a red glow around the edges when YOU have it
		- centre messages for eliminations and the winner
		- a slow orbiting camera once you are out
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local COLOR_SAFE = Color3.fromRGB(126, 232, 148)
local COLOR_WARN = Color3.fromRGB(255, 205, 84)
local COLOR_DANGER = Color3.fromRGB(255, 84, 66)
local COLOR_DIM = Color3.fromRGB(206, 212, 224)

--=============================================================================
-- BUILD THE INTERFACE
--=============================================================================

local gui = Instance.new("ScreenGui")
gui.Name = "HotPotatoHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Red glow around the screen edges, shown only while you hold the bomb.
local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.Visible = false
vignette.ZIndex = 1
vignette.Parent = gui

local vignetteEdges: { Frame } = {}
do
	local edges = {
		{ UDim2.new(1, 0, 0, 150), UDim2.fromScale(0, 0), Vector2.new(0, 0), 90 },
		{ UDim2.new(1, 0, 0, 150), UDim2.fromScale(0, 1), Vector2.new(0, 1), 270 },
		{ UDim2.new(0, 220, 1, 0), UDim2.fromScale(0, 0), Vector2.new(0, 0), 0 },
		{ UDim2.new(0, 220, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180 },
	}
	for i, spec in edges do
		local edge = Instance.new("Frame")
		edge.Name = "Edge" .. i
		edge.Size = spec[1]
		edge.Position = spec[2]
		edge.AnchorPoint = spec[3]
		edge.BackgroundColor3 = COLOR_DANGER
		edge.BorderSizePixel = 0
		edge.ZIndex = 1
		edge.Parent = vignette

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[4]
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge

		vignetteEdges[i] = edge
	end
end

-- Top-centre block: countdown, progress bar, and who has the bomb.
local topPanel = Instance.new("Frame")
topPanel.Name = "TopPanel"
topPanel.AnchorPoint = Vector2.new(0.5, 0)
topPanel.Position = UDim2.new(0.5, 0, 0, 18)
topPanel.Size = UDim2.new(0, 420, 0, 130)
topPanel.BackgroundTransparency = 1
topPanel.ZIndex = 3
topPanel.Parent = gui

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.AnchorPoint = Vector2.new(0.5, 0)
timerLabel.Position = UDim2.new(0.5, 0, 0, 0)
timerLabel.Size = UDim2.new(1, 0, 0, 78)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.Text = "--"
timerLabel.TextColor3 = COLOR_DIM
timerLabel.TextScaled = true
timerLabel.ZIndex = 3
timerLabel.Parent = topPanel

local timerStroke = Instance.new("UIStroke")
timerStroke.Thickness = 3
timerStroke.Color = Color3.fromRGB(0, 0, 0)
timerStroke.Transparency = 0.55
timerStroke.Parent = timerLabel

local barBack = Instance.new("Frame")
barBack.Name = "BarBackground"
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.new(0.5, 0, 0, 82)
barBack.Size = UDim2.new(0, 300, 0, 8)
barBack.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
barBack.BackgroundTransparency = 0.35
barBack.BorderSizePixel = 0
barBack.ZIndex = 3
barBack.Parent = topPanel
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = COLOR_SAFE
barFill.BorderSizePixel = 0
barFill.ZIndex = 4
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.Position = UDim2.new(0.5, 0, 0, 98)
statusLabel.Size = UDim2.new(1, 0, 0, 26)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Text = "Connecting..."
statusLabel.TextColor3 = COLOR_DIM
statusLabel.TextScaled = true
statusLabel.ZIndex = 3
statusLabel.Parent = topPanel

local statusStroke = Instance.new("UIStroke")
statusStroke.Thickness = 2
statusStroke.Color = Color3.fromRGB(0, 0, 0)
statusStroke.Transparency = 0.55
statusStroke.Parent = statusLabel

-- Players remaining, top right.
local aliveLabel = Instance.new("TextLabel")
aliveLabel.Name = "AliveCount"
aliveLabel.AnchorPoint = Vector2.new(1, 0)
aliveLabel.Position = UDim2.new(1, -22, 0, 22)
aliveLabel.Size = UDim2.new(0, 180, 0, 30)
aliveLabel.BackgroundTransparency = 1
aliveLabel.Font = Enum.Font.GothamBold
aliveLabel.Text = ""
aliveLabel.TextColor3 = COLOR_DIM
aliveLabel.TextScaled = true
aliveLabel.TextXAlignment = Enum.TextXAlignment.Right
aliveLabel.ZIndex = 3
aliveLabel.Parent = gui

local aliveStroke = Instance.new("UIStroke")
aliveStroke.Thickness = 2
aliveStroke.Color = Color3.fromRGB(0, 0, 0)
aliveStroke.Transparency = 0.55
aliveStroke.Parent = aliveLabel

-- Big centre message for eliminations and the winner.
local announceLabel = Instance.new("TextLabel")
announceLabel.Name = "Announcement"
announceLabel.AnchorPoint = Vector2.new(0.5, 0.5)
announceLabel.Position = UDim2.new(0.5, 0, 0.34, 0)
announceLabel.Size = UDim2.new(0, 700, 0, 60)
announceLabel.BackgroundTransparency = 1
announceLabel.Font = Enum.Font.GothamBlack
announceLabel.Text = ""
announceLabel.TextColor3 = COLOR_DIM
announceLabel.TextScaled = true
announceLabel.TextTransparency = 1
announceLabel.ZIndex = 5
announceLabel.Parent = gui

local announceStroke = Instance.new("UIStroke")
announceStroke.Thickness = 3
announceStroke.Color = Color3.fromRGB(0, 0, 0)
announceStroke.Transparency = 1
announceStroke.Parent = announceLabel

-- LEAVE SPECTATING (only while you are out of the round)
--
-- Being blown up should not trap you watching. This appears once you have no
-- body left and takes you back to the lobby, where you can wander about, try
-- the pickups, or just wait for the next round somewhere more interesting than
-- an orbiting camera. It hides itself the moment you have a body again.
local leaveButton = Instance.new("TextButton")
leaveButton.Name = "LeaveSpectate"
leaveButton.AnchorPoint = Vector2.new(0.5, 1)
-- Well clear of the bottom edge: consoles crop about 5% of the screen, and the
-- ability button lives in the bottom-right corner on touch.
leaveButton.Position = UDim2.new(0.5, 0, 1, -110)
leaveButton.Size = UDim2.new(0, 260, 0, 52)
leaveButton.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
leaveButton.BackgroundTransparency = 0.15
leaveButton.Font = Enum.Font.GothamBold
leaveButton.Text = "Back to the lobby"
leaveButton.TextColor3 = Color3.fromRGB(235, 238, 245)
leaveButton.TextSize = 20
leaveButton.AutoButtonColor = true
leaveButton.Visible = false
leaveButton.ZIndex = 6
leaveButton.Parent = gui

Instance.new("UICorner", leaveButton).CornerRadius = UDim.new(0, 10)
local leaveStroke = Instance.new("UIStroke")
leaveStroke.Thickness = 2
leaveStroke.Color = Color3.fromRGB(126, 214, 255)
leaveStroke.Transparency = 0.3
leaveStroke.Parent = leaveButton

leaveButton.Activated:Connect(function()
	-- Hide at once so it cannot be pressed twice while the server catches up.
	-- If the server refuses, the per-frame check below puts it straight back.
	leaveButton.Visible = false
	Remotes.LeaveRound:FireServer()
end)

--=============================================================================
-- ABILITY SLOT (bottom centre)
--=============================================================================

local slot = Instance.new("Frame")
slot.Name = "AbilitySlot"
slot.AnchorPoint = Vector2.new(0.5, 1)
slot.Position = UDim2.new(0.5, 0, 1, -26)
slot.Size = UDim2.new(0, 280, 0, 66)
slot.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
slot.BackgroundTransparency = 0.25
slot.BorderSizePixel = 0
slot.Visible = false
slot.ZIndex = 4
slot.Parent = gui
Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 10)

local slotStroke = Instance.new("UIStroke")
slotStroke.Thickness = 2
slotStroke.Color = COLOR_DIM
slotStroke.Parent = slot

local slotIcon = Instance.new("TextLabel")
slotIcon.Name = "Icon"
slotIcon.AnchorPoint = Vector2.new(0, 0.5)
slotIcon.Position = UDim2.new(0, 12, 0.5, 0)
slotIcon.Size = UDim2.fromOffset(44, 44)
slotIcon.BackgroundTransparency = 1
slotIcon.Font = Enum.Font.GothamBlack
slotIcon.Text = ""
slotIcon.TextColor3 = Color3.new(1, 1, 1)
slotIcon.TextScaled = true
slotIcon.ZIndex = 5
slotIcon.Parent = slot

local slotName = Instance.new("TextLabel")
slotName.Name = "AbilityName"
slotName.Position = UDim2.new(0, 64, 0, 10)
slotName.Size = UDim2.new(1, -140, 0, 24)
slotName.BackgroundTransparency = 1
slotName.Font = Enum.Font.GothamBlack
slotName.Text = ""
slotName.TextColor3 = Color3.new(1, 1, 1)
slotName.TextScaled = true
slotName.TextXAlignment = Enum.TextXAlignment.Left
slotName.ZIndex = 5
slotName.Parent = slot

local slotHint = Instance.new("TextLabel")
slotHint.Name = "Hint"
slotHint.Position = UDim2.new(0, 64, 0, 34)
slotHint.Size = UDim2.new(1, -140, 0, 20)
slotHint.BackgroundTransparency = 1
slotHint.Font = Enum.Font.GothamBold
slotHint.Text = ""
slotHint.TextColor3 = COLOR_DIM
slotHint.TextScaled = true
slotHint.TextXAlignment = Enum.TextXAlignment.Left
slotHint.ZIndex = 5
slotHint.Parent = slot

-- Use pips, stacked up the right-hand edge. One lit pip per use remaining --
-- the most readable way to show "3 left" at a glance without reading a number.
local slotPips: { Frame } = {}
do
	local column = Instance.new("Frame")
	column.Name = "Uses"
	column.AnchorPoint = Vector2.new(1, 0.5)
	column.Position = UDim2.new(1, -14, 0.5, 0)
	column.Size = UDim2.fromOffset(18, 46)
	column.BackgroundTransparency = 1
	column.ZIndex = 5
	column.Parent = slot

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = column

	for i = 1, Config.ABILITY_USES do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.fromOffset(16, 10)
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = COLOR_DIM
		pip.LayoutOrder = i
		pip.ZIndex = 5
		pip.Parent = column
		Instance.new("UICorner", pip).CornerRadius = UDim.new(0, 3)
		slotPips[i] = pip
	end
end

--=============================================================================
-- STATE FROM THE SERVER
--=============================================================================

local state = {
	phase = "Waiting",
	holderUserId = nil :: number?,
	deadline = nil :: number?,
	duration = nil :: number?,
	aliveUserIds = {} :: { number },
}

local isHolder = false

local function nameFor(userId: number?): string
	if not userId then
		return "Nobody"
	end
	local other = Players:GetPlayerByUserId(userId)
	return if other then other.DisplayName else "Someone"
end

Remotes.StateChanged.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	state = payload
	state.aliveUserIds = state.aliveUserIds or {}
	isHolder = state.holderUserId == player.UserId

	vignette.Visible = isHolder

	-- The whole round HUD -- countdown, bar, status line, survivor count -- is
	-- only for people who have asked to play. Somebody wandering round the
	-- lobby who has not stepped on the pad does not need a timer, and "waiting
	-- for players" implies the game is waiting on them when it is not.
	local showRoundHud = state.queued ~= false
	topPanel.Visible = showRoundHud
	statusLabel.Visible = showRoundHud
	aliveLabel.Visible = showRoundHud

	if state.phase == "Playing" then
		aliveLabel.Text = #state.aliveUserIds .. " left"
		if isHolder then
			statusLabel.Text = "YOU HAVE THE BOMB -- RUN!"
			statusLabel.TextColor3 = COLOR_DANGER
		else
			statusLabel.Text = nameFor(state.holderUserId) .. " has the bomb"
			statusLabel.TextColor3 = COLOR_DIM
		end
	elseif state.phase == "Sandbox" then
		aliveLabel.Text = "TEST MODE"
		statusLabel.Text = "Sandbox — no bomb, no elimination"
		statusLabel.TextColor3 = COLOR_WARN
	elseif state.phase == "Intermission" then
		aliveLabel.Text = ""
		statusLabel.Text = "Next round starting"
		statusLabel.TextColor3 = COLOR_DIM
	elseif state.phase == "RoundOver" then
		aliveLabel.Text = ""
		statusLabel.Text = "Round over"
		statusLabel.TextColor3 = COLOR_DIM
	else
		aliveLabel.Text = ""
		statusLabel.Text = "Waiting for players"
		statusLabel.TextColor3 = COLOR_DIM
	end
end)

--=============================================================================
-- ABILITY INPUT
--=============================================================================
-- AbilityInput owns the button and the movement; all this does is redraw the
-- slot whenever what you are carrying changes.

local AbilityInput = require(script.AbilityInput)

-- Beacon-event visuals and the reverse-controls override live in their own
-- file; they are independent of the round HUD.
require(script.ScreenEffects).start()

AbilityInput.start(function(definition, usesLeft)
	if not definition then
		slot.Visible = false
		-- Reset the pips too. Nothing is showing them right now, but leaving
		-- them half-lit would flash the previous ability's leftovers for a
		-- frame the next time the slot appears.
		for _, pip in slotPips do
			pip.BackgroundColor3 = Color3.fromRGB(70, 74, 84)
			pip.BackgroundTransparency = 0.45
		end
		return
	end

	slot.Visible = true
	slotIcon.Text = definition.icon
	slotName.Text = definition.name
	slotName.TextColor3 = definition.color
	slotStroke.Color = definition.color
	-- The prompt names whatever button this player actually has -- Shift on a
	-- keyboard, X on a pad, the on-screen button on a phone.
	slotHint.Text = if definition.activation == "AirJump"
		then "Jump again in mid-air"
		else definition.blurb .. "  —  " .. AbilityInput.getPrompt()

	-- Lit pips are uses you still have; spent ones dim right down rather than
	-- disappearing, so the total is always readable.
	--
	-- Abilities do not all carry the same number of uses -- Sneakers is short
	-- and powerful and only gets two -- so pips past this ability's maximum are
	-- hidden entirely. Leaving them showing would read as a use you never had.
	local maxUses = definition.uses or Config.ABILITY_USES
	for index, pip in slotPips do
		pip.Visible = index <= maxUses
		local available = index <= usesLeft
		pip.BackgroundColor3 = if available then definition.color else Color3.fromRGB(70, 74, 84)
		pip.BackgroundTransparency = if available then 0 else 0.45
	end
end)

--=============================================================================
-- CENTRE ANNOUNCEMENTS
--=============================================================================

local announceToken = 0

Remotes.Announce.OnClientEvent:Connect(function(text: string, color: Color3, hold: number)
	announceToken += 1
	local myToken = announceToken

	announceLabel.Text = text
	announceLabel.TextColor3 = color or COLOR_DIM
	announceLabel.TextTransparency = 0
	announceStroke.Transparency = 0.35

	-- A quick pop so it catches the eye.
	announceLabel.Size = UDim2.new(0, 700, 0, 48)
	TweenService:Create(announceLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 700, 0, 60),
	}):Play()

	task.delay(hold or 3, function()
		if announceToken ~= myToken then
			return -- something newer replaced it
		end
		TweenService:Create(announceLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(announceStroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	end)
end)

--=============================================================================
-- PER-FRAME UPDATES
--=============================================================================

local orbitAngle = 0

RunService.RenderStepped:Connect(function(deltaTime)
	--- COUNTDOWN ------------------------------------------------------------
	local deadline, duration = state.deadline, state.duration
	if deadline and duration and duration > 0 then
		local remaining = math.max(0, deadline - workspace:GetServerTimeNow())
		local fraction = math.clamp(remaining / duration, 0, 1)

		timerLabel.Text = string.format("%.1f", remaining)
		barFill.Size = UDim2.fromScale(fraction, 1)

		local color = if fraction > 0.6
			then COLOR_SAFE
			elseif fraction > 0.3 then COLOR_WARN
			else COLOR_DANGER
		barFill.BackgroundColor3 = color
		timerLabel.TextColor3 = if state.phase == "Playing" then color else COLOR_DIM

		-- Heartbeat pulse on the number in the last few seconds.
		if state.phase == "Playing" and remaining < 3 then
			local pulse = 1 + math.abs(math.sin(os.clock() * 9)) * 0.14
			timerLabel.Size = UDim2.new(1, 0, 0, math.floor(78 * pulse))
		else
			timerLabel.Size = UDim2.new(1, 0, 0, 78)
		end
	else
		timerLabel.Text = "--"
		timerLabel.TextColor3 = COLOR_DIM
		timerLabel.Size = UDim2.new(1, 0, 0, 78)
		barFill.Size = UDim2.fromScale(0, 1)
	end

	--- HOLDER GLOW ----------------------------------------------------------
	if vignette.Visible then
		local pulse = 0.2 + math.abs(math.sin(os.clock() * 4)) * 0.35
		for _, edge in vignetteEdges do
			edge.BackgroundTransparency = 1 - pulse
		end
	end

	--- SPECTATOR CAMERA -----------------------------------------------------
	-- Once your body is gone you have no character to follow, so drift the
	-- camera slowly around the arena instead.
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local character = player.Character
	local hasBody = character ~= nil
		and character.Parent ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil

	-- The way out of watching, offered only while there is something to be let
	-- out of.
	--
	-- This cannot key off "have I got a body" any more: a knocked-out player is
	-- a ghost up on the glass platform and very much has one. What marks them
	-- out is being sent the round's HUD while not being on its list of the
	-- living. Anyone in the lobby is sent the neutral state instead, so they
	-- never match.
	local iAmAlive = false
	for _, userId in state.aliveUserIds do
		if userId == player.UserId then
			iAmAlive = true
			break
		end
	end

	if state.phase == "Playing" then
		-- Mid-round: only offered to somebody who is out of it, watching from
		-- the ghost area. Offering it to a living player would be an escape
		-- from the bomb, and the server refuses it anyway.
		leaveButton.Visible = not iAmAlive
		leaveButton.Text = "Back to the lobby"
	else
		-- Between rounds -- the free-for-all in the arena, or waiting in the
		-- queue. Anyone who has asked to play can drop out here, and the wording
		-- says what it actually does: takes you out of the coming round.
		leaveButton.Visible = state.queued == true
		leaveButton.Text = "Leave round"
	end

	if not hasBody then
		camera.CameraType = Enum.CameraType.Scriptable
		orbitAngle += deltaTime * Config.SPECTATOR_ORBIT_SPEED
		local center = Config.ARENA_CENTER
		local eye = center
			+ Vector3.new(
				math.cos(orbitAngle) * Config.SPECTATOR_DISTANCE,
				Config.SPECTATOR_HEIGHT,
				math.sin(orbitAngle) * Config.SPECTATOR_DISTANCE
			)
		camera.CFrame = CFrame.lookAt(eye, center)
	elseif camera.CameraType == Enum.CameraType.Scriptable then
		-- Handing the camera back. Restoring the TYPE alone is not enough:
		-- CameraSubject still points at the humanoid of the body you had before
		-- you were blown up, which no longer exists. Roblox binds the subject
		-- when a character spawns, and a camera that was Scriptable at that
		-- moment can be left holding the dead one -- which looks exactly like
		-- being stuck in spectator view while your new character walks around
		-- perfectly well underneath it.
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CameraType = Enum.CameraType.Custom
	end
end)
