--[[
	TestRange -- the Test Mode showcase.

	A raised platform along one wall of the arena holding one of every ability
	and every beacon in a row, each labelled, each coming back a few seconds
	after you take it. Walk the line, grab whatever you want to try, step into
	the arena and use it.

	It awards things through Pickups.award, the exact same path a real pickup
	uses -- so anything that works here works in a real round, and anything
	broken here is broken there too. It is not a simulation of the real thing.

	Only ever built when Config.TEST_MODE is on.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Config = require(ReplicatedStorage.Shared.Config)

local Pickups = require(script.Parent.Pickups)

local TestRange = {}

type Pedestal = {
	definition: Abilities.Definition,
	position: Vector3,
	model: BasePart?, -- nil while it is respawning
	readyAt: number,
}

local folder: Folder? = nil
local pedestals: { Pedestal } = {}
local heartbeat: RBXScriptConnection? = nil
local getAlive: () -> { Player } = function()
	return {}
end
local nextCheck = 0

--=============================================================================
-- BUILDING IT
--=============================================================================

local function label(parent: BasePart, text: string, colour: Color3, offset: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 40)
	billboard.StudsOffset = Vector3.new(0, offset, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Text = text
	textLabel.TextColor3 = colour
	textLabel.TextScaled = true
	textLabel.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.3
	stroke.Parent = textLabel
end

--[[
	Lays the range out along the far wall of the arena, centred, so it is out of
	the way of normal running-about but only a few seconds' walk from anywhere.
]]
function TestRange.build()
	TestRange.destroy()

	local created = Instance.new("Folder")
	created.Name = "TestRange"
	created.Parent = workspace
	folder = created

	local list = Abilities.list
	local count = #list
	local spacing = Config.TEST_RANGE_SPACING
	local width = (count - 1) * spacing + 16
	local z = -(Config.ARENA_SIZE / 2 - 16)
	local floorY = Config.FLOOR_Y

	-- The platform they all stand on.
	local slab = Instance.new("Part")
	slab.Name = "Platform"
	slab.Anchored = true
	slab.Size = Vector3.new(width, 1, 14)
	slab.CFrame = CFrame.new(0, floorY + 0.5, z)
	slab.Color = Color3.fromRGB(40, 44, 54)
	slab.Material = Enum.Material.Metal
	slab.TopSurface = Enum.SurfaceType.Smooth
	slab.Parent = created
	-- Tagged as floor like the rest of the arena, so Ice Shoes makes the range
	-- slippery too. Otherwise you would be standing on the one grippy patch in
	-- the map while trying to judge how the ice feels.
	CollectionService:AddTag(slab, Config.TAG_FLOOR)

	local banner = Instance.new("Part")
	banner.Name = "Banner"
	banner.Anchored = true
	banner.CanCollide = false
	banner.Transparency = 1
	banner.Size = Vector3.one
	banner.CFrame = CFrame.new(0, floorY + 9, z)
	banner.Parent = created
	label(banner, "TEST RANGE — everything respawns", Color3.fromRGB(255, 214, 92), 0)

	pedestals = {}
	for index, definition in list do
		local x = (index - (count + 1) / 2) * spacing
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

		label(
			stand,
			definition.name .. (if definition.kind == "Beacon" then "  (beacon)" else ""),
			definition.color,
			4.6
		)

		table.insert(pedestals, {
			definition = definition,
			position = position,
			model = Pickups.buildVisual(definition, position, created),
			readyAt = 0,
		})
	end
end

function TestRange.destroy()
	if folder then
		folder:Destroy()
		folder = nil
	end
	pedestals = {}
end

--=============================================================================
-- COLLECTING AND RESPAWNING
--=============================================================================

local function onHeartbeat()
	local clock = os.clock()

	-- Refill anything taken. The turning and bobbing is done on each player's own
	-- machine now, same as the real pickups -- see src/client/PickupSpin.luau.
	for _, pedestal in pedestals do
		if not pedestal.model and clock >= pedestal.readyAt then
			pedestal.model = Pickups.buildVisual(pedestal.definition, pedestal.position, folder)
		end
	end

	if clock < nextCheck then
		return
	end
	nextCheck = clock + 0.1

	local players = getAlive()
	if #players == 0 then
		return
	end

	for _, pedestal in pedestals do
		local model = pedestal.model
		if not model then
			continue
		end
		for _, player in players do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - model.Position).Magnitude < Config.PICKUP_COLLECT_RADIUS then
				Pickups.award(player, pedestal.definition, model.Position)
				model:Destroy()
				pedestal.model = nil
				pedestal.readyAt = clock + Config.TEST_RESPAWN_DELAY
				break
			end
		end
	end
end

function TestRange.setActive(isActive: boolean, aliveProvider: (() -> { Player })?)
	getAlive = aliveProvider or function()
		return {}
	end

	if isActive then
		if not folder then
			TestRange.build()
		end
		if not heartbeat then
			heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
		end
	else
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		TestRange.destroy()
	end
end

return TestRange
