# Hot Potato Bomb

A round-based Roblox party game. One player gets a bomb, has a few seconds to
touch someone else and pass it on, and explodes if they run out of time. Last
player standing wins.

## Running it

Start the sync server from this folder:

```bash
rojo serve
```

Then open the place in Roblox Studio, open the Rojo plugin, and click **Connect**.
Every file you save from here on appears in Studio straight away.

One catch worth knowing: Rojo only reads `default.project.json` when the server
**starts**. If you ever change that file, stop `rojo serve` and start it again,
or your changes will silently not appear.

To build a standalone place file instead:

```bash
rojo build -o "Test1.rbxlx"
```

## Testing

The game currently sits in **playtest dress**: `TEST_MODE` and `SOLO_TEST_MODE`
are both `false` and `TIMER_START` is back to its real 15 seconds. A round needs
two players and plays exactly as a real one would.

To test actual passing, use two characters. In Studio open the **Test** tab ->
**Clients and Servers** -> set players to 2 and click **Start**.

### Playing alone

Set `Config.SOLO_TEST_MODE = true` to let a round start with a single player.
Press Play by yourself and you will get the bomb, have nobody to pass it to, and
blow up -- the quickest way to check the explosion looks right.

**Set it back to `false` before you publish**, or single players will be blown
up on an endless loop with no game around it.

Note that `TEST_MODE` overrides it: while `TEST_MODE` is `true` nobody is ever
given the bomb, so the two switches do not combine.

## Seeing the map in Studio

The arena is built by code every time the server starts, which is why Edit mode
shows an empty Workspace even though everything works when you press Play.

To drop a real copy into Edit mode so you can look at it, open the command bar
(**View → Command Bar**) and paste:

```bash
require(game.ServerScriptService.Server.Arena).preview()
```

To remove it again:

```bash
require(game.ServerScriptService.Server.Arena).clearPreview()
```

The preview is marked `Archivable = false`, so Roblox will never save or publish
it with the place — you can leave it lying around safely. Pressing Play replaces
it with a freshly built one, so it can never drift out of date with `Config`.

## Test Mode

A sandbox for trying things out without the game getting in the way. In
`Config.luau`:

```lua
Config.TEST_MODE = true
```

Then **stop and restart Play** — Config is read when the server starts, so a
live edit alone will not take effect.

With it on: nobody gets the bomb, nobody is eliminated, the round never resets,
and a **test range** appears along one wall of the arena holding one of every
ability and beacon, each respawning a few seconds after you take it.

Set `TEST_NO_BOMB = false` to play a normal round with the range still there.

**Turn it off before judging how the game feels, and before publishing.**

## Pickups

Glowing objects appear around the arena. There are two kinds, both defined in
`src/shared/Abilities.luau` — add an entry there to add a new one.

**Abilities** are yours alone. You carry one at a time with three uses in it;
picking up another replaces it rather than stacking.

| | What it does | How to use it |
|---|---|---|
| Dash | Fires you forwards ~17 studs | Shift / gamepad X / on-screen button |
| Fart Jump | An extra jump | Jump again at the top of your arc |
| Sneakers | 1.5x speed for 8 seconds | Shift / gamepad X / on-screen button |

**Beacons** go off the moment you touch them and change the map for *everyone*.
They stack — several can run at once (`Config.MODIFIERS_STACK`).

| | What it does |
|---|---|
| Ice Shoes | The floor turns to ice and everyone slides |
| Low Gravity | Gravity drops, jumps go floaty, explosions go further |
| Tiny Mode | Everyone shrinks to 60% |
| Reverse Controls | Movement inverted for everyone **except** whoever grabbed it, 5s |
| Brain Rot Alert | An NPC hunts everyone **except** the bomb holder, knocking them down |

## Building your own map

The code finds map features by **tag**, never by name, so a hand-built map is a
drop-in replacement. Set these in Studio's **View → Tag Editor**:

- `HotPotatoFloor` — every walkable surface. Ice Shoes freezes exactly these.
- `HotPotatoPickupZone` — invisible box(es) marking where pickups may appear.
  Use several to cover separate floors of a multi-level map.

You would also need to name the model `Arena`, add SpawnLocations, and update
`ARENA_SIZE` / `FLOOR_Y` / `ARENA_CENTER` in Config to match.

## Where things live

| File | What it does |
|---|---|
| `src/shared/Config.luau` | **Every number worth tuning.** Start here. |
| `src/shared/Abilities.luau` | The catalogue of every pickup and how often it spawns |
| `src/shared/Remotes.luau` | The channels the server uses to update screens |
| `src/server/RoundManager.luau` | All the rules: timers, passing, elimination |
| `src/server/Bomb.luau` | What the bomb looks and sounds like |
| `src/server/Ragdoll.luau` | The explosion, the flying body, and standing back up |
| `src/server/Arena.luau` | Builds the map in code when the server starts |
| `src/server/Pickups.luau` | Spawning and collecting the glowing things |
| `src/server/AbilityService.luau` | Who is carrying what, and whether they may use it |
| `src/server/Modifiers.luau` | The beacon events that change the map |
| `src/server/BrainRot.luau` | The hunting NPC |
| `src/server/TestRange.luau` | The Test Mode showcase row |
| `src/client/init.client.luau` | The heads-up display and spectator camera |
| `src/client/AbilityInput.luau` | The ability button, on all three platforms |
| `src/client/ScreenEffects.luau` | Beacon visuals and the reverse-controls override |

## How a round works

```
Waiting        not enough players yet
Intermission   8 second countdown, everyone gets a fresh character
Playing        the bomb cycles until one player is left
RoundOver      winner shown for 6 seconds, then back to Intermission
```

Inside **Playing**:

1. A random player gets the bomb and a 15 second timer.
2. Getting within 5 studs of another player passes it to them automatically.
   You cannot pass it on for 1 second after receiving it.
3. Every pass restarts the timer **shorter than before** -- 15s, 13s, 11s, 9s,
   7s, then a floor of 5s. This stops two fast players circling forever.
4. If the timer hits zero, the holder is ragdolled, launched across the map and
   knocked out of the round. The timer resets to 15s and a new random survivor
   gets the bomb.
5. Repeat until one player is left.

Nobody is ever damaged. Elimination is pure physics -- the character's joints
are swapped for swinging ones and the body is thrown. Health is never touched.

## Things you might want to change first

All in `src/shared/Config.luau`:

- `TIMER_START`, `TIMER_DECAY_PER_PASS`, `TIMER_MINIMUM` -- the pace of a round
- `PASS_RADIUS` -- how close you must get to pass it (5 studs is about arm's length)
- `LAUNCH_SPEED` -- how far the exploded player flies
- `ARENA_SIZE` -- how big the map is
- `MIN_PLAYERS` -- how many players a real round needs

## Known trade-off

Two players who simply stand next to each other can trade the bomb back and
forth every second forever, because the timer floor (5s) is longer than the pass
cooldown (1s). If you see that happen in a playtest, set
`Config.BLOCK_INSTANT_PASS_BACK = true` -- that stops you handing the bomb
straight back to whoever gave it to you, which breaks the trade.

It ships **off** so you can judge the plain version first.

## What has never actually been tested

Kept deliberately, so nobody later assumes these are proven. Everything else in
this project was verified by running it and measuring; these were not.

**Needs two clients** (Studio → Test → Clients and Servers):

- Passing the bomb between real players. Every timer, elimination and pickup
  path is verified solo, but the pass itself has only ever been measured as a
  distance check, never actually performed by two people.
- Reverse Controls exempting the activator. The rule is verified by driving
  `Humanoid:Move` directly; it has never run with two real players.
- The Brain Rot NPC choosing between several possible victims.

**Needs real hardware:**

- The mobile touch button's position. It was placed by reasoning about where
  the jump button sits, not by looking at it.
- Console safe areas. TVs crop roughly 5% at the edges, and several HUD
  elements sit 22px from an edge.
- Gamepad play generally. The binding is confirmed present; nobody has held a
  controller.

**Needs a human eye.** Numbers can show limbs articulating 67 degrees and
pickups spawning at the right rate. They cannot show whether the ragdoll looks
right, whether eight pickups at once is too busy, or whether Ice Shoes is fun.
