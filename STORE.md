# The store

Everything about selling things: what exists, how to make it real, and what not
to sell.

Right now **nothing can be bought.** The machinery is built and switched off. It
takes about ten minutes to turn on, and the steps are below.

---

## What is for sale

Five fart colours. That is all, and deliberately so.

| Colour | Suggested price | Looks like |
|---|---|---|
| Classic Green | 25 | The original |
| Bubblegum | 25 | Bright pink — **plus extra effects**, see below |
| Deep Freeze | 25 | Pale blue |
| Solid Gold | 99 | Yellow-gold |
| Full Spectrum | 149 | Red into blue |

They change the colour of **everything you leave behind** -- both the fart jump's
puff and the dash's trail. One purchase covers both, so a colour somebody paid
for is never half applied. Nothing else changes.

## Bubblegum gets more than a recolour

The other four change colour and nothing else. Bubblegum is the showpiece, to see
whether a visibly fancier item is worth building more of. On top of the ordinary
cloud it gets four layers:

| Layer | What it does |
|---|---|
| **Bubbles** | Big, nearly see-through, and they **rise** instead of billowing — that one property is what makes them read as bubbles rather than exhaust |
| **Glitter** | Tiny bright sparks thrown outwards, gone in half a second. This is the layer that makes it look expensive |
| **Shockwave** | A ring blown outwards and faded in a quarter of a second, on the jump only. The dash gets a stream instead, since it paints a path rather than marking one spot |
| **Pink flash** | A light that blooms and dies, so the burst lights its surroundings for an instant instead of looking like a flat sticker |

All built from what Roblox ships — nothing to upload.

**Adding a fancy one later** is a two-line job: give the product a
`vfx = "SomeName"` in `Products.luau`, and add a branch for that name in
`src/server/CosmeticVfx.luau`. Anything without a `vfx` stays a plain recolour,
so the other four are untouched.

Every number is a dial in `Config.luau` under **BUBBLEGUM'S EXTRA EFFECTS**, and
`COSMETIC_VFX_ENABLED = false` turns the whole thing off to compare.

## The rule: cosmetic only

Nothing bought may change who wins a round.

The game keeps leaderboards for survival time, bombs passed and abilities used.
The moment something purchasable affects those, they stop measuring skill and
start measuring spending -- and the whole point of a competitive lobby is that
the boards mean something.

So: colours, trails, sounds, faces, hats, victory animations. **Not** extra
ability uses, longer dashes, head starts, or bomb immunity.

---

## Making it real

### 1. Create the products in Roblox

Creator Dashboard → your game → **Monetization → Developer Products → Create**.

One per colour. Set the name and the price. You will get an **ID** for each --
a long number.

**Developer Products, not Passes.** This matters and is not a style choice:

- A **Developer Product** can be bought repeatedly, and every purchase produces
  a *receipt* the game can act on. That receipt is the only way Roblox will ever
  tell your game that somebody spent money, which is what the "Biggest flexer"
  board counts.
- A **Pass** is bought once and produces no receipt. You can only ask "do they
  own it?", so spending can never be counted.

### 2. Paste the IDs in

Open `src/shared/Products.luau`. Each entry has `productId = 0`. Replace the `0`
with the ID from the dashboard:

```lua
{
    id = "GoldFart",
    productId = 1234567890,   -- <- was 0
    name = "Solid Gold",
    ...
}
```

`price` in that file is **only for showing in the game**. Roblox charges whatever
the dashboard says. If the two disagree the dashboard wins, so keep them in step
by hand.

### 3. Turn it on

In `src/shared/Config.luau`:

```lua
Config.PRODUCTS_ENABLED = true
```

### 4. Check it

Stop and restart Play, walk onto a pedestal in the lobby, and the Roblox purchase
window should open. In Studio you can buy without being charged.

**Leave any entry at `productId = 0` and it simply stays unbuyable** -- its
pedestal says "coming soon" and stepping on it says so. So you can release two
colours and add the rest later without touching anything else.

---

## How a purchase actually flows

Worth understanding, because it is the one part of this game where a mistake
costs a real person real money.

```
Player walks onto a pedestal
        ↓
Server opens Roblox's purchase window
        ↓
Player pays  →  Roblox sends the game a RECEIPT
        ↓
Game records it: unlocks the colour, adds the Robux to their total
        ↓
ONLY THEN does the game tell Roblox "yes, granted"
```

Two rules are built into that and should not be loosened:

**Never say yes until it is recorded.** Roblox keeps re-sending a receipt until
the game confirms it. Confirming before the save succeeds means a failed save
leaves somebody having paid for nothing, with no second chance. Every failure
path instead asks Roblox to send it again shortly.

**Never grant the same receipt twice.** Because Roblox re-sends until confirmed,
the same purchase arrives repeatedly by design. The check for "have I already
handled this one?" happens *inside* the same single save as the grant -- checking
beforehand leaves a gap that two deliveries can both slip through, and they can
even arrive on different servers.

---

## What the player sees

**In the lobby:** a row of pedestals along the west wall, each a different
colour, with a floating blob above it in that colour and its name and price.

**Walk onto one:**

| If you | Then |
|---|---|
| Do not own it | Roblox's purchase window opens |
| Already own it | You start wearing it |
| Already wear it | It says so |
| It has no ID yet | It says "not for sale yet" |

You have to step **off and back on** to trigger it again, so standing on a
pedestal does not reopen the window over and over.

**Whatever you are wearing is remembered** between sessions, along with
everything you own.

---

## Robux spend on the leaderboard

The "Biggest flexer" board shows Robux spent, with daily, weekly, monthly and
all-time versions.

**It can only ever count spending in this game, from the day the products go
live.** Roblox gives developers no purchase history, so:

- It will be empty until step 3 above is done
- It can never include anything bought before then
- It can never include Premium, other games, or Robux spent anywhere else

---

## The dials

All in `src/shared/Config.luau`.

| Dial | Now | What it does |
|---|---|---|
| `PRODUCTS_ENABLED` | `false` | The master switch. Nothing can be bought while this is off |
| `SHOP_SPACING` | 14 | Gap between pedestals, in studs |
| `SHOP_PAD_RADIUS` | 5 | How close you must get to trigger one |
| `SHOP_PROMPT_COOLDOWN` | 2s | Least time between purchase windows, so walking the row cannot stack them |

Prices live in `src/shared/Products.luau`, and the real ones live in the Creator
Dashboard.

---

## Where the code is

| File | What it does |
|---|---|
| `src/shared/Products.luau` | The catalogue: IDs, names, prices, colours |
| `src/server/Purchases.luau` | Handles receipts, remembers what people own |
| `src/server/Shop.luau` | The pedestals in the lobby |
| `src/server/StatsStore.luau` | Writes the purchase into the save file, and counts the Robux |

## Testing without spending money

There is a way to fake a purchase, so the whole path can be checked without
Robux changing hands. In Studio, with the game running, paste into the command
bar (**View → Command Bar**):

```bash
require(game.ServerScriptService.Server.Purchases).simulate(game.Players.YOURNAME, "GoldFart")
```

It goes through exactly the same recording path a real receipt does, including
the duplicate check. Replace `YOURNAME` with your username and `GoldFart` with
any `id` from `Products.luau`.

---

## Change log

| Date | Change | Why |
|---|---|---|
| 2026-07-30 | Store built, switched off | Machinery tested and dormant beats untested and live |
| 2026-07-30 | Five fart colours as the first products | The particles were already config-driven, so these were the closest thing to hand |
| 2026-07-30 | A colour now covers the dash trail as well as the fart jump | Only recolouring half of what you leave behind reads as broken, not as two separate items |
