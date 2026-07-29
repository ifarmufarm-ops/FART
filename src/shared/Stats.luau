--!strict
--[[
	Stats -- the catalogue of everything the game counts.

	One table, read by the counting code, the leaderboards and (later) the boards
	in the lobby, so nothing has to hardcode a name or a label. Adding a new
	statistic means adding one entry here.

	This is the same job Abilities.luau does for pickups, and for the same
	reason: the owner should be able to rename a board or change which periods it
	keeps without going looking through code.

	`periods` lists which leaderboards this statistic gets. "AllTime" is the
	hall of fame. The other three reset, which gives somebody who started
	yesterday a board they can realistically top. Only Robux has them for now --
	adding one to another statistic is a one-word edit to its list.

	`display` says how a number becomes text:
		"count"    -- 1,204
		"duration" -- 12m 05s
]]

export type Period = "AllTime" | "Daily" | "Weekly" | "Monthly"
export type Display = "count" | "duration"

export type Definition = {
	id: string,
	-- What the board is called, in the game's own voice.
	label: string,
	-- A plain description, for the owner rather than the player.
	blurb: string,
	display: Display,
	periods: { Period },
}

local Stats = {}

Stats.list = {
	{
		id = "SurviveSeconds",
		label = "SURVIVOR",
		blurb = "Seconds spent alive in a round. Free play does not count.",
		display = "duration" :: Display,
		periods = { "AllTime" :: Period },
	},
	{
		id = "Passes",
		label = "FARTED ON",
		blurb = "Bombs successfully handed to another player.",
		display = "count" :: Display,
		periods = { "AllTime" :: Period },
	},
	{
		id = "AbilityUses",
		label = "ABILITY KING",
		blurb = "Abilities used inside a round. The lobby practice range does not count.",
		display = "count" :: Display,
		periods = { "AllTime" :: Period },
	},
	{
		id = "Punches",
		label = "TUNG TUNG SAHUR HITS",
		blurb = "Punches landed on the thing in the ghost area.",
		display = "count" :: Display,
		periods = { "AllTime" :: Period },
	},
	{
		id = "RobuxSpent",
		label = "BIGGEST FLEXER",
		-- Worth restating wherever this appears: Roblox gives developers no
		-- purchase history, so this can only ever count spending that went
		-- through this game, from the day that existed.
		blurb = "Robux spent in this game. Cannot include anything bought elsewhere or before this shipped.",
		display = "count" :: Display,
		periods = { "AllTime" :: Period, "Daily" :: Period, "Weekly" :: Period, "Monthly" :: Period },
	},
}

local byId: { [string]: Definition } = {}
for _, definition in Stats.list do
	byId[definition.id] = definition
end

function Stats.get(id: string?): Definition?
	return if id then byId[id] else nil
end

--[[
	Every statistic id, in catalogue order. Used to build a fresh, complete set
	of totals so nothing is ever nil.
]]
function Stats.ids(): { string }
	local ids = {}
	for _, definition in Stats.list do
		table.insert(ids, definition.id)
	end
	return ids
end

function Stats.blank(): { [string]: number }
	local totals = {}
	for _, definition in Stats.list do
		totals[definition.id] = 0
	end
	return totals
end

--=============================================================================
-- TURNING NUMBERS INTO TEXT
--=============================================================================

--[[
	1204 -> "1,204". Long numbers are unreadable on a board otherwise.
]]
local function withSeparators(value: number): string
	local text = tostring(math.floor(value))
	local result = text
	while true do
		local replaced: number
		result, replaced = result:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return result
end

--[[
	Seconds -> "12m 05s", or "3h 04m" once it gets long enough that minutes stop
	being the interesting part.
]]
local function asDuration(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	local hours = math.floor(whole / 3600)
	local minutes = math.floor((whole % 3600) / 60)
	local secs = whole % 60

	if hours > 0 then
		return ("%dh %02dm"):format(hours, minutes)
	end
	if minutes > 0 then
		return ("%dm %02ds"):format(minutes, secs)
	end
	return ("%ds"):format(secs)
end

function Stats.format(id: string, value: number): string
	local definition = byId[id]
	if definition and definition.display == "duration" then
		return asDuration(value)
	end
	return withSeparators(value)
end

--=============================================================================
-- WHICH DAY, WEEK OR MONTH ARE WE IN?
--=============================================================================
--[[
	Turns a moment in time into the name of the period it falls in. The daily
	board for today is a different leaderboard from the one for yesterday, and
	this function is what decides which one you are writing to.

	Everything is UTC, so every server in the world agrees on where the day
	boundary is. A board that rolls over at a different moment depending on which
	server you happened to join would be indistinguishable from a bug.

	It is a pure function of the time you pass in, which is what makes rollover
	testable: ask it for a week from now and check the answer changed, instead of
	waiting a week.
]]

-- Monday 5 January 1970, 00:00 UTC -- the first Monday at or after the epoch.
-- Weeks are counted arithmetically from here rather than with os.date's %V,
-- whose support is not something to depend on.
local WEEK_EPOCH = 345600
local WEEK_SECONDS = 604800

function Stats.bucketFor(period: Period, unixTime: number?): string
	local moment = unixTime or os.time()

	if period == "AllTime" then
		return "all"
	elseif period == "Daily" then
		return os.date("!%Y-%m-%d", moment) :: string
	elseif period == "Weekly" then
		return "W" .. tostring(math.floor((moment - WEEK_EPOCH) / WEEK_SECONDS))
	elseif period == "Monthly" then
		return os.date("!%Y-%m", moment) :: string
	end

	return "all"
end

return Stats
