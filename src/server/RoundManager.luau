--[[
	RoundManager -- the referee. Every rule lives in this file and only here.

	Everything that matters is decided on the server: who gets the bomb, whether
	a pass counts, when the timer runs out, and who is eliminated. The client is
	only ever told the result, so there is nothing for an exploiter to fake.

	The round runs as a simple sequence of phases that loops forever:

		Waiting        not enough players yet
		Intermission   countdown, everyone gets a fresh character
		Playing        the bomb cycles until one player is left
		RoundOver      winner shown, then back to Intermission
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AbilityService = require(script.Parent.AbilityService)
local Arena = require(script.Parent.Arena)
local BrainRot = require(script.Parent.BrainRot)
local Bomb = require(script.Parent.Bomb)
local Modifiers = require(script.Parent.Modifiers)
local MovementGuard = require(script.Parent.MovementGuard)
local Pickups = require(script.Parent.Pickups)
local Ragdoll = require(script.Parent.Ragdoll)
local StatsService = require(script.Parent.StatsService)
local TestRange = require(script.Parent.TestRange)

local RoundManager = {}

local COLOR_ELIMINATED = Color3.fromRGB(255, 110, 70)
local COLOR_WINNER = Color3.fromRGB(255, 214, 92)
local COLOR_INFO = Color3.fromRGB(235, 238, 245)

-- Current state of the world. Only this module writes to these.
local phase: string = "Waiting"
local alive: { Player } = {}
local holder: Player? = nil
local deadline: number = 0 -- server clock time the countdown ends
local duration: number = 0 -- how long the current countdown started at
local cycleDuration: number = Config.TIMER_START -- shrinks with every pass
local receivedAt: number = 0 -- when the current holder got the bomb
local previousHolder: Player? = nil -- who passed it to the current holder

--[[
	Who is actually playing.

	This used to be "everybody connected to the server", which was right when
	there was nowhere else to be. Now there is a lobby, so it is "everybody who
	has asked to play" -- and the queue is what answers that.

	Kept as a provider rather than a require so RoundManager and Queue do not
	have to know about each other, the same arrangement Pickups and BrainRot
	already use for the alive list. init.server.luau wires it up.

	The default returns nobody, so a server with no queue wired in sits in
	Waiting forever rather than dragging the whole lobby into a round.
]]
local getParticipants: () -> { Player } = function()
	return {}
end

function RoundManager.setParticipantProvider(provider: () -> { Player })
	getParticipants = provider
end

--[[
	How to put somebody back in the lobby when their round is over.

	Wired from init.server.luau so this file never has to know the lobby exists,
	the same arrangement as the participant provider above. Does nothing until
	it is set.
]]
local returnToLobby: (Player) -> boolean = function()
	return false
end

function RoundManager.setReturnToLobby(handler: (Player) -> boolean)
	returnToLobby = handler
end

--[[
	How to send somebody up to the ghost area, and how to bring them back down.
	Wired from init.server.luau, same as everything else here, so this file does
	not have to know the ghost area exists.
]]
local sendToGhost: (Player) -> boolean = function()
	return false
end
-- Returns whether they WERE a ghost, which is how the round end knows who
-- needs bringing down and who is already standing in the arena.
local clearGhost: (Player) -> boolean = function()
	return false
end

function RoundManager.setGhostHandlers(send: (Player) -> boolean, clear: (Player) -> boolean)
	sendToGhost = send
	clearGhost = clear
end

--=============================================================================
-- SMALL HELPERS
--=============================================================================

local function now(): number
	return workspace:GetServerTimeNow()
end

local function minimumPlayers(): number
	if Config.TEST_MODE or Config.SOLO_TEST_MODE then
		return 1 -- so you can poke at things on your own
	end
	return Config.MIN_PLAYERS
end

-- A player counts as "ready" only if they are still connected and have a body
-- with a living humanoid. Anything else and they cannot hold or receive a bomb.
local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isReady(player: Player): boolean
	return player.Parent == Players and getRoot(player) ~= nil
end

local function indexOf(player: Player): number?
	return table.find(alive, player)
end

--[[
	Is this player still in the round? Used by AbilityService to reject ability
	requests from anyone who is out, spectating, or between rounds.
]]
function RoundManager.isAlive(player: Player): boolean
	return (phase == "Playing" or phase == "Sandbox") and indexOf(player) ~= nil
end

--[[
	Who currently holds the bomb. Stage 3's NPC needs this so it can chase
	everyone EXCEPT them.
]]
--[[
	What the game is doing right now: Waiting, Intermission, Playing, RoundOver
	or Sandbox. The lobby needs this to know whether a player without a body is
	someone to put back on their feet, or someone who is mid-round and should
	stay watching until it ends.
]]
function RoundManager.getPhase(): string
	return phase
end

function RoundManager.getHolder(): Player?
	return holder
end

--[[
	Who this round's messages are for.

	NOT the same as `alive`. Somebody who has just been blown up is no longer
	alive but is still watching the finish, and cutting their HUD off the moment
	they die would be worse than useless. So this is everybody who STARTED the
	round, and it stays put until the round ends.

	Everybody else is in the lobby and must not see any of it -- no bomb timer
	counting down, no "so-and-so has the bomb", no elimination notices. That was
	right when the whole server was in the round and is wrong now there is
	somewhere else to be.
]]
local roundMembers: { Player } = {}

-- Whether a round is in progress at all, which is NOT the same as "roundMembers
-- is non-empty". If every member leaves spectating, the list empties while the
-- round carries on -- and falling back to broadcasting at everyone then would
-- undo the very thing they asked for.
local roundActive = false

-- Everybody knocking about in the arena between rounds. Not in a round, but
-- very much in the arena, and they should be able to use the pickups.
local freePlay: { Player } = {}

local function isRoundMember(player: Player): boolean
	for _, member in roundMembers do
		if member == player then
			return true
		end
	end
	return false
end

--[[
	Sends to the people in this round, and nobody else.

	Outside a round there is nothing round-specific to leak, so it goes to
	everyone -- that is how the lobby still sees "Waiting for players".
]]
local function fireToRound(remote: RemoteEvent, ...)
	if not roundActive then
		remote:FireAllClients(...)
		return
	end
	for _, player in roundMembers do
		if player.Parent == Players then
			remote:FireClient(player, ...)
		end
	end
end

local function announce(text: string, color: Color3, hold: number?)
	fireToRound(Remotes.Announce, text, color, hold or 3)
end

--[[
	The idle state a lobby player sees: no timer, no holder, nobody alive. It
	has to be sent rather than simply withheld, or their HUD would freeze on
	whatever it happened to be showing when they left the round.
]]
local function idleState()
	return {
		phase = "Waiting",
		holderUserId = nil,
		deadline = nil,
		duration = nil,
		aliveUserIds = {},
	}
end

--[[
	Is this player in the queue? Wired from init.server.luau.

	The round HUD -- the countdown, the bar, "waiting for players" -- is only
	shown to people who have actually asked to play. Somebody wandering round
	the lobby who has not stepped on the pad has no use for a countdown, and
	showing them one implies the game is waiting on them when it is not.
]]
local isQueued: (Player) -> boolean = function()
	return true -- until wired, show the HUD to everyone as before
end

function RoundManager.setQueueCheck(check: (Player) -> boolean)
	isQueued = check
end

local function broadcast()
	local ids = table.create(#alive)
	for _, player in alive do
		table.insert(ids, player.UserId)
	end
	local state = {
		phase = phase,
		holderUserId = if holder then holder.UserId else nil,
		deadline = deadline,
		duration = duration,
		aliveUserIds = ids,
	}

	-- Every payload is per-player now, because "are you in the queue" differs
	-- for each of them.
	for _, player in Players:GetPlayers() do
		local mine = if roundActive and not isRoundMember(player) then idleState() else table.clone(state)
		mine.queued = isQueued(player)
		Remotes.StateChanged:FireClient(player, mine)
	end
end

--[[
	"I am out, let me go to the lobby rather than watch the rest of this."

	Only honoured for somebody who is genuinely out of the round -- a living
	player asking for this would be using it to escape the bomb, so the check is
	a rule and not a formality. Returns true if they were released.

	This only releases them from the ROUND. Taking them out of the queue as well
	is done by whoever wired the remote up -- see init.server.luau -- because
	the queue is not this file's business. Handing them a body is left to the
	lobby's own respawner, which is already watching for people without one.
]]
--[[
	Is this player part of the round that is running right now?

	True for everybody who started it, including those already eliminated and
	watching the finish -- and false the moment they ask to leave. The lobby
	uses this to decide who to put back on their feet, so it has to go false as
	soon as somebody opts out, not when the round eventually ends.
]]
--[[
	Everybody in the round right now, for anything that must not touch the
	lobby. A copy, so a caller cannot reach in and change the roster.

	When no round is running this returns EVERYONE, and that is deliberate.
	Test Mode's sandbox has no queue and no round, but everybody present is
	playing in it -- returning nobody there would leave the showcase range's
	beacons affecting no one at all. Outside a round there are no modifiers
	running to leak anyway, because the round's end clears them.
]]
function RoundManager.getRoundMembers(): { Player }
	if not roundActive then
		return Players:GetPlayers()
	end
	return table.clone(roundMembers)
end

--[[
	Everybody currently IN THE ARENA -- which is not the same as everybody in a
	round, because of the free-for-all between rounds.

	Three cases:
	  * a round running   -> its members
	  * between rounds    -> whoever came back down for free play
	  * Test Mode sandbox -> everyone, since that is what a sandbox is

	This is what the pickups and the beacon events use. Getting it from `alive`
	instead would mean nobody could pick anything up between rounds, since
	nobody is alive in a round that has finished -- and getting it from "everyone"
	would let a beacon in the arena reach somebody standing in the lobby.
]]
function RoundManager.getArenaPlayers(): { Player }
	if phase == "Sandbox" then
		return Players:GetPlayers()
	end
	if roundActive then
		return table.clone(roundMembers)
	end
	return table.clone(freePlay)
end

function RoundManager.isInRound(player: Player): boolean
	return roundActive and isRoundMember(player)
end

function RoundManager.requestLeave(player: Player): boolean
	-- The ONLY refusal: you are alive in a round that is actually being played.
	-- Letting that through would turn the button into an escape from the bomb.
	if phase == "Playing" then
		for _, living in alive do
			if living == player then
				return false
			end
		end
	end

	-- Everybody else may go: a ghost watching the finish, somebody knocking
	-- about in the arena during free play, or a queued player in the lobby who
	-- has changed their mind before the round starts.
	for index, member in roundMembers do
		if member == player then
			table.remove(roundMembers, index)
			break
		end
	end
	for index, other in freePlay do
		if other == player then
			table.remove(freePlay, index)
			break
		end
	end

	-- Their HUD returns to the neutral lobby state at once, rather than
	-- whenever the round happens to end.
	Remotes.StateChanged:FireClient(player, idleState())
	return true
end

local function setCountdown(seconds: number)
	duration = seconds
	deadline = now() + seconds
end

--=============================================================================
-- BOMB HANDLING
--=============================================================================

--[[
	Hands the bomb to a player and starts their countdown. The countdown always
	uses cycleDuration, which is shortened on every pass and reset after an
	explosion (see Config.TIMER_DECAY_PER_PASS).
]]
local function giveBombTo(player: Player): boolean
	local character = player.Character
	if not character or not Bomb.attachTo(character) then
		return false
	end

	-- Carrying the bomb makes you faster, so the chase is a real chase rather
	-- than two players jogging at identical speed. Hand it over BEFORE changing
	-- who the holder is, so the person losing it drops back to normal.
	if holder then
		AbilityService.setBombHolder(holder, false)
	end
	AbilityService.setBombHolder(player, true)

	previousHolder = holder
	holder = player
	receivedAt = now()
	setCountdown(cycleDuration)
	broadcast()
	return true
end

--[[
	Picks a random player who can actually take the bomb.

	Anyone who has already been eliminated is gone from `alive` by this point,
	so there is nobody to exclude -- this only ever chooses between survivors
	who currently have a usable body.
]]
local function pickRandomHolder(): Player?
	local candidates = {}
	for _, player in alive do
		if isReady(player) then
			table.insert(candidates, player)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(#candidates)]
end

--[[
	Finds the closest other living player within passing range, or nil.
	This is the "touch" in touch-to-pass -- it is a distance check rather than a
	Touched event because distance is reliable and cannot be spoofed by a client.
]]
local function findPassTarget(): Player?
	local currentHolder = holder
	if not currentHolder then
		return nil
	end
	local holderRoot = getRoot(currentHolder)
	if not holderRoot then
		return nil
	end

	local best: Player? = nil
	local bestDistance = Config.PASS_RADIUS

	for _, player in alive do
		if player == currentHolder then
			continue
		end
		-- Optional rule: you cannot hand it straight back to whoever gave it
		-- to you. Only applies in a crowd -- in a one-on-one the excluded
		-- player is the ONLY player, so applying it there would leave the
		-- holder with no legal target and guarantee their death. The final
		-- duel is ended by the shrinking timer instead.
		-- See Config.BLOCK_INSTANT_PASS_BACK and Config.PASS_BACK_MIN_PLAYERS.
		if
			Config.BLOCK_INSTANT_PASS_BACK
			and #alive >= Config.PASS_BACK_MIN_PLAYERS
			and player == previousHolder
		then
			continue
		end
		local root = getRoot(player)
		if not root then
			continue
		end
		local distance = (root.Position - holderRoot.Position).Magnitude
		if distance < bestDistance then
			best = player
			bestDistance = distance
		end
	end

	return best
end

--=============================================================================
-- ELIMINATION
--=============================================================================

--[[
	Blows a player up and takes them out of the round. No damage is dealt --
	they are made floppy and thrown, then their body is cleaned up and they
	switch to a spectator camera.
]]
local function eliminate(player: Player)
	local index = indexOf(player)
	if index then
		table.remove(alive, index)
	end

	-- Bank their survive time before anything else. Doing it up here rather than
	-- at the end means an error in the ragdoll or the explosion cannot swallow
	-- the accounting.
	StatsService.endRound(player)

	local character = player.Character
	local blastPosition = Bomb.getPosition()

	-- Whatever happens next, they are not carrying it any more, so the speed
	-- that came with it goes too.
	AbilityService.setBombHolder(player, false)

	if holder == player then
		Bomb.detach()
		holder = nil
	end

	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if not blastPosition and root and root:IsA("BasePart") then
			blastPosition = root.Position + Vector3.new(0, 2, 0)
		end
		if blastPosition then
			Ragdoll.explode(blastPosition)
		end

		Ragdoll.apply(character)
		Ragdoll.launch(character)

		-- Let the body fly and settle, then take them up to the ghost area with
		-- a fresh one. Losing your body entirely and watching a drifting camera
		-- is a long time to spend doing nothing; up there you can walk about
		-- and watch the rest of the round through the glass.
		task.delay(Config.CORPSE_LIFETIME, function()
			if character and character.Parent then
				character:Destroy()
			end
			-- Only if the round is still going. If it ended while the body was
			-- in the air, everybody is about to be put back in the arena
			-- anyway and sending them up first would be a pointless round trip.
			if phase == "Playing" and player.Parent == Players then
				sendToGhost(player)
			end
		end)
	end

	announce(player.DisplayName .. " was blown up!", COLOR_ELIMINATED, 3)
	broadcast()
end

--[[
	Has this player dropped out for a reason that has nothing to do with the
	bomb -- left the server, hit the Reset button, fell out of the world?

	Note that a ragdolled body is NOT dead (we never touch health), so this
	never fires on someone who is mid-explosion.
]]
local function hasDroppedOut(player: Player): boolean
	if player.Parent ~= Players then
		return true
	end
	local character = player.Character
	if not character or not character.Parent then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return true
	end
	return false
end

--[[
	Drops anyone who is no longer in a fit state to play. Without this a player
	who resets in Studio would sit in the alive list forever and the round would
	never be able to end.
]]
local function pruneAlive()
	for i = #alive, 1, -1 do
		local player = alive[i]
		if not hasDroppedOut(player) then
			continue
		end

		table.remove(alive, i)

		-- The involuntary way out -- pressed Reset, fell out of the world,
		-- disconnected. This path never calls eliminate(), so without banking
		-- the clock here their survive time would be thrown away.
		StatsService.endRound(player)

		if holder == player then
			Bomb.detach()
			holder = nil
		end

		-- Clear away a dead-but-still-there body so the player flips over to
		-- the spectator camera like everyone else who is out.
		local character = player.Character
		if character and character.Parent then
			character:Destroy()
		end

		if player.Parent == Players then
			announce(player.DisplayName .. " is out!", COLOR_ELIMINATED, 2.5)
		end
	end
end

--=============================================================================
-- SPAWNING
--=============================================================================

local function spawnEveryone(list: { Player })
	local spawns = Arena.getShuffledSpawns()
	local pending = #list

	for i, player in list do
		task.spawn(function()
			pcall(function()
				player:LoadCharacter()
			end)
			local character = player.Character
			if character and #spawns > 0 then
				local cf = spawns[((i - 1) % #spawns) + 1]
				pcall(function()
					character:PivotTo(cf)
				end)
			end
			if character then
				-- Re-tag here as well as on CharacterAdded: LoadCharacter has
				-- definitely finished by now, so nothing is missed if a limb
				-- arrived a moment after the character was parented.
				Ragdoll.setCollisionGroup(character, Ragdoll.LIVE_GROUP)
			end
			-- The lobby-to-arena jump is the server's doing, not the player's.
			MovementGuard.forgive(player)
			pending -= 1
		end)
	end

	-- Wait for everyone, but never hang the whole game on one slow load.
	local giveUpAt = os.clock() + 10
	while pending > 0 and os.clock() < giveUpAt do
		task.wait()
	end
end

--=============================================================================
-- PHASES
--=============================================================================

local function runIntermission()
	phase = "Intermission"
	holder = nil
	alive = {}
	-- Belt and braces. If a round ended down a path that skipped the round-end
	-- code, this catches any clock still running before the next one starts.
	StatsService.endRoundAll()
	-- The countdown belongs to whoever is queued: they are the ones about to be
	-- pulled in, and it is their window to change their mind. Anybody else in
	-- the lobby should not see a countdown for a round they are not in.
	roundMembers = getParticipants()
	roundActive = true
	Bomb.detach()
	setCountdown(Config.INTERMISSION_SECONDS)
	broadcast()

	announce("Get ready...", COLOR_INFO, 3)

	while now() < deadline do
		task.wait(0.25)
		if #getParticipants() < minimumPlayers() then
			return false -- someone left or unqueued, fall back to Waiting
		end
	end
	return true
end

--[[
	TEST MODE. Not a round at all -- a sandbox that never ends.

	Nobody gets the bomb, nobody is eliminated, and nothing resets, so you can
	stand still and try things for as long as you like. The showcase range along
	the far wall holds one of everything.

	Anyone who loses their character (fell out of the world, hit Reset) is
	quietly given a new one rather than being knocked out of the round.
]]
local function runSandbox()
	phase = "Sandbox"
	holder = nil
	duration = 0
	deadline = 0

	alive = {}
	for _, player in Players:GetPlayers() do
		table.insert(alive, player)
	end

	spawnEveryone(alive)
	AbilityService.clearAll()
	Modifiers.clearAll()

	Pickups.setActive(true, function()
		return alive
	end)
	if Config.TEST_SHOW_RANGE then
		TestRange.setActive(true, function()
			return alive
		end)
	end

	broadcast()
	announce("TEST MODE — no bomb, no elimination", COLOR_INFO, 6)

	while Config.TEST_MODE do
		task.wait(1)

		-- Keep the roster current, and put anybody who lost a body back on
		-- their feet instead of dropping them.
		alive = {}
		for _, player in Players:GetPlayers() do
			table.insert(alive, player)
			if hasDroppedOut(player) and player.Parent == Players then
				task.spawn(function()
					pcall(function()
						player:LoadCharacter()
					end)
				end)
			end
		end
		broadcast()
	end

	Pickups.setActive(false)
	TestRange.setActive(false)
end

--[[
	One full round. Runs until a single player is left standing.
]]
local function runRound()
	phase = "Playing"

	-- Only the queue plays. Everyone else stays in the lobby, untouched by the
	-- bomb, the pickups and the eliminations.
	alive = {}
	for _, player in getParticipants() do
		table.insert(alive, player)
	end

	-- Everyone who STARTED gets this round's HUD, and keeps it after they are
	-- eliminated so they can watch the finish. See roundMembers.
	roundMembers = table.clone(alive)
	roundActive = true
	freePlay = {} -- the free-for-all is over; the round owns the arena again

	spawnEveryone(alive)
	pruneAlive()

	if #alive < minimumPlayers() then
		return
	end

	-- Normally the round ends when one player is left standing. When you are
	-- testing alone there is nobody to be "last", so we let it run until you
	-- have blown yourself up -- otherwise the round would end the instant it
	-- started and you would never see the explosion.
	local endWhenAtOrBelow = if #alive <= 1 then 0 else 1

	cycleDuration = Config.TIMER_START

	-- Fresh slots and a fresh scattering of pickups every round. The provider
	-- hands Pickups the live `alive` list without either file having to know
	-- about the other.
	AbilityService.clearAll()
	Modifiers.clearAll()
	Pickups.setActive(true, function()
		return alive
	end)
	-- Test Mode with the bomb left ON: normal round, but the showcase range is
	-- still there so you can grab whatever you want to try mid-round.
	if Config.TEST_MODE and Config.TEST_SHOW_RANGE then
		TestRange.setActive(true, function()
			return alive
		end)
	end

	local first = pickRandomHolder()
	if not first or not giveBombTo(first) then
		return
	end

	announce(first.DisplayName .. " has the bomb!", COLOR_ELIMINATED, 2.5)
	broadcast()

	-- Survive clocks start HERE and not where `alive` was filled in. Between the
	-- two there are early returns -- not enough players, nobody able to take the
	-- bomb -- that abandon the round without ever reaching the round-end code. A
	-- clock started before them would run for the rest of the server's life.
	StatsService.beginRound(alive)

	-- The beeping runs on its own clock so it can speed up smoothly without
	-- interfering with the main rule checks below.
	task.spawn(function()
		while phase == "Playing" do
			if holder and duration > 0 then
				local fraction = math.clamp((deadline - now()) / duration, 0, 1)
				Bomb.beep(fraction)
				task.wait(0.18 + fraction * 0.62)
			else
				task.wait(0.2)
			end
		end
	end)

	while true do
		task.wait(Config.PASS_CHECK_INTERVAL)
		if phase ~= "Playing" then
			return
		end

		pruneAlive()

		if #alive <= endWhenAtOrBelow then
			break
		end

		-- If the holder vanished (left, or reset in Studio), pass it on so the
		-- round cannot stall with nobody holding the bomb.
		if not holder or not isReady(holder) then
			local replacement = pickRandomHolder()
			if not replacement or not giveBombTo(replacement) then
				break
			end
		end

		-- Live progress for the light, sparks and bomb colour.
		if duration > 0 then
			Bomb.setUrgency(math.clamp((deadline - now()) / duration, 0, 1))
		end

		-- 1. Has the holder caught somebody? (blocked briefly after receiving it)
		if now() - receivedAt >= Config.PASS_COOLDOWN then
			local target = findPassTarget()
			if target then
				-- In a one-on-one the timer keeps shrinking past the normal
				-- floor, until it is shorter than the pass cooldown and the
				-- trade physically cannot continue. That is what ends a duel.
				local floor = if #alive <= 2 then Config.TIMER_MINIMUM_DUEL else Config.TIMER_MINIMUM
				cycleDuration = math.max(floor, cycleDuration - Config.TIMER_DECAY_PER_PASS)

				-- Who gets the credit, captured BEFORE the hand-over. giveBombTo
				-- reassigns `holder`, so reading it afterwards would credit every
				-- pass to the player who RECEIVED the bomb. That mistake looks
				-- entirely plausible from the outside -- the numbers still go up
				-- -- and cannot be spotted playing alone, because there is
				-- nobody to pass to.
				local passer = holder

				if giveBombTo(target) then
					-- Only on success. giveBombTo returns false when the bomb
					-- fails to attach, and a failed hand-over is not a pass.
					--
					-- This is the ONLY genuine player-to-player pass. The other
					-- three calls to giveBombTo are the opening hand-out, the
					-- replacement when a holder vanishes, and the hand-out after
					-- an explosion -- none of which anybody passed.
					StatsService.add(passer, "Passes", 1)
					continue
				end
			end
		end

		-- 2. Has the timer run out?
		if now() >= deadline then
			local victim = holder
			if victim then
				eliminate(victim)
			end

			if Config.RESET_TIMER_AFTER_EXPLOSION then
				cycleDuration = Config.TIMER_START
			end

			if #alive <= endWhenAtOrBelow then
				break
			end

			local nextHolder = pickRandomHolder()
			if not nextHolder or not giveBombTo(nextHolder) then
				break
			end
			announce(nextHolder.DisplayName .. " has the bomb!", COLOR_ELIMINATED, 2.5)
		end
	end

	-- Round over.
	--
	-- The pickups, abilities and beacon events are deliberately LEFT RUNNING
	-- through the celebration below. The winner has the map to themselves for a
	-- few seconds and should be able to run about grabbing whatever is still
	-- lying around, rather than standing in a map that froze the instant they
	-- won. Everything is tidied up shortly before the next round instead.
	phase = "RoundOver"

	-- Everybody still standing stops the clock here -- the winner, and anyone
	-- the loop broke out early for. Every exit from the round above falls
	-- through to this line.
	StatsService.endRoundAll()

	-- A natural checkpoint: a whole round's worth of survive time has just been
	-- banked, so get it written rather than waiting for the routine save.
	for _, member in roundMembers do
		if member.Parent == Players then
			task.spawn(StatsService.flush, member)
		end
	end

	Bomb.detach()
	holder = nil
	duration = 0
	deadline = 0
	broadcast()

	local winner = alive[1]
	if winner then
		announce(winner.DisplayName .. " survives!", COLOR_WINNER, Config.ROUND_OVER_SECONDS)
	else
		-- Only reachable when testing alone, or if everyone left at once.
		announce("No survivors.", COLOR_INFO, Config.ROUND_OVER_SECONDS)
	end

	-- A few seconds on the winner, then EVERYBODY comes back into the arena --
	-- winner, losers, ghosts, all of them -- and the map stays live.
	--
	-- That gap before the next round is deliberately a free-for-all: bodies but
	-- no bomb, with pickups still spawning. It is the main chance a new player
	-- gets to work out what the abilities do without a round riding on it, and
	-- it is why nobody is sent back to the lobby here. The lobby is for people
	-- who have chosen to stop playing, not a waiting room between rounds.
	task.wait(Config.ROUND_OVER_SECONDS)

	local spawns = Arena.getShuffledSpawns()
	freePlay = {}
	for index, member in roundMembers do
		if member.Parent == Players then
			table.insert(freePlay, member)

			-- Solid again, and no longer treated as dead. Tells us whether they
			-- were up on the glass or already down here.
			local wasGhost = clearGhost(member)

			local character = member.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local onTheirFeet = humanoid ~= nil and humanoid.Health > 0

			if onTheirFeet and not wasGhost then
				-- THE WINNER. They are already standing in the arena with a
				-- perfectly good body, so leave them entirely alone -- they
				-- carry on roaming while everybody else drops back in around
				-- them. Respawning them here is what briefly flashed them
				-- through the lobby, because a respawn always lands on the
				-- lobby's spawn pads before anything can move them.
				continue
			end

			local destination = spawns[((index - 1) % math.max(#spawns, 1)) + 1]
			if wasGhost and onTheirFeet then
				-- A ghost already has a body; just bring it down. No respawn,
				-- so no trip through the lobby.
				if character and destination then
					pcall(function()
						character:PivotTo(destination)
					end)
					if character.PrimaryPart then
						character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
					end
					-- Brought down 130 studs by the server.
					MovementGuard.forgive(member)
				end
				continue
			end

			-- No usable body at all, so they need a new one.
			task.spawn(function()
				pcall(function()
					member:LoadCharacter()
				end)
				local fresh = member.Character
				if fresh and destination then
					pcall(function()
						fresh:PivotTo(destination)
					end)
				end
				if fresh then
					Ragdoll.setCollisionGroup(fresh, Ragdoll.LIVE_GROUP)
				end
			end)
		end
	end

	-- Hand the pickups over to the free-play crowd. Without this they would
	-- keep asking `alive`, which is empty now the round is over, and nobody
	-- would be able to pick anything up.
	Pickups.setActive(true, RoundManager.getArenaPlayers)

	announce("Free play -- next round soon", COLOR_INFO, 3)

	-- The round itself is over even though everyone is still in the arena.
	-- Clearing this hands every HUD back to the neutral state and stops the
	-- next round's messages reaching last round's players by accident.
	roundMembers = {}
	roundActive = false
	broadcast()
end

--=============================================================================
-- START
--=============================================================================

function RoundManager.start()
	-- We control every spawn ourselves so that players eliminated mid-round do
	-- not pop straight back into the arena.
	Players.CharacterAutoLoads = false

	-- The NPC needs to know who is still playing and who has the bomb, and this
	-- is the only file that knows both. Handing the two questions over as
	-- functions keeps BrainRot from having to require this module back.
	BrainRot.setContext(function()
		return alive
	end, RoundManager.getHolder)

	-- Every body that spawns goes into the "live player" collision group, so
	-- that exploded bodies (which go into the corpse group) cannot barge into
	-- players who are still running.
	local function watchCharacters(player: Player)
		player.CharacterAdded:Connect(function(character)
			Ragdoll.setCollisionGroup(character, Ragdoll.LIVE_GROUP)
			-- A speed boost must survive a respawn rather than silently
			-- vanishing, so whatever the player should currently have is
			-- re-applied to the new body.
			AbilityService.applyToCharacter(player)
			-- Likewise a live beacon event: someone spawning into Tiny Mode
			-- has to be shrunk too, or they get a free advantage.
			Modifiers.applyToCharacter(character)
		end)
		if player.Character then
			Ragdoll.setCollisionGroup(player.Character, Ragdoll.LIVE_GROUP)
			AbilityService.applyToCharacter(player)
			Modifiers.applyToCharacter(player.Character)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		watchCharacters(player)
		broadcast()
		Modifiers.resync()
		-- Anyone joining outside a live round gets a body right away so they
		-- are not stuck staring at nothing while they wait.
		if phase ~= "Playing" then
			task.defer(function()
				pcall(function()
					player:LoadCharacter()
				end)
			end)
		end
	end)

	-- Covers the rare case where somebody joined in the split second before the
	-- connection above was made, which would otherwise leave them bodyless.
	for _, existing in Players:GetPlayers() do
		watchCharacters(existing)
		if not existing.Character then
			task.defer(function()
				pcall(function()
					existing:LoadCharacter()
				end)
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		local index = indexOf(player)
		if index then
			table.remove(alive, index)
		end
		if holder == player then
			Bomb.detach()
			holder = nil
		end
	end)

	-- A slow repeat of the current state. Cheap insurance: if a client's HUD
	-- script starts a moment after we sent an update, it catches up within two
	-- seconds instead of sitting blank until the next phase change.
	task.spawn(function()
		while true do
			task.wait(2)
			broadcast()
		end
	end)

	task.spawn(function()
		while true do
			-- TEST MODE'S SANDBOX comes first and ignores the queue entirely.
			--
			-- It has to, and this was missed when rounds began taking their
			-- players from the queue: the sandbox sat behind the same "enough
			-- players queued" gate as a real round, so it waited forever for
			-- somebody to step on a pad that Test Mode does not even ask you to
			-- use. Test Mode has been quietly doing nothing ever since.
			if Config.TEST_MODE and Config.TEST_NO_BOMB then
				local sandboxOk, sandboxErr = pcall(runSandbox) -- never returns while TEST_MODE is on
				if not sandboxOk then
					warn("[Hot Potato] Sandbox stopped: " .. tostring(sandboxErr))
					task.wait(2)
				end
				continue
			end

			-- Only tear the arena down if there is genuinely nobody to play with.
			--
			-- This block used to run on EVERY pass of the loop, including the one
			-- straight after a round finished -- which shipped the whole
			-- free-play crowd back to the lobby and switched the pickups off a
			-- fraction of a second after the round end had set them up. That is
			-- why free play had no pickups, and why the winner was briefly seen
			-- in the lobby before reappearing in the arena.
			--
			-- With enough players still queued we now go straight on to the next
			-- countdown and the arena is simply left running.
			if #getParticipants() < minimumPlayers() then
				phase = "Waiting"
				holder = nil
				alive = {}
				roundMembers = {} -- no round, so no round-only audience
				roundActive = false
				-- Nobody to play with, so the free-for-all ends too and anybody
				-- still in the arena goes back to the lobby.
				for _, player in freePlay do
					if player.Parent == Players then
						clearGhost(player)
						returnToLobby(player)
					end
				end
				freePlay = {}
				duration = 0
				deadline = 0
				Bomb.detach()
				Pickups.setActive(false)
				AbilityService.clearAll()
				broadcast()

				while #getParticipants() < minimumPlayers() do
					task.wait(1)
				end
			end

			-- Wrapped so that an unexpected error in one round cannot kill the
			-- loop and leave the server permanently stuck with no game running.
			-- The error still shows up in the output for you to read.
			local ok, err = pcall(function()
				if runIntermission() then
					runRound()
				end
			end)

			if not ok then
				warn("[Hot Potato] Round ended early: " .. tostring(err))
				Bomb.detach()
				holder = nil
				task.wait(2)
			end
		end
	end)
end

return RoundManager
