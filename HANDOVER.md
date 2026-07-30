# Where this project is right now

Last updated 2026-07-30.

**Read this first if you are picking the project up cold.** It says what state
things are in, what is deliberately switched off, what has never been verified,
and what to do next. The other docs explain *how* each part works; this one
explains *where we are*.

---

## The one-paragraph version

Hot Potato Bomb is a round-based Roblox party game, and the whole loop is built:
a lobby with a queue pad, an arena, a free-for-all between rounds, a ghost area
for knocked-out players, abilities and beacon events, persistent stats with
global leaderboards, an anti-cheat movement check, and a cosmetic store. Nothing
is published. **Nobody has ever played it for fun** -- every test so far has been
"does this work", not "is this good".

---

## Current branch and state

- Working on `lobby-stage-1`, ~30 commits ahead of `main`, pushed.
- `gh` is **not installed**, so PRs cannot be created from the agent side. Push
  the branch and give Elias the `pull/new/<branch>` link.
- Working tree should be clean. If it is not, something was left half-done --
  check `git status` before starting.

## Switches that are deliberately OFF

Do not turn these on casually; each is off for a stated reason.

| Switch | State | Why |
|---|---|---|
| `PRODUCTS_ENABLED` | `false` | The five cosmetics have no Roblox product IDs yet. See `STORE.md` |
| `MOVEMENT_CORRECT` | `false` | The anti-cheat is watch-only until real rounds prove it does not flag honest players |
| `TEST_MODE` | `false` | Sandbox. Turning it on gives a showcase range and no bomb |
| `SOLO_TEST_MODE` | `false` | Lets a round run with one player. Handy for testing, must be off to publish |

Agents: if you flip any of these to test, **flip them back and confirm in the
commit**. This has been a recurring source of accidental commits.

## What is blocked on Elias, not on code

1. **Four placeholder assets.** Two fart sounds, the Brain Rot NPC's face, and
   the punching bag's thump are Roblox stand-ins. Roblox ships no fart noises, so
   these cannot be fixed from here.
2. **Creating the five developer products** and pasting the IDs into
   `src/shared/Products.luau`. `STORE.md` has the exact steps.
3. **Publishing and playing it with real people.** This is the biggest
   outstanding item in the whole project.

---

## Never verified

Kept deliberately, so nobody assumes these are proven.

**Needs more than one client** (Studio → Test → Clients and Servers):
- The punching bag responding to a real mouse click. The logic behind it is
  verified; a genuine `ClickDetector` click has never happened
- The shop pedestals with several people around them
- Beacon isolation with a lobby player present, beyond the three-client pass
  already done

**Needs real hardware:**
- Where the mobile touch button sits. Placed by reasoning, never looked at
- Console safe areas. TVs crop ~5% and several HUD elements sit near edges
- Gamepad play. The bindings exist; nobody has held a controller

**Needs a human eye. This is the big one:**
- Whether any of it is fun. Whether the final duel is tense or abrupt. Whether
  the lobby is the right size now. Whether the boards read well. Numbers cannot
  answer any of these

---

## What to do next

In the order I would do it:

1. **Publish privately and play with four or five people for twenty minutes.**
   Everything else is guesswork until this happens. The loop has been stable for
   a while and there is now a shop and leaderboards to give a session shape.
2. **Swap the four placeholder assets**, so a playtest is not judged on Roblox's
   default smiley face and a jump sound standing in for a fart.
3. **Turn on `MOVEMENT_CORRECT`** once real rounds have run and the output stays
   free of `[MovementGuard]` lines.
4. **Real maps.** `MAP_INTEGRATION.md` is written and current. Biggest visual
   jump for the least gameplay risk. Both the boards and the lobby geometry are
   already tag-driven, so hand-built replacements need no code change.
5. **The obby.** Sketched in `LOBBY_PLAN.md`, never planned properly.

Elias has said he does not want to test or build maps for a while, so expect
small feature and feel requests rather than big pushes.

---

## How to work on this

Elias is a project manager, not an engineer. He describes mechanics in plain
language and expects them translated into code. So:

- **Read the docs before asking him anything.** They are kept current on purpose
  so he does not have to be the memory.
- Ask design questions in terms of what happens in the game, not in terms of
  APIs, and give a recommendation rather than a survey of options.
- Keep every tunable number in `src/shared/Config.luau`, commented in terms of
  what it does to the game.
- He has asked more than once for **shorter replies**. Report what changed, what
  was measured, and what is still unknown. Skip the walkthrough.

### Verify empirically, and distrust your own probes

The project's standard is measure, do not assert. Three specific traps have each
cost real time in this project, twice each:

1. **Confirm the synced source AFTER editing and BEFORE pressing Play.** Rojo's
   push is not instant. Starting Play straight after an edit boots the old code,
   and the result looks exactly like a broken feature. This produced two
   convincing false failures in one session.
2. **`require()` from the command bar gives a SEPARATE copy of a module.** Its
   internal state is not the running game's. Assert on real Instances, saved
   data, or the client's HUD -- never on a module's own variables. This is also
   why the icon toggle is stored as a `BoolValue` and not a variable.
3. **A probe that finds nothing is the one to distrust.** A filter bug once
   reported "0 of 10 obstructed" when the answer was 4. Give a negative result a
   positive control before believing it.

---

## Where everything is documented

| File | What it covers |
|---|---|
| `README.md` | What the game is, how to run it, what has never been tested |
| `BALANCE.md` | The ~25 numbers that change how it plays, and a change log |
| `STORE.md` | Everything about selling things, and the four steps to switch it on |
| `STATS_PLAN.md` | The stats and leaderboard design, all five stages |
| `LOBBY_PLAN.md` | The lobby stage. Complete; kept for the reasoning |
| `MAP_INTEGRATION.md` | Moving onto a hand-built map |
| `PLANNING_PROMPT.md` | The working pattern for running a feature end to end |

## Testing setup

- `rojo serve` from the project root, then **Connect** in the Studio plugin. If
  Rojo is restarted the plugin disconnects and must be reconnected -- syncs
  silently stop until it is.
- Saving needs **Game Settings → Security → Enable Studio Access to API
  Services**. Studio always writes to a separate `_studio` save file, so
  playtesting can never touch real player data.
- Screenshots via the Studio MCP tools time out fairly often. Fall back to
  reading state numerically and say plainly that you could not look at it.

## The one thing to be careful with

`src/server/StatsStore.luau` is the only file that touches saved data, and the
only code in this project that can destroy something a player cannot get back.
The rule the whole feature rests on: **a profile that failed to load is never
written back.** Without it, a brief data outage means a player's blank totals get
saved over months of real history, with nothing looking wrong at any point.

If you change that file, re-read its header comment first.
