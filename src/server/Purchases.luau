--!strict
--[[
	Purchases -- taking money, and remembering what it bought.

	NOTHING CAN BE BOUGHT YET. Every product id in shared/Products.luau is still
	0 and Config.PRODUCTS_ENABLED is false. The receipt handler below is wired up
	and refuses everything, which is the right way round: the machinery is tested
	and dormant rather than untested and live.

	THE TWO RULES THAT ARE NOT NEGOTIABLE HERE, because this is the one place in
	the game where a mistake costs a real person real money:

	1. NEVER say yes until it is safely recorded. Roblox stops re-delivering a
	   receipt the moment the game returns PurchaseGranted. Say yes before the
	   write succeeds and a failed write means somebody paid for nothing, with no
	   second chance to fix it. So every failure path returns NotProcessedYet,
	   which asks Roblox to deliver it again shortly.

	2. NEVER grant the same receipt twice. Roblox re-delivers until confirmed, so
	   the same purchase arrives repeatedly by design. The duplicate check lives
	   inside the same single write as the grant -- see StatsStore.recordPurchase
	   -- because checking beforehand leaves a gap two deliveries can both pass
	   through.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Products = require(ReplicatedStorage.Shared.Products)

local StatsService = require(script.Parent.StatsService)
local StatsStore = require(script.Parent.StatsStore)

local Purchases = {}

local started = false

local function log(message: string)
	if Config.STATS_DEBUG_LOG then
		print("[Purchases] " .. message)
	end
end

--=============================================================================
-- WHAT SOMEBODY OWNS
--=============================================================================

function Purchases.owns(player: Player, cosmeticId: string): boolean
	return StatsStore.getCosmetics(player.UserId).owned[cosmeticId] == true
end

function Purchases.getEquipped(player: Player): string?
	return StatsStore.getCosmetics(player.UserId).equipped
end

--[[
	The two colours this player's smoke should fade between.

	One purchase covers everything you leave behind -- the fart jump's puff and
	the dash's trail both come through here -- so a colour someone paid for is not
	half applied.

	The two fall back to slightly different greens because that is what each has
	always used. Anybody who has bought nothing, and anybody whose history could
	not be read, therefore looks exactly as before rather than seeing something
	they did not pay for.
]]
local function colorsFor(player: Player, defaultFrom: Color3, defaultTo: Color3): (Color3, Color3)
	local equipped = Purchases.getEquipped(player)
	if equipped and Purchases.owns(player, equipped) then
		local product = Products.get(equipped)
		if product then
			return product.colorFrom, product.colorTo
		end
	end
	return defaultFrom, defaultTo
end

function Purchases.getFartColors(player: Player): (Color3, Color3)
	return colorsFor(player, Products.FART_DEFAULT_FROM, Products.FART_DEFAULT_TO)
end

function Purchases.getDashColors(player: Player): (Color3, Color3)
	return colorsFor(player, Products.DASH_DEFAULT_FROM, Products.DASH_DEFAULT_TO)
end

--[[
	Wears something already owned. Refuses anything not owned, so this is safe to
	drive from a client request later without further checking.
]]
function Purchases.equip(player: Player, cosmeticId: string?): boolean
	if cosmeticId ~= nil and not Purchases.owns(player, cosmeticId) then
		return false
	end
	local cached = StatsStore.getCosmetics(player.UserId)
	cached.equipped = cosmeticId
	return StatsStore.setEquipped(player.UserId, cosmeticId)
end

--=============================================================================
-- ASKING SOMEBODY TO BUY
--=============================================================================

--[[
	Opens Roblox's purchase window. Refuses politely if the product has not been
	created in the dashboard yet, rather than throwing.
]]
function Purchases.prompt(player: Player, cosmeticId: string): boolean
	if not Config.PRODUCTS_ENABLED then
		log("prompt refused: PRODUCTS_ENABLED is false")
		return false
	end
	local product = Products.get(cosmeticId)
	if not product or product.productId == 0 then
		warn(("[Purchases] %s has no product id yet -- create it in the Creator Dashboard"):format(cosmeticId))
		return false
	end
	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.productId)
	end)
	return ok
end

--=============================================================================
-- THE RECEIPT
--=============================================================================

local function onReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local retry = Enum.ProductPurchaseDecision.NotProcessedYet

	if not Config.PRODUCTS_ENABLED then
		-- Should be unreachable, since nothing can be prompted. Refusing rather
		-- than granting means a stray receipt is never quietly consumed.
		warn("[Purchases] a receipt arrived while PRODUCTS_ENABLED is false; not processing")
		return retry
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- They have left. Roblox will deliver it again when they come back.
		return retry
	end

	local product = Products.fromProductId(receiptInfo.ProductId)
	if not product then
		-- Something was bought that this game does not recognise. Do NOT take
		-- the money for something it cannot grant.
		warn(("[Purchases] unknown product %s -- not granting"):format(tostring(receiptInfo.ProductId)))
		return retry
	end

	local spent = tonumber(receiptInfo.CurrencySpent) or 0
	local outcome = StatsStore.recordPurchase(
		player.UserId,
		tostring(receiptInfo.PurchaseId),
		product.id,
		spent
	)

	if outcome == "failed" then
		log(("could not record %s for %s; asking Roblox to retry"):format(product.id, player.Name))
		return retry
	end

	if outcome == "granted" then
		-- The store already added this to the saved total and the board, inside
		-- the same write that granted it. This only brings the live in-memory
		-- figure into line, WITHOUT queueing it to be saved again.
		StatsService.noteAlreadySaved(player, "RobuxSpent", spent)

		local cached = StatsStore.getCosmetics(player.UserId)
		cached.owned[product.id] = true
		if cached.equipped == nil then
			cached.equipped = product.id
		end
		log(("%s bought %s for %d"):format(player.Name, product.id, spent))
	end

	-- "already" lands here too: say yes so Roblox stops re-delivering, but
	-- nothing above counted it a second time.
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Purchases.start()
	if started then
		return
	end
	started = true

	-- Connected even while switched off, so a receipt can never fall on the
	-- floor. Roblox retries anything left unhandled, and an unhandled receipt is
	-- money taken with nothing given.
	MarketplaceService.ProcessReceipt = onReceipt

	Players.PlayerRemoving:Connect(function(player)
		StatsStore.forget(player.UserId)
	end)

	if not Config.PRODUCTS_ENABLED then
		log("running with purchases switched off")
	elseif not Products.anyConfigured() then
		warn("[Purchases] PRODUCTS_ENABLED is true but no product has an id yet; nothing can be bought")
	end
end

--[[
	Pretends somebody bought something, for testing the whole pipeline without
	spending real Robux. Safe: it goes through exactly the same recording path a
	real receipt does, including the duplicate check.

		require(game.ServerScriptService.Server.Purchases)
			.simulate(game.Players.YourName, "GoldFart")
]]
function Purchases.simulate(player: Player, cosmeticId: string, fakeReceiptId: string?): string
	local product = Products.get(cosmeticId)
	if not product then
		return "no such cosmetic: " .. tostring(cosmeticId)
	end
	local receiptId = fakeReceiptId or ("simulated_" .. cosmeticId .. "_" .. tostring(os.time()))
	local outcome = StatsStore.recordPurchase(player.UserId, receiptId, product.id, product.price)
	if outcome == "granted" then
		StatsService.noteAlreadySaved(player, "RobuxSpent", product.price)
		local cached = StatsStore.getCosmetics(player.UserId)
		cached.owned[product.id] = true
		if cached.equipped == nil then
			cached.equipped = product.id
		end
	end
	return ("%s -> %s (receipt %s)"):format(cosmeticId, outcome, receiptId)
end

return Purchases
