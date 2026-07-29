# Reusable prompt: iterative feature design

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
