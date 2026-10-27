/**
 * Symbol configuration for the Imperial slot game.
 *
 * Symbol types:
 *   - "wild":    substitutes for regular symbols (with exclusions). Also pays on lines.
 *   - "regular": standard left-to-right line symbol.
 *   - "scatter": pays / triggers anywhere on the reels, no payline required.
 *   - "bonus":   cash-orb symbol used for the Hold & Spin feature.
 *
 * `pays` maps a matching-symbol count to a bet multiplier.
 *
 * NOTE: These payout values are starting values, not a mathematically balanced
 * paytable. Final RTP depends on reel strips, symbol frequency, bonus frequency
 * and jackpot odds.
 */
export const SYMBOLS = {
  EMPEROR: {
    id: "emperor",
    name: "Emperor",
    type: "wild",
    substitutes: true,
    // The wild substitutes for every regular symbol except these.
    excludedSubstitutions: ["banner", "bonus_orb"],
    pays: { 2: 2, 3: 20, 4: 75, 5: 250 },
  },

  ROYAL_WOMEN: {
    id: "royal_women",
    name: "Royal Women",
    type: "regular",
    pays: { 3: 10, 4: 30, 5: 100 },
  },

  WARRIORS: {
    id: "warriors",
    name: "Terracotta Warriors",
    type: "regular",
    pays: { 3: 6, 4: 20, 5: 60 },
  },

  BANNER: {
    id: "banner",
    name: "Golden Banner",
    type: "scatter",
    paysAnywhere: true,
    // Scatter count -> free spins awarded.
    freeSpins: { 3: 8, 4: 12, 5: 20 },
    // Landing this many scatters during Free Spins adds additional spins.
    retrigger: { count: 3, additionalSpins: 5 },
  },

  BONUS_ORB: {
    id: "bonus_orb",
    name: "Flaming Gold Orb",
    type: "bonus",
    // Number of orbs in a single spin needed to trigger Hold & Spin.
    triggerCount: 6,
    startingRespins: 3,
    // Each new orb that lands locks and resets the respin counter to the start value.
    resetsRespinsOnLand: true,
    // Possible credit values (in total-bet multiples) assigned to a landed orb.
    values: [1, 2, 3, 5, 10, 15, 25, 50, 100],
  },

  K: {
    id: "k",
    name: "Crown K",
    type: "regular",
    pays: { 3: 3, 4: 8, 5: 25 },
  },

  Q: {
    id: "q",
    name: "Crown Q",
    type: "regular",
    pays: { 3: 2, 4: 6, 5: 20 },
  },

  J: {
    id: "j",
    name: "J",
    type: "regular",
    pays: { 3: 2, 4: 5, 5: 15 },
  },

  TEN: {
    id: "ten",
    name: "Red 10",
    type: "regular",
    pays: { 3: 1.5, 4: 4, 5: 12 },
  },

  NINE: {
    id: "nine",
    name: "Green 9",
    type: "regular",
    pays: { 3: 1, 4: 3, 5: 10 },
  },
};

/** Lookup of symbol definition by its string id (e.g. "emperor"). */
export const SYMBOLS_BY_ID = Object.fromEntries(
  Object.values(SYMBOLS).map((s) => [s.id, s]),
);

export const WILD_ID = SYMBOLS.EMPEROR.id;
export const SCATTER_ID = SYMBOLS.BANNER.id;
export const BONUS_ID = SYMBOLS.BONUS_ORB.id;

/** Ids of all symbols that appear on paylines (regular symbols + the wild). */
export const LINE_SYMBOL_IDS = Object.values(SYMBOLS)
  .filter((s) => s.type === "regular" || s.type === "wild")
  .map((s) => s.id);

/**
 * Whether the wild may substitute for the given symbol id.
 */
export function wildSubstitutesFor(symbolId) {
  return !SYMBOLS.EMPEROR.excludedSubstitutions.includes(symbolId);
}
