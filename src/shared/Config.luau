--!strict
--[[
	Config -- every number worth tuning lives here.

	Change a value, hit save, and Rojo pushes it into Studio. Most of these you
	can safely fiddle with mid-playtest without touching any other file.
]]

local Config = {}

--=============================================================================
-- ROUND FLOW
--=============================================================================

-- How many players must be in the server before a round starts.
Config.MIN_PLAYERS = 2

-- Lets you playtest completely alone in Studio. With one player you'll get the
-- bomb, have nobody to pass it to, and explode -- which is exactly what you
-- want when checking the explosion looks right.
-- SET THIS TO FALSE BEFORE PUBLISHING.
Config.SOLO_TEST_MODE = false

-- Countdown before a round starts, in seconds. This is also the WINDOW TO JOIN:
-- anybody who steps on the queue pad before it runs out is in the round that
-- follows. Doubled from 8 to 16 after playtesting -- 8 seconds was not enough
-- time to notice a round was forming and get to the pad.
Config.INTERMISSION_SECONDS = 16

-- How long the winner is on screen before everybody -- winners and losers --
-- respawns in the arena to muck about until the next round starts.
Config.ROUND_OVER_SECONDS = 4

-- The pickups and abilities stay live from the moment a round ends right
-- through the countdown to the next one. That gap is deliberately a free-for-all
-- in the arena: everybody has a body, nobody has the bomb, and the pickups keep
-- coming. It is the main way a new player gets familiar with the abilities
-- without a round riding on it. The next round clears everything and starts
-- fresh, so nothing carries over.

--=============================================================================
-- THE GHOST AREA
--=============================================================================
-- Where you go when you are blown up, instead of watching from a drifting
-- camera. A glass-floored platform directly above the arena: you keep a body,
-- you are see-through, and you can walk about and watch the round finish
-- underneath you.

Config.GHOST_HEIGHT = 130 -- studs above the arena floor
Config.GHOST_SIZE = 80 -- width and depth of the glass platform
Config.GHOST_WALL_HEIGHT = 14 -- glass rail, so nobody wanders off the edge
Config.GHOST_SPAWN_COUNT = 8

-- How see-through a ghost is. 0 is solid, 1 is invisible. High enough to read
-- as "not really here", low enough that you can still see each other.
Config.GHOST_TRANSPARENCY = 0.65

-- THE PUNCHING BAG. A meme-faced thing standing in the middle of the ghost
-- platform that you hit to pass the time while waiting for the round to end.
-- It counts every punch it has taken.

Config.CLICKER_CLICK_DISTANCE = 26 -- how close you must be to hit it, in studs

-- How far the thump carries. Deliberately short: it should be audible to the
-- ghosts standing around it and to nobody in the arena 130 studs below.
Config.CLICKER_SOUND_RANGE = 55

-- PLACEHOLDER -- swap for a proper thump. Roblox ships no punch noise, so this
-- is a stand-in purely so the thing is testable today.
Config.CLICKER_SOUND = "rbxasset://sounds/switch3.wav"

-- How far it rocks back when hit, in degrees, and how long the recoil takes.
-- The return is deliberately slower than the hit, which is what makes it read
-- as being knocked back rather than just wobbling.
Config.CLICKER_RECOIL_ANGLE = 18
Config.CLICKER_RECOIL_TIME = 0.06
Config.CLICKER_RECOVER_TIME = 0.22

--=============================================================================
-- THE BOMB TIMER
--=============================================================================
-- The timer restarts every time the bomb is passed, but it gets shorter each
-- time: 15s -> 13s -> 11s -> 9s ... down to the floor below. That guarantees
-- every cycle ends instead of two fast players trading it forever.

Config.TIMER_START = 15 -- seconds the first holder of a cycle gets
Config.TIMER_DECAY_PER_PASS = 2 -- seconds removed from the timer on each pass
Config.TIMER_MINIMUM = 5 -- the timer never drops below this

-- THE FINAL DUEL. When only two players are left the timer keeps shrinking past
-- the floor above, down to this instead. That is what ends a one-on-one.
--
-- It has to be SHORTER than PASS_COOLDOWN (1s), because that is the whole
-- mechanism: eventually the holder's timer is shorter than the time they must
-- wait before they are allowed to pass at all, so the trade cannot continue and
-- somebody has to die. The duel speeds up until it breaks.
--
-- Raise it towards 1 for a longer, tenser endgame; lower it to end duels
-- sooner. At or above 1 the duel can run forever again.
Config.TIMER_MINIMUM_DUEL = 0.75

-- After someone explodes, does the timer go back up to TIMER_START for the
-- next cycle? True = each cycle starts fresh at 15s. False = it keeps
-- shrinking across the whole round, so late rounds are brutal.
Config.RESET_TIMER_AFTER_EXPLOSION = true

--=============================================================================
-- PASSING THE BOMB
--=============================================================================

-- HOLDING THE BOMB MAKES YOU FASTER. Multiplies your walking speed while you
-- have it, so a holder can realistically run somebody down instead of trudging
-- after them at exactly their speed. 1.35 is 21.6 studs/s against a normal 16.
--
-- It stacks with Sneakers, so a holder wearing them moves at 16 x 2 x 1.35 =
-- 43 studs/s -- terrifying, brief, and something you have to have earned.
Config.BOMB_HOLDER_SPEED = 1.35

-- How close the holder has to get to another player to pass it, in studs.
-- Two players standing chest-to-chest are about 4 studs apart.
Config.PASS_RADIUS = 5

-- After you receive the bomb, you cannot pass it on for this many seconds.
-- Stops the bomb ping-ponging between two players stuck next to each other.
Config.PASS_COOLDOWN = 1

-- How often the server checks for a pass. Smaller = more responsive, slightly
-- more work for the server. 0.05 is 20 checks per second, which feels instant.
Config.PASS_CHECK_INTERVAL = 0.05

-- ANTI-STALEMATE SWITCH. Now ON, because the stalemate was CONFIRMED in a
-- two-client playtest on 2026-07-29 -- two players standing next to each other
-- really do ping-pong the bomb forever.
--
-- The problem it solves: each pass resets the timer to TIMER_MINIMUM (5s),
-- which is longer than the 1s PASS_COOLDOWN, so a pair can trade indefinitely
-- and the round never ends.
--
-- With this on, whoever just gave you the bomb is not a valid target until you
-- have passed it to somebody else, which breaks the trade. Set it back to
-- false to feel the unfixed version again.
--
Config.BLOCK_INSTANT_PASS_BACK = true

-- The rule above is right for a crowd and WRONG for a one-on-one: with two
-- players left, the only person you could pass to is the one it excludes, so
-- the receiver would have no legal target at all and would be guaranteed to
-- explode. The round would end by decree rather than by play.
--
-- So it only applies while at least this many players are still alive. Below
-- that, the final duel is a real chase again -- and it is TIMER_MINIMUM_DUEL,
-- not this rule, that stops the last two stalling forever.
Config.PASS_BACK_MIN_PLAYERS = 3

--=============================================================================
-- THE EXPLOSION
--=============================================================================

-- How fast the eliminated player is flung, in studs per second. For scale, a
-- player runs at 16. 90 is a satisfying launch across the arena.
Config.LAUNCH_SPEED = 90

-- Shape of the launch. Higher vertical = more "punted into the sky",
-- higher horizontal = more "fired sideways across the map".
Config.LAUNCH_VERTICAL = 1.4
Config.LAUNCH_HORIZONTAL = 1

-- How much the body tumbles as it flies, in radians per second.
Config.LAUNCH_SPIN = 14

-- Purely visual radius of the explosion effect, in studs.
-- It does not push anyone else -- only the eliminated player is launched.
Config.EXPLOSION_RADIUS = 18

-- How long the ragdolled body lies on the ground before it disappears and the
-- player switches to spectator camera.
Config.CORPSE_LIFETIME = 4

--=============================================================================
-- THE ARENA
--=============================================================================

Config.ARENA_SIZE = 160 -- width and depth of the playable floor, in studs
Config.WALL_HEIGHT = 28 -- height of the perimeter walls
Config.FLOOR_Y = 2 -- height of the arena floor surface
Config.ARENA_CENTER = Vector3.new(0, Config.FLOOR_Y, 0)

-- SPAWN HEIGHT. Players are placed by their ROOT, which sits about 3 studs
-- above their feet -- not by their feet. Get this wrong and everyone starts the
-- round standing inside the floor, gets shoved out by physics over the next
-- second, and it reads as popping, jitter, or falling through the map.
--
-- 3.04 is measured, not assumed: an R15 character has HipHeight 2.0 and a
-- 2-stud root part, so the root centre sits 2.0 + 1.0 = 3.04 above the soles.
Config.SPAWN_ROOT_HEIGHT = 3.04

-- A little daylight under the feet so a character never starts a frame
-- intersecting the pad. They fall this far on spawn, which is imperceptible.
Config.SPAWN_CLEARANCE = 0.15

--=============================================================================
-- THE LOBBY
--=============================================================================
-- Where players stand when they are not in a round. Same place as the arena,
-- just a long way away -- no loading screen, no teleport, and you can watch the
-- arena in the distance if you walk to the edge.
--
-- IMPORTANT: the lobby floor deliberately does NOT carry Config.TAG_FLOOR.
-- That tag is exactly what Ice Shoes looks for, so tagging the lobby would
-- freeze it every time somebody in the arena grabbed the beacon. If the lobby
-- ever needs its own floor behaviour, give it its own tag.

-- Far enough from the arena (160 wide, centred on the origin) that nothing
-- happening in one can reach the other. Explosions launch players at 90
-- studs/s, so this is many times further than anyone can be thrown.
Config.LOBBY_CENTER = Vector3.new(0, 2, 600)

-- Went 110 -> 220 -> 148. At 110 the queue pad, the practice range and the
-- boards were close enough that their floating labels overlapped on screen from
-- most angles. 220 fixed that and was too far to walk. 148 is the middle.
Config.LOBBY_SIZE = 148 -- width and depth of the lobby floor, in studs
Config.LOBBY_WALL_HEIGHT = 22 -- perimeter walls, so nobody wanders into the void
Config.LOBBY_SPAWN_COUNT = 8 -- pads in the ring players appear on

-- How far IN from the lobby wall the ring of spawn pads sits, in studs.
--
-- This has to clear the practice range, which stands against one wall. At an
-- earlier value of 18 a spawn pad ended up 2 studs from the Fart Jump pedestal
-- -- inside its 4 stud collect radius -- so anybody who happened to spawn there
-- was handed a free ability the instant they appeared, and the pedestal spent
-- most of its life empty.
Config.LOBBY_SPAWN_INSET = 30

-- How often the lobby looks for somebody who has lost their body and puts them
-- back on their feet. The game hands out every body itself (see
-- Players.CharacterAutoLoads in RoundManager), so without this a player who
-- pressed Reset in the lobby would never come back.
Config.LOBBY_RESPAWN_CHECK = 1

-- THE PRACTICE RANGE. A row of abilities along one wall of the lobby that you
-- can pick up and use as much as you like while you wait. Abilities ONLY --
-- never beacons, because a beacon changes the map for everybody in the round
-- and somebody idly messing about in the lobby must not be able to do that.
Config.PRACTICE_RANGE_SPACING = 12 -- gap between pedestals, in studs
Config.PRACTICE_RESPAWN_DELAY = 2 -- how quickly one comes back after you take it

-- THE QUEUE PAD. Stepping onto it puts you in the next round; stepping onto it
-- again takes you back out. You have to step OFF and back ON to toggle, so
-- standing on it does not flicker you in and out.
--
-- Queueing is STICKY: once you are in, you stay in for round after round until
-- you step on the pad again. Nobody has to re-join between every game.
Config.QUEUE_PAD_RADIUS = 7 -- how close you must get, in studs
Config.QUEUE_CHECK_INTERVAL = 0.2 -- how often the pad looks for players

-- Colours for the pad: waiting for you, and you-are-in.
Config.QUEUE_COLOR_IDLE = Color3.fromRGB(126, 214, 255)
Config.QUEUE_COLOR_ACTIVE = Color3.fromRGB(120, 255, 150)

-- Height the spectator camera floats at, and how far out it orbits.
Config.SPECTATOR_HEIGHT = 90
Config.SPECTATOR_DISTANCE = 130
Config.SPECTATOR_ORBIT_SPEED = 0.08 -- radians per second

--=============================================================================
-- TEST MODE
--=============================================================================
-- A sandbox for trying things out without the game getting in the way.
--
-- Flip TEST_MODE to true, then STOP AND RESTART Play in Studio (Config is read
-- when the server starts, so a live edit alone will not take effect).
--
-- With it on:
--   * nobody is ever given the bomb
--   * nobody is ever eliminated, and the round never ends or resets
--   * a showcase range appears along one wall of the arena holding one of
--     every ability and every beacon, each respawning shortly after you take it
--
-- TURN THIS OFF BEFORE PUBLISHING, and before judging how the game feels.
Config.TEST_MODE = false

-- Sub-switches, only meaningful while TEST_MODE is on. Turn one off to test a
-- narrower slice -- e.g. set TEST_NO_BOMB to false with two players to play a
-- normal round while still having the showcase range available.
-- Setting TEST_NO_BOMB to false with TEST_MODE on is the beacon-testing setup:
-- a normal round with elimination, plus the showcase range so you can grab any
-- beacon on demand instead of waiting for a random spawn.
Config.TEST_NO_BOMB = true
Config.TEST_SHOW_RANGE = true

-- How long a showcase pickup takes to come back after you grab it.
Config.TEST_RESPAWN_DELAY = 3

-- Gap between the pedestals on the range, in studs.
Config.TEST_RANGE_SPACING = 12

--=============================================================================
-- MAP TAGS  (how the code finds things in the map)
--=============================================================================
-- These are Roblox "tags", set in Studio's Tag Editor (View -> Tag Editor).
-- The code never looks for parts by NAME -- it looks for these tags. That is
-- what makes a hand-built map a drop-in replacement later: build whatever you
-- like, tick these two tags on the right parts, and everything keeps working
-- with no code changes.
--
--   FLOOR       -- every surface players walk on. Ice Shoes makes exactly
--                  these slippery, and tints them blue.
--   PICKUP_ZONE -- invisible box(es) marking where pickups may appear. Their
--                  volume is the spawn area; the code rays downwards inside it
--                  to find the ground. Use several for a multi-level map.
--
-- If no PICKUP_ZONE exists anywhere, pickup spawning falls back to a flat
-- square of ARENA_SIZE around ARENA_CENTER.
Config.TAG_FLOOR = "HotPotatoFloor"
Config.TAG_PICKUP_ZONE = "HotPotatoPickupZone"

--=============================================================================
-- PICKUPS
--=============================================================================
-- Glowing objects that appear around the arena. Walk into one to collect it.

-- How often a new one appears. Was 8, then 5.3; now a further third quicker,
-- because abilities are what give the game its pace and there were not enough
-- of them going around.
Config.PICKUP_SPAWN_INTERVAL = 4

-- How many sit on the floor at once. This scales with how many people are
-- still in the round, because a flat number cannot suit both ends of a 4-to-10
-- player game: four pickups feels generous with 4 players and starved with 10.
--
-- Effective cap = players x PER_PLAYER, held between MIN and MAX.
--   4 players  -> 3 on the floor
--   10 players -> 8 on the floor
-- All three raised by about a third for the same reason as the interval above:
-- more abilities in play, at every player count rather than only a full lobby.
--   4 players  -> 4 on the floor (was 3)
--   10 players -> 11 on the floor (was 8)
Config.PICKUP_PER_PLAYER = 1.07
Config.PICKUP_MIN_ACTIVE = 4
Config.PICKUP_MAX_ACTIVE = 11

-- How close you must get to collect one, in studs.
Config.PICKUP_COLLECT_RADIUS = 4

-- CAN YOU SEE PICKUP ICONS THROUGH WALLS?
--
-- True is how it has always been: the little emoji floats in front of everything,
-- so you can see what is available across the whole map. False hides it behind
-- pillars and crates, so you have to look round things to find them -- which
-- makes the map matter more and rewards knowing it.
--
-- This is the STARTING value. It can be flipped mid-game without restarting:
--
--     require(game.ServerScriptService.Server.Pickups).iconsThroughWalls(false)
--
-- so you can feel the difference immediately. See BALANCE.md.
Config.PICKUP_ICONS_THROUGH_WALLS = true

-- How high above the floor a pickup hovers.
Config.PICKUP_FLOAT_HEIGHT = 3

-- A pickup nobody grabs disappears after this long, so the map does not slowly
-- fill up with untouched ones in a corner.
Config.PICKUP_LIFETIME = 30

--=============================================================================
-- ABILITIES
--=============================================================================
-- You carry ONE ability at a time, with a few uses in it. Picking up a new one
-- REPLACES what you had and resets the count -- uses do not stack up, so
-- hoarding two of the same thing gains you nothing.

-- How many times a single pickup can be used before it runs out.
Config.ABILITY_USES = 3

-- Roblox's normal walking speed and jump power, for reference. Change these
-- and the whole game gets faster or floatier.
Config.BASE_WALK_SPEED = 16
Config.BASE_JUMP_POWER = 50

-- DASH: how hard you get flung forwards, and for how long. For scale, running
-- is 16. Speed x duration is roughly how far you travel, so 85 x 0.18 is about
-- 15 studs -- a decent lunge, not a teleport.
--
-- The duration matters: Roblox's character controller constantly pulls your
-- speed back down to walking pace, so a single instant shove gets eaten almost
-- immediately. Holding the speed for a fraction of a second is what makes the
-- dash actually cover ground.
Config.DASH_SPEED = 85
Config.DASH_DURATION = 0.18

-- THE GLIDE. Without this the dash stops dead: Roblox's character controller
-- yanks you back to walking pace the instant the burst ends, which feels like
-- hitting a wall and makes chaining two dashes together impossible.
--
-- So the dash hands over to a short slide instead, as though the floor were
-- briefly icy. You keep moving, you can turn, and a second dash launched during
-- the slide carries straight on from the first.
Config.DASH_GLIDE_DURATION = 0.3

-- How fast the slide starts, as a fraction of the dash itself. 1 would carry on
-- at full dash speed (no slowing at all); 0 would remove the glide entirely.
Config.DASH_GLIDE_STRENGTH = 0.55

-- Dashing leaves a streak of smoke hanging in the air behind you rather than a
-- solid ribbon. This is how thickly it pours out -- particles per second, for
-- the length of the dash only. At 220 a 0.18s dash lays down about 40 puffs.
Config.DASH_SMOKE_RATE = 220

-- The trail keeps pouring until you land, then for this much longer. Stopping
-- it at the end of the burst left the streak hanging in mid-air while you flew
-- on without it.
Config.DASH_TRAIL_LINGER = 0.3

-- Safety cap, in case somebody dashes off the map and never lands.
Config.DASH_TRAIL_MAX = 3

-- FART JUMP: the upward kick of the second jump.
--
-- Raised from 45 to 68 and then to 75 after playtesting. It used to sit just
-- under a normal jump (50) so it read as a small boost, and that made it the
-- dullest of the three abilities. At 75 it is half again as strong as a normal
-- jump, so using it clearly launches you somewhere you could not otherwise get.
Config.FART_JUMP_POWER = 75

-- You cannot fart jump until you are near the top of your first jump or
-- already falling. This is the difference between the ability working and
-- appearing broken: pressing jump again immediately after take-off, while
-- still shooting upwards at ~45 studs/s, would set your speed to 45 -- no
-- visible change at all, and the charge gone.
--
-- Measured in upward studs/second. Anything at or below this counts as "at the
-- top of the arc". It is deliberately a speed and not a timer, so it still
-- behaves correctly when Low Gravity is active and jumps last much longer.
Config.FART_JUMP_APEX_SPEED = 15

-- How many smoke puffs the fart jump coughs out. More is thicker and funnier,
-- but costs a little more to render on weaker phones.
Config.FART_PUFF_PARTICLES = 24

-- SNEAKERS: how much faster, and for how long.
--
-- Rebalanced from "1.5x for 8 seconds, three times" to "2x for 5 seconds,
-- twice": a much bigger burst, but far less of it. It is now an escape you
-- spend at the right moment rather than a general-purpose speed boost.
--
-- 2x is 32 studs/s against the Brain Rot NPC's 18, so it remains a reliable way
-- to get clear of it -- just for a shorter window.
Config.SNEAKERS_MULTIPLIER = 2
Config.SNEAKERS_DURATION = 5

-- How many uses Sneakers gets, overriding the usual ABILITY_USES. See the
-- `uses` field in Abilities.luau for how per-ability counts work.
Config.SNEAKERS_USES = 2

-- Minimum gap between ability requests from one player. Stops a modified
-- client spamming the server with use-attempts.
Config.ABILITY_REQUEST_COOLDOWN = 0.25

--=============================================================================
-- BEACON EVENTS  (map-wide modifiers)
--=============================================================================
-- Picking up a beacon changes a rule of the map for EVERYONE, not just you.

-- Can several run at once? You chose yes -- Ice + Low Gravity + Tiny can all be
-- live together. If that turns out to be uncontrollable in a playtest, set this
-- to false and a new beacon will cancel whatever is already running instead.
Config.MODIFIERS_STACK = true

-- ICE SHOES: the floor loses its grip and everybody slides.
--
-- Friction runs 0 (ice) to 1 (rubber); normal ground is about 0.3.
--
-- IMPORTANT, because it makes this number behave oddly: Roblox works out the
-- grip between two touching surfaces by BLENDING them, weighted by each one's
-- FrictionWeight. So the player's own legs (0.3, weight 1) drag the result
-- back up no matter how low the floor goes:
--
--     effective = (floorFriction x floorWeight + 0.3 x 1) / (floorWeight + 1)
--
-- That is why the weight had to move too. At the old 0.02 / weight 10 the real
-- grip was 0.045 -- less than half as slippery as the 0.02 suggested.
--
--     old: (0.02 x 10  + 0.3) / 11  = 0.045
--     new: (0.006 x 100 + 0.3) / 101 = 0.009   <- 5x more slippery
--
-- 100 is the highest weight Roblox accepts. Even a friction of 0 only reaches
-- 0.003, so there is roughly 3x more headroom left if 5x is still too grippy.
Config.ICE_DURATION = 20
Config.ICE_FRICTION = 0.006
Config.ICE_FRICTION_WEIGHT = 100
Config.ICE_TINT = Color3.fromRGB(150, 212, 255)

-- LOW GRAVITY: Roblox's normal gravity is 196.2. Lower means floatier jumps
-- and much longer hang time -- and much bigger explosions.
--
-- HOW THIS WORKS, because it is not what you would expect: Roblox has ONE
-- gravity setting for the whole game world. There is no way to make it lower in
-- the arena than in the lobby. Turning it down would make everybody float,
-- including people who are not even playing.
--
-- So the game no longer touches it. Instead each player in the round gets a
-- gentle upward push, sized to their own weight, which cancels out part of what
-- gravity is doing to them. The feeling is the same; it just only happens to
-- the people it should. Change LOW_GRAVITY_VALUE and the push is recalculated
-- from it, so this still behaves like a gravity dial.
Config.LOW_GRAVITY_DURATION = 20
Config.LOW_GRAVITY_VALUE = 60
Config.NORMAL_GRAVITY = 196.2

-- How often the upward push is recalculated while Low Gravity is running.
-- It has to be redone periodically because a player's weight changes -- Tiny
-- Mode shrinks them -- and because anyone who respawns needs a fresh one.
Config.LOW_GRAVITY_REFRESH = 0.5

-- TINY MODE: everyone shrinks. 0.6 is 60% of normal height.
Config.TINY_DURATION = 20
Config.TINY_SCALE = 0.6

-- REVERSE CONTROLS: movement inverted for everyone EXCEPT whoever grabbed the
-- beacon. Deliberately short and deliberately rare.
Config.REVERSE_DURATION = 5

-- BRAIN ROT ALERT: a meme-faced NPC turns up and hunts everyone who is NOT
-- holding the bomb. Catching someone knocks them down for a moment -- it is a
-- way of herding people towards the bomb, not a second way of dying.
Config.BRAINROT_DURATION = 25

-- Slightly quicker than a running player (16), so it closes in over time and
-- you cannot simply outrun it forever. Sneakers (24) still gets you clear.
Config.BRAINROT_WALK_SPEED = 18

-- How close it has to get to knock you over, and how long you stay down.
Config.BRAINROT_CATCH_RADIUS = 5
Config.BRAINROT_KNOCKDOWN = 2

-- How hard the tackle shoves you, in studs per second. Without a push a limp
-- body just stands there -- this is what actually knocks you off your feet.
-- Much gentler than the explosion launch (90).
Config.BRAINROT_SHOVE = 30

-- After a catch it has to wait this long before it can grab anyone again, so
-- it cannot pin one player down over and over.
Config.BRAINROT_CATCH_COOLDOWN = 3

-- How often it re-picks a victim, and how often it re-plans its route. Lower
-- is more responsive and more work for the server.
Config.BRAINROT_RETARGET_INTERVAL = 0.5
Config.BRAINROT_REPATH_INTERVAL = 0.8

-- PLACEHOLDER -- swap for your own meme face decal.
-- This one is Roblox's built-in smiley, which ships with every client, so the
-- NPC has a face today without you having to upload anything.
Config.BRAINROT_FACE = "rbxasset://textures/face.png"

--=============================================================================
-- MOVEMENT GUARD  (the one thing a cheat can actually do)
--=============================================================================
-- Every rule in this game is decided on the server and cannot be lied to --
-- who has the bomb, whether a pass happened, whether an ability may be used.
-- Movement is the single exception: Roblox gives each player's own machine
-- control of their character, which is what makes the dash feel instant, and
-- the price is that a modified client can move itself however it likes.
--
-- So the server watches where people actually are and flags anybody covering
-- ground faster than the game allows.

Config.MOVEMENT_GUARD_ENABLED = true

-- SNAPPING BACK IS OFF TO BEGIN WITH, deliberately.
--
-- With this false the guard only watches and writes to the output. Play a few
-- real rounds like that first and see whether anything honest trips it -- a
-- laggy player being yanked backwards is a far worse bug than a cheater getting
-- away with it for another week. Turn it on once the log stays quiet.
Config.MOVEMENT_CORRECT = false
Config.MOVEMENT_LOG = true

-- How often each player's position is checked. Every quarter second is plenty:
-- a cheater has to keep it up to gain anything, and checking more often mostly
-- measures network jitter.
Config.MOVEMENT_CHECK_INTERVAL = 0.25

-- How much faster than legal is still forgiven, and a flat allowance on top.
-- Both exist for honest reasons -- running downhill, being shoved by another
-- player, and lag arriving late then catching up all at once.
Config.MOVEMENT_TOLERANCE = 1.6
Config.MOVEMENT_MARGIN = 10

-- Ground covered in one check that is a teleport rather than running. A dash at
-- 85 studs/s covers about 21 in a quarter second, and an explosion launch about
-- the same, so this is comfortably clear of anything legitimate.
Config.MOVEMENT_TELEPORT_STUDS = 60

-- How many flags before acting, and how long a flag stays on the record. One
-- odd reading in a lag spike should not sit there waiting for two more.
Config.MOVEMENT_STRIKES = 3
Config.MOVEMENT_STRIKE_WINDOW = 10

-- When the game itself flings somebody -- a dash, an explosion, the NPC's
-- tackle -- it tells the guard how fast they are about to travel. This multiplies
-- that figure, because a launch bounces and a dash slides, so the real peak is
-- a little above the number the game asked for.
Config.MOVEMENT_GRANT_HEADROOM = 1.6

-- HOW LONG A DASH'S MOMENTUM IS FORGIVEN FOR.
--
-- A dash does not just end. Jump straight after one and you are in the air with
-- no friction at all, keeping the full 85 studs/s until you land -- and Low
-- Gravity makes that hang time roughly two and a half times longer. Land on Ice
-- Shoes and you keep most of it again while you slide.
--
-- So a dash buys the full dash speed for this long, not the slower slide speed
-- for a moment. Anything less and a player chaining a dash into a jump onto ice
-- -- ordinary, skilful play -- gets flagged as a cheat.
--
-- The trade: somebody with a dash charge could travel fast for this long
-- without being flagged. That is deliberate. Sustained speed is not the
-- dangerous cheat in this game -- you still have to touch somebody to pass the
-- bomb, and the holder is faster than everyone anyway. The cheat that actually
-- wins games is appearing next to someone instantly, and that is caught by
-- MOVEMENT_TELEPORT_STUDS regardless of any permission.
Config.MOVEMENT_MOMENTUM_SECONDS = 6

--=============================================================================
-- STATS AND LEADERBOARDS
--=============================================================================
-- What the game counts, and what it shows for it. The catalogue of statistics
-- itself -- their names, and which boards get a daily/weekly/monthly version --
-- lives in src/shared/Stats.luau. See STATS_PLAN.md.

Config.STATS_ENABLED = true

-- Prints every single increment to the output. Useful while checking that
-- something is counted where you think it is; very noisy otherwise.
Config.STATS_DEBUG_LOG = false

-- Do abilities used in the LOBBY count towards "Ability king"?
--
-- Off, and it matters: the practice range hands out an ability every couple of
-- seconds forever, so counting them would let anybody top that board by
-- standing in the lobby and never playing a round.
Config.COUNT_PRACTICE_ABILITIES = false

-- Which statistics appear in Roblox's own player list. Keep it to two or three
-- -- more than that is unreadable on a phone, and all five show properly on the
-- boards in the lobby anyway. Names must match ids in Stats.luau.
Config.LEADERSTATS_COLUMNS = { "SurviveSeconds", "Passes" }

-- How often the player list is repainted. A punch counter does not need to be
-- frame-accurate, and a slow tick turns a burst of clicks into one update.
Config.STATS_REFRESH_SECONDS = 1

-- Least time between two punches that both count, in seconds. Without this an
-- auto-clicker owns the punch board outright.
Config.CLICKER_MIN_PUNCH_INTERVAL = 0.15

--=============================================================================
-- SAVING THE STATS
--=============================================================================
-- This is the first thing in the project that can lose something a player
-- earned and cannot get back. Everything else here, if it breaks, produces a
-- funny explosion.
--
-- Studio ALWAYS uses a separate save file with "_studio" on the end of its name,
-- so playtesting can never touch a real player's history. That means you can
-- test saving properly without risking anything -- but Studio has to be allowed
-- to reach the service at all first:
--
--     Game Settings -> Security -> Enable Studio Access to API Services
--
-- With that off, the game runs perfectly and simply does not save, and says so
-- once in the output rather than filling it with errors.

Config.STATS_SAVE_ENABLED = true

-- The name of the save file. The version number is part of it deliberately: if
-- the shape of what we store ever has to change, bumping this starts clean
-- rather than trying to repair half-old data.
Config.STATS_STORE_NAME = "HotPotatoStats_v1"

-- How often each player's progress is written, in seconds. Nothing is written
-- per punch or per pass -- those add up in memory and go out together. Each
-- player's turn is staggered so ten of them do not all write in the same second.
Config.STATS_FLUSH_SECONDS = 60

-- How many times to retry a failed load, and the first gap between tries (it
-- doubles each time: 1, 2, 4, 8). Getting this wrong is the worst thing that can
-- happen here, so it tries hard before giving up.
Config.STATS_LOAD_ATTEMPTS = 4
Config.STATS_RETRY_BASE = 1

-- How long the server waits on its way down for everybody's progress to finish
-- saving. Without this, shutting down loses up to a whole flush interval, and
-- players see their numbers go backwards -- the most trust-destroying thing a
-- leaderboard can do.
Config.STATS_SHUTDOWN_WAIT = 25

--=============================================================================
-- THINGS FOR SALE
--=============================================================================
-- OFF, and it must stay off until the products actually exist. See the notes at
-- the top of src/shared/Products.luau -- you create each one in the Creator
-- Dashboard, paste its id in, and then turn this on.
--
-- Everything for sale is cosmetic. Nothing bought changes who wins a round,
-- deliberately: the game keeps leaderboards for surviving, passing and abilities,
-- and anything purchasable that affected those would turn them into a measure of
-- spending rather than skill.
Config.PRODUCTS_ENABLED = false

-- THE SHOP. A row of pedestals along one lobby wall, one per colour. Walk onto
-- one to buy it, or to wear it if you already own it. See STORE.md.
Config.SHOP_SPACING = 14 -- gap between pedestals, in studs
Config.SHOP_PAD_RADIUS = 5 -- how close you must get, in studs
Config.SHOP_CHECK_INTERVAL = 0.2 -- how often the pedestals look for players

-- Least time between two purchase prompts for the same player, in seconds.
-- Roblox's own window takes a moment to appear, and without this walking across
-- two pedestals would stack prompts on top of each other.
Config.SHOP_PROMPT_COOLDOWN = 2

--=============================================================================
-- THE BOARDS IN THE LOBBY
--=============================================================================
-- Each board is a flat part with the text drawn onto one of its faces. The code
-- does NOT build them at fixed positions and hope -- it goes looking for any
-- part wearing the tag below, which is the same trick that makes the arena floor
-- and the pickup zones swappable.
--
-- TO REPLACE THESE WITH YOUR OWN SIGNS:
--   1. Build a sign however you like -- a flat part, or a model with a flat front
--   2. Select it, open View -> Tag Editor, and add the tag named below
--   3. Add an Attribute called StatId, set to one of: SurviveSeconds, Passes,
--      AbilityUses, Punches, RobuxSpent
--   4. Optionally add an Attribute called Period: AllTime, Daily, Weekly or
--      Monthly. Left out, RobuxSpent cycles through all four and everything else
--      shows all-time
--   5. Optionally add an Attribute called Face if the text should be on a
--      different side: Front, Back, Left, Right, Top or Bottom
--
-- As soon as ANYTHING carries that tag, the code stops generating its own
-- placeholder slabs and uses yours instead. Nothing to delete twice.
Config.TAG_SCOREBOARD = "HotPotatoScoreboard"

Config.SCOREBOARD_ENABLED = true
Config.SCOREBOARD_ROWS = 10 -- how many names each board lists

-- How often one board is refreshed. Boards take turns rather than all
-- refreshing together: reading a sorted board is a rationed request, and eight
-- of them in the same instant can exceed what Roblox allows in one go.
Config.SCOREBOARD_REFRESH_SECONDS = 20

-- How long the Robux board shows each of its four periods before moving on.
-- Cycling comes out of memory, so it costs nothing.
Config.SCOREBOARD_CYCLE_SECONDS = 12

-- The placeholder slabs, if you have not tagged your own. Sizes in studs.
Config.SCOREBOARD_WIDTH = 16
Config.SCOREBOARD_HEIGHT = 13
Config.SCOREBOARD_SPACING = 19

--=============================================================================
-- SOUNDS
--=============================================================================
-- These "rbxasset://" paths are built into every Roblox client, so they always
-- work with no uploading. Swap in your own "rbxassetid://1234567" any time.

Config.SOUND_BEEP = "rbxasset://sounds/electronicpingshort.wav"
Config.SOUND_PASS = "rbxasset://sounds/switch3.wav"
Config.SOUND_PICKUP = "rbxasset://sounds/electronicpingshort.wav"

-- PLACEHOLDERS -- swap these for your own uploaded sounds.
-- Roblox ships no fart noises, so these are stand-ins purely so the abilities
-- are testable today. Upload your own and paste the id as "rbxassetid://1234".
Config.SOUND_DASH = "rbxasset://sounds/action_get_up.mp3" -- wants: long fart
Config.SOUND_FART_JUMP = "rbxasset://sounds/action_jump.mp3" -- wants: short fart

--=============================================================================
-- PARTICLE TEXTURES
--=============================================================================
-- Roblox's own smoke texture, which ships with every client. A soft circle
-- with faded edges, which is exactly what smoke wants -- the puffs overlap
-- into a cloud rather than reading as separate dots.
Config.PARTICLE_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- The explosion sound is built into Roblox's Explosion effect, so there is
-- nothing to configure for it here.

return Config
