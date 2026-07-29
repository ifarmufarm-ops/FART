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
local Lobby = require(script.Lobby)
local Queue = require(script.Queue)
local Ragdoll = require(script.Ragdoll)
local RoundManager = require(script.RoundManager)

Ragdoll.setupCollisionGroups()
Arena.build()
Lobby.build()
Queue.build() -- the pad sits on the lobby's plinth, so build it after the lobby
Bomb.create()

-- AbilityService needs to know who is still in the round before it will honour
-- an ability request. Passing the check in from here keeps the two files from
-- having to require each other.
AbilityService.start(RoundManager.isAlive)

-- Who is in the round: everybody who has stepped on the queue pad. Anyone else
-- stays in the lobby and is left entirely alone by the round.
RoundManager.setParticipantProvider(Queue.getQueued)
Queue.start()

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
	if RoundManager.getPhase() == "Sandbox" then
		return true -- Test Mode does its own respawning
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
	end
end)

RoundManager.start()

print("[Hot Potato] Server ready.")
