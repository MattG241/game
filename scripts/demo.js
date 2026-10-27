/**
 * Tiny demo: spin random grids until something interesting happens,
 * then print the evaluated result. Run with `npm run demo`.
 */
import { evaluateSpin } from "../src/index.js";
import { SYMBOLS, LINE_SYMBOL_IDS } from "../src/symbols.js";

// A naive flat reel pool (NOT balanced for RTP) for demonstration only.
const POOL = [
  ...LINE_SYMBOL_IDS,
  ...LINE_SYMBOL_IDS,
  "banner",
  "bonus_orb",
];

function randomGrid() {
  return Array.from({ length: 5 }, () =>
    Array.from({ length: 3 }, () => POOL[Math.floor(Math.random() * POOL.length)]),
  );
}

const grid = randomGrid();
const result = evaluateSpin(grid, { totalBet: 25 });

console.log("Grid (reel x row):");
for (let row = 0; row < 3; row++) {
  console.log(grid.map((reel) => reel[row].padEnd(11)).join(" "));
}
console.log("\nLine wins:", result.lineWins);
console.log("Total win:", result.totalWin);
console.log("Scatter:", result.scatter);
console.log("Hold & Spin:", result.holdAndSpin);

void SYMBOLS;
