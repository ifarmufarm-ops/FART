--!strict
--[[
	Products -- the things that can be bought, and what they unlock.

	NOTHING HERE WORKS YET. Every productId below is 0, a placeholder, and
	Config.PRODUCTS_ENABLED is false. Nothing can be bought and no money can
	change hands until you do the two steps at the bottom of this comment.

	Everything here is COSMETIC. Nothing affects who wins a round, which is
	deliberate: the game keeps leaderboards for survival, passing and abilities,
	and the moment something bought changes those, they stop measuring skill and
	start measuring spending.

	These are DEVELOPER PRODUCTS, not gamepasses, and that is also deliberate. A
	developer product can be bought again and again and every purchase goes
	through a receipt, which is the only way Roblox lets a game count what
	somebody has spent -- and counting spend is what the "Biggest flexer" board
	needs. A gamepass is bought once and produces no receipt to count.

	TO MAKE THESE REAL
	------------------
	1. Roblox Creator Dashboard -> your game -> Monetization -> Developer
	   Products -> Create. Do one per entry below. Set the name and the price.
	2. Copy each product's ID and paste it in as `productId` here, replacing the
	   0. Then set Config.PRODUCTS_ENABLED = true.

	`price` below is only for showing in the game. Roblox charges whatever the
	dashboard says, so if the two ever disagree the dashboard wins -- keep them
	in step by hand.
]]

export type Product = {
	id: string,
	-- 0 means "not created yet". Nothing with a 0 here can ever be bought.
	productId: number,
	name: string,
	blurb: string,
	price: number, -- for display only; the dashboard is what actually charges
	-- The two colours the smoke fades between. Used by BOTH the fart jump's puff
	-- and the dash's trail, so one purchase recolours everything you leave
	-- behind rather than only half of it.
	colorFrom: Color3,
	colorTo: Color3,
}

local Products = {}

Products.list = {
	{
		id = "GreenFart",
		productId = 0,
		name = "Classic Green",
		blurb = "The original. Pungent.",
		price = 25,
		colorFrom = Color3.fromRGB(198, 226, 106),
		colorTo = Color3.fromRGB(112, 138, 62),
	},
	{
		id = "PinkFart",
		productId = 0,
		name = "Bubblegum",
		blurb = "Suspiciously sweet.",
		price = 25,
		colorFrom = Color3.fromRGB(255, 158, 222),
		colorTo = Color3.fromRGB(196, 74, 160),
	},
	{
		id = "BlueFart",
		productId = 0,
		name = "Deep Freeze",
		blurb = "Cold enough to see.",
		price = 25,
		colorFrom = Color3.fromRGB(148, 224, 255),
		colorTo = Color3.fromRGB(58, 122, 196),
	},
	{
		id = "GoldFart",
		productId = 0,
		name = "Solid Gold",
		blurb = "For the truly refined.",
		price = 99,
		colorFrom = Color3.fromRGB(255, 226, 122),
		colorTo = Color3.fromRGB(196, 146, 30),
	},
	{
		id = "RainbowFart",
		productId = 0,
		name = "Full Spectrum",
		blurb = "Every colour, all at once.",
		price = 149,
		colorFrom = Color3.fromRGB(255, 108, 108),
		colorTo = Color3.fromRGB(108, 168, 255),
	},
}

-- What everybody has before buying anything.
--
-- The fart puff and the dash trail have always used very slightly different
-- greens, so both are kept exactly as they were. Anybody who has bought nothing
-- sees no change at all; a purchase then recolours both to the same thing.
Products.FART_DEFAULT_FROM = Color3.fromRGB(198, 226, 106)
Products.FART_DEFAULT_TO = Color3.fromRGB(112, 138, 62)
Products.DASH_DEFAULT_FROM = Color3.fromRGB(206, 232, 128)
Products.DASH_DEFAULT_TO = Color3.fromRGB(118, 146, 68)

local byId: { [string]: Product } = {}
local byProductId: { [number]: Product } = {}
for _, product in Products.list do
	byId[product.id] = product
	if product.productId ~= 0 then
		byProductId[product.productId] = product
	end
end

function Products.get(id: string?): Product?
	return if id then byId[id] else nil
end

--[[
	Finds a product from the number Roblox gives us in a receipt.

	Returns nil for anything unknown, which the receipt handler treats as "do not
	take their money" rather than "grant something and hope".
]]
function Products.fromProductId(productId: number): Product?
	return byProductId[productId]
end

--[[
	Whether anything is actually purchasable. False while every productId is
	still 0, which is a useful thing to be able to check before showing a shop
	full of buttons that cannot work.
]]
function Products.anyConfigured(): boolean
	return next(byProductId) ~= nil
end

return Products
