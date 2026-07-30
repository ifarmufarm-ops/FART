--!strict
--[[
	StatsStore -- the only file in the project that touches saved data.

	It knows how to load and save. It knows nothing about bombs, rounds or
	players doing things. That separation is the whole point: the dangerous code
	is small, boring, and in one place you can read end to end.

	THE ONE RULE THAT MATTERS MOST
	------------------------------
	If loading somebody's history fails, their profile is marked failedToLoad and
	is NEVER written back. Here is the failure it prevents, which has erased real
	players' progress in real games:

	  A player joins during a brief data outage. Every retry fails. Their totals
	  in memory are therefore zero. They play for ten minutes. The next routine
	  save writes "zero, plus this session" over the top of two months of real
	  history. Nothing in the game looks wrong at any point.

	That single boolean is the difference. Everything else here is plumbing.

	WHY SAVES ADD RATHER THAN OVERWRITE
	-----------------------------------
	A save sends the CHANGE since the last successful save, and UpdateAsync adds
	it to whatever is stored. It would be simpler to write the whole total, but
	then two servers holding the same player at once -- which happens, on a
	rejoin or a teleport -- would each clobber the other. Adding changes means
	they combine instead.

	The residual risk is the opposite one: a save that actually landed but
	errored on the way back gets retried and counted twice, inflating a punch
	count. For a joke leaderboard that is a fair trade, and it is written down
	here so nobody is surprised by it later.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)

local StatsStore = {}

export type Profile = {
	version: number,
	totals: { [string]: number },
	-- One entry per period that any statistic asks for. `bucket` is which day,
	-- week or month these numbers belong to; when it no longer matches the
	-- current one, the values are cleared. That is how the daily board resets
	-- with no nightly job -- it happens lazily, per player, when they next play.
	periods: { [string]: { bucket: string, values: { [string]: number } } },
	lastSeen: number,
}

-- Whether saving is possible at all. False in Studio without API access, and
-- false if the very first request throws for any other reason.
StatsStore.available = false

local store: DataStore? = nil
local warnedUnavailable = false

local function log(message: string)
	if Config.STATS_DEBUG_LOG then
		print("[StatsStore] " .. message)
	end
end

local function blank(): Profile
	return {
		version = 1,
		totals = Stats.blank(),
		periods = {},
		lastSeen = 0,
	}
end

StatsStore.blank = blank

--=============================================================================
-- GETTING HOLD OF THE STORE
--=============================================================================

--[[
	Opens the save file, once, and works out whether saving is possible at all.

	Studio gets a completely separate file. Playtesting must never be able to
	touch a real player's history, and a suffix is a stronger guarantee of that
	than remembering to set a flag.
]]
function StatsStore.init()
	if store or not Config.STATS_SAVE_ENABLED then
		return
	end

	local name = Config.STATS_STORE_NAME
	if RunService:IsStudio() then
		name = name .. "_studio"
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)

	if ok and result then
		store = result
		StatsStore.available = true
		log(("using save file %q"):format(name))
	else
		StatsStore.available = false
		warn(
			"[Hot Potato] Leaderboards are not saving. In Studio, tick "
				.. "Game Settings -> Security -> Enable Studio Access to API Services. "
				.. "The game runs fine without it; nothing will be remembered."
		)
	end
end

local function keyFor(userId: number): string
	return "player_" .. tostring(userId)
end

--=============================================================================
-- LOADING
--=============================================================================

--[[
	Reads a player's history.

	Returns the profile and whether it loaded cleanly. A FALSE second return is
	the important case: the caller must serve zeros and must never save.

	A player who has genuinely never played before returns a blank profile and
	TRUE -- that is a successful load of nothing, not a failure, and they are
	safe to save.
]]
function StatsStore.load(userId: number): (Profile, boolean)
	if not StatsStore.available or not store then
		-- Not an outage: saving is switched off or unreachable, and every
		-- profile is in the same boat. Serve zeros, save nothing.
		return blank(), false
	end

	local currentStore = store :: DataStore
	local wait = Config.STATS_RETRY_BASE

	for attempt = 1, Config.STATS_LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return currentStore:GetAsync(keyFor(userId))
		end)

		if ok then
			if result == nil then
				log(("%d is new"):format(userId))
				return blank(), true
			end
			if typeof(result) == "table" then
				local profile = result :: any
				-- Fill in anything a newer version of the game added, so a
				-- missing field can never become a nil arithmetic error.
				profile.version = profile.version or 1
				profile.totals = profile.totals or {}
				profile.periods = profile.periods or {}
				for _, id in Stats.ids() do
					profile.totals[id] = profile.totals[id] or 0
				end
				log(("%d loaded"):format(userId))
				return profile :: Profile, true
			end
			-- Something is stored but it is not what we write. Refuse to touch
			-- it rather than overwrite whatever it is.
			warn(("[StatsStore] %d has unreadable saved data; not saving for them"):format(userId))
			return blank(), false
		end

		log(("%d load attempt %d failed: %s"):format(userId, attempt, tostring(result)))
		if attempt < Config.STATS_LOAD_ATTEMPTS then
			task.wait(wait)
			wait *= 2
		end
	end

	warn(("[StatsStore] gave up loading %d after %d tries -- their progress will NOT be saved this session")
		:format(userId, Config.STATS_LOAD_ATTEMPTS))
	return blank(), false
end

--=============================================================================
-- SAVING
--=============================================================================

--[[
	Applies a set of changes to a stored profile. Pure, so it can be reasoned
	about on its own and reused inside UpdateAsync's transform.
]]
local function applyDelta(stored: Profile?, delta: { [string]: number }, at: number): Profile
	local profile = stored or blank()
	profile.totals = profile.totals or {}
	profile.periods = profile.periods or {}

	for id, amount in delta do
		profile.totals[id] = (profile.totals[id] or 0) + amount
	end

	-- The period buckets. Rolling over happens here: if what is stored belongs
	-- to yesterday, yesterday's numbers are dropped rather than added to.
	for _, definition in Stats.list do
		for _, period in definition.periods do
			if period == "AllTime" then
				continue
			end
			local bucket = Stats.bucketFor(period, at)
			local slot = profile.periods[period]
			if not slot or slot.bucket ~= bucket then
				slot = { bucket = bucket, values = {} }
				profile.periods[period] = slot
			end
			local amount = delta[definition.id]
			if amount and amount ~= 0 then
				slot.values[definition.id] = (slot.values[definition.id] or 0) + amount
			end
		end
	end

	profile.lastSeen = at
	return profile
end

StatsStore.applyDelta = applyDelta

--[[
	Writes a player's changes.

	Returns true only if the write definitely landed. The caller keeps its
	pending changes until then, so a failure loses nothing -- it just goes out
	with the next attempt.
]]
function StatsStore.flush(userId: number, delta: { [string]: number }): boolean
	if not StatsStore.available or not store then
		return false
	end

	local anything = false
	for _, amount in delta do
		if amount ~= 0 then
			anything = true
			break
		end
	end
	if not anything then
		return true -- nothing to write is a successful write
	end

	local currentStore = store :: DataStore
	local at = os.time()

	local ok, err = pcall(function()
		currentStore:UpdateAsync(keyFor(userId), function(stored)
			return applyDelta(stored, delta, at)
		end)
	end)

	if not ok then
		log(("%d save failed: %s"):format(userId, tostring(err)))
		return false
	end

	log(("%d saved"):format(userId))
	return true
end

--[[
	For checking what was actually written, from the command bar.
]]
function StatsStore.debugRead(userId: number): string
	if not StatsStore.available or not store then
		return "saving is unavailable"
	end
	local currentStore = store :: DataStore
	local ok, result = pcall(function()
		return currentStore:GetAsync(keyFor(userId))
	end)
	if not ok then
		return "read failed: " .. tostring(result)
	end
	if result == nil then
		return "nothing stored for " .. tostring(userId)
	end

	local profile = result :: any
	local lines = { ("stored for %d (lastSeen %s):"):format(userId, os.date("!%Y-%m-%d %H:%M", profile.lastSeen or 0)) }
	for _, id in Stats.ids() do
		table.insert(lines, ("  %-16s %s"):format(id, Stats.format(id, profile.totals[id] or 0)))
	end
	for period, slot in (profile.periods or {}) do
		local parts = {}
		for id, value in slot.values do
			table.insert(parts, ("%s=%s"):format(id, Stats.format(id, value)))
		end
		table.insert(lines, ("  %s [%s] %s"):format(period, slot.bucket, table.concat(parts, " ")))
	end
	return table.concat(lines, "\n")
end

return StatsStore
