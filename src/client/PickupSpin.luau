--!strict
--[[
	PickupSpin -- makes the pickups turn and bob, on each player's own machine.

	This used to be done by the server, which meant up to fourteen parts having
	their position sent to every player sixty times a second, forever, for
	something purely decorative. It was the largest continuous cost in the game
	and it grew every time the pickup count went up.

	Doing it here costs nothing to send: every machine works out the same motion
	from the clock, so everyone sees the same thing without a single byte crossing
	the network.

	The server still owns what matters. It leaves each pickup at its base position
	and measures collection from there, so being close enough to pick something up
	is decided on the server as before and cannot be faked by fiddling with this.

	Which parts to animate is found by name prefix, so it covers the arena's
	pickups, the lobby practice range and Test Mode's showcase row without any of
	them registering anything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local PickupSpin = {}

local PREFIX = "Pickup_"

-- Where each pickup actually lives, remembered the first time it is seen. The
-- part is never read back for its position afterwards -- otherwise the bob would
-- creep further from home every frame instead of swinging around one point.
local homes: { [BasePart]: Vector3 } = {}

local function isPickup(thing: Instance): boolean
	return thing:IsA("BasePart") and thing.Name:sub(1, #PREFIX) == PREFIX
end

function PickupSpin.start()
	if not Config.PICKUP_SPIN_ON_CLIENT then
		return
	end

	local watched: { BasePart } = {}

	local function watch(thing: Instance)
		if not isPickup(thing) then
			return
		end
		local part = thing :: BasePart
		homes[part] = part.Position
		table.insert(watched, part)
	end

	for _, thing in workspace:GetDescendants() do
		watch(thing)
	end
	workspace.DescendantAdded:Connect(watch)

	-- Heartbeat rather than RenderStepped, for two reasons. It keeps running when
	-- the window is not the one being rendered, which for a slowly turning pickup
	-- is harmless and means they are never found frozen. And it is the only one of
	-- the two that fires when Studio is being driven from outside, so this can
	-- actually be verified rather than taken on trust. The difference is one
	-- frame of lag on a spin nobody is timing.
	RunService.Heartbeat:Connect(function()
		local clock = os.clock()
		local spin = CFrame.Angles(0, clock * Config.PICKUP_SPIN_SPEED, 0)

		-- Walked backwards so a pickup that has been collected can be dropped
		-- from the list without disturbing the ones not yet visited.
		for index = #watched, 1, -1 do
			local part = watched[index]
			if not part.Parent then
				homes[part] = nil
				table.remove(watched, index)
				continue
			end
			local home = homes[part]
			if not home then
				continue
			end
			local bob = math.sin(clock * 2 + home.X + home.Z) * Config.PICKUP_BOB_HEIGHT
			part.CFrame = CFrame.new(home + Vector3.new(0, bob, 0)) * spin
		end
	end)
end

return PickupSpin
