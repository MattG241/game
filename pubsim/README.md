# The Irish Pub Simulator

A free, offline, single-player, first-person 3D Irish pub simulator for Android, built with
**Godot 4.4.1** (GDScript, Compatibility renderer). You inherit **The Crooked Shamrock**, a slightly
shabby pub on a rainy street. You pour proper two-part stouts, serve the locals, wash the glasses,
change the kegs and spend your takings on improvements you can see.

No ads, no purchases, no accounts, no internet permission.

## Install on your phone (no computer needed)

1. On your Android phone, open **https://github.com/MattG241/game/releases/latest** in Chrome.
2. Under *Assets*, tap **IrishPubSimulator.apk**.
3. When the download finishes, tap **Open**. If Android asks, allow *Install unknown apps* for Chrome
   (Settings → Apps → Chrome → Install unknown apps), then tap **Install**.
4. Launch **Irish Pub Sim** from your app drawer. Hold the phone sideways.

### Updating without losing your pub
Install a newer APK the same way: it installs *over* the old one and keeps your save, as long as both
builds were signed with the same key (see "Signing" below). Don't uninstall first, because uninstalling
deletes the save.

## Controls (touch only)

| Action | How |
| --- | --- |
| Walk | Drag anywhere on the **left** of the screen (floating joystick) |
| Look | Swipe on the **right** of the screen |
| Use / pick up / serve | The big button bottom-right shows what it will do. Some actions are *held* (wiping, washing, changing kegs) |
| Pour | At the tap: drag **TILT GLASS** (left) to angle the glass, drag **PULL TAP** (right) down to open the tap. Let go to stop |
| Menu | Top-right **Menu** (upgrades, stock, prices, ledger, settings, save). Android back button also opens it |
| Speed up time | **>>** (only when nobody is waiting) |

## How to pour the perfect stout
1. Take a clean glass from the rack on the back counter.
2. At the brass stout tap, tilt the glass to **45°** and pull the tap fully.
3. Straighten the glass as it fills and **stop at about three-quarters**.
4. **Let it settle.** Tap *Leave to settle* and go do something else (wash a glass, take an order).
5. Pick it up when it's dark, return to the tap, hold it **upright** and **top up gently** until the
   head domes just above the rim.
6. Serve it to the customer who ordered it. Score, payment, tip and their reaction follow.

The score weighs the initial angle, first-pour level, settling time, final fill, head thickness,
spills, glass cleanliness, keg freshness and how long it sat on the bar.

## What's in this version (0.1)
- A furnished first-person pub: wooden bar, brass stout tap, back bar with mirror and bottles,
  fireplace, tables, armchairs, photographs, a notice board, a stone cellar with kegs, and a wet
  cobbled street with rain and a terrace opposite.
- Customers who walk in, queue, order, lose patience, pay, tip, sit, sip, chat and leave. Eleven named
  regulars with their own drinks, lines and relationship scores.
- The two-part stout pour with a real-time liquid shader: tilted liquid surface, cascading nitro
  bubbles, settling dark body, creamy domed head, lacing and slosh.
- Glasses are physical and counted: take, pour, settle, serve, collect, wash, return to the rack.
- Spills to wipe. Kegs that run dry and must be changed in the cellar. Stock orders delivered the next day.
- Price setting, a ledger, end-of-day accounts (rent, utilities), reputation and weather.
- Upgrades that change the room and how it runs (restored lamps, glassware, chalkboard, brass drip tray,
  lit fireplace, paint & tiles, dartboard, snug stage, sound system, jukebox restoration).
- Opening and closing routine, last orders, autosave plus an atomic, versioned save with a backup.
- Settings: sensitivity, invert look, button opacity, HUD scale, vibration, five volume sliders,
  subtitles, quality preset, FPS limit, render scale, reduced motion/effects, high contrast,
  pour assist, day length, performance overlay.

### Added since 0.1
- **Your 20-song soundtrack**, played by a central MusicDirector (details below).
- **Live music nights**: book eight acts from the *Live music* tab. Musicians appear (by the fire, round a
  table or on the snug stage), play your songs from where they sit in 3D, and lift footfall, atmosphere, stay
  length, tips and the next day's reputation. Dancing nights get customers dancing in front of the stage. A great
  night ends with *One More Round* sung by the whole pub.
- **Jukebox** by the front window (and the *Jukebox* menu tab): browse all 20 songs by category, play any,
  pause/resume, skip, set music volume, switch Automatic / My choice.
- **Darts** (301 against a regular), **Split the G** challenge, a **pint by the fire**.
- **Awards** with prize money, and celebration cards for big renovations.

### Second pass
- **GALAGERS Irish Stout**: an original house stout brand. It has a fiddle emblem in a Celtic ring and
  a Cinzel serif wordmark, in black, ivory, antique gold, copper and burgundy. It appears on:
  - the pint glass, with a big readable G and condensation on a fresh pint
  - the tap badges, the illuminated back-bar sign, the drip and bar mats, and coasters
  - posters, an etched mirror, the keg label, bottle crates, the facade, table menus and a menu board.

  The artwork comes from `tools/gen_brand.py`. Swap `assets/brand/` and `data/brand.json` to rebrand.
- **Split the G**: stop your gulp with the line between stout and head exactly halfway through the G.
  - The target is the measured centre of the printed G, and the glass turns so the G faces you.
  - A slow-motion replay glides the line down before the score.
  - The crowd reacts, and your best score is saved.
- **A calmer, fairer bar**: people come in, sit and chat, and are called up to order at a pace based on
  how fast *you* actually serve. Orders are capped, and the HUD shows the queue and the next order's
  countdown. Choose Relaxed, Balanced or Busier in Settings. See `docs/TESTING.md` for old vs new numbers.
- **Voices and recorded sound** (made once with ElevenLabs, bundled offline):
  - customers order, praise, complain and say goodbye; regulars have their own voices
  - the landlord calls last orders, and the band introduces tunes
  - the room reacts to Split the G
  - mouths move and the music dips under speech
  - recorded tap, glass, till, door, darts, crowd, rain and fire sounds.
- **Realism pass**:
  - brass, chrome and glass reflect the room
  - wood grain, plaster, tile and stone relief; leather and metal wear
  - soft contact shadows under furniture and people
  - jointed characters with faces, jackets, jumpers and skirts
  - your own hand holding the pint
  - timber, ivory and brass menus.
- **Graphics presets**: Performance, Balanced, High and Ultra, plus a 30 FPS battery-saver mode.

### Overnight polish (0.2.0)
- **People**: sculpted bodies, faces and hands from `tools/gen_people.py`, made from smooth
  signed-distance shapes meshed with marching cubes, about 10k triangles each.
  - Clothes, faces, hair and shoes are painted by shaders.
  - Eyes sit in sockets and blink; people breathe.
  - They glance at you, chat with their neighbours, gesture and laugh.
- **Fire**: living turf flames with sparks and smoke. The fiddler sits by the hearth on a stool,
  playing a proper fiddle.
- **The pub front**: a two-storey Irish shopfront.
  - Gilt fascia, fluted pilasters, carriage lanterns and flower baskets.
  - Sash windows, a slate roof and chimneys.
  - Across the street, a detailed terrace.
- **Inside**:
  - real bottles with labels on the back bar, and an aged ceiling
  - lamplight cones with drifting dust, a hearth rug
  - the last-orders bell, hurleys, a newspaper and beer mats
  - rain running down the windows behind lace café curtains
- **The pour**: a hero framing of the brass font and the glass, a flowing stream and a ribbed
  GALAGERS drip mat.
- **The pint**: near-black stout with ruby edges and natural condensation.
- **Title screen**: a living pub, with regulars, a fiddler and a flickering fire.
- **Fixes**:
  - customers at the bar now face you
  - a voice-player race is fixed
  - CI now fails on any script error

### Feedback round (0.2.0)
- **Drinking looks right**: arms used to swing backwards (a pose sign error). A held pint is now carried
  in front at waist height. A sip lifts the rim to the lips with the glass tipped back. Seated drinkers
  reach for the glass on the table, drink and put it down again. The level only drops at the lips.
- **Real session instruments**: a sculpted fiddle and bow, guitar, banjo, button accordion, bodhrán
  and tipper, and a tin whistle, made by `tools/gen_instruments.py`. A shader paints the f-holes,
  purfling, rosette, frets, goatskin and pearloid. Both hands reach the instrument:
  - the bow travels across the strings
  - the guitar is strummed and its neck fingered
  - the bellows breathe
  - the tipper strikes the drum
- **More natural people**: real shoulder widths with sloping shoulders, larger heads, lower lids, softer
  lips and a rounder talking mouth. Band members no longer come out dressed alike.
- **Realistic people, built in Blender**: the customers are 16 rigged characters made from
  MakeHuman's CC0 data: real skins, eyes, brows and lashes, hair, clothes and shoes.
  `tools/people/` assembles them, and Blender builds and exports them. They blink, talk with their
  mouths, smile when they laugh, and close their fingers round a pint or an instrument. The existing
  animation drives their skeletons (walking, sitting, drinking, playing). See
  `tools/people/README.md`.
- **Real furniture**: the pub tables, chairs, green fireside armchairs, the fiddler's stool, the old
  cash register and a mantel clock are CC0 scanned models from Poly Haven, prepared in Blender
  (`tools/props/`).
- **Thick Irish accents**: lines were re-recorded one take per character with thick regional accent
  tags. This covers the old regular, the Cork local and most of the Dubliner's lines; the free credits
  ran out before the rest (see `docs/TESTING.md`). Voices also get a light room reverb.
- **A mix you can hear people in**: rain and storms have their own muffled "through the windows"
  bus and volume slider, set well below the room. The crowd murmur sits on the room bus. Whenever
  someone speaks, the room and the weather dip 9 dB and the music dips further. A limiter on the
  master stops peaks from clipping. Older settings are moved onto the new balance once.
- **Hire staff** (Menu → Staff): five people are looking for work. Two of them want a pub with some
  reputation first.
  - Bar staff take the orders you aren't seeing to. They fetch a glass, pour with a hand on the tap
    (stout gets its two-part pour and settle) and serve. Their skill sets their speed and how good
    the pint is. Customers they're looking after aren't offered to you.
  - A glass collector clears empties to the sink, washes them back onto the rack and wipes spills.
  - Wages are paid at close. More bar staff means the pub can take more orders.
- **Always know what to do next**: a "Next" line (top right) and a floating gold marker point at the
  most useful thing to do. For example: open up, take Nora's order, grab a glass, pour, top up the
  settled stout, serve, wash the empties, change the keg, or chat with a regular when it's quiet.
  It can be turned off in Settings.
- **Daily goals and streaks**: three goals a day pay cash when you meet them (serve 8 drinks, pour
  two 90+ pints, nobody walks out...). Good pints in a row build a streak that adds up to +30% on
  tips. The end-of-day summary shows the goals and looks ahead: what you can afford, who you could
  hire, and what's running low.
- **A clean, modern HUD**: smoked-glass panels with hairline edges in place of the timber boxes.
  - Cash sits over a single line of day, time, weather and state. Cleanliness only shows when the pub needs a tidy.
  - The next step is one centred pill.
  - Orders appear only when someone is waiting, as slim rows with a patience line.
  - Today's goals fold into a "Goals 1/3" chip that opens briefly when one is met.
  - The action button alone names the action; the centre text only shows "can't yet" hints.
  - The pour screen matches.
- **Tutorial fixes**: last night's empty glasses no longer skip the tutorial ahead. Tips sit low in
  the middle of the screen, clear of the status panel. The sink prompt no longer says "hold".
- **Every drink on the menu**: lager, ale, cider, Galagers Zero, whiskey and lemonade used to be
  impossible to serve, because their unlocks were missing. Each now has its own station on the bar,
  bought as an upgrade:
  - the Lough Glas lager font;
  - a Red Fox hand pump;
  - cider and Zero fonts;
  - a whiskey optic stand that stops at one measure;
  - a soda gun.

  Each has its own technique and instructions. Whiskey and lemonade go in a tumbler (the second
  button at the rack), and pour assist now pours a good lager.
- **31 upgrades and reputation tiers**: the pub grows from "a quiet local" to "a legend of a pub".
  Bigger upgrades unlock with reputation, for example a glass washer, cellar cooling, snug booths,
  a big screen, a beer garden and a function room.
- **The regulars' stories**: seven regulars have short story arcs, with favours tied to real play.
  - Nora's late husband's perfect pint.
  - Packie's darts title.
  - Tomás's session.
  - Liam's under-12s final.
  - Margaret's table quiz.
  - Eamon's palate.
  - Aoife after the night shift.

  A gold "..." shows who has something to say.
- **Sit in on the bodhrán**: during a live act, keep the beat in a rhythm lane synced to the real
  song. Each song's tempo is measured offline by `tools/beat_track.py`, and the band now moves at
  that tempo too.
- **Match days**: a big screen over the fireplace shows Ballyfinn's games on Sunday afternoons and
  Wednesday evenings. The room cheers and groans with every score, and trade picks up.
- **Festival days**: the Fleadh, the county final, St Patrick's Day and the harvest fair, with
  bunting and big crowds.
- **Lock-ins** after closing with your closest regulars, unless the Gardaí knock.
- **Beer lines** to clean in the cellar, or draught pints lose quality.
- **Menus restyled** in the same glass look as the HUD:
  - the tabs scroll if they don't fit;
  - the day's report lists every line so the profit adds up;
  - a colour-blind option switches patience colours to amber-to-blue.
- **Bug fixes from a full audit**:
  - darts Rematch crashed, and leaving mid-turn locked the next game;
  - fast-forward stayed on in minigames;
  - leaving customers were called back to the bar;
  - orders were still taken after closing;
  - the end-of-day music never changed;
  - the guide said to top up an unsettled stout;
  - the tutorial could end early;
  - a resumed gig counted twice;
  - booking refunds were miscounted;
  - the booths could never be bought;
  - the paint upgrade's "stays cleaner" did nothing;
  - staff ignored keg freshness;
  - a broke pub with no stock could never recover (the supplier now puts one keg on the slate);
  - a large HUD scale pushed the menu's close button off-screen.
- **Balance pass**, after looking at how similar games pace staff:
  - **The research:** Two Point Hospital charges a recruitment fee up front, and its staff tire and
    take breaks. Better staff cost far more. PlateUp players report the late game turning easy once
    automation covers everything.
  - **Staff costs:** staff now need reputation (the first bartender at 30, a second at 50). Each
    has an agency fee paid up front, plus higher wages for better staff.
  - **Bartenders:** they only pick up orders left waiting 15 seconds, so you stay the first port of
    call. Demand grows with the size of the team.
  - **Breaks:** everyone needs one every so often.
  - **Measured:** `tests/balance_probe.tscn` plays whole days. A novice bartender takes you from 67%
    to 89% busy and pays back the fee in about 9 days. A full team keeps you 96% busy. A slow
    player can't lean on staff to carry the pub.
- **Less clutter:**
  - at most two short notices, with no repeats and routine news held back;
  - names over people only up close;
  - the goal list folded until one is met;
  - the Next pill only for real actions, and never on top of a tutorial tip;
  - orders listed only when two or more are waiting;
  - tutorial tips fade on their own.
- **The glass** now draws its far wall, so a pint looks whole. **Menus scroll** under a finger
  anywhere on the list, with a little momentum, and a drag never presses a button.

## The soundtrack: who plays what
| # | Song | When it plays |
| --- | --- | --- |
| 01 | Welcome to The Local | Title screen; fades out when you start or continue |
| 02 | First Pint of the Day | Setting up before opening, quiet early trade |
| 03 | A Quiet Tuesday | Ordinary trading with few customers |
| 04 | Rain on the Windows | Rainy days, especially after dark (chosen when a song ends, never cuts one off) |
| 05 | The Friday Crowd | When the bar fills up (8+ customers, or a busy Friday/Saturday evening) |
| 06 | Last Orders | From last orders through closing, and on the end-of-day accounts |
| 07 | Fiddles by the Fire | Live act: solo fiddler by the fireplace (cheapest, no upgrade needed) |
| 08 | The Galway Reel | Live act: weekend trad session on the snug stage |
| 09 | The Wild Session | Live act: high-energy band, needs the sound system |
| 10 | The Old Country Jig | Live act: Irish dancing night; customers dance |
| 11 | The Fiddler's Table | Live act: trio seated round a table, best on quieter nights |
| 12 | The Big Night | Live act: the biggest event, needs sound system and reputation 50, best Saturday |
| 13 | Split the G | The Split the G challenge (fades back to pub music after) |
| 14 | Perfect Pint | A 9-second excerpt over the music when you serve a pint scoring 92+ (not more than once every 75s), with cheers |
| 15 | The Pub Gets Bigger | Celebration card after major renovations (€200+) |
| 16 | Champions of the Pub | Award cards (reputation and career milestones) |
| 17 | One More Round | Sung live as the finale of an especially good night (atmosphere 45+, 6+ customers, happy crowd); customers gather at the stage and raise their glasses |
| 18 | Mind the Line | Live act: the Split the G Championship night (enter for a €50 prize) |
| 19 | The Pub on the Corner | End-of-day accounts on milestone days (days 1, 3, 7, 14...) and after a singalong night |
| 20 | The Landlord's Lament | Live act: comedy singalong night; the crowd laughs and cheers |

How it behaves: songs inside one situation finish naturally before the next is chosen; changes of situation
(menu, live band, challenge, celebration, closing time) crossfade. Only one background song is ever at
full volume, and while musicians play the background music fades right out so you only hear the band, getting
louder as you walk up to them and muffled from the cellar or the street. The Music, Effects and Ambience volume
sliders are separate, and music can be turned off without muting anything else. Choices are saved.

The songs are MP3s, kept exactly as supplied and loaded only when needed; they're decoded while they play rather
than all at once, and the APK carries them for offline play.

Planned next (not claimed): food, furniture placement and room expansions. See `docs/ROADMAP.md`.

## Signing (for consistent updates)
The CI workflow derives the release keystore from **one** repository secret so every build has the
same signature. To set it from your phone:

1. Open **github.com/MattG241/game** → **Settings** → **Secrets and variables** → **Actions**.
2. Tap **New repository secret**. Name: `PUBSIM_SIGNING_PASSPHRASE`. Value: any long random text
   (30+ characters, e.g. a few unrelated words and numbers). Keep a private copy; it *is* your key.
3. Save. The next build (and every one after) is signed with that key.

Until the secret is set, CI signs with a generated fallback key kept in the GitHub Actions cache.
That key can be lost if the cache expires (7 days unused), and builds from different branches may
differ. When the key changes, Android refuses to update over the old install: uninstall and reinstall
(this loses the save). Setting the secret avoids that permanently.

## Building
Every push to `pubsim/` runs `.github/workflows/pubsim-android.yml`: it installs Godot 4.4.1 and its
templates, runs the automated test suite, exports a signed arm64 APK, uploads it as an artifact and
publishes a GitHub Release.

Locally: `godot --headless --path pubsim --export-release Android build/IrishPubSimulator.apk`
(with the Android SDK set in Godot's editor settings).

### Tests
`godot --headless --path pubsim --fixed-fps 60 res://tests/test_runner.tscn` runs the unit and
integration tests (pour physics, scoring, economy, inventory, save/backup recovery, and a full
simulated day: open, customer, order, pour, settle, top-up, serve, pay, upgrade, collect, wash,
close, reload). `docs/TESTING.md` lists what has and hasn't been verified.

## Project layout
```
pubsim/
  assets/        audio (generated), fonts (OFL), icons, shaders
  data/          editable JSON: economy, drinks, upgrades, regulars, customer lines
  scripts/       autoload/ (data, state+save, audio), world/, npc/, ui/
  tests/         automated tests and screenshot capture
  tools/         gen_audio.py, gen_icons.py, derive_keystore.py
```
