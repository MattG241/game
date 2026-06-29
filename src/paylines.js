/**
 * 25 fixed paylines for a 5-reel, 3-row grid.
 *
 * Each payline is an array of 5 row indices (0 = top, 1 = middle, 2 = bottom),
 * one per reel from left to right. Wins are evaluated left-to-right on
 * adjacent reels.
 */
export const PAYLINES = [
  [1, 1, 1, 1, 1], // 1  - middle
  [0, 0, 0, 0, 0], // 2  - top
  [2, 2, 2, 2, 2], // 3  - bottom
  [0, 1, 2, 1, 0], // 4  - V
  [2, 1, 0, 1, 2], // 5  - ^
  [0, 0, 1, 2, 2], // 6
  [2, 2, 1, 0, 0], // 7
  [1, 0, 0, 0, 1], // 8
  [1, 2, 2, 2, 1], // 9
  [0, 1, 1, 1, 0], // 10
  [2, 1, 1, 1, 2], // 11
  [1, 0, 1, 2, 1], // 12
  [1, 2, 1, 0, 1], // 13
  [0, 1, 0, 1, 0], // 14
  [2, 1, 2, 1, 2], // 15
  [1, 1, 0, 1, 1], // 16
  [1, 1, 2, 1, 1], // 17
  [0, 0, 1, 0, 0], // 18
  [2, 2, 1, 2, 2], // 19
  [0, 1, 2, 2, 2], // 20
  [2, 1, 0, 0, 0], // 21
  [0, 2, 0, 2, 0], // 22
  [2, 0, 2, 0, 2], // 23
  [1, 0, 2, 0, 1], // 24
  [1, 2, 0, 2, 1], // 25
];

export const PAYLINE_COUNT = PAYLINES.length;
