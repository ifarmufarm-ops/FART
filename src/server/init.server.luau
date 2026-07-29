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

local AbilityService = require(script.AbilityService)
local Arena = require(script.Arena)
local Bomb = require(script.Bomb)
local Lobby = require(script.Lobby)
local Ragdoll = require(script.Ragdoll)
local RoundManager = require(script.RoundManager)

Ragdoll.setupCollisionGroups()
Arena.build()
Lobby.build()
Bomb.create()

-- AbilityService needs to know who is still in the round before it will honour
-- an ability request. Passing the check in from here keeps the two files from
-- having to require each other.
AbilityService.start(RoundManager.isAlive)

-- Who is in the round. STAGE 1a: nobody yet -- the queue pad arrives in the
-- next stage, and until it does the server sits in Waiting and everybody stays
-- in the lobby. Swapping this one function for Queue.getQueued() is the whole
-- of the change that makes rounds pick their players.
RoundManager.setParticipantProvider(function()
	return {}
end)

RoundManager.start()

print("[Hot Potato] Server ready.")
