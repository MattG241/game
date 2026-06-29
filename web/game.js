import { SYMBOLS, SYMBOLS_BY_ID } from "../src/symbols.js";
import { GAME_CONFIG } from "../src/config.js";
import { PAYLINES } from "../src/paylines.js";
import { evaluateSpin } from "../src/engine.js";
import { REEL_STRIPS, FREE_SPIN_STRIPS, spinGrid } from "../src/reels.js";

/* ------------------------------------------------------------------ *
 * Symbol presentation
 * ------------------------------------------------------------------ */
const SYM_VIEW = {
  emperor: { image: "assets/sym_emperor.png", tag: "Wild" },
  royal_women: { image: "assets/sym_royal_women.png" },
  warriors: { image: "assets/sym_warriors.png" },
  banner: { image: "assets/sym_banner.png", tag: "Scatter" },
  bonus_orb: { image: "assets/sym_bonus_orb.png", tag: "Bonus" },
  k: { image: "assets/sym_k.png" },
  q: { image: "assets/sym_q.png" },
  j: { image: "assets/sym_j.png" },
  ten: { image: "assets/sym_ten.png" },
  nine: { image: "assets/sym_nine.png" },
};

const { reels: REELS, rows: ROWS } = GAME_CONFIG;
const ALL_IDS = Object.values(SYMBOLS).map((s) => s.id);

/* ------------------------------------------------------------------ *
 * State
 * ------------------------------------------------------------------ */
const BET_STEPS = [10, 25, 50, 100, 250, 500, 1000];
const state = {
  balance: 10000,
  betIndex: 1,
  spinning: false,
  auto: false,
  sound: true,
  fast: false,
  grid: spinGrid(),
};

const $ = (sel) => document.querySelector(sel);
const reelsEl = $("#reels");
const reelBoxEl = $("#reel-box");
const linesCanvas = $("#lines");
const ctx = linesCanvas.getContext("2d");
const featureBanner = $("#feature-banner");

const REEL_PAD = 5; // #reels inner padding (px)
const REEL_GAP = 4; // gap between reels (px)
let cell = 64;

/* ------------------------------------------------------------------ *
 * Audio (lightweight WebAudio blips, no asset files needed)
 * ------------------------------------------------------------------ */
let audioCtx = null;
function tone(freq, dur = 0.08, type = "square", gain = 0.05) {
  if (!state.sound) return;
  try {
    audioCtx ||= new (window.AudioContext || window.webkitAudioContext)();
    const osc = audioCtx.createOscillator();
    const g = audioCtx.createGain();
    osc.type = type;
    osc.frequency.value = freq;
    g.gain.value = gain;
    osc.connect(g).connect(audioCtx.destination);
    const now = audioCtx.currentTime;
    osc.start(now);
    g.gain.setTargetAtTime(0.0001, now, dur / 3);
    osc.stop(now + dur);
  } catch {
    /* ignore audio errors */
  }
}
const sfx = {
  click: () => tone(420, 0.06, "square", 0.04),
  reelStop: () => tone(220, 0.05, "sine", 0.05),
  win: () => tone(660, 0.12, "triangle", 0.06),
  bigWin: () => {
    [523, 659, 784, 1047].forEach((f, i) =>
      setTimeout(() => tone(f, 0.16, "triangle", 0.07), i * 110),
    );
  },
  feature: () => {
    [392, 523, 659, 880].forEach((f, i) =>
      setTimeout(() => tone(f, 0.2, "sawtooth", 0.05), i * 130),
    );
  },
};

/* ------------------------------------------------------------------ *
 * Layout
 * ------------------------------------------------------------------ */
function layout() {
  // Available width inside the gold frame for the reels block.
  const framePad = 18 * 2;
  const availW = reelBoxEl.clientWidth - framePad;
  cell = Math.floor((availW - REEL_PAD * 2 - REEL_GAP * (REELS - 1)) / REELS);
  cell = Math.max(40, cell);
  document.documentElement.style.setProperty("--cell", `${cell}px`);

  // Overlay the line canvas exactly over the reels block.
  const boxRect = reelBoxEl.getBoundingClientRect();
  const reelsRect = reelsEl.getBoundingClientRect();
  const w = Math.round(reelsRect.width);
  const h = Math.round(reelsRect.height);
  linesCanvas.style.left = `${reelsRect.left - boxRect.left}px`;
  linesCanvas.style.top = `${reelsRect.top - boxRect.top}px`;
  linesCanvas.style.width = `${w}px`;
  linesCanvas.style.height = `${h}px`;
  linesCanvas.width = w;
  linesCanvas.height = h;
}

/* ------------------------------------------------------------------ *
 * Rendering
 * ------------------------------------------------------------------ */
function symEl(id) {
  const view = SYM_VIEW[id] || { glyph: "?" };
  const cellEl = document.createElement("div");
  cellEl.className = "cell";
  cellEl.dataset.id = id;
  const sym = document.createElement("div");
  sym.className = `sym s-${id}`;
  if (view.image) {
    const img = document.createElement("img");
    img.src = view.image;
    img.alt = id;
    img.loading = "eager";
    img.draggable = false;
    sym.appendChild(img);
  } else {
    const g = document.createElement("div");
    g.className = "glyph";
    g.textContent = view.glyph;
    sym.appendChild(g);
  }
  if (view.tag) {
    const t = document.createElement("div");
    t.className = "tag";
    t.textContent = view.tag;
    sym.appendChild(t);
  }
  cellEl.appendChild(sym);
  return cellEl;
}

function buildReels() {
  reelsEl.innerHTML = "";
  for (let r = 0; r < REELS; r++) {
    const reel = document.createElement("div");
    reel.className = "reel";
    const strip = document.createElement("div");
    strip.className = "reel-strip";
    for (let row = 0; row < ROWS; row++) strip.appendChild(symEl(state.grid[r][row]));
    reel.appendChild(strip);
    reelsEl.appendChild(reel);
  }
}

function randId() {
  return ALL_IDS[Math.floor(Math.random() * ALL_IDS.length)];
}

/* ------------------------------------------------------------------ *
 * Spin animation
 * ------------------------------------------------------------------ */
function animateReel(reelEl, finalCol, delay, duration) {
  return new Promise((resolve) => {
    const strip = reelEl.firstChild;
    const spinCount = 14;
    strip.innerHTML = "";
    for (let i = 0; i < spinCount; i++) strip.appendChild(symEl(randId()));
    for (let row = 0; row < ROWS; row++) strip.appendChild(symEl(finalCol[row]));

    const distance = spinCount * (cell);
    strip.style.transition = "none";
    strip.style.transform = "translateY(0)";
    // force reflow then animate
    void strip.offsetHeight;
    setTimeout(() => {
      strip.style.transition = `transform ${duration}ms cubic-bezier(0.18, 0.9, 0.25, 1.05)`;
      strip.style.transform = `translateY(-${distance}px)`;
      const done = () => {
        strip.removeEventListener("transitionend", done);
        // settle: keep only final 3 cells
        strip.style.transition = "none";
        strip.style.transform = "translateY(0)";
        strip.innerHTML = "";
        for (let row = 0; row < ROWS; row++) strip.appendChild(symEl(finalCol[row]));
        sfx.reelStop();
        resolve();
      };
      strip.addEventListener("transitionend", done);
    }, delay);
  });
}

async function spinReelsTo(grid, fast) {
  const base = fast ? 320 : 620;
  const step = fast ? 90 : 170;
  const promises = [];
  for (let r = 0; r < REELS; r++) {
    const reelEl = reelsEl.children[r];
    promises.push(animateReel(reelEl, grid[r], r * step, base + r * step));
  }
  await Promise.all(promises);
}

/* ------------------------------------------------------------------ *
 * Win presentation
 * ------------------------------------------------------------------ */
function cellAt(reel, row) {
  return reelsEl.children[reel]?.firstChild?.children[row];
}

function clearHighlights() {
  ctx.clearRect(0, 0, linesCanvas.width, linesCanvas.height);
  reelsEl.querySelectorAll(".cell").forEach((c) => c.classList.remove("win", "dim"));
}

const LINE_COLORS = [
  "#ffd24d", "#4dff88", "#4dd2ff", "#ff7ad2", "#ff6b3d",
  "#b07aff", "#7affd2", "#ffe14d", "#ff4d6b", "#9dff4d",
];

function cellCenter(reel, row) {
  const x = REEL_PAD + reel * (cell + REEL_GAP) + cell / 2;
  const y = REEL_PAD + row * cell + cell / 2;
  return { x, y };
}

function drawWinningLines(lineWins) {
  ctx.clearRect(0, 0, linesCanvas.width, linesCanvas.height);
  lineWins.forEach((w, i) => {
    const pattern = PAYLINES[w.line - 1];
    ctx.beginPath();
    ctx.lineWidth = 4;
    ctx.strokeStyle = LINE_COLORS[i % LINE_COLORS.length];
    ctx.shadowColor = ctx.strokeStyle;
    ctx.shadowBlur = 8;
    for (let reel = 0; reel < w.count; reel++) {
      const { x, y } = cellCenter(reel, pattern[reel]);
      reel === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.shadowBlur = 0;
  });
}

function highlightWins(result) {
  const winning = new Set();
  result.lineWins.forEach((w) => {
    const pattern = PAYLINES[w.line - 1];
    for (let reel = 0; reel < w.count; reel++) winning.add(`${reel},${pattern[reel]}`);
  });
  // scatters always celebrate
  if (result.scatter.triggered) {
    for (let r = 0; r < REELS; r++)
      for (let row = 0; row < ROWS; row++)
        if (state.grid[r][row] === "banner") winning.add(`${r},${row}`);
  }
  if (winning.size === 0) return;
  reelsEl.querySelectorAll(".cell").forEach((c) => c.classList.add("dim"));
  winning.forEach((key) => {
    const [r, row] = key.split(",").map(Number);
    const c = cellAt(r, row);
    if (c) {
      c.classList.add("win");
      c.classList.remove("dim");
    }
  });
  drawWinningLines(result.lineWins);
}

/* ------------------------------------------------------------------ *
 * Counters / formatting
 * ------------------------------------------------------------------ */
const fmt = (n) =>
  n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function setBalance(v) {
  state.balance = v;
  $("#balance").textContent = fmt(v);
}
function setWinDisplay(v) {
  $("#win").textContent = fmt(v);
}
function currentBet() {
  return BET_STEPS[state.betIndex];
}
function updateBet() {
  $("#bet-value").textContent = fmt(currentBet());
}
function message(text, big = false) {
  const m = $("#message");
  m.textContent = text;
  m.classList.toggle("bigwin", big);
}

function countUp(target, duration = 700) {
  return new Promise((resolve) => {
    if (target <= 0) {
      setWinDisplay(0);
      resolve();
      return;
    }
    const start = performance.now();
    const tick = (now) => {
      const t = Math.min(1, (now - start) / duration);
      setWinDisplay(target * t);
      if (t < 1) requestAnimationFrame(tick);
      else resolve();
    };
    requestAnimationFrame(tick);
  });
}

/* ------------------------------------------------------------------ *
 * Feature banner helper
 * ------------------------------------------------------------------ */
function showBanner(big, sub, ms = 1600) {
  return new Promise((resolve) => {
    featureBanner.innerHTML = `<div class="big">${big}</div><div class="sub">${sub}</div>`;
    featureBanner.classList.remove("hidden");
    setTimeout(() => {
      featureBanner.classList.add("hidden");
      resolve();
    }, ms);
  });
}

/* ------------------------------------------------------------------ *
 * Hold & Spin bonus
 * ------------------------------------------------------------------ */
function randomOrbValue() {
  const { values } = SYMBOLS.BONUS_ORB;
  // ~6% chance to roll a jackpot instead of a plain value.
  if (Math.random() < 0.06) {
    const jp = ["MINI", "MINOR", "MAJOR", "GRAND"];
    const roll = Math.random();
    const tier = roll < 0.6 ? "MINI" : roll < 0.85 ? "MINOR" : roll < 0.97 ? "MAJOR" : "GRAND";
    return { jackpot: tier, value: GAME_CONFIG.holdAndSpin.jackpots[tier] };
  }
  return { value: values[Math.floor(Math.random() * values.length)] };
}

async function runHoldAndSpin() {
  sfx.feature();
  await showBanner("HOLD &amp; SPIN", "6 orbs collected!", 1700);

  const totalBet = currentBet();
  const { startingRespins, gridPositions, jackpots, fillAllAwardsGrand } =
    GAME_CONFIG.holdAndSpin;

  // locked[r][row] = orb object or null
  const locked = Array.from({ length: REELS }, () => Array(ROWS).fill(null));
  let filled = 0;

  // seed with the triggering orbs from the current grid
  for (let r = 0; r < REELS; r++)
    for (let row = 0; row < ROWS; row++)
      if (state.grid[r][row] === "bonus_orb") {
        locked[r][row] = randomOrbValue();
        filled++;
      }

  // build a fresh dark grid showing only orbs
  buildBonusGrid(locked);

  let respins = startingRespins;
  while (respins > 0 && filled < gridPositions) {
    message(`Respins left: ${respins}`);
    await sleep(state.fast ? 250 : 550);

    // each empty position has a chance to land a new orb
    let landed = false;
    for (let r = 0; r < REELS; r++) {
      for (let row = 0; row < ROWS; row++) {
        if (locked[r][row]) continue;
        if (Math.random() < 0.16) {
          locked[r][row] = randomOrbValue();
          filled++;
          landed = true;
        }
      }
    }

    if (landed) {
      respins = startingRespins; // reset on any new orb
      buildBonusGrid(locked);
      sfx.win();
    } else {
      respins--;
    }
  }

  // tally
  let total = 0;
  let grandHit = false;
  for (let r = 0; r < REELS; r++)
    for (let row = 0; row < ROWS; row++)
      if (locked[r][row]) total += locked[r][row].value;

  if (fillAllAwardsGrand && filled >= gridPositions) {
    total += jackpots.GRAND;
    grandHit = true;
  }

  const award = total * totalBet;
  await showBanner(
    grandHit ? "GRAND JACKPOT!" : "BONUS WIN",
    `${fmt(award)}`,
    grandHit ? 2600 : 1900,
  );
  return award;
}

function buildBonusGrid(locked) {
  reelsEl.innerHTML = "";
  clearHighlights();
  for (let r = 0; r < REELS; r++) {
    const reel = document.createElement("div");
    reel.className = "reel";
    const strip = document.createElement("div");
    strip.className = "reel-strip";
    for (let row = 0; row < ROWS; row++) {
      const orb = locked[r][row];
      if (orb) {
        const c = symEl("bonus_orb");
        c.classList.add("locked");
        const v = document.createElement("div");
        if (orb.jackpot) {
          v.className = "orb-value jackpot";
          v.textContent = orb.jackpot;
        } else {
          v.className = "orb-value";
          v.textContent = `${orb.value}x`;
        }
        c.appendChild(v);
        strip.appendChild(c);
      } else {
        const blank = document.createElement("div");
        blank.className = "cell";
        const s = document.createElement("div");
        s.className = "sym";
        s.style.background = "linear-gradient(180deg,#1a0e06,#0c0603)";
        blank.appendChild(s);
        strip.appendChild(blank);
      }
    }
    reel.appendChild(strip);
    reelsEl.appendChild(reel);
  }
}

/* ------------------------------------------------------------------ *
 * Free spins
 * ------------------------------------------------------------------ */
async function runFreeSpins(initialSpins) {
  sfx.feature();
  let spinsLeft = initialSpins;
  let totalWon = 0;
  await showBanner("FREE SPINS", `${initialSpins} spins • 2× wins`, 1900);

  const mult = GAME_CONFIG.freeSpins.winMultiplier;
  while (spinsLeft > 0) {
    spinsLeft--;
    message(`Free spins left: ${spinsLeft + 1}`);
    state.grid = spinGrid({ strips: FREE_SPIN_STRIPS });
    await spinReelsTo(state.grid, state.fast);

    const result = evaluateSpin(state.grid, { totalBet: currentBet(), winMultiplier: mult });
    highlightWins(result);

    if (result.lineWins.length) {
      totalWon += result.totalWin;
      await countUp(result.totalWin, 500);
      sfx.win();
    }

    // retrigger
    const rt = SYMBOLS.BANNER.retrigger;
    if (result.scatter.count >= rt.count) {
      spinsLeft += rt.additionalSpins;
      await showBanner("+5 SPINS", "Retrigger!", 1200);
    }

    // orbs can still trigger hold & spin
    if (result.holdAndSpin.triggered) {
      totalWon += await runHoldAndSpin();
    }

    await sleep(state.fast ? 250 : 650);
    clearHighlights();
  }

  await showBanner("FREE SPINS COMPLETE", `Total: ${fmt(totalWon)}`, 2200);
  return totalWon;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/* ------------------------------------------------------------------ *
 * Main spin
 * ------------------------------------------------------------------ */
async function spin() {
  if (state.spinning) return;
  const bet = currentBet();
  if (state.balance < bet) {
    message("Not enough balance — lower your bet");
    state.auto = false;
    $("#auto-btn").classList.remove("active");
    return;
  }

  state.spinning = true;
  $("#spin-btn").classList.add("spinning");
  setBalance(state.balance - bet);
  setWinDisplay(0);
  clearHighlights();
  message("Good luck!");
  sfx.click();

  state.grid = spinGrid({ strips: REEL_STRIPS });
  await spinReelsTo(state.grid, state.fast);

  let roundWin = 0;
  const result = evaluateSpin(state.grid, { totalBet: bet });
  highlightWins(result);

  if (result.lineWins.length) {
    roundWin += result.totalWin;
    await countUp(result.totalWin, 700);
    result.totalWin >= bet * 15 ? sfx.bigWin() : sfx.win();
  }

  // Free spins
  if (result.scatter.triggered) {
    await sleep(700);
    clearHighlights();
    roundWin += await runFreeSpins(result.scatter.freeSpinsAwarded);
    buildReels();
  }

  // Hold & spin
  if (result.holdAndSpin.triggered) {
    await sleep(500);
    roundWin += await runHoldAndSpin();
    buildReels();
  }

  if (roundWin > 0) {
    setBalance(state.balance + roundWin);
    setWinDisplay(roundWin);
    const big = roundWin >= bet * 15;
    message(big ? `BIG WIN ${fmt(roundWin)}!` : `You won ${fmt(roundWin)}`, big);
  } else {
    message("No win — spin again");
  }

  state.spinning = false;
  $("#spin-btn").classList.remove("spinning");

  if (state.auto) {
    await sleep(700);
    if (state.auto && !state.spinning) spin();
  }
}

/* ------------------------------------------------------------------ *
 * Paytable
 * ------------------------------------------------------------------ */
function buildPaytable() {
  const rows = [
    ["emperor", "Emperor (Wild)"],
    ["royal_women", "Royal Women"],
    ["warriors", "Terracotta Warriors"],
    ["k", "Crown K"],
    ["q", "Crown Q"],
    ["j", "Jack"],
    ["ten", "Red 10"],
    ["nine", "Green 9"],
  ];
  let html = `<table><thead><tr><th>Symbol</th><th>2</th><th>3</th><th>4</th><th>5</th></tr></thead><tbody>`;
  for (const [id, name] of rows) {
    const pays = SYMBOLS_BY_ID[id].pays;
    const thumb = SYM_VIEW[id]?.image
      ? `<img class="pt-sym" src="${SYM_VIEW[id].image}" alt="" />`
      : "";
    html += `<tr><td class="sym-name">${thumb}<span>${name}</span></td>` +
      `<td>${pays[2] ? pays[2] + "×" : "–"}</td>` +
      `<td>${pays[3] ? pays[3] + "×" : "–"}</td>` +
      `<td>${pays[4] ? pays[4] + "×" : "–"}</td>` +
      `<td>${pays[5] ? pays[5] + "×" : "–"}</td></tr>`;
  }
  html += `</tbody></table>`;
  html += `
    <h3>🏮 Golden Banner — Scatter</h3>
    <p>Pays anywhere. 3 → 8 spins, 4 → 12 spins, 5 → 20 spins. During Free Spins
    every win is multiplied 2×, Wilds appear more often, and 3 more banners add 5 spins.</p>
    <h3>🔥 Flaming Orb — Hold &amp; Spin</h3>
    <p>Land 6+ orbs to start. Orbs lock and award 3 respins; each new orb resets the
    counter. Collect every orb value, with MINI / MINOR / MAJOR / GRAND jackpots.
    Fill all 15 positions for the GRAND.</p>
    <h3>👑 Emperor — Wild</h3>
    <p>Substitutes for every symbol except the Banner and the Orb. Five Emperors pay 250× the line bet.</p>
    <p style="opacity:.7;margin-top:14px">5 reels · 3 rows · 25 fixed paylines · left-to-right · adjacent reels.</p>`;
  $("#paytable-body").innerHTML = html;
}

/* ------------------------------------------------------------------ *
 * Wiring
 * ------------------------------------------------------------------ */
function init() {
  buildReels();
  layout();
  buildPaytable();
  setBalance(state.balance);
  setWinDisplay(0);
  updateBet();

  window.addEventListener("resize", () => {
    layout();
    if (!state.spinning) clearHighlights();
  });

  $("#spin-btn").addEventListener("click", spin);
  document.addEventListener("keydown", (e) => {
    if (e.code === "Space" && !e.repeat) {
      e.preventDefault();
      spin();
    }
  });

  $("#bet-minus").addEventListener("click", () => {
    if (state.spinning) return;
    state.betIndex = Math.max(0, state.betIndex - 1);
    updateBet();
    sfx.click();
  });
  $("#bet-plus").addEventListener("click", () => {
    if (state.spinning) return;
    state.betIndex = Math.min(BET_STEPS.length - 1, state.betIndex + 1);
    updateBet();
    sfx.click();
  });

  $("#auto-btn").addEventListener("click", () => {
    state.auto = !state.auto;
    $("#auto-btn").classList.toggle("active", state.auto);
    sfx.click();
    if (state.auto && !state.spinning) spin();
  });

  $("#sound-btn").addEventListener("click", () => {
    state.sound = !state.sound;
    $("#sound-btn").classList.toggle("active", state.sound);
    $("#set-sound").checked = state.sound;
  });
  $("#sound-btn").classList.toggle("active", state.sound);

  $("#info-btn").addEventListener("click", () => {
    $("#paytable").classList.remove("hidden");
    sfx.click();
  });
  $("#settings-btn").addEventListener("click", () => {
    $("#settings").classList.remove("hidden");
    sfx.click();
  });
  document.querySelectorAll("[data-close]").forEach((b) =>
    b.addEventListener("click", (e) => e.target.closest(".overlay").classList.add("hidden")),
  );
  document.querySelectorAll(".overlay").forEach((o) =>
    o.addEventListener("click", (e) => {
      if (e.target === o) o.classList.add("hidden");
    }),
  );

  $("#set-sound").addEventListener("change", (e) => {
    state.sound = e.target.checked;
    $("#sound-btn").classList.toggle("active", state.sound);
  });
  $("#set-fast").addEventListener("change", (e) => (state.fast = e.target.checked));
  $("#set-reset").addEventListener("click", () => {
    setBalance(10000);
    message("Balance reset to 10,000");
  });

  // Optional debug hooks for manual/automated feature testing (?debug).
  if (location.search.includes("debug")) {
    window.__game = { spin, runFreeSpins, runHoldAndSpin, buildReels, state };
  }
}

init();
