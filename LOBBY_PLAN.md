# Lobby foundation: queue, teleport, spectate, practice

## Context

Every player who joins is currently dropped straight into the arena and forced
into every round. There is nowhere to wait, nothing to do between rounds, and no
way to sit one out. The lobby is the container that stats, the shop, the jukebox
and the obby all hang off — none of them have anywhere to live until it exists.

**Scope: one lobby, one arena.** Lobby → arena → lobby.

Concurrent arenas are explicitly **not** being built. If queue times later become
a real problem, the escalation is: first dedicated match servers via teleport,
and only then concurrency inside a single server, and only with evidence that
teleporting is hurting players enough to justify it.

That decision removes the single most expensive item from the previous draft —
converting six server modules from singletons to instances. `RoundManager`,
`Bomb`, `Pickups`, `Modifiers`, `BrainRot` and `Arena` all stay as they are.

---

## The lobby isolation problem

The beacon events are **global by design** — that was correct when everyone in
the server was in the round. With a lobby it is not, and this is the real
design work in this stage.

| Event | Leaks into the lobby? | Fix |
|---|---|---|
| **Ice Shoes** | ~~Only if the lobby floor is tagged~~ **DONE** | Lobby floor is untagged, asserted in testing |
| **Tiny Mode** | ~~Yes — iterates every player~~ **DONE** | Applies to round members; reverts for everyone, so nobody can be left shrunk |
| **Reverse Controls** | ~~Yes — `FireAllClients`~~ **DONE** | `ModifierChanged` goes per-player; non-participants get an empty list, which actively clears their client effects |
| **Brain Rot** | No | Already scoped: lives in the arena, targets `getAlive()` |
| **Low Gravity** | ~~**Yes, and cannot be scoped as written**~~ **DONE** | Rewritten as a per-character upward force. No longer touches `workspace.Gravity` |

### Correction to my earlier draft

The previous version of this plan said to tag the lobby floor with
`Config.TAG_FLOOR` "so it behaves under the later map swap". **That was wrong.**
That tag is exactly what Ice Shoes looks for, so tagging the lobby floor would
freeze the lobby every time someone in the arena grabbed the beacon. The lobby
floor must NOT carry that tag. If the lobby later needs its own tagged
behaviour, it gets its own tag.

### Low Gravity has to be rebuilt

`workspace.Gravity` is a **single global property**. There is no per-region
gravity in Roblox, so there is no way to scope the current implementation —
lobby players will float whenever an arena player grabs the beacon.

The fix is to stop touching `workspace.Gravity` and instead apply a per-character
upward `VectorForce` to each player in the round, proportional to their assembly
mass, cancelling part of their weight. Same felt effect, applied only to the
people who should feel it.

Roughly 30 lines, but with three things to watch:

- **Mass changes.** Tiny Mode shrinks players, which changes assembly mass, so
  the force has to be recalculated when both are active together.
- **Ragdoll interaction.** `Ragdoll.apply` takes network ownership and sets
  velocities directly; the force must be removed or accounted for so a knocked
  down player does not drift.
- **Cleanup.** The force must be removed on expiry, on death, on respawn and on
  the player leaving — the same "restore everything" discipline the other
  modifiers already follow.

This is the one genuinely non-trivial piece of the stage, and your question is
what surfaced it. It would have shipped as a bug otherwise.

### One nuance on who receives what

The recipient list for round messages is **"everyone in this round"**, not
"everyone alive" — eliminated players are still watching and should still see
the event HUD until they are returned to the lobby.

---

## Stage 1 — the work

Playable outcome: spawn in a lobby, touch a pad to queue, roam freely, get pulled
into the arena when a round starts, come back afterwards.

### Decisions taken

Recommendations, not your answers — **overrule any on review**, all are cheap now
and expensive later.

- **One place**, lobby and arena separated by distance. No `TeleportService`.
- **Join once, then roam.** Touch the pad to queue, then go anywhere.
- **Eliminated players watch, then auto-return** at round end, reusing the orbit
  camera already in `init.client.luau`.
- **Lobby is code-generated placeholder** geometry, same approach as the arena,
  replaced at the map stage.

### The core change

`RoundManager.runRound()` currently takes every connected player as a
participant. That becomes **"everyone in the queue"**. Everything else here is
mechanical; this is the change that matters.

### The eligibility trap — FIXED (2026-07-29)

`init.server.luau` used to wire `AbilityService.start(RoundManager.isAlive)`,
which would have thrown away every ability used in a lobby practice range —
pickup spent, nothing happening, HUD identical to success.

Fixed **before** the practice range exists to fall into it. The check now
allows anyone alive in a round *or* in the lobby, and still refuses a player
who has been blown up and is watching the rest of the round.

### The trap that will bite

`init.server.luau` wires `AbilityService.start(RoundManager.isAlive)`, which
requires phase `Playing`/`Sandbox` **and** membership of `alive`. A player in the
lobby practice area is neither, so **Dash and Sneakers would be silently
rejected** — pickup consumed, nothing happens. This is exactly the failure we
already fixed once on the fart jump, and it looks identical to success on the
HUD. Widen the eligibility check to "in a live round **or** in the lobby".

Related: the lobby practice range must offer **abilities only**, never beacons.

### Files

**New:** `src/server/Lobby.luau` (placeholder geometry, spawn points,
`sendToLobby` / `sendToArena` — mirror `Arena.luau` including a `preview()`),
`src/server/Queue.luau` (pad, membership, a `getQueued()` provider in the same
shape as the existing `getAlive` providers).

**Modified:** `RoundManager.luau` (participants from queue),
`Modifiers.luau` (scope Tiny Mode and Reverse Controls; rebuild Low Gravity),
`TestRange.luau` (generalise `build()` to take a position and an abilities-only
flag, so one implementation serves Test Mode and the lobby),
`AbilityService.luau` (eligibility), `Config.luau`, `Remotes.luau` (queue state),
`init.client.luau` (queue indicator, return-to-lobby).

**Reuse:** the proximity pattern from `RoundManager.findPassTarget` for the pad;
`Arena.build()`/`preview()` as the shape for `Lobby.luau`; `TestRange` as an
already-working practice range; the orbit spectator camera.

### Verification

1. A joining player appears in the **lobby**, never the arena.
2. Touching the pad queues you; walking away keeps you queued. Assert membership
   server-side, not by eye.
3. Round start moves **only queued players**. A non-queued player stays in the
   lobby, untouched by the bomb.
4. **Isolation — the point of this stage.** With a round running and a second
   player standing in the lobby, trigger each beacon in turn and assert on the
   lobby player: floor friction unchanged, gravity effect absent, body scale
   still 1, controls not inverted. This needs **two clients**
   (Test → Clients and Servers), so it cannot be checked solo.
5. **Practice abilities actually fire.** A silent rejection looks identical to
   success on the HUD — assert the character's velocity changed, not just that
   the slot emptied.
6. Elimination → orbit camera → back in the lobby at round end.
7. Regression: a full round still runs clean, no console errors.

---

## If queue times ever become a real problem

In order, and only with evidence:

1. **Dedicated match servers** via `TeleportService` and reserved servers. The
   well-trodden Roblox path, and it leaves this codebase almost untouched.
2. **Concurrent arenas in one server** — only if teleport latency or the loading
   screen is measurably hurting the experience. This is the one that permanently
   complicates every server module.

---

## Stages after this — sketched, not planned

- **Stats and scoreboard.** Survive time, passes and abilities used are fully
  trustworthy; the server already owns them. `OrderedDataStore` for the global
  board. Robux spend is possible, but Roblox keeps no purchase history for you,
  so it is only ever as accurate as your own saving.
- **Monetization.** Cosmetic fart variants are close at hand — the particles are
  already config-driven. The jukebox is blocked on audio rights, not code.
- **Obby** — checkpoints, timer, records on the same OrderedDataStore work.
- **Real maps** — lobby and arena together, following `MAP_INTEGRATION.md`.

Worth saying plainly: these are the first work here that can lose real player
data or real money. The arena could only ever produce a funny explosion.

---

## Also deliverable — DONE

`PLANNING_PROMPT.md` is written and committed. Nothing to do here.
