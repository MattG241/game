# Underground Arena Fighters

A production-ready MVP for a competitive 1v1 / 2v2 underground arena fighting
game on Roblox. Server-authoritative combat, matchmaking, a best-of-3 round
system, progression, cosmetics, DataStore persistence, and full monetization —
all written as clean, commented Luau and mapped to Studio via **Rojo**.

Everything is **playable out of the box**: arenas and the lobby are built
procedurally and all UI is generated from code, so you don't need to model or
design a single asset to test the full game loop.

---

## 1. Project structure

The repo is a [Rojo](https://rojo.space) source tree. `default.project.json`
maps these folders into the Roblox DataModel:

```
ReplicatedStorage/Shared/         (src/shared)
├── GameConfig        — every tunable value (combat, rounds, rewards, IDs)
├── Remotes           — single registry of all RemoteEvents/Functions
├── Progression       — XP curve + reward math (pure functions)
├── Cosmetics         — skin/outfit catalogue (data-only)
└── Arenas            — arena defs + procedural arena/spawn builder

ServerScriptService/Server/       (src/server)
├── init.server       — bootstrap: atmosphere, lobby, service start order
├── DataService       — DataStore wrapper: session locks, retries, autosave
├── PlayerService     — player lifecycle, leaderstats, profile sync, rewards
├── CombatService     — SERVER-AUTHORITATIVE combat, hit detection, KO/ragdoll
├── MatchmakingService— queue, match creation, best-of-3 round loop
└── MonetizationService — gamepasses + dev products (ProcessReceipt)

StarterPlayer/StarterPlayerScripts/Client/   (src/client)
├── init.client       — bootstrap: starts all controllers
├── CombatController  — input → combat requests (PC + mobile via ContextAction)
├── HUDController     — health/stamina/special/combo/timer/score + toasts
├── MenuController    — top bar, FIGHT/queue button, shop, inventory, leaderboard
└── EffectsController — hit sparks, special bursts, sounds, camera shake
```

### Architecture principles
- **Server authority everywhere.** Clients only ever *request* actions
  (`RequestPunch`, `RequestDodge`, …). The server validates cooldowns, stamina,
  range, and i-frames before applying any damage. A hacked client can spam
  requests but cannot deal illegitimate damage.
- **One config file.** Rebalancing the game means editing `GameConfig.lua` only.
- **One remote registry.** `Remotes.lua` is the single audit point for the
  entire client→server surface area.
- **Data safety.** `DataService` uses per-player session locking and refuses to
  overwrite data it couldn't authoritatively load (prevents rollbacks/wipes).

---

## 2. Setup

### Option A — Rojo (recommended)
1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) and
   the Rojo Studio plugin.
2. From the repo root: `rojo serve`
3. In Studio: open the Rojo plugin → **Connect**. The tree syncs in live.
4. Press **Play**. You spawn in the lobby; press **FIGHT** to queue.

> Testing matchmaking needs 2 players. Use Studio's
> **Test → Clients and Servers → 2 players** local server.

### Option B — no Rojo
Recreate the folder structure above by hand in Studio and paste each file into a
matching `Script` / `LocalScript` / `ModuleScript`:
- `init.server.lua` → a `Script` in `ServerScriptService`
- `init.client.lua` → a `LocalScript` in `StarterPlayerScripts`
- everything else → `ModuleScript`s in the folders shown above.

---

## 3. Filling in your IDs (monetization)

Open `src/shared/GameConfig.lua` → `GameConfig.Monetization` and replace every
`0` with the real asset IDs from the
[Creator Dashboard](https://create.roblox.com):

```lua
Gamepasses = { VIP = 0, DoubleRewards = 0, SkinPack = 0 },
Products   = { Coins500 = 0, Coins1200 = 0, Coins3000 = 0 },
```

- **VIP** and **DoubleRewards** automatically apply their reward multipliers.
- **SkinPack** auto-grants every cosmetic whose `unlock == "gamepass"`.
- **Products** grant Fight Coins via `ProcessReceipt` (amounts in
  `ProductCoinGrants`).

No IDs? The game still runs — purchase buttons simply do nothing.

---

## 4. Asset placement guide

**Nothing is required** — the lobby and all three+ arenas build themselves at
runtime, and every GUI is generated from code. To upgrade visuals later:

| Asset | How to add |
|---|---|
| **Hand-built arena** | Model it, set `prebuilt = true` on its entry in `Arenas.lua`, and drop the model under `Workspace/Arenas/<id>`. The builder reuses yours instead of generating one. |
| **Sound effects** | Put `rbxassetid://…` strings into the `SOUNDS` table in `EffectsController.lua` (`punch`, `finisher`, `special`, `dodge`, `block`). |
| **Skins** | Add entries to `Cosmetics.List`. Each is data-only (body color, accent, material, unlock rule) and instantly appears in shop + inventory. |
| **Particles / VFX** | Extend `EffectsController.spawnHitSpark` or add emitters keyed off `CombatFeedback` kinds. |
| **Music / ambience** | Add a looping `Sound` in `SoundService`; respect `profile.settings.musicEnabled`. |

The concept-art PNGs in the repo root are reference only and are not used by the
game.

---

## 5. Controls

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Punch / combo | LMB | R2 | on-screen PUNCH |
| Block | Hold RMB | L2 | on-screen BLOCK |
| Dodge (roll) | Q | L1 | on-screen DODGE |
| Special (meter full) | E | R1 | on-screen SPECIAL |

Combos chain up to 4 hits; the 4th is a high-damage finisher with extra
knockback. Dodging grants brief i-frames. Blocking absorbs 80% damage but drains
stamina; a fully drained block breaks for a guard-break punish.

---

## 6. Testing checklist

- [ ] Two test clients can queue and a 1v1 match starts on a random arena.
- [ ] Countdown → FIGHT banner → combat enables only after the countdown.
- [ ] Punch combo counter climbs 1→4 and the 4th hit launches the opponent.
- [ ] Blocking reduces damage and drains stamina; guard break works.
- [ ] Dodge moves you and grants i-frames (hit during dodge deals 0).
- [ ] Special only fires at a full meter and resets it.
- [ ] KO (or ring-out via kill plane) ends the round and updates the score.
- [ ] Best-of-3 resolves; VICTORY/DEFEAT shows; XP + coins awarded.
- [ ] Level-up unlocks level-gated cosmetics automatically.
- [ ] Buying a coin-priced skin deducts coins, equips, and persists on rejoin.
- [ ] Leaderstats (Level/Wins/Coins) and the in-game leaderboard update.
- [ ] Data persists across a rejoin; session lock blocks double-load.
- [ ] Dev product purchase grants coins via ProcessReceipt (Studio API test).
- [ ] Mobile buttons appear and drive all four actions.

---

## 7. Future expansion ideas

- **Ranked mode** with an MMR/ELO ladder and seasonal resets.
- **2v2 / team play** — already structured: set `Matchmaking.TeamSize = 2`.
- **Reserved-server matches** via `TeleportService` (swap `assignArena` /
  `returnToLobby` in `MatchmakingService`).
- **More moves**: heavy attacks, grabs, parries, directional specials.
- **Move/skill unlock tree** spending Fight Coins (hook into `Progression`).
- **Tournaments / brackets** with spectator mode.
- **Replay highlights**: record the last few seconds of a KO and replay it on the
  death screen (the `CombatFeedback` stream is a good capture source).
- **Daily quests & login streaks** for retention.
- **Cosmetic rarities & crates**, trails, KO effects, victory poses.
- **Private servers** with custom rules (already supported by Roblox; gate via a
  VIP-only arena pool).

---

## 8. Balancing

All combat/round/reward numbers live in `GameConfig.lua`. Common knobs:

- Faster fights: raise `Combat.PunchDamage` or lower `Round.RoundTime`.
- More defensive meta: raise `Combat.BlockDamageReduction`,
  lower `Combat.StaminaRegenPerSecond`.
- Reward economy: tune `Progression.Rewards` and the XP curve
  (`BaseXP`, `XPGrowth`).
