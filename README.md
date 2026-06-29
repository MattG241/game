# Golden Century

A polished, playable Chinese-imperial slot game — configuration, evaluation
engine, and a browser front end built around the supplied art.

- **5 reels × 3 rows**
- **25 fixed paylines**, evaluated left-to-right on adjacent reels
- Emperor **Wild**, Golden Banner **Scatter** (Free Spins), Flaming Orb **Hold & Spin** bonus

## Play it

```sh
npm start        # serves the game at http://localhost:8080/web/
```

Then open the URL in a browser. Press **SPIN** (or the spacebar) to play.
The front end (`web/`) reuses the exact same evaluation logic as the engine in
`src/`, so what you see is what the math produces.

Features in the playable build:

- Animated, staggered reel spins with win-line overlays and symbol glow
- Free Spins round (2× wins, retriggers, more wilds)
- Hold & Spin bonus with locking orbs, respins, orb values and jackpots
- Adjustable bet, autoplay, sound toggle, in-game paytable and settings
- Starting play-money balance of 10,000 (resettable from Settings)

> ⚠️ The payout values here are **starting values**, not a mathematically balanced
> paytable. Final return-to-player (RTP) depends on reel strips, symbol frequency,
> bonus frequency and jackpot odds.

## Symbols

| Icon | Symbol ID | Function |
| --- | --- | --- |
| Emperor | `emperor` | Highest-paying regular symbol. Also acts as the **Wild**. |
| Royal women | `royal_women` | Second-highest regular payout. |
| Terracotta warriors | `warriors` | Third-highest regular payout. |
| Golden banner | `banner` | **Scatter** that triggers Free Spins. Pays anywhere. |
| Flaming gold orb | `bonus_orb` | Cash-orb symbol for the **Hold & Spin** bonus. |
| Crown K | `k` | Highest-value card symbol. |
| Crown Q | `q` | Medium card symbol. |
| J | `j` | Card symbol. |
| Red 10 | `ten` | Lower-value card symbol. |
| Green 9 | `nine` | Lowest-value card symbol. |

### Paytable (bet multipliers)

| Symbol | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- |
| Emperor (Wild) | 2× | 20× | 75× | 250× |
| Royal women | – | 10× | 30× | 100× |
| Warriors | – | 6× | 20× | 60× |
| K | – | 3× | 8× | 25× |
| Q | – | 2× | 6× | 20× |
| J | – | 2× | 5× | 15× |
| 10 | – | 1.5× | 4× | 12× |
| 9 | – | 1× | 3× | 10× |

## Features

### Emperor Wild
Substitutes for every regular symbol **except** `banner` and `bonus_orb`.

### Golden Banner Scatter — Free Spins
Pays anywhere. Triggers: **3 → 8**, **4 → 12**, **5 → 20** free spins.
During Free Spins, every win uses a **2× multiplier**, Wilds appear more
frequently, and landing **3 more banners adds 5 spins**.

### Flaming Orb — Hold & Spin
**6+ orbs** in one spin start the feature: triggering orbs lock, the player gets
**3 respins**, and every new orb locks and resets the counter to 3. The feature
ends when the counter reaches zero or every position is filled. Orbs carry
credit values (`1×…100×` total bet) and may be replaced by **MINI / MINOR /
MAJOR / GRAND** jackpots. Filling all 15 positions awards the **Grand Jackpot**.

## Usage

```js
import { evaluateSpin } from "./src/index.js";

// grid[reel][row] of symbol ids (5 reels × 3 rows)
const grid = [
  ["k", "q", "nine"],
  ["k", "ten", "j"],
  ["k", "nine", "q"],
  ["ten", "j", "nine"],
  ["q", "nine", "ten"],
];

const result = evaluateSpin(grid, { totalBet: 25 });
console.log(result.totalWin, result.lineWins);
```

## Project layout

```
src/
  symbols.js    Symbol definitions, types, paytable
  paylines.js   The 25 payline patterns
  config.js     Reel / feature configuration
  reels.js      Weighted reel strips + random grid generator
  engine.js     Spin evaluation (line wins, scatter, hold & spin)
  index.js      Public entry point
web/
  index.html    Game shell
  style.css     Theme / layout
  game.js       Front-end controller (imports the engine from src/)
  assets/       Game art (logo, frame, symbols, UI buttons)
test/           Engine tests (node --test)
scripts/
  serve.js      Zero-dependency static server (npm start)
  demo.js       Random-spin demo
```

## Develop

```sh
npm start      # play the game in a browser
npm test       # run the test suite
npm run demo   # print a random evaluated spin
```

## Assets

UI and theme art live in `web/assets/` (Golden Century pack: logo, dragon reel
frame, Emperor wild, and control buttons). Card and premium symbols are rendered
as styled tiles. White backgrounds were made transparent for compositing.
