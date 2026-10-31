# Test status

## Automated (run on every CI build and before every release)
`tests/test_runner.gd`: unit, integration and simulated-playtest checks, **450 checks, all passing**
(`godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn`).

| Area | Status | How |
| --- | --- | --- |
| Main menu, new game, save/load (including corrupted-save recovery) | Pass | integration |
| Touch controls, movement, camera | Pass | the real touch router with simulated touch events |
| Customers arrive, mingle, are called up to order, wait, pay, sit, drink, leave | Pass | integration |
| Glass from the rack, tap only pours when pulled, angle and flow matter | Pass | integration and unit |
| Under, over, spilled and perfect pours; settle; top-up | Pass | unit |
| Payment, satisfaction, tips, stock, cleaning, close and new day | Pass | integration |
| Upgrades change cash, systems and visuals | Pass | integration |
| **Order pacing and queue caps** (new) | Pass | simulated 15-minute sessions, see below |
| **Split the G** (new) | Pass | target is the measured G centre from `data/brand.json`; the glass turns so the G faces you; a slow-motion replay plays before the score; exact stop scores 100; best score saved |
| Darts | Pass | geometry, scoring, AI turn, bust, checkout |
| Live music, soundtrack, jukebox | Pass | headless audio (see below) |
| **Voices and recorded effects** (new) | Pass | recorded lines indexed; an order plays the character's line; mouth moves; music dips; second voice held back (no pile-ups); drink-matched order lines; voices can be turned off; recorded tap effect replaces the synthesised one; ambience loops |
| **Characters** (new) | Pass | realistic MakeHuman people (Blender-built, CC0) on a game-engine skeleton driven by the animation joints; regulars have their own voice and model; seated thighs point forward and knees bend; raised arms reach forward and bend at the elbow; a held pint is carried in front at waist height; a sip brings the rim to the lips (within 5 cm) with the glass tipped towards the drinker, then back down; an empty glass is left behind; each musician's hands reach their instrument (within 4 cm) |
| **First-person hand** (new) | Pass | shown while holding a glass, hidden otherwise |
| **Graphics presets** (new) | Pass | old Low/Medium settings map to Performance/Balanced; Ultra turns on 4x MSAA and shadows; Performance lowers resolution, shadows and crowd size; 30 FPS mode caps the frame rate |
| **Camera handover** (new, regression) | Pass | a close-up started straight after another keeps its camera, and the view returns to you afterwards |
| **Audio mix** (new) | Pass | rain plays on its own low-passed weather bus feeding the room; voices are louder than the weather by default; the room and rain dip at least 4 dB while someone speaks and come back afterwards |
| **Hired staff** (new) | Pass | hiring rules (reputation, room per role, no double hire); staff arrive on their own models; with the player away from the bar, a novice bartender takes orders, pours and serves on their own (pints average 79); customers a bartender is seeing to aren't offered to the player; the glass collector picks up, washes and wipes spills; no glass lost or made; let-go staff leave their glasses by the sink; wages and save |
| **Rota, growth, morale and kegs** (new) | Pass | a night off costs no wages and they stay home; tonight's shift is fixed once open; the week ahead shows weekends busier; serving builds skill up to potential and a level up asks for a raise; agreeing lifts wage and mood, refusing costs morale; nights off restore morale; a fed-up worker hands in notice, a bonus keeps them, notice served means they leave; weekly applicants have a role, trait and potential and can be hired; letting go pays a night's notice; old saves get a rota and traits; a stale keg can be swapped (the rest counted as waste) or says to order one; a cellar hand changes an empty keg unasked |
| **Next step, goals and streaks** (new) | Pass | overnight glasses don't skip the tutorial; the guide points at the sign before opening, then take order, grab a glass and pour in turn, then cash up at close; the gold marker shows when away; three daily goals pay out when met; a streak grows tips; the summary lists goals and looks ahead |
| **Every drink** (new) | Pass | every drink has an unlock; 31 upgrades, bigger ones gated by reputation; each of lager, ale, cider, Zero, whiskey and lemonade has a visible station, the right glass, an open prompt, and a careful pour scores 100; the optic stops at one measure; a bottle swaps itself; a bartender serves whiskey in a tumbler |
| **The pub's character** (new) | Pass | festivals and bunting; match day on the big screen (throw-in, scores, picture and score on screen, full time); beer lines go off and are cleaned; Nora's story, favour, reward and next chapter; the lock-in (once a night); the bodhrán session hits 32 of 32 on the measured beats and hands back control |
| **Audit regressions** (new) | Pass | darts in real time, Rematch, no stuck turn; leaving customers and closing time; settle guidance; tutorial not ended by a pour-away; booths; paint cleanliness; resumed gigs; refunds; supplier slate; session buttons and early exit; summary music |
| **Physical world** (new) | Pass | people are solid; staff go round the bar end and wait while you use a tap; the door stays shut until someone is at it, swings in for arrivals and out for leavers, and closes behind them; the door sign has OPEN and CLOSED faces and turns round (not snapped) to show the street the pub's state; one person per seat and armchair; furniture you haven't bought isn't solid; people always sit on their chair, never in mid-air; the fireside musician is clear of the armchairs; dancers keep apart and out of the chairs with pints held in front, below the head; name tags hide up close; long action labels fit their button; the floor and ceiling come in pieces of at most 3.5 m so every nearby lamp lights them; the pendants are downward spotlights; a night sky and a Filmic grade |
| APK export | CI | signed arm64 APK, signature verified, published as a Release |

## Queue and difficulty: old vs new

The old build sent every arriving customer straight to the bar. `tests/queue_probe.tscn` measures how the
queue builds on day 1 when nobody is served:

| Time after opening | Old build: waiting at the bar (people in pub) | New build: waiting at the bar |
| --- | --- | --- |
| 30 s | 2 | 1 (4) |
| 60 s | 4 | 1 (5) |
| 90 s | 5 (8) | 1 (5) |
| 120 s | **9 (12)** | **2 (5)** |
| 180-300 s | (kept growing) | 2 (5): held at the soft cap even with nobody served |

Old arrivals came every 7-11 s, all of them ordering, against a 50-90 s two-part pour.

The new model (`scripts/world/order_dispatcher.gd`):
- People in the pub and orders at the bar are separate. Arrivals sit or stand and chat; an order
  dispatcher calls them up one at a time.
- Order interval = measured serving time / (target utilisation × bartenders), with a gentle first two days.
  - Target utilisation: Relaxed 45%, Balanced 60%, Busier 80%.
  - The serving time is learned from your own play (default 55 s).
- No burst catch-up after a quiet spell: at most one order is "owed".
- Order caps on Balanced day 1: soft 2 (pacing halves), hard 3 (no new orders). Caps grow every
  3 days and with bar staff, up to 6.
- Patience = serving time × 2.8 + 45 s (×1.5 on day 1), so about 300 s on day 1, versus 75 s before.
- The HUD shows orders/cap, the next order's countdown and who is next. Settings → Game →
  "How busy the bar gets" picks Relaxed, Balanced or Busier.

Simulated playtests (a bot bartender serving at a fixed pace, in game time):

| Session | Served | Most orders waiting | Walk-outs | Bartender busy |
| --- | --- | --- | --- | --- |
| Balanced, day 1, 55 s per pint, 15 min | 8 | 1 (caps 2/3) | 0 | 52% |
| Balanced, day 1, slow player 95 s per pint, 15 min | 6 | 1 | 0 | 65% (learned 88 s, interval 168 s) |
| Busier, day 9, reputation 60, 45 s per pint, 15 min | 12 | 2 (caps 5/6) | 0 | 92% |

## Soundtrack (automated, headless with Godot's dummy audio driver)
- All 20 files present and unchanged (SHA-256 manifest); selection rules for every situation; real
  playback, crossfades, live music, jukebox, preferences. Unchanged by this update.

## Rendering load per graphics preset

`tests/perf_probe.tscn` renders a busy evening: 25 people, a five-piece band and every upgrade, seen
from behind the bar looking out into the room. It records the most expensive of ten frames. These are
engine counts from a desktop software renderer, not phone frame rates.

| Preset | Crowd cap | Draw calls | Triangles | Before (sculpted people) |
| --- | --- | --- | --- | --- |
| Performance (75% resolution) | 10 | 1,346 | 220k | 1,677 / 242k |
| Balanced | 14 | 1,354 | 206k | 1,685 / 234k |
| High (tap shadows, 2x MSAA, dust) | 20 | 1,443 | 206k | 1,774 / 240k |
| Ultra (fire shadows, 4x MSAA) | 24 | 1,931 | 286k | 2,318 / 324k |

The Blender-built people have far more detail close up, but cost less than the earlier sculpted ones.
They are drawn as fewer pieces, and Godot's automatic levels of detail thin them out with distance.
The probe used to face the back bar, which hid the crowd; earlier figures in this file came from
that view. Point-light shadows re-render the scene six times each, so the pendant lamps cast none.

## Not verified
- **Frame rate and memory on a phone.** No FPS figures are claimed. Turn on *Settings → Show performance
  overlay* to see live FPS, draw calls and memory, and compare the four Quality presets.
- **How the voices sound.** The free ElevenLabs plan only allows its premade voices (none are Irish), so
  the accents come from eleven_v3 accent tags. The first recordings were one short line per request,
  which v3 handles poorly (flat, synthetic delivery). Customer lines (orders, praise, complaints,
  waiting, paying, goodbyes) were re-recorded as one take per character, then cut into lines by the
  API's timestamps. A cut is used only if speech-to-text confirms the words.
  - Thick regional accents: the old regular, the Cork local and 10 of the Dubliner's 13 lines. The
    Dubliner's other three were heard as "point" for "pint", so they kept the old clips.
  - Colleen's orders and praise were re-recorded with the earlier, lighter tag.
  - Everyone else, and the landlord, musician and chatter lines, keep the first recordings. The free
    credits ran out (about 170 left).
  - Nobody has judged the accents by ear, and the mix was set by loudness, not by listening.
- Android launch, orientation and background-resume on hardware (no device available to the developer).

## Feedback checklist for a phone test
1. Does it install over the previous build and keep your pub?
2. Day 1: is the pace comfortable? Try Relaxed and Busier in Settings → Game.
3. Pour, settle, top-up and serve a Galagers; then try Split the G from the menu.
4. Do the voices sound Irish enough? Note any line that sounds wrong.
5. Note the FPS from the overlay on a busy evening with each Quality preset.


## Staff balance (`tests/balance_probe.tscn`)
Each row is one full trading day, 16:00 to midnight. A bot barman serves at 45 s per order (90 s in the
last row), on the Balanced setting. "You" and "staff" count orders served. "Busy" is the share of
opening time the player spends serving. Profit is sales and tips, minus the cost of drinks, wages, rent
and utilities. The agency fee is paid once and is not in the profit column.

| Config | You | Staff | Busy | Sales | Wages | Fee | Profit/day |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Solo, early (rep 25, day 3) | 7 | 0 | 58% | €45 | 0 | 0 | €7 |
| Solo, established (rep 45, day 8) | 9 | 0 | 67% | €56 | 0 | 0 | €18 |
| + novice bartender | 11 | 2 | 89% | €81 | €15 | €60 | €25 |
| + novice + glass collector | 12 | 2 | 90% | €89 | €26 | €95 | €23 |
| + 2 bartenders + collector (rep 65, day 14) | 12 | 11 | 96% | €132 | €68 | €310 | €11 |
| Slow player (90 s) + novice | 6 | 4 | 90% | €60 | €15 | €60 | €2 |

Before this pass, a €14 bartender could be hired on day 1 with no fee and took every order the player
didn't reach first. Staff now take only orders that have waited 15 s, so the player stays busy. In the
probe, the collector's value doesn't show, because the bot washes glasses for free.
