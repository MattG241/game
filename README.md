# Underground Arena Fighters

A production-ready MVP for a **Super Smash Bros-style platform fighter** on
Roblox, with an underground-neon skin. Server-authoritative combat built on a
**damage-percent + knockback + ring-out** model, **stock** matches, matchmaking,
progression, cosmetics, DataStore persistence, and full monetization — all
written as clean, commented Luau and mapped to Studio via **Rojo**.

**How a fight works:** attacks don't drain health — they pile on a **damage %**.
The higher your %, the farther the next hit launches you. You only get KO'd by
being knocked off the stage into a **blast zone**, and each KO costs a **stock**
(life). Last fighter with stocks left wins.

Everything is **playable out of the box**: arenas and the lobby are built
procedurally and all UI is generated from code, so you don't need to model or
design a single asset to test the full game loop.

---

## 1. Project structure

The repo is a [Rojo](https://rojo.space) source tree. `default.project.json`
maps these folders into the Roblox DataModel:

```
ReplicatedStorage/Shared/         (src/shared)
├── GameConfig        — every tunable value (combat, stocks, rewards, IDs)
├── Remotes           — single registry of all RemoteEvents/Functions
├── Animations        — animation ID registry + player/cacher + hit-stop freeze
├── Progression       — XP curve + reward math (pure functions)
├── Cosmetics         — skin/outfit catalogue (recolor + optional catalog items)
└── Arenas            — stage defs + procedural stage/blast-zone/spawn builder

ServerScriptService/Server/       (src/server)
├── init.server       — bootstrap: atmosphere, gravity, lobby, service order
├── DataService       — DataStore wrapper: session locks, retries, autosave
├── PlayerService     — lifecycle, leaderstats, profile sync, rewards, skins
├── CombatService     — SERVER-AUTHORITATIVE %/knockback/launch, anims, hit-stop
├── MatchmakingService— queue + stock matches (respawns until stocks run out)
└── MonetizationService — gamepasses + dev products (ProcessReceipt)

StarterPlayer/StarterPlayerScripts/Client/   (src/client)
├── init.client       — bootstrap: starts all controllers
├── CombatController  — input → combat requests (PC + mobile via ContextAction)
├── HUDController     — per-fighter %/stock panels, shield/special/combo, timer
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
| **Animations** | Paste `rbxassetid://…` strings into `Animations.Ids` in `Shared/Animations.lua` (`punch1/2/3`, `finisher`, `block`, `dodge`, `special`, `hit`). Grab free ones from the Toolbox or make them in the Animation Editor. Empty = no-op, so combat works without them. |
| **Skins** | Add entries to `Cosmetics.List`. Recolor-only by default; add optional `shirtId` / `pantsId` / `accessoryIds` (free catalog asset IDs) for detailed skins via HumanoidDescription. Instantly appears in shop + inventory. |
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

Combos chain up to 4 hits; the 4th is a launching finisher. Higher damage % =
farther launches, so finishers KO at high %. Dodging grants brief i-frames.
Shielding absorbs most of a hit's % and knockback but drains stamina; a fully
drained shield breaks for a big launch punish. **Jump off-stage to recover** —
gravity is floaty and jumps are high for that platform-fighter feel.

---

## 6. Testing checklist

- [ ] Two test clients can queue and a 1v1 match starts on a random stage.
- [ ] Countdown → "GO!" banner → combat enables only after the countdown.
- [ ] Punch combo counter climbs 1→4; the 4th hit launches the opponent.
- [ ] Damage % climbs with hits and the % label recolors white→red.
- [ ] Launch distance scales with % (a 100%+ fighter goes flying).
- [ ] Getting knocked into a blast zone = a KO and costs one stock.
- [ ] Losing a stock respawns you (with brief invuln) until stocks hit 0.
- [ ] Last fighter/team standing wins; VICTORY/DEFEAT shows; XP + coins awarded.
- [ ] Match timeout decides by most stocks, then lowest %.
- [ ] Shielding reduces %/knockback and drains stamina; shield break works.
- [ ] Dodge moves you and grants i-frames (hit during dodge deals nothing).
- [ ] Special only fires at a full meter and resets it.
- [ ] Stock icons + both fighters' % render correctly in the HUD.
- [ ] Level-up unlocks level-gated cosmetics automatically.
- [ ] Buying a coin-priced skin deducts coins, equips, and persists on rejoin.
- [ ] Leaderstats (Level/Wins/Coins) and the in-game leaderboard update.
- [ ] Data persists across a rejoin; session lock blocks double-load.
- [ ] Dev product purchase grants coins via ProcessReceipt (Studio API test).
- [ ] Mobile buttons appear and drive all four actions.
- [ ] (Optional) Animation IDs play on punch/finisher/block/dodge/special.

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

All combat/match/reward numbers live in `GameConfig.lua`. Common knobs:

- **KO speed**: raise `Combat.KnockbackGrowth` / `BaseKnockback` for earlier
  KOs, or lower them so fights last longer.
- **Hit damage**: `Combat.PunchPercent`, `SpecialPercent`,
  `ComboFinisherMultiplier`.
- **Match length**: `Match.Stocks`, `Match.MatchTime`.
- **Feel**: `Combat.Gravity` (lower = floatier), `Combat.JumpPower`,
  `Combat.WalkSpeed`, `Combat.HitStop` / `HeavyHitStop` (impact freeze).
- **Defensive meta**: `Combat.BlockKnockbackReduction`,
  `BlockPercentReduction`, `StaminaRegenPerSecond`.
- **Reward economy**: `Progression.Rewards` and the XP curve
  (`BaseXP`, `XPGrowth`).
- **Stage size / blast distance**: per-stage `size` in `Arenas.lua`.
