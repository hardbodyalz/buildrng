# Build & Defend RNG

A Roblox **RNG + base-building + tower-defence + idle** game:

**ROLL → COLLECT → BUILD → DEFEND → EARN → UPGRADE → ROLL AGAIN**

This repository contains the **first playable vertical slice** (design spec §57): one plot per player, a Core, grid building, a player-shaped enemy route, 12 structures, 5 enemy types, 10 hand-authored waves plus an infinite procedural wave generator, a multi-phase boss, server-authoritative rolling with luck, pity and mutations, an inventory, an Index, coins, session-locked saving and offline progress.

Everything is built in code. There are no hand-made assets: structures, enemies, plots and UI are generated from data, so new content is mostly a matter of adding config entries.

See [`docs/DESIGN.md`](docs/DESIGN.md) for the game design, balance numbers and the roadmap for the rest of the spec.

## Running it

Requires [Rojo](https://rojo.space) 7.7 (`aftman install` installs it from `aftman.toml`).

```bash
rojo build -o buildrng.rbxlx     # build a place file, open it in Roblox Studio
rojo serve                       # or live-sync into an open place
```

The world (hub, plots, lighting) is generated at runtime. You don't need to set anything up in Studio.

**Saving in Studio:** turn on *Game Settings → Security → Enable Studio Access to API Services*. If it's off, the server falls back to an in-memory store, warns in the output, and shows a toast in-game.

## How to play

| | PC | Mobile |
|---|---|---|
| Roll | **ROLL** button or `E` | tap **ROLL** |
| Auto-roll | **AUTO** toggle (pauses on Epic+) | same |
| Build mode | **BUILD** button or `B` | tap **BUILD** |
| Place | pick an item in the hotbar, then click a tile | tap a tile, then **PLACE HERE** |
| Rotate / cancel | `R` / `Q` | on-screen buttons |
| Camera (build) | right-drag to pan, mouse wheel to zoom | drag / pinch |
| Upgrade, move, store | click a placed structure | tap a placed structure |
| Defend | **START DEFENCE** (top-left) | same |

The tutorial walks through the first loop in about 2 minutes. Other features unlock as you progress (Index → Upgrades → Expansion → Mutations → Lucky Rolls).

## Architecture

```
src/
  shared/                     ReplicatedStorage.Shared   (pure data + maths, used by both sides)
    Config/                   ALL content and tuning: Items, Enemies, Waves, Rarities,
                              Mutations, Progression (expansions/upgrades/unlocks/pity), Sounds, GameConfig
    Util/                     Grid, FlowField (enemy routing), RollMath, Luck, ItemStats,
                              WaveGen, ModelBuilder (data -> Models), Signal, Format, ...
    Net/Remotes.luau          the single list of remotes + their rate-limit buckets
  server/                     ServerScriptService.Server
    init.server.luau          ServerMain: Init() every service, then Start()
    Services/                 Data, Economy, Progression, Inventory, Roll, Plot, Base, Defense, Offline
    Sim/                      DefenseSim (pure tower-defence simulation), OfflineSim
    Util/                     Net (remote wrapper), RateLimiter, Validate
  client/                     StarterPlayerScripts.Client
    init.client.luau          ClientMain: boot controllers, request initial state
    Controllers/              Hud, Roll, Inventory, Index, Shop, Build, Defense,
                              EnemyRenderer, Fx, Offline, Tutorial, Notify, Sound
    UI/                       UI kit (builder + components) and Theme
tests/                        headless Luau test suites + Roblox mock
```

Key decisions:

- **The server decides everything.** Rolls, rewards, inventory, placement, combat and trading-relevant state never trust the client. Every remote is validated, rate-limited, and returns `{ ok, err }` (`server/Util/Net.luau`).
- **Combat is a pure simulation.** `DefenseSim` has no Roblox instances. Enemies exist only as data on the server and are replicated as compact 10 Hz snapshots, and clients render them with pooled models (`EnemyRenderer`, using `BulkMoveTo`). No physics, no server-side enemy parts.
- **Offline progress uses the same simulation.** `OfflineSim` runs the real `DefenseSim` once, headless, to measure what the base can hold, then extrapolates. A better layout means better offline rewards.
- **Routing comes from the layout.** `FlowField` runs Dijkstra from the Core. Walls are expensive to walk through but never impassable, so enemies walk your maze (or smash through when that's shorter), and brutes and enraged bosses prefer smashing. Build mode draws the predicted route live.
- **Data-driven behaviours.** Items pick a generic `Behavior` (`SingleTarget`, `Splash`, `Pierce`, `Chain`, `Aura`, `Trap`, `Support`, `Generator`, `Wall`), so adding 100 items is 100 config entries.
- **Safe saving.** UpdateAsync only, with session locking (duplication protection), migrations and reconciliation. A profile that failed to load is never saved; the player is kicked instead, so a DataStore outage can't wipe data.

## Adding content

| To add... | Edit |
|---|---|
| a structure / weapon / trap | `Config/Items.luau` (stats, behaviour, footprint, part-list model) |
| an enemy | `Config/Enemies.luau`; set `MinWave` so procedural waves start using it |
| a boss | `Config/Enemies.luau` with `IsBoss` + `Phases`, then add its id to `Waves.Bosses.Rotation` |
| a mutation | `Config/Mutations.luau` (odds, stat/value multiplier, look) |
| a rarity tier | `Config/Rarities.luau` |
| a wave modifier | `Waves.Modifiers` (the sim applies Health/Speed/Armor/Regen/Structure damage multipliers) |
| an upgrade / expansion / unlock | `Config/Progression.luau` |

## Tests

The pure modules, the sim, the server services and the client controllers all run headlessly with the [`luau`](https://github.com/luau-lang/luau/releases) CLI:

```bash
python3 tests/run.py path/to/luau            # all suites
python3 tests/run.py path/to/luau sim        # filter by file name
```

- `rng.spec` checks odds normalisation, luck curves, the empirical distribution, pity guarantees and mutation rates.
- `grid.spec` checks placement rules (green, yellow and red) and flow-field routing and detours.
- `sim.spec` checks balance: how far each layout gets, whether upgrades matter, boss phases, determinism and offline estimates.
- `server.spec` runs the server end to end on a Roblox mock: join, roll, place, defend, upgrade, sell, save and lock release, the offline report, a foreign session lock, stale-lock takeover, and a DataStore outage.
- `server_client.spec` runs the real client and server together with remotes looped back: the tutorial flow, roll animation, windows, build-mode placement, the defence HUD, every FX event type and the offline screen.

`tests/mock/Roblox.luau` is a small engine mock (instances, signals, a virtual-clock `task` scheduler, CFrame maths, an in-memory DataStore). It approximates Roblox, so final visual and feel testing still belongs in Studio.
