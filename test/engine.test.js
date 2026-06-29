import { test } from "node:test";
import assert from "node:assert/strict";

import { evaluateSpin, evaluateLine } from "../src/engine.js";
import { GAME_CONFIG } from "../src/config.js";
import { PAYLINE_COUNT } from "../src/paylines.js";
import { SYMBOLS } from "../src/symbols.js";

const TOTAL_BET = 25; // 1 unit per line across 25 lines

/**
 * Build a 5x3 grid (grid[reel][row]) filled with `fill`, then place
 * `ids` along the middle row (row index 1) left-to-right.
 */
function gridWithMiddleRow(ids, fill = "nine") {
  const grid = Array.from({ length: 5 }, () => [fill, fill, fill]);
  ids.forEach((id, reel) => {
    grid[reel][1] = id;
  });
  return grid;
}

test("25 paylines are configured", () => {
  assert.equal(PAYLINE_COUNT, 25);
  assert.equal(GAME_CONFIG.paylineCount, 25);
});

test("evaluateLine scores a simple 3-of-a-kind", () => {
  const result = evaluateLine(["k", "k", "k", "nine", "q"]);
  assert.deepEqual(result, { symbolId: "k", count: 3, multiplier: 3 });
});

test("wild substitutes to complete a line", () => {
  // emperor stands in for the third K
  const result = evaluateLine(["k", "k", "emperor", "nine", "q"]);
  assert.equal(result.symbolId, "k");
  assert.equal(result.count, 3);
  assert.equal(result.multiplier, SYMBOLS.K.pays[3]);
});

test("wild does NOT substitute for scatter or bonus", () => {
  const scatter = evaluateLine(["banner", "banner", "emperor", "nine", "q"]);
  assert.equal(scatter, null); // scatter can't start a line win
});

test("five wilds pay the emperor top line win", () => {
  const result = evaluateLine([
    "emperor",
    "emperor",
    "emperor",
    "emperor",
    "emperor",
  ]);
  assert.equal(result.symbolId, "emperor");
  assert.equal(result.count, 5);
  assert.equal(result.multiplier, 250);
});

test("evaluateSpin sums line wins on the middle row", () => {
  const grid = gridWithMiddleRow(["k", "k", "k", "ten", "ten"]);
  const spin = evaluateSpin(grid, { totalBet: TOTAL_BET });
  const line1 = spin.lineWins.find((w) => w.line === 1);
  assert.ok(line1, "middle payline should win");
  assert.equal(line1.symbolId, "k");
  assert.equal(line1.win, SYMBOLS.K.pays[3] * (TOTAL_BET / PAYLINE_COUNT));
});

test("free spins trigger on 3 scatters anywhere", () => {
  const grid = gridWithMiddleRow(["nine", "nine", "nine", "nine", "nine"]);
  grid[0][0] = "banner";
  grid[2][2] = "banner";
  grid[4][0] = "banner";
  const spin = evaluateSpin(grid, { totalBet: TOTAL_BET });
  assert.equal(spin.scatter.count, 3);
  assert.equal(spin.scatter.freeSpinsAwarded, 8);
  assert.equal(spin.scatter.triggered, true);
});

test("hold & spin triggers on 6 bonus orbs", () => {
  const grid = gridWithMiddleRow(["nine", "nine", "nine", "nine", "nine"]);
  let placed = 0;
  for (let reel = 0; reel < 5 && placed < 6; reel++) {
    for (let row = 0; row < 3 && placed < 6; row++) {
      grid[reel][row] = "bonus_orb";
      placed++;
    }
  }
  const spin = evaluateSpin(grid, { totalBet: TOTAL_BET });
  assert.equal(spin.holdAndSpin.orbCount, 6);
  assert.equal(spin.holdAndSpin.triggered, true);
});

test("free-spin win multiplier is applied", () => {
  const grid = gridWithMiddleRow(["k", "k", "k", "ten", "ten"]);
  const base = evaluateSpin(grid, { totalBet: TOTAL_BET });
  const boosted = evaluateSpin(grid, { totalBet: TOTAL_BET, winMultiplier: 2 });
  assert.equal(boosted.totalWin, base.totalWin * 2);
});
