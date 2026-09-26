# Build & Defend RNG: Design Notes

This document covers what the vertical slice implements, why it works the way it does, the current balance, and how the remaining spec systems plug into the existing architecture.

The goal is to deliver three feelings at once, and every system below is judged against them:

- **"What will I roll?"** RNG anticipation.
- **"How do I use it?"** Strategic placement.
- **"How far can my base go?"** Long-term progression.

---

## 1. Slice scope (spec §57)

| Slice requirement | Implementation |
|---|---|
| 1 player plot | 6 plots around a hub, one per player (`PlotService`) |
| 1 Core | 3×3 Core at the fixed +Z end of every plot; HP is upgradeable |
| 10 defensive objects | 12 items, Common → Mythic, plus 1 secret (`Config/Items`) |
| 5 enemy types | Walker, Runner, Swarmling, Brute, Shieldbearer (`Config/Enemies`) |
| 10 waves | 10 hand-authored waves, then an infinite procedural generator (`Config/Waves`, `Util/WaveGen`) |
| 1 boss | The Colossus: 4 HP-based phases, summons, a wall-breaking phase and a rage phase |
| RNG rolling | Server-authoritative, with weighted rarity, luck, pity and mutations (`RollService`, `Util/RollMath`) |
| Inventory | Stacks with lock, favourite, sell, mass-sell, category tabs, search and sort |
| Grid placement | Snapping, rotation, move, store, green/yellow/red preview, live enemy-route preview |
| Coins | Earned from kills, wave clears, Coin Presses, selling and offline play |
| Basic saving | Session-locked UpdateAsync with retries, migrations and reconciliation |
| Basic offline rewards | A headless run of the real simulation, extrapolated (see §6) |

Also included because they cost little and make the slice feel complete: the Index with collection luck rewards, permanent upgrades, 7 base-expansion tiers, progressive unlocks, a sub-3-minute tutorial, Dice and Lucky Rolls, and global announcements for rare pulls.

---

## 2. The core loop in the first five minutes

1. **Roll.** The first roll is scripted to give a Scrap Turret (and the second a Wooden Barricade), so the tutorial always has something to place.
2. **Inventory → PLACE.** Build mode opens with the item selected. The red route shows where enemies will walk.
3. **Place** the turret beside the route. The preview is green when valid, yellow when legal but questionable (for example a trap that isn't on the route), and red when invalid, with a reason.
4. **START DEFENCE.** Wave 1 is six Walkers. One turret beside the route kills all six (`sim.spec` verifies this).
5. **Reward.** You get coins per kill plus a wave-clear bonus, with pop-ups and a banner.
6. **Roll again.** Free rolls on a cooldown mean the loop never stalls on currency.

After that the pressure points arrive in order:

| Wave | What changes |
|---|---|
| 3 | Swarms (traps shine) |
| 4 | Runners, Brutes |
| 6 | Shieldbearers (armour punishes the Machine Gun and rewards the Cannon) |
| 10 | The Colossus |

A one-turret base cannot survive, so the player learns to reshape the route with walls and to upgrade.

---

## 3. RNG

**Odds.** Each rarity has a conceptual `OneIn`. The actual odds are the normalised weights of the rarities that currently have rollable items, so empty tiers never swallow rolls, and the UI (Odds window) always shows the true "1 in N".

**Luck, in two layers:**

1. **Sources combine with diminishing returns.**
   - `raw = upgradeTrack × (1 + collection bonuses) × temporary multipliers`
   - Above a soft cap of 5, `effective = 5 × (raw/5)^0.55`, with a hard cap of 250.
   - The upgrade track follows the spec: 1 → 1.25 → 1.5 → 2 → 3, then +0.4 steps.
2. **Each rarity responds with `luck ^ LuckScaling`.**
   - Common 0, Uncommon 0.3, Rare 0.6, Epic 0.85, Legendary and above 1, Secret 0.5.
   - Luck moves probability mass upward instead of multiplying everything linearly, and secrets stay secret.

**Pity** (`Progression.Pity`): per-tier counters that reset when you hit that tier or better.

| Tier | Soft boost starts | Guaranteed at |
|---|---|---|
| Epic | 80 | 200 |
| Legendary | 500 | 1500 |
| Mythic | 1000 | 2500 |

The counter closest to triggering is shown under the ROLL button.

**Mutations** are an independent second roll, checked rarest first:

| Mutation | Odds | Stats |
|---|---|---|
| Golden | 1/40 | ×1.5 |
| Shiny | 1/150 | ×2 |
| Corrupted | 1/600 | ×3 |
| Galaxy | 1/2 500 | ×5 |
| Glitched | 1/10 000 | ×8 |
| Void (secret) | 1/50 000 | ×15 |

Mutations respond to `luck^0.5`. They change stats, sell value and the model's colours, material, glow and particles. They unlock at wave 6, so the first session stays readable.

**Reveal escalation** (`RollController`): the spin length is roughly fixed, so it doesn't leak the rarity. Epic and above get a tension pulse. Legendary and above get a flash and an FOV punch. Mythic and above add screen shake and a banner. Server-wide announcements go out for Mythic+ or Galaxy+ mutations. Commons stay quick and quiet.

---

## 4. Building and routing

- The grid is at most 21×25 cells (4 studs each). Expansions grow the active area outward from a fixed Core, so placed structures never move.
- **Flow field:** Dijkstra from the Core, where entering a cell costs `1 + structureHP × PathCostPerHp × enemyCostMult`.
  - Nothing is ever impassable, so the player can never "soft-lock" the path.
  - A stone wall (700 HP) costs about 29 steps, so enemies walk a long detour instead of smashing it. A barricade (150 HP) costs about 7 steps, so enemies smash it if the detour is long.
  - Brutes (`PathCostMult 0.6`) and the Colossus' Wallbreaker phase (0.15) prefer smashing.
  - Mazes are real strategy: the same four turrets do far more when enemies zig-zag past them.
- Enemies re-route whenever the layout changes: something built, a wall destroyed, or a wall restored.
- Destroyed structures become rubble until the wave ends, then rebuild for free. The player keeps everything earned, and the base is fully restored after a run.

### Structure roles

| Item | Rarity | Role / counter |
|---|---|---|
| Wooden Barricade | Common | cheap maze wall; forces detours |
| Scrap Turret | Common | steady single target |
| Spike Trap | Common | walk-over AoE; the swarm counter |
| Coin Press | Uncommon | economy vs. space trade-off |
| Machine Gun Nest | Uncommon | fast and weak; bad vs. armour |
| Frost Beacon | Uncommon | slow field; buys time for everything else |
| Stone Wall | Rare | 3-wide, very high HP maze piece |
| Cannon | Rare | splash, targets the strongest; the armour and boss answer |
| War Drum | Epic | +30% damage and +15% speed aura; placement puzzle |
| Mortar | Epic | 2×2, range 8, min range 2, big splash |
| Prism Laser | Legendary | pierces every enemy in a line; rewards straight corridors |
| Tesla Coil | Mythic | chains up to 5 enemies |
| ??? | Secret | you'll know it when you see it |

A Common in the right place beats a Legendary in the wrong one. Spike Traps on the route outperform a badly placed Prism Laser against swarms.

---

## 5. Waves and the boss

Every wave `w` has:

- HP scale `1 + 0.07(w-1) + 0.0022(w-1)²` (polynomial, not exponential)
- reward scale `1 + 0.06(w-1)`
- clear bonus `10 + 4w + 0.05w²`

Procedural waves (11+) spend a threat budget `8 + 1.6w + 0.18·w^1.45` across 2–5 enemy groups, using a seeded RNG, so wave N is the same wave for everyone.

Instead of only piling on HP, later waves add **modifiers** (never on bosses):

| Wave | Modifier |
|---|---|
| 11 | Elite |
| 16 | Swift |
| 22 | Regenerating |
| 28 | Armoured |
| 35 | Enraged (wall damage) |

Bosses appear every 10 waves and cycle through `Waves.Bosses.Rotation`. Each later cycle adds +35% HP, and every 50th wave adds ×2.5.

**The Colossus:**

| Phase | Trigger | Behaviour |
|---|---|---|
| 1 | spawn | slow march |
| 2 | 75% HP | summons Walkers |
| 3 | 50% HP | Wallbreaker: ×4 structure damage, prefers smashing |
| 4 | 25% HP | RAGE: ×1.9 speed, summons Runners |

Each boss has a health bar, phase banners, screen shake, optional music (`MusicId`) and a Dice reward.

### Measured balance (`sim.spec`, tier-1 base)

| Layout | Result |
|---|---|
| Empty base | falls at wave 3 |
| 1 turret beside the route | clears wave 1 cleanly |
| Starter (3 turrets, a trap, a barricade, an MG) | clears ~7 |
| 10-piece maze at level 1 | clears 9, loses to the boss |
| Same maze at level 3–5 | survives the boss, walls at ~19 |
| Same maze at level 8 | kills the boss, reaches 25+ |

Upgrades, layout and rarity all move the needle.

---

## 6. Offline progression

Offline progress doesn't simulate hours of enemies. `OfflineSim` runs the **real** `DefenseSim` once, headless, at a coarse 0.25 s step, from wave 1 until the Core falls (capped at 60 waves / 40k steps, yielding every 400 steps).

- The run's **cleared** waves define what the base can reliably hold, and how long that takes.
- The time away (capped at 8 h) counts as repeated runs × 50% efficiency.
- The return screen shows: time away, waves, enemies, coins, XP, Dice, bosses, the best wave held, and the Core HP left after the last cleared wave.
- A base that can't clear wave 1 still earns a 20% consolation share, with a floor of 120 coins/hour. The player never loses progress.
- `LastOnline` moves forward in the same profile that receives the rewards, so the report can never be granted twice.

---

## 7. Economy

| Currency | Earned from | Spent on |
|---|---|---|
| Coins | kills, wave clears, Coin Press, selling, offline | structure levels, permanent upgrades, base expansions |
| Dice | bosses, offline boss kills | Lucky Rolls (×2 luck) |

Rolling is free on a cooldown. Roll Speed is an upgrade track, which is the natural place for a "Fast Roll" pass later.

Future currencies stay scoped: Relics are boss-only progression items, and each world gets one currency. See §9.

---

## 8. Security and data

- Every remote goes through `server/Util/Net.luau`, which applies:
  - a profile-loaded check
  - per-player token-bucket rate limiting (`GameConfig.RateLimits`)
  - pcall isolation
  - a uniform `{ ok, err }` response
- Arguments are type- and range-checked (`Validate`), and inventory keys are parsed against config.
- Roll cooldown, placement legality, ownership, sell locks, upgrade costs, unlocks and rewards are all server-side. The client preview is only a hint.
- `DataService`:
  - UpdateAsync with a session lock `{ JobId, Time }`
  - retries, then a kick, while another server holds a fresh lock
  - takes over locks older than 5 minutes (a crashed server)
  - never saves a profile that failed to load
  - stops saving and kicks if the lock is lost mid-session
  - autosaves every 60 s, saves in BindToClose, and runs versioned migrations plus template reconciliation

---

## 9. Roadmap: the remaining spec, mapped onto this architecture

Each system has a home, and none of them needs a rewrite.

| Spec | System | Where it plugs in |
|---|---|---|
| §16 | **Crafting** | `Config/Recipes` (inputs → item id). A `CraftingService` validates and consumes inventory stacks and currencies; the UI is a new window. Items gain `Rollable = false` for craft-only blueprints. |
| §15, §17 | **Relics and boss drops** | Boss defs get a `Drops` table, rolled in `DefenseService` on boss kill. Relics live in `data.Relics`. `ProgressionService` folds relic bonuses into luck (Additive), damage/HP (a new sim-wide multiplier passed to `DefenseSim.new`), and capacity. |
| §18 | **Heroes** | A new placeable category with `Behavior = "Hero"`: aura buffs (Commander), repair ticks (Engineer), Core heals (Medic). Heroes use the same sim hooks as Support/Aura structures. Level and skill tree go in `data.Heroes`. |
| §19–20 | **Worlds** | `Config/Worlds` (theme, enemy pool, boss rotation, currency, roll pool filter). `RollService` already builds pools per world (`pools.Greenland`), and `WaveGen` takes a world's enemy list. Plot terrain styles are already data-driven. |
| §26–27 | **Fusion** | "3 of rarity N → 1 of N+1", as a remote on `InventoryService` using the same stack keys. |
| §28 | **Prestige** | `data.Prestige` gives a permanent luck multiplier (a `Luck.Multipliers` source), capacity, offline efficiency (`OfflineSim` param) and prestige-only pools (item `World`/filter). The reset clears Coins, Upgrades and Base tier and keeps the Index. |
| §29–30 | **Events** | `Config/Events` holds timed global modifiers: roll pool additions, mutation chance multiplier (`PickMutation`'s `chanceMultiplier`), wave modifiers, reward multipliers. An `EventService` broadcasts the active event. |
| §31 | **Trading** | A `TradingService` state machine: offer → both lock → countdown → both confirm → atomic swap. Offers are immutable once locked, and a re-lock resets confirmation. Stacks and placed-structure snapshots are transferable. It needs a cross-profile atomic save (both profiles are in one server). |
| §32–33 | **Social and leaderboards** | Plots already replicate their defence state to every nearby player (Core billboards, enemy snapshots, FX), so watching works today. Leaderboards read `data.Stats` into OrderedDataStores on save. |
| §34–35 | **Quests and daily login** | `Config/Quests` holds counters on existing stats (`TotalRolls`, `EnemiesDefeated`, `WavesCleared`...). A `QuestService` snapshots stats at assignment and compares. |
| §38–39 | **Layouts and presets** | `data.Base.Layouts[n] = Structures` snapshots. Switching validates against inventory counts, with a cooldown to prevent abuse. |
| §49 | **Monetisation** | `MarketplaceService.ProcessReceipt` in a `ShopService`. Luck boosts become temporary `Luck.Multipliers` sources; Fast Roll becomes a RollSpeed floor. No direct sales of ultra-rares. |

### Content still to author (spec §46 targets)

The slice ships 12 structures, 5 enemies and 1 boss. The generic behaviours already cover walls, turrets, cannons, machine guns, mortars, slow fields, lasers, chain weapons, buff towers and generators. Reaching the launch targets (50 defences, 30 weapons, 20 traps, 10 bosses, 5 worlds) is config authoring plus a few new behaviours:

- `Summoner` / `Healer` enemy abilities (a sim `Abilities` list)
- flying enemies (straight-line movement that ignores the flow field, plus an `AntiAir` targeting flag)
- invisible enemies (a `Detection` stat)
- `Splitter` (spawn on death)

### Audio and visual polish

Sounds default to engine-bundled `rbxasset://` sounds, pitch-shifted per rarity. Replace them with uploaded ids in `Config/Sounds` (and boss `MusicId`) to give each rarity and boss its own audio identity.
