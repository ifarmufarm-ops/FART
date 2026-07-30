--!strict
--[[
	StatsService -- counting what players do.

	This file knows about the game and nothing about saving. Everything to do
	with DataStores lives in StatsStore, which arrives in the next stage. Until
	then the numbers are held in memory and are gone when the server restarts.

	Splitting it that way is deliberate: the risky code -- retries, shutdown,
	never overwriting a profile that failed to load -- ends up in one small file
	with no game logic in it, and this stage can be finished and tested before
	any of it exists.

	It requires only shared/Stats, so RoundManager, AbilityService and
	GhostClicker can all require it directly with no circular-require worries.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)

local StatsStore = require(script.Parent.StatsStore)

local StatsService = {}

-- Every player's running totals. Kept as floats: survive time accrues in
-- fractions of a second, and flooring on every elimination would quietly lose
-- up to a second per round per player.
local totals: { [Player]: { [string]: number } } = {}

-- What has changed since their last successful save. Saves send this rather
-- than the whole total, so two servers holding the same player add up instead of
-- overwriting each other. Cleared only once a write definitely landed.
local pending: { [Player]: { [string]: number } } = {}

-- Players whose history could not be read. They play with zeros and are NEVER
-- written back -- see the note at the top of StatsStore. This is the flag that
-- stops a data outage erasing somebody's progress.
local failedToLoad: { [Player]: boolean } = {}

-- Guards against two saves for the same player running at once, which would
-- double-count the pending changes.
local saving: { [Player]: boolean } = {}

-- When each player's survive clock started, for those currently alive in a
-- round. Absent means the clock is not running.
local clockFrom: { [Player]: number } = {}

local leaderstatValues: { [Player]: { [string]: ValueBase } } = {}

local running = false

local function log(message: string)
	if Config.STATS_DEBUG_LOG then
		print("[Stats] " .. message)
	end
end

local function profileOf(player: Player): { [string]: number }
	local existing = totals[player]
	if existing then
		return existing
	end
	local fresh = Stats.blank()
	totals[player] = fresh
	return fresh
end

--=============================================================================
-- COUNTING
--=============================================================================

--[[
	Adds to a statistic. The single way anything gets counted.
]]
function StatsService.add(player: Player?, statId: string, delta: number)
	if not Config.STATS_ENABLED or not player or delta == 0 then
		return
	end
	if not Stats.get(statId) then
		warn("[Stats] unknown statistic: " .. tostring(statId))
		return
	end

	local profile = profileOf(player)
	profile[statId] += delta

	-- Remember it for the next save as well as for right now.
	local queue = pending[player]
	if not queue then
		queue = {}
		pending[player] = queue
	end
	queue[statId] = (queue[statId] or 0) + delta

	log(("%s  %s +%s  ->  %s"):format(player.Name, statId, tostring(delta), tostring(profile[statId])))
end

--[[
	Brings the live figure into line with something ALREADY saved elsewhere.

	Purchases go straight into the save file, because the duplicate check has to
	happen inside the same write that grants them. This updates what the player
	list shows without queueing the amount to be saved a second time -- calling
	the ordinary add() here would count every purchase twice.
]]
function StatsService.noteAlreadySaved(player: Player, statId: string, amount: number)
	if amount == 0 then
		return
	end
	local profile = profileOf(player)
	profile[statId] = (profile[statId] or 0) + amount
	log(("%s  %s +%s (already saved elsewhere)"):format(player.Name, statId, tostring(amount)))
end

function StatsService.get(player: Player, statId: string): number
	local profile = totals[player]
	return if profile then (profile[statId] or 0) else 0
end

function StatsService.getAll(player: Player): { [string]: number }
	return table.clone(profileOf(player))
end

--=============================================================================
-- SAVING
--=============================================================================

--[[
	Writes one player's outstanding changes.

	Refuses in two cases, both deliberately: their history failed to load (so
	writing would replace it with zeros), or a save for them is already running
	(so the same changes would be counted twice).
]]
function StatsService.flush(player: Player): boolean
	if failedToLoad[player] then
		return false
	end
	if saving[player] then
		return false
	end

	local queue = pending[player]
	if not queue or next(queue) == nil then
		return true
	end

	-- Take the changes out and hand them over. If the write fails they are put
	-- back, so nothing is lost -- it just goes out with the next attempt.
	pending[player] = {}
	saving[player] = true

	local userId = player.UserId
	local ok = StatsStore.flush(userId, queue)

	saving[player] = nil

	if not ok then
		local queueAgain = pending[player] or {}
		for id, amount in queue do
			queueAgain[id] = (queueAgain[id] or 0) + amount
		end
		pending[player] = queueAgain
		log(("save failed for %s; %d change(s) held for next time"):format(player.Name, #Stats.ids()))
	end
	return ok
end

--[[
	Everybody, at once, waited on. Used when the server is shutting down.

	Each player is saved in parallel because they are separate writes, but the
	whole thing is waited on with a deadline -- fire-and-forget here is what makes
	numbers go backwards after a restart.
]]
function StatsService.flushAll()
	local outstanding = 0
	for _, player in Players:GetPlayers() do
		outstanding += 1
		task.spawn(function()
			StatsService.flush(player)
			outstanding -= 1
		end)
	end

	local giveUpAt = os.clock() + Config.STATS_SHUTDOWN_WAIT
	while outstanding > 0 and os.clock() < giveUpAt do
		task.wait(0.1)
	end
	log(("flushAll finished with %d still outstanding"):format(outstanding))
end

--=============================================================================
-- THE SURVIVE CLOCK
--=============================================================================
--[[
	Survive time counts ONLY while a player is alive in a running round.

	Not free play, not the lobby, not the ghost area. There is no surviving to do
	in any of them -- you cannot be eliminated -- so counting them would turn the
	board into a measure of who leaves the game open longest.
]]

local function now(): number
	return os.clock()
end

--[[
	Stops one player's clock and banks what it measured. Safe to call when the
	clock is not running, which is what lets the three separate stop sites in
	RoundManager all call it without checking first.
]]
function StatsService.endRound(player: Player)
	local from = clockFrom[player]
	if not from then
		return
	end
	clockFrom[player] = nil

	local elapsed = now() - from
	if elapsed > 0 then
		StatsService.add(player, "SurviveSeconds", elapsed)
	end
end

--[[
	Starts the clock for everybody in a round.

	Closes any clock still open first. That matters because a round can end down
	a path that never reaches the round-end code -- the phase check partway
	through the main loop, for instance -- and a clock left running would
	otherwise keep accruing through the whole of free play.
]]
function StatsService.beginRound(players: { Player })
	for player in clockFrom do
		StatsService.endRound(player)
	end

	local at = now()
	for _, player in players do
		clockFrom[player] = at
	end
	log(("round started, clock running for %d player(s)"):format(#players))
end

function StatsService.endRoundAll()
	local closed = 0
	for player in clockFrom do
		StatsService.endRound(player)
		closed += 1
	end
	if closed > 0 then
		log(("round ended, closed %d clock(s)"):format(closed))
	end
end

function StatsService.isClockRunning(player: Player): boolean
	return clockFrom[player] ~= nil
end

--=============================================================================
-- THE PLAYER LIST
--=============================================================================
--[[
	The numbers Roblox shows in its own player list. Deliberately only a couple
	of columns -- more than three is unreadable on a phone -- with all five
	boards shown properly on the lobby wall instead.

	These show ALL-TIME totals, not this session's. A number that silently resets
	when a server restarts reads as a bug to a player. In this stage all-time and
	this-session happen to be the same thing.
]]

local function buildLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local values: { [string]: ValueBase } = {}
	for _, statId in Config.LEADERSTATS_COLUMNS do
		local definition = Stats.get(statId)
		if not definition then
			warn("[Stats] LEADERSTATS_COLUMNS names an unknown statistic: " .. tostring(statId))
			continue
		end

		-- A duration has to be a StringValue so it can read "12m 05s" rather
		-- than a raw pile of seconds.
		local value: ValueBase
		if definition.display == "duration" then
			local text = Instance.new("StringValue")
			text.Value = Stats.format(statId, 0)
			value = text
		else
			local number = Instance.new("IntValue")
			number.Value = 0
			value = number
		end

		value.Name = definition.label
		value.Parent = folder
		values[statId] = value
	end

	leaderstatValues[player] = values
	folder.Parent = player
end

--[[
	Repaints the player list. Called on a slow tick rather than on every
	increment -- a punch counter does not need to be frame-accurate, and this
	way a burst of clicks is one update instead of thirty.
]]
local function refreshLeaderstats()
	for player, values in leaderstatValues do
		if player.Parent ~= Players then
			continue
		end
		for statId, value in values do
			local total = StatsService.get(player, statId)
			-- Add whatever the clock has accrued but not yet banked, or the
			-- number visibly freezes for the whole of a round.
			local from = clockFrom[player]
			if statId == "SurviveSeconds" and from then
				total += now() - from
			end

			if value:IsA("StringValue") then
				value.Value = Stats.format(statId, total)
			elseif value:IsA("IntValue") then
				value.Value = math.floor(total)
			end
		end
	end
end

--=============================================================================
-- START
--=============================================================================

function StatsService.start()
	if running then
		return
	end
	running = true

	StatsStore.init()

	local function watch(player: Player)
		-- Load first, so their real totals are in place before anything can be
		-- added to them. Loading yields, so a player who does something in that
		-- window would otherwise have it added to zeros and then overwritten.
		local stored, loadedCleanly = StatsStore.load(player.UserId)

		if not loadedCleanly then
			failedToLoad[player] = true
			warn(("[Stats] %s plays this session without saving -- their history could not be read")
				:format(player.Name))
		end

		local profile = profileOf(player)
		for _, id in Stats.ids() do
			profile[id] = stored.totals[id] or 0
		end
		-- Anything counted while the load was in flight still counts; it is
		-- already in `pending` and gets added on top rather than lost.
		local queue = pending[player]
		if queue then
			for id, amount in queue do
				profile[id] = (profile[id] or 0) + amount
			end
		end

		buildLeaderstats(player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(watch, player) -- loading yields; do not hold up the join
	end)
	-- Anybody who joined in the moment before that connection was made.
	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end

	--[[
		Its OWN leaving handler, deliberately not RoundManager's.

		The order two handlers on the same event run in is not guaranteed, and
		getting it wrong here means the clock is thrown away before it is banked
		-- silently losing the player's last stretch of survive time on every
		single disconnect. Closing it here, first, removes the question.
	]]
	Players.PlayerRemoving:Connect(function(player)
		-- Clock first, then save, then forget. In that order: banking the clock
		-- after the save would write everything except their last stretch of
		-- survive time, on every single disconnect.
		StatsService.endRound(player)
		log(("%s left with %s"):format(player.Name, Stats.format("SurviveSeconds", StatsService.get(player, "SurviveSeconds"))))
		StatsService.flush(player)

		totals[player] = nil
		pending[player] = nil
		failedToLoad[player] = nil
		saving[player] = nil
		clockFrom[player] = nil
		leaderstatValues[player] = nil
	end)

	--[[
		Routine saving. Each player's turn is spread out by their user id so ten
		of them do not all write in the same second, which is what runs a server
		into the request limit.
	]]
	task.spawn(function()
		while true do
			task.wait(1)
			local slot = os.time() % Config.STATS_FLUSH_SECONDS
			for _, player in Players:GetPlayers() do
				if player.UserId % Config.STATS_FLUSH_SECONDS == slot then
					task.spawn(StatsService.flush, player)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.STATS_REFRESH_SECONDS)
			refreshLeaderstats()

			-- Safety sweep: a clock belonging to somebody who is no longer here
			-- should never be left running.
			for player in clockFrom do
				if player.Parent ~= Players then
					StatsService.endRound(player)
				end
			end
		end
	end)
end

return StatsService
