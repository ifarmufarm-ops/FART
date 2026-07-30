# Prompts for working on this project

Two reusable prompts: one for picking the project back up after a break or a
context reset, one for running a new feature.

---

## Prompt 1: resuming work

```
We are picking up Hot Potato Bomb, a Roblox game at this repo. You have no
memory of previous sessions beyond your memory files and what is written here.

Read these first, in this order, before asking me anything or proposing work:
  1. HANDOVER.md          -- where the project is RIGHT NOW: what is built, what
                             is switched off and why, what has never been
                             verified, and what to do next. Start here
  2. README.md            -- what the game is and how to run it
  3. BALANCE.md           -- the numbers that change how it plays
  4. src/shared/Config.luau -- every tunable, commented in gameplay terms
  5. STORE.md             -- only if the task involves anything for sale
  6. STATS_PLAN.md        -- only if the task involves stats or leaderboards
  7. MAP_INTEGRATION.md   -- only if the task involves maps
  8. git log              -- the commit messages explain the whole build,
                             including what was measured and what was not

Then tell me, briefly:
  - what you understand the current state to be
  - what the agreed next step is
  - anything in the docs that looks stale or contradictory

Do NOT relitigate decisions already recorded in the docs or your memory. The
settled ones include: one place not two, no concurrent arenas, Low Gravity as a
per-character force, nothing purchasable affecting who wins, and survive time
counting only while alive in a round. If you think one is wrong, say so in a
sentence and let me decide -- do not silently redesign around it.

To get set up:
  - run `rojo serve` from the project root and ask me to click Connect in the
    Studio plugin. If rojo restarts, the plugin disconnects and syncs silently
    stop until I reconnect it
  - check which switches are on: TEST_MODE, SOLO_TEST_MODE, MOVEMENT_CORRECT and
    PRODUCTS_ENABLED should all be false in normal play
  - ALWAYS stop Play, confirm the synced source contains your change, then start
    Play. Rojo's push is not instant, and testing stale code has produced
    convincing false failures more than once
  - if you flip a switch to test something, flip it back and say so in the commit

Before proposing anything, ask me how the game actually FELT to play. Numbers
tell you the code works; only I can tell you whether it is any good.
```

---

## Prompt 2: iterative feature design

Paste this at the start of a new feature, replacing `[FEATURE]`. It encodes the
working pattern from the abilities, beacons and NPC stages — the one that kept
finding real bugs instead of shipping them.

---

```
I want to add [FEATURE] to the project.

BEFORE WRITING ANY CODE
- Read the project's own docs first (README.md, MAP_INTEGRATION.md,
  LOBBY_PLAN.md, src/shared/Config.luau) rather than asking me things they
  already answer.
- Flag assumptions and missing details. Ask me about anything where different
  readings would lead to materially different work -- in plain language, framed
  as gameplay consequences rather than implementation detail, and give me your
  recommendation rather than a survey of options.
- If part of what I asked for is contradictory or will not work, say so in a
  sentence and propose the nearest thing that will.

THEN
- Break it into stages that are each independently playable and testable. Tell
  me the staging before you start.
- Put every tunable number in Config, commented in terms of what it does to the
  game rather than what it does to the code.

WHILE BUILDING
- Verify each stage empirically in Studio before moving on. Actually run it and
  measure -- do not assert that it works.
- Stop Play, confirm the synced source, then start Play. Testing stale code has
  cost us real time more than once.
- When something does not work, diagnose with evidence before changing
  anything. Do not guess twice.

WHEN REPORTING
- Separate what you measured from what you assumed.
- Say plainly what you could NOT verify. Anything about how it looks or feels is
  mine to judge, not yours.
- If you found a real bug while testing, say what it was and what the
  measurement showed.
```

---

## Why each part is there

**Read the docs first.** This project documents itself deliberately, because
Elias is a PM rather than an engineer and should not have to be the memory.

**Ask before building.** Every stage that went smoothly started with three or
four plain-language questions. The one time a request was internally
contradictory — "rotate the dash trail 45 degrees so the line is horizontal",
where horizontal is 90 — saying so took one sentence and saved building the
wrong thing.

**Stage the work.** Each stage being playable meant problems surfaced while they
were still cheap.

**Measure, do not assert.** Testing caught things that looked fine in code and
were not: an NPC crawling at a fifth of its intended speed, a double jump
spending its charge for no visible effect, two of three abilities completely
unusable on a gamepad. None of those would have been found by reading the code.

**Say what you could not verify.** Numbers can show that limbs articulate 67
degrees. They cannot show whether the ragdoll *looks* right. That judgement is
the human's, and pretending otherwise wastes their time.
