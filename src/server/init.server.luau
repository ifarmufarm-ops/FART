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

RoundManager.start()

print("[Hot Potato] Server ready.")
