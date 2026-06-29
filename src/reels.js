import { GAME_CONFIG } from "./config.js";

/**
 * Weighted reel strips. Each reel is a list of symbol ids; a symbol's
 * frequency in the list determines how often it lands. These are tuned for
 * a playable feel, NOT for a certified RTP — balance with real math before
 * any production use.
 */
const COMMON = ["nine", "ten", "j", "q", "k"];
const PREMIUM = ["warriors", "royal_women"];

function buildStrip({ wild = 2, scatter = 2, orb = 2 } = {}) {
  const strip = [];
  // Low cards are the bulk of the strip.
  for (const id of COMMON) {
    const weight = id === "nine" || id === "ten" ? 9 : id === "j" ? 8 : 7;
    for (let i = 0; i < weight; i++) strip.push(id);
  }
  // Premiums are rarer.
  for (const id of PREMIUM) {
    const weight = id === "warriors" ? 5 : 4;
    for (let i = 0; i < weight; i++) strip.push(id);
  }
  for (let i = 0; i < wild; i++) strip.push("emperor");
  for (let i = 0; i < scatter; i++) strip.push("banner");
  for (let i = 0; i < orb; i++) strip.push("bonus_orb");
  return strip;
}

export const REEL_STRIPS = [
  buildStrip({ wild: 1, scatter: 2, orb: 2 }),
  buildStrip({ wild: 2, scatter: 2, orb: 2 }),
  buildStrip({ wild: 3, scatter: 2, orb: 3 }),
  buildStrip({ wild: 2, scatter: 2, orb: 2 }),
  buildStrip({ wild: 1, scatter: 2, orb: 2 }),
];

/** Free-spin strips have more wilds, per the design. */
export const FREE_SPIN_STRIPS = [
  buildStrip({ wild: 4, scatter: 2, orb: 2 }),
  buildStrip({ wild: 5, scatter: 2, orb: 2 }),
  buildStrip({ wild: 6, scatter: 2, orb: 3 }),
  buildStrip({ wild: 5, scatter: 2, orb: 2 }),
  buildStrip({ wild: 4, scatter: 2, orb: 2 }),
];

function pick(strip, rng) {
  return strip[Math.floor(rng() * strip.length)];
}

/**
 * Produce a random grid (grid[reel][row]) from the given strips.
 * @param {object} [opts]
 * @param {string[][]} [opts.strips=REEL_STRIPS]
 * @param {() => number} [opts.rng=Math.random]
 */
export function spinGrid({ strips = REEL_STRIPS, rng = Math.random } = {}) {
  const { reels, rows } = GAME_CONFIG;
  return Array.from({ length: reels }, (_, reel) =>
    Array.from({ length: rows }, () => pick(strips[reel], rng)),
  );
}
