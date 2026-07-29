--!strict
--[[
	PracticeRange -- a row of abilities along one wall of the lobby.

	Take one, use it, take another. It never runs out and it costs nothing,
	which is the point: the abilities are the most interesting thing in the game
	and a new player should be able to work out what they do before a round is
	riding on it.

	ABILITIES ONLY. Never beacons. A beacon changes the map for everybody in the
	round, and somebody idly poking about in the lobby must not be able to reach
	into a game they are not playing. LOBBY_PLAN.md called this out and it is
	enforced here by filtering on `kind`.

	Deliberately close to TestRange in shape rather than shared with it. That one
	is a single arena-wide fixture wired into the round; this one always exists,
	belongs to the lobby, and carries a different set of things. Merging them
	would mean making TestRange support two live instances, which is a lot of
	machinery for eighty lines of pedestals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Config = require(ReplicatedStorage.Shared.Config)

local Pickups = require(script.Parent.Pickups)

local PracticeRange = {}

type Pedestal = {
	definition: Abilities.Definition,
	position: Vector3,
	model: BasePart?,
	readyAt: number,
}

local folder: Folder? = nil
local pedestals: { Pedestal } = {}
local heartbeat: RBXScriptConnection? = nil
local nextCheck = 0

local function label(parent: BasePart, text: string, color: Color3, offsetY: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 44)
	billboard.StudsOffset = Vector3.new(0, offsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = parent

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.TextScaled = true
	textLabel.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.3
	stroke.Parent = textLabel
end

--[[
	Only the things you carry and use yourself.
]]
local function abilitiesOnly(): { Abilities.Definition }
	local list = {}
	for _, definition in Abilities.list do
		if definition.kind == "Ability" then
			table.insert(list, definition)
		end
	end
	return list
end

function PracticeRange.build()
	PracticeRange.destroy()

	local created = Instance.new("Folder")
	created.Name = "PracticeRange"
	created.Parent = workspace
	folder = created

	local list = abilitiesOnly()
	local count = #list
	if count == 0 then
		return
	end

	local spacing = Config.PRACTICE_RANGE_SPACING
	local width = (count - 1) * spacing + 16
	local centre = Config.LOBBY_CENTER
	local z = centre.Z - (Config.LOBBY_SIZE / 2 - 16)
	local floorY = centre.Y

	local slab = Instance.new("Part")
	slab.Name = "Platform"
	slab.Anchored = true
	slab.Size = Vector3.new(width, 1, 14)
	slab.CFrame = CFrame.new(centre.X, floorY + 0.5, z)
	slab.Color = Color3.fromRGB(58, 54, 72)
	slab.Material = Enum.Material.Metal
	slab.TopSurface = Enum.SurfaceType.Smooth
	slab.Parent = created
	-- NOT tagged as floor. That tag is what Ice Shoes freezes, and this is in
	-- the lobby -- see the note at the top of Config's lobby section.

	local banner = Instance.new("Part")
	banner.Name = "Banner"
	banner.Anchored = true
	banner.CanCollide = false
	banner.Transparency = 1
	banner.Size = Vector3.one
	banner.CFrame = CFrame.new(centre.X, floorY + 9, z)
	banner.Parent = created
	label(banner, "PRACTICE — take one and try it", Color3.fromRGB(126, 214, 255), 0)

	pedestals = {}
	for index, definition in list do
		local x = centre.X + (index - (count + 1) / 2) * spacing
		local position = Vector3.new(x, floorY + 4, z)

		local stand = Instance.new("Part")
		stand.Name = "Stand_" .. definition.id
		stand.Anchored = true
		stand.CanCollide = true
		stand.Size = Vector3.new(4, 1.6, 4)
		stand.CFrame = CFrame.new(x, floorY + 1.8, z)
		stand.Color = definition.color
		stand.Material = Enum.Material.Neon
		stand.Transparency = 0.55
		stand.Parent = created

		label(stand, definition.name, definition.color, 4.6)

		table.insert(pedestals, {
			definition = definition,
			position = position,
			model = Pickups.buildVisual(definition, position, created),
			readyAt = 0,
		})
	end
end

function PracticeRange.destroy()
	if folder then
		folder:Destroy()
		folder = nil
	end
	pedestals = {}
end

--=============================================================================
-- TAKING ONE
--=============================================================================

local function onHeartbeat()
	local clock = os.clock()

	for _, pedestal in pedestals do
		if pedestal.model then
			pedestal.model.CFrame = CFrame.new(pedestal.position) * CFrame.Angles(0, clock * 1.6, 0)
		elseif clock >= pedestal.readyAt then
			pedestal.model = Pickups.buildVisual(pedestal.definition, pedestal.position, folder)
		end
	end

	if clock < nextCheck then
		return
	end
	nextCheck = clock + 0.1

	-- Everybody is a candidate; standing within arm's reach of a pedestal in the
	-- lobby is the only qualification, and nobody in a round is anywhere near it.
	for _, pedestal in pedestals do
		local model = pedestal.model
		if not model then
			continue
		end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if
				root
				and root:IsA("BasePart")
				and (root.Position - model.Position).Magnitude < Config.PICKUP_COLLECT_RADIUS
			then
				Pickups.award(player, pedestal.definition, model.Position)
				model:Destroy()
				pedestal.model = nil
				pedestal.readyAt = clock + Config.PRACTICE_RESPAWN_DELAY
				break
			end
		end
	end
end

--[[
	The range is part of the lobby, so unlike TestRange it is simply always on.
]]
function PracticeRange.start()
	if not folder then
		PracticeRange.build()
	end
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
	end
end

return PracticeRange
