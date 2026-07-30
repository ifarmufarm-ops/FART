--!strict
--[[
	MovementGuard -- notices characters moving faster than the game allows.

	WHY THIS EXISTS. Roblox hands each player's own machine control of their
	character's physics. That is what makes Dash and the fart jump feel instant
	rather than laggy, and it is not something that can be turned off without
	making the whole game feel worse. The cost is that a modified client can move
	its own character however it likes: teleport next to somebody to force a pass,
	or run at ten times normal speed. Every OTHER rule in this game is decided on
	the server and cannot be lied to; movement is the one exception, and in a
	competitive lobby it is the exception that matters.

	So the server watches where everybody actually is, works out how fast they
	must have been travelling, and compares that against the fastest they could
	legally be going right now.

	THE HARD PART is that the game itself flings people about constantly --
	explosions, the NPC's tackle, the dash, and every time a round starts and
	players are placed in the arena. Each of those looks exactly like cheating
	from the outside. Two things handle that:

	  * `allow(player, speed, seconds)` -- "this player is about to legitimately
	    travel this fast, do not count it". Called by the dash, the explosion
	    launch and the NPC's shove.
	  * `forgive(player)` -- "the SERVER just moved this player, forget where
	    they were". Called wherever the game teleports somebody itself.

	Miss one of those and honest players get flagged, which is far worse than
	missing a cheater. That is also why this ships in WATCH-ONLY mode: see
	Config.MOVEMENT_CORRECT.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MovementGuard = {}

-- One "you are allowed to go this fast until then" permission.
type Grant = { speed: number, until_: number }

type Watch = {
	lastPosition: Vector3?,
	lastSampleAt: number,
	-- Where they were last seen moving legally. Where a snap-back puts them.
	lastGoodPosition: Vector3?,
	-- Several at once, each expiring on its own. A single "highest so far" value
	-- does not work: it can only ever go up, so one dash would raise a player's
	-- limit to dash speed for the rest of their session, and every later
	-- permission -- a gentle shove, say -- would silently inherit it.
	grants: { Grant },
	strikes: number,
	lastStrikeAt: number,
	-- Set by forgive(): skip the next sample entirely, because the distance
	-- covered was the server's doing.
	skipNext: boolean,
}

local watched: { [Player]: Watch } = {}
local running = false

--[[
	Should this player's movement actually be acted on?

	Wired from init.server.luau. Enforcing everywhere would mean rubber-banding
	somebody messing about in the lobby, which gains nothing -- there is nothing
	to gain by cheating there. What matters is a live round.
]]
local shouldEnforce: (Player) -> boolean = function()
	return false
end

function MovementGuard.setEnforceCheck(check: (Player) -> boolean)
	shouldEnforce = check
end

local function log(message: string)
	if Config.MOVEMENT_LOG then
		warn("[MovementGuard] " .. message)
	end
end

local function watchFor(player: Player): Watch
	local existing = watched[player]
	if existing then
		return existing
	end
	local fresh: Watch = {
		lastPosition = nil,
		lastSampleAt = 0,
		lastGoodPosition = nil,
		grants = {},
		strikes = 0,
		lastStrikeAt = 0,
		skipNext = false,
	}
	watched[player] = fresh
	return fresh
end

--=============================================================================
-- TELLING IT WHAT IS LEGITIMATE
--=============================================================================

--[[
	"This player is about to travel this fast on purpose, for this long."

	Can be called several times over; each permission stands on its own and the
	most generous one that is still live decides the limit. That is what lets the
	dash ask for two -- a brief fast one for the burst, and a longer slower one to
	cover the fall and the slide it lands into.
]]
function MovementGuard.allow(player: Player?, speed: number, seconds: number)
	if not player or speed <= 0 or seconds <= 0 then
		return
	end
	local watch = watchFor(player)
	table.insert(watch.grants, { speed = speed, until_ = os.clock() + seconds })
end

--[[
	"The server just moved this player itself."

	Throws away the last known position so the jump is not measured as speed.
	Every server-side teleport must call this -- a round starting, a return to
	the lobby, a trip to the ghost area.
]]
function MovementGuard.forgive(player: Player?)
	if not player then
		return
	end
	local watch = watchFor(player)
	watch.lastPosition = nil
	watch.lastGoodPosition = nil
	watch.skipNext = true
end

--=============================================================================
-- WATCHING
--=============================================================================

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

--[[
	The fastest this player could honestly be moving right now.
]]
local function allowedSpeed(player: Player, watch: Watch): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local walk = if humanoid then humanoid.WalkSpeed else Config.BASE_WALK_SPEED

	-- Whichever live permission is most generous, dropping any that have run
	-- out as we go. Clearing them here matters: an expired permission must stop
	-- raising the limit, or one dash would licence a player for good.
	local limit = walk
	local clock = os.clock()
	for index = #watch.grants, 1, -1 do
		local grant = watch.grants[index]
		if clock >= grant.until_ then
			table.remove(watch.grants, index)
		elseif grant.speed > limit then
			limit = grant.speed
		end
	end

	-- The tolerance absorbs slopes, being pushed by another player, and the
	-- ordinary jitter of measuring position a few times a second. The flat
	-- margin on top absorbs a lag spike, where a real player's position arrives
	-- late and then catches up all at once.
	return limit * Config.MOVEMENT_TOLERANCE + Config.MOVEMENT_MARGIN
end

local function strike(player: Player, watch: Watch, reason: string)
	local clock = os.clock()

	-- Strikes fade. One odd reading during a lag spike should not sit on a
	-- player's record forever waiting for two more.
	if clock - watch.lastStrikeAt > Config.MOVEMENT_STRIKE_WINDOW then
		watch.strikes = 0
	end
	watch.strikes += 1
	watch.lastStrikeAt = clock

	log(("%s: %s (strike %d of %d)"):format(player.Name, reason, watch.strikes, Config.MOVEMENT_STRIKES))

	if watch.strikes < Config.MOVEMENT_STRIKES then
		return
	end
	watch.strikes = 0

	if not Config.MOVEMENT_CORRECT then
		log(("%s would have been snapped back, but MOVEMENT_CORRECT is off"):format(player.Name))
		return
	end

	local root = rootOf(player)
	local back = watch.lastGoodPosition
	if not root or not back then
		return
	end

	-- Put them back where they were last legitimately seen. Not a kick: a false
	-- positive should cost somebody a moment of confusion, not their game.
	root.CFrame = CFrame.new(back)
	root.AssemblyLinearVelocity = Vector3.zero
	watch.lastPosition = back
	log(("%s snapped back to their last legal position"):format(player.Name))
end

local function sample(player: Player)
	local watch = watchFor(player)
	local root = rootOf(player)
	if not root then
		-- No body: nothing to measure, and the next body starts fresh.
		watch.lastPosition = nil
		watch.lastGoodPosition = nil
		return
	end

	local position = root.Position
	local clock = os.clock()

	if watch.skipNext or not watch.lastPosition then
		watch.skipNext = false
		watch.lastPosition = position
		watch.lastGoodPosition = position
		watch.lastSampleAt = clock
		return
	end

	local dt = clock - watch.lastSampleAt
	if dt <= 0 then
		return
	end

	local from = watch.lastPosition :: Vector3
	-- HORIZONTAL only. Falling is legitimately fast, more so under Low Gravity
	-- and when an explosion punts somebody into the sky, and none of it helps a
	-- cheater reach another player.
	local moved = (Vector3.new(position.X, 0, position.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
	local speed = moved / dt

	watch.lastPosition = position
	watch.lastSampleAt = clock

	if not shouldEnforce(player) then
		-- Still tracked, so the moment a round starts there is a baseline, but
		-- nothing is judged.
		watch.lastGoodPosition = position
		return
	end

	-- A single enormous jump is a teleport, not speed, and is worth catching on
	-- its own: a cheater only needs one to appear next to somebody.
	if moved > Config.MOVEMENT_TELEPORT_STUDS then
		strike(player, watch, ("jumped %.0f studs in one sample"):format(moved))
		return
	end

	local limit = allowedSpeed(player, watch)
	if speed > limit then
		strike(player, watch, ("%.0f studs/s against a limit of %.0f"):format(speed, limit))
		return
	end

	watch.lastGoodPosition = position
end

function MovementGuard.start()
	if running or not Config.MOVEMENT_GUARD_ENABLED then
		return
	end
	running = true

	local function watch(player: Player)
		watchFor(player)
		-- A brand new body appears wherever the game put it, which is not
		-- movement the player is responsible for.
		player.CharacterAdded:Connect(function()
			MovementGuard.forgive(player)
		end)
	end

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		watched[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.MOVEMENT_CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				sample(player)
			end
		end
	end)
end

--[[
	For checking what the guard thinks, from the command bar or a test.
]]
function MovementGuard.debugStateOf(player: Player): string
	local watch = watched[player]
	if not watch then
		return "not watched"
	end
	return ("strikes=%d liveGrants=%d enforcing=%s limit=%.0f")
		:format(watch.strikes, #watch.grants, tostring(shouldEnforce(player)), allowedSpeed(player, watch))
end

return MovementGuard
