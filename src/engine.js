import { GAME_CONFIG } from "./config.js";
import {
  SYMBOLS_BY_ID,
  WILD_ID,
  SCATTER_ID,
  BONUS_ID,
  wildSubstitutesFor,
} from "./symbols.js";

/**
 * A grid is represented as `grid[reel][row]` holding a symbol id string.
 * Reels are left-to-right (0..reels-1), rows top-to-bottom (0..rows-1).
 */

function isWild(id) {
  return id === WILD_ID;
}

/**
 * Evaluate a single payline given the symbol ids landing on it
 * (one id per reel, left to right).
 *
 * Returns the best line result: { symbolId, count, multiplier } or null.
 */
function evaluateLine(lineSymbols) {
  const first = lineSymbols[0];
  const firstDef = SYMBOLS_BY_ID[first];

  // Scatter / bonus symbols never form a left-to-right line win.
  if (!firstDef || firstDef.type === "scatter" || firstDef.type === "bonus") {
    return null;
  }

  // Candidate target symbols to score this line against.
  // A leading wild can stand in for any substitutable symbol, so we try each.
  const candidates = new Set();
  if (isWild(first)) {
    candidates.add(WILD_ID); // the wild paying as itself
    for (const id of lineSymbols.slice(1)) {
      if (id !== WILD_ID && wildSubstitutesFor(id)) candidates.add(id);
    }
  } else {
    candidates.add(first);
  }

  let best = null;
  for (const target of candidates) {
    let count = 0;
    for (const id of lineSymbols) {
      const matches =
        id === target || (isWild(id) && wildSubstitutesFor(target));
      if (!matches) break;
      count += 1;
    }
    const multiplier = SYMBOLS_BY_ID[target]?.pays?.[count];
    if (multiplier && (!best || multiplier > best.multiplier)) {
      best = { symbolId: target, count, multiplier };
    }
  }
  return best;
}

/**
 * Count how many of a given symbol id appear anywhere on the grid.
 */
function countAnywhere(grid, symbolId) {
  let count = 0;
  for (const reel of grid) {
    for (const id of reel) {
      if (id === symbolId) count += 1;
    }
  }
  return count;
}

/**
 * Evaluate a complete spin.
 *
 * @param {string[][]} grid - grid[reel][row] of symbol ids
 * @param {object} [opts]
 * @param {number} [opts.totalBet=1]  - total bet for the spin
 * @param {number} [opts.winMultiplier=1] - global multiplier (e.g. 2x in free spins)
 * @returns {object} spin result
 */
export function evaluateSpin(grid, opts = {}) {
  const { totalBet = 1, winMultiplier = 1 } = opts;
  const { paylines, paylineCount } = GAME_CONFIG;
  const betPerLine = totalBet / paylineCount;

  // --- Line wins ---
  const lineWins = [];
  paylines.forEach((rowsByReel, index) => {
    const lineSymbols = rowsByReel.map((row, reel) => grid[reel][row]);
    const result = evaluateLine(lineSymbols);
    if (result) {
      const win = result.multiplier * betPerLine * winMultiplier;
      lineWins.push({
        line: index + 1,
        symbolId: result.symbolId,
        count: result.count,
        multiplier: result.multiplier,
        win,
      });
    }
  });

  // --- Scatter (Golden Banner) ---
  const scatterCount = countAnywhere(grid, SCATTER_ID);
  const scatterDef = SYMBOLS_BY_ID[SCATTER_ID];
  const freeSpinsAwarded = scatterDef.freeSpins[scatterCount] ?? 0;

  // --- Bonus orbs (Hold & Spin) ---
  const orbCount = countAnywhere(grid, BONUS_ID);
  const holdAndSpinTriggered =
    orbCount >= GAME_CONFIG.holdAndSpin.triggerCount;

  const lineWinTotal = lineWins.reduce((sum, w) => sum + w.win, 0);

  return {
    grid,
    totalBet,
    betPerLine,
    winMultiplier,
    lineWins,
    lineWinTotal,
    totalWin: lineWinTotal,
    scatter: {
      count: scatterCount,
      freeSpinsAwarded,
      triggered: freeSpinsAwarded > 0,
    },
    holdAndSpin: {
      orbCount,
      triggered: holdAndSpinTriggered,
    },
  };
}

export { evaluateLine, countAnywhere };
