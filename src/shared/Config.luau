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

-- Countdown shown between rounds, in seconds.
Config.INTERMISSION_SECONDS = 8

-- How long the winner gets to celebrate before the next intermission.
Config.ROUND_OVER_SECONDS = 6

--=============================================================================
-- THE BOMB TIMER
--=============================================================================
-- The timer restarts every time the bomb is passed, but it gets shorter each
-- time: 15s -> 13s -> 11s -> 9s ... down to the floor below. That guarantees
-- every cycle ends instead of two fast players trading it forever.

Config.TIMER_START = 15 -- seconds the first holder of a cycle gets
Config.TIMER_DECAY_PER_PASS = 2 -- seconds removed from the timer on each pass
Config.TIMER_MINIMUM = 5 -- the timer never drops below this

-- After someone explodes, does the timer go back up to TIMER_START for the
-- next cycle? True = each cycle starts fresh at 15s. False = it keeps
-- shrinking across the whole round, so late rounds are brutal.
Config.RESET_TIMER_AFTER_EXPLOSION = true

--=============================================================================
-- PASSING THE BOMB
--=============================================================================

-- How close the holder has to get to another player to pass it, in studs.
-- Two players standing chest-to-chest are about 4 studs apart.
Config.PASS_RADIUS = 5

-- After you receive the bomb, you cannot pass it on for this many seconds.
-- Stops the bomb ping-ponging between two players stuck next to each other.
Config.PASS_COOLDOWN = 1

-- How often the server checks for a pass. Smaller = more responsive, slightly
-- more work for the server. 0.05 is 20 checks per second, which feels instant.
Config.PASS_CHECK_INTERVAL = 0.05

-- ANTI-STALEMATE SWITCH. Off by default, because you asked for the plain
-- 1-second cooldown. Leave it off first and see how it plays.
--
-- The problem it solves: two players who just stand next to each other can
-- trade the bomb back and forth every second forever, because each pass resets
-- the timer to TIMER_MINIMUM (5s) which is longer than the 1s cooldown. The
-- round then never ends.
--
-- Turning this on blocks the player who just gave you the bomb from being a
-- valid target until you have passed it to somebody else, which kills the
-- trade. Flip it to true if you see players abusing this in a playtest.
Config.BLOCK_INSTANT_PASS_BACK = false

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

-- How often a new one appears. Was 8; now 50% more often.
Config.PICKUP_SPAWN_INTERVAL = 5.3

-- How many sit on the floor at once. This scales with how many people are
-- still in the round, because a flat number cannot suit both ends of a 4-to-10
-- player game: four pickups feels generous with 4 players and starved with 10.
--
-- Effective cap = players x PER_PLAYER, held between MIN and MAX.
--   4 players  -> 3 on the floor
--   10 players -> 8 on the floor
Config.PICKUP_PER_PLAYER = 0.8
Config.PICKUP_MIN_ACTIVE = 3
Config.PICKUP_MAX_ACTIVE = 8

-- How close you must get to collect one, in studs.
Config.PICKUP_COLLECT_RADIUS = 4

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

-- Dashing leaves a streak of smoke hanging in the air behind you rather than a
-- solid ribbon. This is how thickly it pours out -- particles per second, for
-- the length of the dash only. At 220 a 0.18s dash lays down about 40 puffs.
Config.DASH_SMOKE_RATE = 220

-- FART JUMP: the upward kick of the second jump. Slightly under a normal jump
-- so it reads as a "boost" rather than a full second launch.
Config.FART_JUMP_POWER = 45

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
Config.SNEAKERS_MULTIPLIER = 1.5
Config.SNEAKERS_DURATION = 8

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
Config.LOW_GRAVITY_DURATION = 20
Config.LOW_GRAVITY_VALUE = 60
Config.NORMAL_GRAVITY = 196.2

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
