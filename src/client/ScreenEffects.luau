--[[
	ScreenEffects -- what the beacon events look like from inside your head,
	plus the one that has to actually change how you move.

	Three jobs:
		* a readout of which events are running and how long is left
		* a frost tint while Ice Shoes is on
		* inverting your movement while Reverse Controls is on

	Reverse Controls has to live on the client, because "which way is forward"
	is decided by your own machine every frame. Everything else here is purely
	cosmetic -- the actual physics changes (friction, gravity, size) are done on
	the server and simply replicate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local ScreenEffects = {}

local REVERSE_BIND = "HotPotatoReverseControls"

type Entry = { id: string, endsAt: number, activatorUserId: number? }

local activeList: { Entry } = {}
local reverseActive = false

--=============================================================================
-- THE INTERFACE
--=============================================================================

local gui: ScreenGui
local frost: Frame
local strip: Frame
local rows: { [string]: TextLabel } = {}

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "HotPotatoEffects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Icy edges. Same four-gradient trick as the bomb-holder vignette, so the
	-- middle of the screen stays clear and readable.
	frost = Instance.new("Frame")
	frost.Name = "Frost"
	frost.Size = UDim2.fromScale(1, 1)
	frost.BackgroundTransparency = 1
	frost.Visible = false
	frost.Parent = gui

	local edges = {
		{ UDim2.new(1, 0, 0, 180), UDim2.fromScale(0, 0), Vector2.new(0, 0), 90 },
		{ UDim2.new(1, 0, 0, 180), UDim2.fromScale(0, 1), Vector2.new(0, 1), 270 },
		{ UDim2.new(0, 260, 1, 0), UDim2.fromScale(0, 0), Vector2.new(0, 0), 0 },
		{ UDim2.new(0, 260, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180 },
	}
	for i, spec in edges do
		local edge = Instance.new("Frame")
		edge.Name = "FrostEdge" .. i
		edge.Size = spec[1]
		edge.Position = spec[2]
		edge.AnchorPoint = spec[3]
		edge.BackgroundColor3 = Color3.fromRGB(200, 238, 255)
		edge.BackgroundTransparency = 0.55
		edge.BorderSizePixel = 0
		edge.Parent = frost

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[4]
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge
	end

	-- A running list of what is currently happening to the map, top-left.
	strip = Instance.new("Frame")
	strip.Name = "ActiveEvents"
	strip.Position = UDim2.new(0, 22, 0, 22)
	strip.Size = UDim2.fromOffset(300, 140)
	strip.BackgroundTransparency = 1
	strip.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.Parent = strip
end

local function rowFor(definition: Abilities.Definition): TextLabel
	local existing = rows[definition.id]
	if existing then
		return existing
	end

	local row = Instance.new("TextLabel")
	row.Name = definition.id
	row.Size = UDim2.fromOffset(300, 28)
	row.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.Font = Enum.Font.GothamBold
	row.TextColor3 = definition.color
	row.TextScaled = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Text = definition.name
	row.Parent = strip
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = row

	rows[definition.id] = row
	return row
end

--=============================================================================
-- REVERSE CONTROLS
--=============================================================================

--[[
	Runs every frame, AFTER Roblox's own control script has decided where you
	are trying to go -- then sends you the opposite way.

	The priority matters: bound any earlier and the default controls would
	simply overwrite this a moment later and nothing would happen.
]]
local function reverseStep()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude > 0.01 then
		humanoid:Move(-direction, false)
	end
end

local function setReverse(enabled: boolean)
	if enabled == reverseActive then
		return
	end
	reverseActive = enabled

	if enabled then
		RunService:BindToRenderStep(REVERSE_BIND, Enum.RenderPriority.Character.Value + 1, reverseStep)
	else
		RunService:UnbindFromRenderStep(REVERSE_BIND)
	end
end

--=============================================================================
-- REACTING TO THE SERVER
--=============================================================================

local function isRunning(id: string): Entry?
	for _, entry in activeList do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function onModifierChanged(list: { Entry })
	activeList = list or {}

	frost.Visible = isRunning("IceShoes") ~= nil

	-- Reverse Controls spares whoever grabbed the beacon.
	local reverse = isRunning("ReverseControls")
	setReverse(reverse ~= nil and reverse.activatorUserId ~= player.UserId)

	-- Drop rows for anything that has finished.
	for id, row in rows do
		if not isRunning(id) then
			row:Destroy()
			rows[id] = nil
		end
	end
end

--=============================================================================
-- START
--=============================================================================

function ScreenEffects.start()
	buildGui()

	Remotes.ModifierChanged.OnClientEvent:Connect(onModifierChanged)

	-- Keep the countdowns ticking between updates, the same way the bomb timer
	-- does -- the server sends an end time, not a number every frame.
	RunService.RenderStepped:Connect(function()
		local clock = workspace:GetServerTimeNow()
		for _, entry in activeList do
			local definition = Abilities.get(entry.id)
			if definition then
				local row = rowFor(definition)
				local left = math.max(0, entry.endsAt - clock)
				local mine = entry.activatorUserId == player.UserId
				row.Text = ("%s  %s   %.0fs%s"):format(
					definition.icon,
					definition.name,
					left,
					if entry.id == "ReverseControls" and mine then "  (not you)" else ""
				)
			end
		end
	end)
end

return ScreenEffects
