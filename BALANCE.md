# Balance dials

The short list of numbers that change **how the game plays**, as opposed to how
it is built. Every one of them lives in `src/shared/Config.luau`, which has the
full reasoning next to each value — this page is the overview: what to reach for
when something feels wrong.

Config has around eighty values. Roughly twenty-five of them are balance. The
rest are plumbing, placeholders and map geometry, and are deliberately not
listed here.

**Changing anything: stop Play, save the file, confirm it synced, start Play.**
Config is read when the server starts, so a live edit alone does nothing.

---

## If it feels wrong, start here

| It feels… | Try |
|---|---|
| Too slow, not enough happening | `TIMER_START` down, `PICKUP_SPAWN_INTERVAL` down |
| Frantic, no time to think | `TIMER_START` up, `PICKUP_PER_PLAYER` down |
| Rounds drag at the end | `TIMER_DECAY_PER_PASS` up, `TIMER_MINIMUM` down |
| The duel is a grind | `TIMER_MINIMUM_DUEL` down, `TIMER_DECAY_PER_PASS` up |
| Passing is fiddly, you miss people | `PASS_RADIUS` up |
| Passing is too easy, no chase | `PASS_RADIUS` down, `PASS_COOLDOWN` up |
| Too busy, screen full of junk | `PICKUP_MAX_ACTIVE` down, `MODIFIERS_STACK` off |
| Beacons dominate the round | Their `_DURATION`s down |
| Explosions are underwhelming | `LAUNCH_SPEED` up, `LAUNCH_SPIN` up |

---

## Round pace

The dials that decide how long a round lasts and how it accelerates.

| Dial | Now | What it does |
|---|---|---|
| `TIMER_START` | 15s | How long the first holder of a cycle gets. **The single biggest pace dial.** |
| `TIMER_DECAY_PER_PASS` | 2s | Taken off the timer on every pass, so each cycle tightens |
| `TIMER_MINIMUM` | 5s | The timer never drops below this with 3+ players alive |
| `TIMER_MINIMUM_DUEL` | 0.75s | The floor once only two are left. **Must stay below `PASS_COOLDOWN`** or duels can run forever |
| `RESET_TIMER_AFTER_EXPLOSION` | `true` | `true` = every cycle starts fresh at 15s. `false` = it keeps shrinking all round, so late rounds are brutal |
| `MIN_PLAYERS` | 2 | How many are needed for a real round |
| `INTERMISSION_SECONDS` | 16s | Countdown before a round starts — and **the window to join**. Anyone who reaches the queue pad before it runs out is in |
| `ROUND_OVER_SECONDS` | 6s | How long the winner is shown before the next countdown. The map stays live through it, so the winner can run around with whatever is left |
| `ROUND_CLEANUP_LEAD` | 0.75s | How long before that ends the pickups are tidied away, so the next round starts clean |

## The lobby and the queue

| Dial | Now | What it does |
|---|---|---|
| `LOBBY_CENTER` | (0, 2, 600) | How far the lobby sits from the arena. Far enough that nothing in one can reach the other |
| `LOBBY_SIZE` | 110 studs | How much room there is to roam between rounds |
| `LOBBY_SPAWN_COUNT` | 8 | Pads in the ring players appear on |
| `QUEUE_PAD_RADIUS` | 7 studs | How close you must get to the pad to join or leave |
| `LOBBY_RESPAWN_CHECK` | 1s | How quickly somebody who lost their body gets it back. **Not** cosmetic — the game hands out every body itself, so without this you would stay bodyless |

## Passing

| Dial | Now | What it does |
|---|---|---|
| `PASS_RADIUS` | 5 studs | How close you must get. Two players chest-to-chest are about 4 apart |
| `PASS_COOLDOWN` | 1s | How long after receiving it before you may pass it on |
| `BLOCK_INSTANT_PASS_BACK` | `true` | Stops you handing it straight back to whoever gave it to you |
| `PASS_BACK_MIN_PLAYERS` | 3 | The rule above only applies with this many alive. **Do not set it to 2** — the last two players would have no legal target and the receiver would be guaranteed to die |

## The explosion

Pure feel. None of it affects who wins.

| Dial | Now | What it does |
|---|---|---|
| `LAUNCH_SPEED` | 90 | How hard the eliminated player is flung. A player runs at 16 |
| `LAUNCH_VERTICAL` / `LAUNCH_HORIZONTAL` | 1.4 / 1 | Shape of it. More vertical = punted skywards, more horizontal = fired across the map |
| `LAUNCH_SPIN` | 14 | How much the body tumbles |
| `EXPLOSION_RADIUS` | 18 | Visual size only — it never pushes anyone else |
| `CORPSE_LIFETIME` | 4s | How long the body lies there before the spectator camera takes over |

## Pickups

How much stuff is on the floor.

| Dial | Now | What it does |
|---|---|---|
| `PICKUP_SPAWN_INTERVAL` | 5.3s | How often a new one appears |
| `PICKUP_PER_PLAYER` | 0.8 | How many may be out at once, per living player |
| `PICKUP_MIN_ACTIVE` / `PICKUP_MAX_ACTIVE` | 3 / 8 | Held between these two, so 4 players get 3 and 10 players get 8 |
| `PICKUP_LIFETIME` | 30s | An untouched one disappears after this, so corners do not silt up |
| `PICKUP_COLLECT_RADIUS` | 4 studs | How close you must get to take one |
| `PICKUP_ICONS_THROUGH_WALLS` | `true` | Whether the little emoji shows in front of walls. `false` hides it behind pillars and crates, so you have to look round things — see below |
| `ABILITY_USES` | 3 | Uses in a single pickup. You carry one ability at a time; a new one **replaces** it rather than stacking. An individual ability can override this with a `uses` field in `Abilities.luau` — Sneakers does |

Which pickups exist and how often each appears is in `src/shared/Abilities.luau`,
not Config — that is where you add a new one or change the odds.

### Trying the icon change without restarting

`PICKUP_ICONS_THROUGH_WALLS` is the value the game **starts** with, but you can
flip it mid-game to feel the difference straight away. In Studio, with the game
running, open **View → Command Bar** and paste:

```bash
require(game.ServerScriptService.Server.Pickups).iconsThroughWalls(false)
```

Every icon already on the map changes at once, and so does everything that spawns
afterwards. `true` puts it back. Leave off the `false` and it just tells you what
the setting currently is.

Whichever you prefer, set `PICKUP_ICONS_THROUGH_WALLS` in Config to match so it
sticks.

## Abilities

| Dial | Now | What it does |
|---|---|---|
| `DASH_SPEED` / `DASH_DURATION` | 85 / 0.18s | Speed × duration ≈ distance, so about 15 studs. A lunge, not a teleport |
| `FART_JUMP_POWER` | 68 | The second jump's kick. Now clearly stronger than a normal jump (50), so it reaches places a plain jump cannot |
| `FART_JUMP_APEX_SPEED` | 15 | You cannot fart jump until rising slower than this. **Leave it alone unless the ability feels broken** — it is what stops the charge being spent for no visible effect |
| `SNEAKERS_MULTIPLIER` / `SNEAKERS_DURATION` | 2× / 5s | 2 × 16 = 32 studs/s, comfortably clear of the Brain Rot NPC at 18 |
| `SNEAKERS_USES` | 2 | Sneakers alone overrides `ABILITY_USES`. Short and powerful, so you get fewer of them |

## Beacon events

Each one changes the map for everyone. `MODIFIERS_STACK` (`true`) lets several
run at once — turn it off and a new beacon cancels whatever is already running.

| Event | Duration | Strength | Notes |
|---|---|---|---|
| Ice Shoes | `ICE_DURATION` 20s | `ICE_FRICTION` 0.006 | Friction blends with the player's own legs, so the effective grip is much higher than the number suggests. Config explains the maths. Roughly 3× headroom left |
| Low Gravity | `LOW_GRAVITY_DURATION` 20s | `LOW_GRAVITY_VALUE` 60 | Normal is 196.2. Lower = floatier jumps **and much bigger explosions** |
| Tiny Mode | `TINY_DURATION` 20s | `TINY_SCALE` 0.6 | 60% height |
| Reverse Controls | `REVERSE_DURATION` 5s | — | Deliberately short. Everyone except whoever grabbed it |
| Brain Rot | `BRAINROT_DURATION` 25s | `BRAINROT_WALK_SPEED` 18 | Hunts everyone except the bomb holder |

Brain Rot has its own feel dials: `BRAINROT_CATCH_RADIUS` (5), `BRAINROT_KNOCKDOWN`
(2s on the ground), `BRAINROT_SHOVE` (30 — the push that actually knocks you off
your feet), and `BRAINROT_CATCH_COOLDOWN` (3s, so it cannot pin one player down
over and over).

Its speed of 18 is the interesting one: just above a running player (16) so it
closes in over time, but below Sneakers (24) so there is always an escape.

---

## Not balance — do not tune these by feel

- `SPAWN_ROOT_HEIGHT` (3.04) and `SPAWN_CLEARANCE` (0.15) — **measured**, not
  chosen. Changing them puts players back inside the floor. See
  `MAP_INTEGRATION.md`
- `PASS_CHECK_INTERVAL`, `ABILITY_REQUEST_COOLDOWN` — server cost and
  anti-cheat, not feel
- `ARENA_SIZE`, `FLOOR_Y`, `WALL_HEIGHT`, `ARENA_CENTER` — map geometry. Changing
  these means re-reading `MAP_INTEGRATION.md`
- `BASE_WALK_SPEED`, `BASE_JUMP_POWER`, `NORMAL_GRAVITY` — Roblox's own defaults,
  written down for reference. Everything else is expressed relative to them

## Before publishing

| | Must be |
|---|---|
| `TEST_MODE` | `false` |
| `SOLO_TEST_MODE` | `false` |
| `SOUND_DASH`, `SOUND_FART_JUMP` | Real fart sounds — currently Roblox stand-ins |
| `BRAINROT_FACE` | Your own meme face — currently Roblox's default smiley |

---

## Change log

Add a line whenever a dial moves, so the reasoning is not lost. Newest first.

| Date | Change | Why |
|---|---|---|
| 2026-07-29 | `FART_JUMP_POWER` 45 → **68** | At just under a normal jump it was the dullest of the three abilities |
| 2026-07-29 | `ROUND_OVER_SECONDS` 10 → **6**, and the map stays live through it | 10s felt like standing about, and a frozen map left the winner nothing to do |
| 2026-07-29 | Sneakers → 2× for 5s, **2 uses** (was 1.5× for 8s, 3 uses) | A burst you spend at the right moment rather than a general speed boost. Needed a per-ability `uses` override, which any ability can now use |
| 2026-07-29 | `INTERMISSION_SECONDS` 8 → **16** | 8s was not long enough to notice a round forming and reach the queue pad |
| 2026-07-29 | `ROUND_OVER_SECONDS` 6 → **10** | The gap after a round ended felt rushed |
| 2026-07-29 | `TIMER_MINIMUM_DUEL` added at 0.75s | Ends a one-on-one by the clock. Verified as logic, **not yet played** |
| 2026-07-29 | `PASS_BACK_MIN_PLAYERS` added at 3 | The pass-back rule alone would have guaranteed the death of whoever received the bomb in a duel |
| 2026-07-29 | `BLOCK_INSTANT_PASS_BACK` → `true` | Trade-back stalemate confirmed with two clients: two players really do ping-pong forever |
| 2026-07-29 | `TIMER_START` 30 → 15 | 30 was a temporary testing value, not a balance decision |

## Open questions for the next playtest

Things nobody has judged yet. Numbers cannot answer any of them.

- Does the final duel feel tense, or just abrupt? Seven passes, accelerating
- Is eight pickups at once too busy with a full lobby?
- Is Ice Shoes fun, or just annoying? There is 3× more slipperiness available
- Do stacked beacons (`MODIFIERS_STACK`) read as chaos or as noise?
- Is 15s the right starting timer with real players who dodge?
