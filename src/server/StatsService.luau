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

local StatsService = {}

-- Every player's running totals. Kept as floats: survive time accrues in
-- fractions of a second, and flooring on every elimination would quietly lose
-- up to a second per round per player.
local totals: { [Player]: { [string]: number } } = {}

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
	log(("%s  %s +%s  ->  %s"):format(player.Name, statId, tostring(delta), tostring(profile[statId])))
end

function StatsService.get(player: Player, statId: string): number
	local profile = totals[player]
	return if profile then (profile[statId] or 0) else 0
end

function StatsService.getAll(player: Player): { [string]: number }
	return table.clone(profileOf(player))
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

	local function watch(player: Player)
		profileOf(player)
		buildLeaderstats(player)
	end

	Players.PlayerAdded:Connect(watch)
	-- Anybody who joined in the moment before that connection was made.
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	--[[
		Its OWN leaving handler, deliberately not RoundManager's.

		The order two handlers on the same event run in is not guaranteed, and
		getting it wrong here means the clock is thrown away before it is banked
		-- silently losing the player's last stretch of survive time on every
		single disconnect. Closing it here, first, removes the question.
	]]
	Players.PlayerRemoving:Connect(function(player)
		StatsService.endRound(player)
		log(("%s left with %s"):format(player.Name, Stats.format("SurviveSeconds", StatsService.get(player, "SurviveSeconds"))))
		-- Stage 2 flushes to the datastore here, before dropping the profile.
		totals[player] = nil
		clockFrom[player] = nil
		leaderstatValues[player] = nil
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
