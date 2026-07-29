--!strict
--[[
	Abilities -- the catalogue of everything that can spawn as a pickup.

	One table, read by both the server and the client, so the client never has
	to hardcode a name or a colour. Adding a new pickup means adding one entry
	here and one handler in AbilityService -- nothing else needs to know.

	`weight` decides how often something spawns relative to everything else. A
	weight of 30 spawns three times as often as a weight of 10. Set a weight to
	0 to keep an entry in the list but stop it appearing.

	`activation` says how a carried ability gets used:
		"Key"      -- press the ability key (Shift on desktop)
		"AirJump"  -- happens by itself when you jump again in mid-air
		"Instant"  -- beacons: goes off the moment you touch it, nothing carried

	`uses` is optional. Leave it out and the ability gets Config.ABILITY_USES
	like everything else; set it to give one ability a different number, which
	is how a short powerful ability is balanced against a mild repeatable one.
]]

export type Kind = "Ability" | "Beacon"
export type Activation = "Key" | "AirJump" | "Instant"

export type Definition = {
	id: string,
	name: string,
	blurb: string, -- one line shown on the HUD
	kind: Kind,
	activation: Activation,
	color: Color3,
	icon: string,
	weight: number,
	uses: number?, -- optional override for Config.ABILITY_USES
}

local Config = require(script.Parent.Config)

local Abilities = {}

Abilities.list = {
	--- ABILITIES: yours alone, carried and used ----------------------------
	{
		id = "Dash",
		name = "Dash",
		blurb = "Fire yourself forwards",
		kind = "Ability" :: Kind,
		activation = "Key" :: Activation,
		color = Color3.fromRGB(120, 200, 255),
		icon = "💨",
		weight = 30,
	},
	{
		id = "FartJump",
		name = "Fart Jump",
		blurb = "Propel yourself in mid-air",
		kind = "Ability" :: Kind,
		activation = "AirJump" :: Activation,
		-- Yellow-green, kept clearly apart from Dash's blue and Sneakers' mint
		-- so the three are still tellable apart at a glance on the floor.
		color = Color3.fromRGB(206, 224, 88),
		icon = "🌬️",
		weight = 30,
	},
	{
		id = "Sneakers",
		name = "Sneakers",
		blurb = "Run twice as fast, briefly",
		kind = "Ability" :: Kind,
		activation = "Key" :: Activation,
		color = Color3.fromRGB(140, 255, 170),
		icon = "👟",
		weight = 30,
		-- Short and powerful rather than mild and repeatable, so it gets fewer
		-- uses than the other two. See Config.SNEAKERS_USES.
		uses = Config.SNEAKERS_USES,
	},

	--- BEACONS: go off on touch and change the map for EVERYONE -------------
	{
		id = "IceShoes",
		name = "Ice Shoes",
		blurb = "The floor turns to ice",
		kind = "Beacon" :: Kind,
		activation = "Instant" :: Activation,
		color = Color3.fromRGB(150, 212, 255),
		icon = "🧊",
		weight = 12,
	},
	{
		id = "LowGravity",
		name = "Low Gravity",
		blurb = "Everyone goes floaty",
		kind = "Beacon" :: Kind,
		activation = "Instant" :: Activation,
		color = Color3.fromRGB(190, 170, 255),
		icon = "🌙",
		weight = 12,
	},
	{
		id = "TinyMode",
		name = "Tiny Mode",
		blurb = "Everyone shrinks",
		kind = "Beacon" :: Kind,
		activation = "Instant" :: Activation,
		color = Color3.fromRGB(255, 190, 120),
		icon = "🐭",
		weight = 12,
	},
	{
		id = "ReverseControls",
		name = "Reverse Controls",
		blurb = "Everyone else steers backwards",
		kind = "Beacon" :: Kind,
		activation = "Instant" :: Activation,
		color = Color3.fromRGB(255, 120, 190),
		icon = "🔀",
		weight = 4, -- rare, as specified
	},

	{
		id = "BrainRot",
		name = "Brain Rot Alert",
		blurb = "Something starts hunting everyone",
		kind = "Beacon" :: Kind,
		activation = "Instant" :: Activation,
		color = Color3.fromRGB(220, 120, 255),
		icon = "🧠",
		weight = 10,
	},
}

local byId: { [string]: Definition } = {}
for _, definition in Abilities.list do
	byId[definition.id] = definition
end

function Abilities.get(id: string?): Definition?
	return if id then byId[id] else nil
end

--[[
	Picks a random entry, respecting the weights above.
]]
function Abilities.roll(): Definition?
	local total = 0
	for _, definition in Abilities.list do
		total += definition.weight
	end
	if total <= 0 then
		return nil
	end

	local roll = math.random() * total
	for _, definition in Abilities.list do
		roll -= definition.weight
		if roll <= 0 then
			return definition
		end
	end
	return Abilities.list[#Abilities.list]
end

return Abilities
