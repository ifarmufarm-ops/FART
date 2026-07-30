--!strict
--[[
	Shop -- where you buy and choose fart colours.

	A row of pedestals along a lobby wall, one per colour. Walk onto one and:

	    do not own it  ->  Roblox's purchase window opens
	    already own it ->  you start wearing it

	No shop screen, no menus. It works the same way as the queue pad, which is
	the pattern the rest of this game uses: things in the world you walk into,
	detected by distance on a loop rather than by a Touched event.

	Detection is edge-triggered -- it fires when you arrive and will not fire again
	until you have stepped off and back on. Without that, standing on a pedestal
	would open the purchase window over and over.

	NOTHING CAN BE BOUGHT until the products exist. Until then, stepping onto a
	pedestal says so plainly rather than doing nothing. See STORE.md.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Products = require(ReplicatedStorage.Shared.Products)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Purchases = require(script.Parent.Purchases)

local Shop = {}

local COLOR_TEXT = Color3.fromRGB(255, 255, 255)
local COLOR_INFO = Color3.fromRGB(235, 238, 245)
local COLOR_GOOD = Color3.fromRGB(120, 255, 150)

type Pedestal = {
	part: BasePart,
	product: Products.Product,
}

local pedestals: { Pedestal } = {}
local folder: Folder? = nil
local running = false

-- Who was standing on which pedestal last time we looked, so arriving is what
-- triggers rather than staying.
local onPad: { [Player]: { [string]: boolean } } = {}
local lastPromptAt: { [Player]: number } = {}

local function tell(player: Player, message: string, color: Color3)
	Remotes.Announce:FireClient(player, message, color, 3)
end

--=============================================================================
-- BUILDING IT
--=============================================================================

function Shop.build()
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		error("Shop.build() needs the Lobby to exist -- call Lobby.build() first", 2)
	end

	local existing = lobby:FindFirstChild("Shop")
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = "Shop"
	created.Parent = lobby
	folder = created

	local centre = Config.LOBBY_CENTER
	local count = #Products.list
	-- Along the west wall, so the queue pad, the practice range and the boards
	-- each keep their own side of the lobby.
	local x = centre.X - (Config.LOBBY_SIZE / 2 - 14)
	local floorY = centre.Y

	local banner = Instance.new("Part")
	banner.Name = "Banner"
	banner.Anchored = true
	banner.CanCollide = false
	banner.Transparency = 1
	banner.Size = Vector3.one
	banner.CFrame = CFrame.new(x, floorY + 10, centre.Z)
	banner.Parent = created

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(300, 50)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 140
	billboard.Parent = banner
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "FART COLOURS"
	title.TextColor3 = COLOR_TEXT
	title.TextScaled = true
	title.Parent = billboard

	pedestals = {}
	for index, product in Products.list do
		local z = centre.Z + (index - (count + 1) / 2) * Config.SHOP_SPACING

		local pad = Instance.new("Part")
		pad.Name = "Shop_" .. product.id
		pad.Anchored = true
		pad.CanCollide = true
		pad.Size = Vector3.new(6, 1.2, 6)
		pad.CFrame = CFrame.new(x, floorY + 0.6, z)
		pad.Color = product.colorFrom
		pad.Material = Enum.Material.Neon
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.Parent = created

		-- A blob above it in the colour you would be buying, so the pedestals
		-- are tellable apart without reading anything.
		local sample = Instance.new("Part")
		sample.Name = "Sample"
		sample.Anchored = true
		sample.CanCollide = false
		sample.Shape = Enum.PartType.Ball
		sample.Size = Vector3.new(2.6, 2.6, 2.6)
		sample.CFrame = CFrame.new(x, floorY + 4, z)
		sample.Color = product.colorFrom
		sample.Material = Enum.Material.Neon
		sample.Transparency = 0.25
		sample.Parent = created

		local sign = Instance.new("BillboardGui")
		sign.Size = UDim2.fromOffset(210, 56)
		sign.StudsOffset = Vector3.new(0, 2.6, 0)
		sign.AlwaysOnTop = true
		sign.MaxDistance = 90
		sign.Parent = sample

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.Text = product.name
		name.TextColor3 = product.colorFrom
		name.TextScaled = true
		name.Parent = sign

		local price = Instance.new("TextLabel")
		price.Position = UDim2.new(0, 0, 0.55, 0)
		price.Size = UDim2.new(1, 0, 0.45, 0)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamMedium
		-- Says "coming soon" until the product exists, rather than advertising a
		-- price for something nobody can buy.
		price.Text = if product.productId == 0 and not Config.PRODUCTS_ENABLED
			then "coming soon"
			else ("%d Robux"):format(product.price)
		price.TextColor3 = COLOR_INFO
		price.TextScaled = true
		price.Parent = sign

		table.insert(pedestals, { part = pad, product = product })
	end
end

--=============================================================================
-- STEPPING ON ONE
--=============================================================================

local function activate(player: Player, product: Products.Product)
	-- Already owned: wear it. No money involved, so nothing to guard.
	if Purchases.owns(player, product.id) then
		if Purchases.getEquipped(player) == product.id then
			tell(player, ("Already wearing %s"):format(product.name), COLOR_INFO)
		elseif Purchases.equip(player, product.id) then
			tell(player, ("Now wearing %s"):format(product.name), COLOR_GOOD)
		else
			tell(player, "Could not change that just now", COLOR_INFO)
		end
		return
	end

	if not Config.PRODUCTS_ENABLED or product.productId == 0 then
		tell(player, ("%s is not for sale yet"):format(product.name), COLOR_INFO)
		return
	end

	-- Roblox's own purchase window takes a moment to appear. Without a cooldown,
	-- walking along the row would stack prompts on top of each other.
	local clock = os.clock()
	if clock - (lastPromptAt[player] or 0) < Config.SHOP_PROMPT_COOLDOWN then
		return
	end
	lastPromptAt[player] = clock

	Purchases.prompt(player, product.id)
end

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

function Shop.start()
	if running then
		return
	end
	running = true

	if not folder then
		Shop.build()
	end

	Players.PlayerRemoving:Connect(function(player)
		onPad[player] = nil
		lastPromptAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.SHOP_CHECK_INTERVAL)

			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				local standing = onPad[player]
				if not standing then
					standing = {}
					onPad[player] = standing
				end

				if not root then
					-- No body: forget where they were, so returning counts as
					-- arriving rather than being ignored.
					table.clear(standing)
					continue
				end

				for _, pedestal in pedestals do
					local flat = Vector3.new(
						root.Position.X - pedestal.part.Position.X,
						0,
						root.Position.Z - pedestal.part.Position.Z
					)
					local inside = flat.Magnitude <= Config.SHOP_PAD_RADIUS
						and math.abs(root.Position.Y - pedestal.part.Position.Y) <= 10

					if inside and not standing[pedestal.product.id] then
						activate(player, pedestal.product)
					end
					standing[pedestal.product.id] = inside
				end
			end
		end
	end)
end

return Shop
