# Stats and scoreboards

## Context

The game has no memory. Nothing a player does survives the server restarting:
the punching bag's counter, who won, how long anybody lasted -- all of it dies
with the session. `GhostClicker.luau` says so in a comment and parks the problem
until now.

This is the stage that gives the game a reason to come back to, and it is also
the first work here that can **lose something a player earned and cannot get
back**. The arena could only ever produce a funny explosion; this can wipe two
months of somebody's history. That difference drives most of the decisions
below.

## The five boards

| Board | Counts | Periods |
|---|---|---|
| Survivor | Seconds alive in a round | All-time |
| Farted on | Bombs passed to another player | All-time |
| Ability king | Abilities used **in a round** | All-time |
| Tung tung sahur hits | Punches on the ghost-area bag | All-time |
| Biggest flexer | Robux spent **in this game** | All-time + daily, weekly, monthly |

Decisions taken (2026-07-30):

- **Survive time counts only while alive in a round.** Free play, lobby and
  ghost time do not count, or the board measures who leaves the game open
  longest.
- **Only Robux gets time periods.** Eight leaderboards rather than twenty.
  Adding a period to another stat later is a one-line change.
- **Practice-range abilities do not count.** The range hands one out every two
  seconds forever, so counting them means anybody can top that board without
  ever playing a round.
- **Boards are physical, in the lobby** -- and **swappable**, see below.

## Robux spend cannot be backfilled

Roblox gives developers no purchase history. The only spend this game can ever
count is a purchase made through **this game's own** `ProcessReceipt`, from the
moment that exists. So the flexer board is empty until stage 5, can never
include anything bought before it shipped, and can never include Premium, other
games, or Robux spent anywhere else.

## Boards must be replaceable

The lobby's boards are placeholder geometry, the same as the lobby itself, and
will be swapped for proper models. So the scoreboard is found **by tag**, never
by name -- exactly what makes the map swappable in `MAP_INTEGRATION.md`.

- `Config.TAG_SCOREBOARD = "HotPotatoScoreboard"` on any part that should
  display a board.
- Which board it shows comes from an **attribute** on that part:
  `StatId` (`SurviveSeconds`, `Passes`, `AbilityUses`, `Punches`, `RobuxSpent`)
  and optionally `Period` (`AllTime`, `Daily`, `Weekly`, `Monthly`).
- `Scoreboard.build()` only creates the placeholder slabs **if nothing carrying
  that tag already exists**. Build your own, tag it, set the attributes, and the
  code stops generating its own.

That means replacing the boards later is a Studio job with no code change, and
it is the same deal already documented for floors and pickup zones.

---

## Files

**New**

| File | Job |
|---|---|
| `src/shared/Stats.luau` | The catalogue: ids, labels, which periods each gets, formatters, and the bucket-key function. Same role `Abilities.luau` plays for pickups |
| `src/server/StatsService.luau` | Counting, the survive clock, leaderstats. Knows the game, knows nothing about saving |
| `src/server/StatsStore.luau` | The only file that touches `DataStoreService`. Knows saving, knows nothing about the game |
| `src/server/Scoreboard.luau` | The boards. `build()` / `refresh()` / `start()` / `preview()`, same shape as `Lobby.luau` |
| `src/server/Monetisation.luau` | Stage 5 only. `ProcessReceipt` |
| `src/shared/Products.luau` | Stage 5 only. Product id, price, what it grants |

**Modified:** `RoundManager.luau`, `AbilityService.luau`, `GhostClicker.luau`,
`init.server.luau`, `Config.luau`.

`StatsService` is a leaf module -- it requires only `shared/Stats` -- so
`RoundManager`, `AbilityService` and `GhostClicker` can require it directly. No
provider wiring needed except where noted.

---

## Stage 1 -- count everything, in memory only

Numbers appear in the Roblox player list and reset on restart. No DataStore code
exists yet, so nothing can lose data, and every counting site is proven before
persistence goes on top.

**Passes** -- in `RoundManager.runRound`'s pass branch (the `giveBombTo(target)`
call reached after `findPassTarget` succeeds), **not** inside `giveBombTo`.
Three of its four callers are not passes: the initial hand-out, the replacement
when a holder vanishes, and the post-explosion hand-out. Capture the passer
**before** the call -- `giveBombTo` reassigns `holder` -- and only count when it
returns true, since a failed attach is not a pass.

**Ability uses** -- in `AbilityService`, immediately after `slot.uses -= 1`.
Every branch above it is a rejection. Gated by a new
`AbilityService.setCountCheck`, wired in `init.server.luau` to
`RoundManager.isAlive`, following the existing setter convention (`AbilityService`
must not require `RoundManager`, which already requires it).

**Punches** -- in `GhostClicker.punch`, beside the existing counters. Add a
minimum interval between counted punches, or an auto-clicker owns that board.

**Survive time** -- start after the first bomb hand-out succeeds in `runRound`
(not when `alive` is filled: the early returns above would leave a clock running
forever). Three stop sites: `eliminate`, `pruneAlive` (the reset/disconnect path
that never calls `eliminate`), and round end. `StatsService` connects its **own**
`PlayerRemoving` -- relying on `RoundManager`'s would depend on handler order and
silently drop the last stretch of time. Keep the running total as a float and
round only for display and for the board.

**leaderstats** -- a `Folder` per player showing all-time totals, two columns
(`Config.LEADERSTATS_COLUMNS`), refreshed on a 1-second tick rather than on every
increment. All five boards still show on the lobby wall.

**Verification:** `Config.STATS_DEBUG_LOG` prints every increment. Solo: blow
yourself up, punch the bag, watch it count; use the practice range and confirm
it does **not** count; queue and use one in a round and confirm it does; press
Reset mid-round and confirm the survive clock closed once with the right value.

**Cannot be verified solo:** the pass counter at all, including whether the
passer or the receiver gets credited. Needs two clients.

---

## Stage 2 -- persistence

`StatsStore.luau`. Profile store `HotPotatoStats_v1`, key `player_<userId>`,
holding all-time totals, the three Robux period buckets, and `lastSeen`.

Period rollover is **lazy and per player**: each period stores its bucket string
(`2026-07-30`, `W2952`, `2026-07`) and zeroes itself on load or flush when the
current bucket no longer matches. No nightly job.

**The one rule that matters.** If loading a profile fails after retries, mark it
`failedToLoad`, serve zeros so the game still works, and **never write it**. A
failed load followed by a successful save is exactly how two months of history
gets erased. That boolean carries the entire feature's data safety.

**Writes are merge-deltas via `UpdateAsync`**, not whole-total overwrites, so two
servers holding the same player add up instead of clobbering each other. Deltas
clear only after the write returns cleanly and are re-added if it throws.

**Flush on:** a 60-second timer staggered by `userId`, player leaving (clock
closed first, then flush, then drop), round end, and `game:BindToClose` --
`endRoundAll()` then `flushAll()`, waited on with a deadline, never
fire-and-forget.

Nothing writes per pass or per punch. A punch adds to an in-memory delta that
reaches the datastore at most once a minute.

**Studio:** probe `DataStoreService` in a `pcall`; if it fails, run in memory and
print one plain-language line about ticking Game Settings → Security → Enable
Studio Access to API Services. `Config.STATS_SAVE_IN_STUDIO = false` keeps
playtest junk out of live player data.

**Verification:** with API access on, earn numbers, Stop, Play -- they come back.
Stop mid-round and confirm the last chunk survived. Then turn API access off and
confirm the game still runs and the old numbers are still intact afterwards,
which proves the never-write-a-failed-load rule.

---

## Stage 3 -- ranked global boards

`OrderedDataStore`, one per stat per period: `HPBoard_v1_<stat>_<bucket>`, key
`userId`, value an integer. A `_studio` suffix in Studio so test players never
land rows in the real board.

Eight stores: all-time for all five, plus daily/weekly/monthly for Robux. Write
the current cumulative total with `SetAsync` only when it changed -- the profile
is authoritative and this is a denormalised copy for ranking, so a lost write
corrects itself next flush.

Weekly buckets are arithmetic from a fixed UTC Monday, not `%V`. All buckets UTC
so every server agrees. `Stats.bucketFor(period, unixTime)` is a pure function so
rollover can be tested from the command bar with fabricated timestamps.

Reads rotate **one board per refresh tick** -- `GetSortedAsync` has a small
budget and eight reads in one tick can exceed it outright. Results cached; names
memoised through `GetNameFromUserIdAsync` in a `pcall`.

**Cannot be verified solo:** ordering. One row proves the plumbing, not the sort.

---

## Stage 4 -- the boards in the lobby

`Scoreboard.luau`, mirroring `Lobby.luau`. Finds tagged parts (see
"Boards must be replaceable"); builds placeholder slabs only if none exist.
Each board is a part with a server-created `SurfaceGui` -- which replicates on
its own, so this stage adds **no client code**.

Placeholder geometry: a row of slabs inside a lobby wall, positioned from
`Config.LOBBY_CENTER` and `Config.SCOREBOARD_*` so they move with the lobby, and
parented into the `Lobby` model so `Lobby.clearPreview()` takes them with it.

The Robux board cycles Daily → Weekly → Monthly → All-time from cache, no extra
reads. Three honest empty states: loading, nobody yet, and "leaderboards need
API access turned on".

All labels and formatting come from `shared/Stats.luau`, so renaming a board is
a one-word edit in one place.

Optional: point the punching bag's own sign at the global punch total instead of
this server's.

---

## Stage 5 -- Robux spend

`Monetisation.luau` + `shared/Products.luau`, behind
`Config.PRODUCTS_ENABLED = false`.

Count inside `ProcessReceipt`, after the grant succeeds and before returning
`PurchaseGranted`. Two non-optional rules:

- **Idempotency.** Roblox re-delivers a receipt until you return
  `PurchaseGranted`. Store the last handled `PurchaseId` or one purchase counts
  three times.
- **Order.** Only return `PurchaseGranted` once the profile write has succeeded;
  return `NotProcessedYet` otherwise. Backwards means either double-granting or
  losing a purchase somebody paid for.

---

## Riskiest part

**The load-failure path in `StatsStore.luau`.** Everything else here is cosmetic
if it breaks.

The failure, concretely: a player joins during a transient datastore outage, all
retries fail, their in-memory profile is zeros. They play ten minutes. The flush
writes zeros-plus-this-session over two months of real totals. No in-game signal
that anything happened.

Mitigation is the `failedToLoad` flag and the absolute rule above. Escape hatch
if it ever does happen: datastores keep about 30 days of versions, so
`ListVersionsAsync` / `GetVersionAsync` can recover one player by hand.

**Second:** `BindToClose` not actually waiting, which makes numbers go backwards
after every restart -- the most trust-destroying bug a leaderboard can have.

**Third:** reading the passer *after* `giveBombTo` instead of before. Credits
every pass to the receiver, looks entirely plausible, and is invisible in
single-client testing.
