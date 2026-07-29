# Plugging the game into a hand-built map

Everything needed to move Hot Potato Bomb off the code-generated arena and onto
a map built by hand in Studio. Written so it can be picked up cold, months
later, without the conversation that produced it.

The arena today is built entirely in code by `src/server/Arena.luau` when the
server starts, which is why Edit mode shows an empty Workspace. Replacing it is
a small job — but **not a zero-code job**. Two things are already tag-driven and
need nothing; four still assume the generated arena's shape.

---

## Part 1 — Already portable (tags only, no code)

Set these in Studio's **View → Tag Editor**. Nothing else required.

| Tag | Put it on | Used by |
|---|---|---|
| `HotPotatoFloor` | Every walkable surface | Ice Shoes freezes exactly these, and tints them blue |
| `HotPotatoPickupZone` | Invisible box(es) over playable space | Where pickups may appear |

Pickups pick a random point inside a zone and ray straight **down** to find
ground, so a zone should sit *above* the floor it covers. Use several zones for
a multi-level map — one per floor. With no zone tagged anywhere, the code falls
back to a flat square around `ARENA_CENTER` rather than breaking.

Tag names live in `Config.TAG_FLOOR` / `Config.TAG_PICKUP_ZONE`.

---

## Part 2 — Still hardcoded (needs code changes)

These four assume a square arena centred on the world origin. Each is small, but
none of them adapt on their own.

### 1. Spawn points — `src/server/Arena.luau`

`Arena.getShuffledSpawns()` returns a ring of `CFrame`s that `Arena.build()`
generated. It is the **only** thing the rest of the game asks the map for —
called once, from `RoundManager.spawnEveryone`.

**Change to:** collect `SpawnLocation`s out of the map model instead.

**Height is the part that goes wrong.** Reported in a playtest on 2026-07-29 —
players spawning inside the floor — then measured in Studio and fixed.

`spawnEveryone` uses `character:PivotTo(cf)`, and a character's pivot is its
**HumanoidRootPart**, whose centre sits **3.04 studs above the soles of its
feet** (measured, R15, `HipHeight` 2.0 plus half the 2-stud root part). So the
spawn `CFrame` must be about 3 studs above the surface you want the player
standing on — measured from the **top of the spawn pad**, not the floor
underneath it.

The generated arena was wrong by exactly the pad's height. Measured before the
fix:

```
floor top = 2.00
pad top   = 3.00      (1-stud pad sitting on the floor)
spawn Y   = 5.00      <- root placed here
feet land = 1.96      <- 1.04 studs BELOW the pad top, and under the floor too
```

Physics then ejected the character upward over the following second, settling
the root at 6.00. That eject is what players see as popping, jitter, or
occasionally falling through.

Whatever the map is, apply the same check: **feet = spawn Y minus 3.04**, and
that must land just *above* the surface. Give it a little clearance rather than
landing it exactly, so a character never starts a frame intersecting anything.
A hand-built map inherits this trap unchanged — `SpawnLocation`s are authored at
*pad* height, which is not root height.

### The second cause: props standing in the spawn pads

Measured at the same time, and it was the bigger of the two. The spawn ring is
placed by one formula and the low walls, pillars and crates by others, and
**nothing checked that the two did not collide**. Four of the ten pads had a low
wall or a pillar standing in them. A player spawning there started inside solid
geometry and was flung out by the physics solver — one test character was
ejected 2.8 studs and ended up standing on top of a low wall.

`Arena.build()` now parents the arena *before* placing the spawn ring, so it can
ask the physics engine what is already there, and slides each pad around the
ring in 3° steps until a character-sized volume above it is clear. Re-measured
after the change: **0 of 10 obstructed**.

A hand-built map needs the same check by hand, or the same code pointed at its
`SpawnLocation`s. Placing ten characters at once and looking for anyone standing
inside a wall is the cheap version.

### 2. Brain Rot NPC spawn — `src/server/BrainRot.luau`

```lua
local radius = Config.ARENA_SIZE / 2 - 14
local position = Vector3.new(math.cos(angle) * radius, Config.FLOOR_Y + 4, math.sin(angle) * radius)
```

Puts the NPC on a circle around the origin. On another map shape it can land
inside geometry or outside the play area.

**Change to:** reuse the spawn points from (1), or add a third tag for NPC entry
points.

### 3. Test Mode showcase range — `src/server/TestRange.luau`

Places its platform at `z = -(Config.ARENA_SIZE / 2 - 16)`, i.e. against one
wall of the generated arena.

**Change to:** a fixed position chosen for the new map, or a tagged marker part.
Test-Mode-only, so lowest priority.

### 4. Spectator camera — `src/client/init.client.luau`

Orbits `Config.ARENA_CENTER` at `SPECTATOR_DISTANCE` / `SPECTATOR_HEIGHT`.
Wrong centre or radius just means eliminated players watch the wrong spot.

**Change to:** update the three Config values to frame the new map. No code
change needed if the map is still roughly centred.

---

## Part 3 — Config values to re-measure

| Value | Meaning |
|---|---|
| `ARENA_SIZE` | Width/depth of playable floor. Used for the pickup fallback square and the two positions above |
| `FLOOR_Y` | Height of the main floor surface |
| `ARENA_CENTER` | Middle of the map, at floor height |
| `SPECTATOR_HEIGHT` / `SPECTATOR_DISTANCE` | Framing for the dead-player camera |

---

## Part 4 — Order of work

1. Build the map in Studio. Name the top model **`Arena`** in Workspace.
2. Add `SpawnLocation`s where players should start — 10 for a full lobby.
3. Tag walkable surfaces `HotPotatoFloor`.
4. Add invisible zone parts over playable space, tagged `HotPotatoPickupZone`.
5. Measure the map and update the Config values in Part 3.
6. Change `Arena.build()` to **find** `workspace.Arena` rather than create it,
   and `getShuffledSpawns()` to read the map's `SpawnLocation`s.
7. Fix the NPC spawn and the test range positions.
8. Delete or keep the generator — `Arena.preview()` is handy either way.

Rough size: **30–40 lines changed, about an hour including testing.**

---

## Part 5 — Verification

Nothing here is visual-only; each has a checkable signal.

1. **Players spawn spread out**, inside the map, not stacked or in geometry.
2. **Pickups appear** and stay at or below the cap — and on *every* level of a
   multi-level map, not just the ground floor.
3. **Ice Shoes** changes friction on the floor you are standing on, and restores
   it. Assert `CustomPhysicalProperties.Friction` before/during/after.
4. **Brain Rot NPC** spawns somewhere reachable and can path to a player. Watch
   the distance close; it should not wedge on geometry.
5. **Spectator camera** frames the map when you are eliminated.
6. **Thin walls:** the bomb passes on a distance check with no line-of-sight
   test (`Config.PASS_RADIUS`, 5 studs). Any wall thinner than ~4 studs can be
   passed through. This is a known, deliberate limitation — worth re-testing on
   real geometry, and the reason the generated arena's low walls are 3 studs
   thick and *do* leak.

---

## Part 6 — Things that will trip you up

- **Rojo only reads `default.project.json` when `rojo serve` starts.** Adding
  instances there mid-session silently does nothing. Declare runtime instances
  in code instead.
- **Rojo does not sync into a running Play session at all.** Stop Play, confirm
  the synced source in Edit, then start Play. Skipping this means testing stale
  code, which has wasted real time on this project more than once.
- **`Workspace.FallenPartsDestroyHeight` is −500.** Never park an unanchored
  part at or below it to hide it; set `Parent = nil` instead.
- **The place file is disposable.** Arena, bomb and pickups are all built at
  runtime, so `Test1.rbxlx` is a rebuildable artifact and is gitignored. Once
  the map is hand-built this stops being true — **the place file becomes real
  data and must be committed or it will be lost.**
