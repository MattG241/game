import { PAYLINES, PAYLINE_COUNT } from "./paylines.js";

/**
 * Top-level game / reel configuration.
 */
export const GAME_CONFIG = {
  reels: 5,
  rows: 3,
  paylines: PAYLINES,
  paylineCount: PAYLINE_COUNT,

  // Wins are evaluated left to right, requiring adjacent reels starting at reel 1.
  evaluation: {
    direction: "leftToRight",
    adjacentReelsRequired: true,
  },

  // Hold & Spin bonus configuration.
  holdAndSpin: {
    triggerCount: 6, // orbs needed in one spin to start the feature
    startingRespins: 3,
    resetsRespinsOnLand: true,
    gridPositions: 5 * 3, // 15 total positions
    // Optional jackpots that can replace a random orb value.
    jackpots: {
      MINI: 10,
      MINOR: 25,
      MAJOR: 100,
      GRAND: 1000,
    },
    // If every position is filled, award the Grand Jackpot automatically.
    fillAllAwardsGrand: true,
  },

  // Free Spins feature configuration.
  freeSpins: {
    trigger: { 3: 8, 4: 12, 5: 20 }, // scatter count -> spins
    retrigger: { count: 3, additionalSpins: 5 },
    winMultiplier: 2, // every win during free spins uses this multiplier
    increasedWilds: true, // Emperor Wilds appear more frequently
  },
};
