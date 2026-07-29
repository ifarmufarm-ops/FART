--[[
	Hot Potato Bomb -- server entry point.

	This runs once when the server starts. It builds the arena, creates the
	bomb, and hands control to RoundManager, which then runs rounds forever.

	The interesting files are:
		RoundManager    all the rules
		Bomb            what the bomb looks and sounds like
		Ragdoll         the explosion, the flying body, and standing back up
		Arena           the map
		Pickups         the glowing things that spawn around the arena
		AbilityService  who is carrying what, and whether they may use it
		Modifiers       the beacon events that change the map for everyone
		Shared/Config   every number you might want to change
		Shared/Abilities  the catalogue of what can spawn as a pickup
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AbilityService = require(script.AbilityService)
local Arena = require(script.Arena)
local Bomb = require(script.Bomb)
local GhostArea = require(script.GhostArea)
local Lobby = require(script.Lobby)
local Modifiers = require(script.Modifiers)
local Queue = require(script.Queue)
local Ragdoll = require(script.Ragdoll)
local RoundManager = require(script.RoundManager)

Ragdoll.setupCollisionGroups()
Arena.build()
Lobby.build()
GhostArea.build() -- the glass platform knocked-out players watch from
Queue.build() -- the pad sits on the lobby's plinth, so build it after the lobby
Bomb.create()

-- AbilityService will not honour an ability request unless this says the player
-- is allowed to use one. Passing the check in from here keeps the two files
-- from having to require each other.
--
-- This used to be "are they alive in the round", which was right when the round
-- was the only place to be. It is not any more: somebody in the LOBBY is not
-- alive in a round, so every ability they tried to use would have been thrown
-- away silently -- the pickup spent, nothing happening, and the HUD looking
-- exactly as it does on success. That is the trap LOBBY_PLAN.md flagged, and
-- it is fixed here BEFORE the lobby practice range exists to fall into it.
--
-- Allowed: alive in a round, or in the lobby. Deliberately NOT allowed: a
-- player who has been blown up and is watching the rest of the round.
AbilityService.start(function(player: Player): boolean
	if RoundManager.isAlive(player) then
		return true
	end
	return not RoundManager.isInRound(player)
end)

-- Who is in the round: everybody who has stepped on the queue pad. Anyone else
-- stays in the lobby and is left entirely alone by the round.
RoundManager.setParticipantProvider(Queue.getQueued)

-- Where players go when their round finishes. Everyone who took part is moved
-- back here, winner included -- otherwise the winner is left alone in the arena
-- until enough people queue for another round, which may never happen.
RoundManager.setReturnToLobby(Lobby.sendToLobby)

-- Where you go when you are blown up, and how you come back.
RoundManager.setGhostHandlers(GhostArea.send, GhostArea.restore)

Queue.start()

-- Beacon events reach the round and nothing else. Tiny Mode and Reverse
-- Controls are scoped by this; Ice Shoes was already safe, because it freezes
-- whatever carries the floor tag and the lobby floor deliberately does not.
--
-- LOW GRAVITY IS STILL GLOBAL AND STILL LEAKS. workspace.Gravity is a single
-- property for the whole place, so it cannot be scoped -- it has to be rebuilt
-- as a per-character force. That is the remaining piece of stage 1d; see
-- LOBBY_PLAN.md.
--
-- The list is "everyone in the round", not "everyone still alive": a player who
-- has been blown up is still standing in the arena watching, and un-shrinking
-- them mid-round would look like a bug. Outside a round it is everyone, which
-- is what keeps Test Mode's sandbox working.
Modifiers.setParticipantProvider(RoundManager.getArenaPlayers)

-- Anybody in the lobby who loses their body gets it straight back. The one
-- exception is a player who is part of a round that is actually running: they
-- have been eliminated and are watching the finish, and pulling them back to
-- the lobby mid-round would take that away from them.
--
-- Test Mode's sandbox does its own respawning, so leave it alone entirely.
-- The test is "are you still part of the round", NOT "are you queued". Queueing
-- is sticky, so an eliminated player is still queued for the next round -- using
-- that as the test left anyone who pressed "back to the lobby" waiting for the
-- round to end before they got a body, which is exactly what the button exists
-- to avoid. RoundManager.isInRound goes false the moment they opt out.
Lobby.startRespawner(function(player)
	local phase = RoundManager.getPhase()
	if phase == "Sandbox" then
		return true -- Test Mode does its own respawning
	end
	-- During the countdown to the next round, everybody gets a body in the
	-- lobby -- including somebody who was blown up in the round before and is
	-- still queued. Without this they spend the whole 16 second wait bodyless,
	-- watching the spectator camera, which is the very thing the lobby exists
	-- to stop. The round start moves them to the arena a moment later anyway.
	if phase == "Intermission" then
		return false
	end
	-- A ghost who loses their body -- pressing Reset, most likely -- belongs
	-- back on the glass platform, not in the lobby. Put them there and tell the
	-- lobby to leave them alone.
	if GhostArea.isGhost(player) then
		GhostArea.send(player)
		return true
	end
	return RoundManager.isInRound(player)
end)

-- "Back to the lobby", pressed by a player who has been blown up.
--
-- Two separate things happen, and the order matters: RoundManager decides
-- whether they are allowed to go -- it refuses anyone still alive, so this can
-- never be used to dodge the bomb -- and only if it agrees do they also come
-- out of the queue. Pressing it means "I am done for now", so they will not be
-- pulled into the next round; they step back on the pad when they want in.
--
-- The wiring lives here rather than in either module because it is the only
-- place that knows about both.
Remotes.LeaveRound.OnServerEvent:Connect(function(player)
	if RoundManager.requestLeave(player) then
		Queue.setQueued(player, false)
		-- A ghost has a body already, so nothing would move them on its own --
		-- they have to be carried down and made solid again explicitly.
		GhostArea.restore(player)
		Lobby.sendToLobby(player)
	end
end)

RoundManager.start()

print("[Hot Potato] Server ready.")
