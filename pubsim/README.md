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
- Seven upgrades that change the room and how it runs (restored lamps, glassware, chalkboard,
  brass drip tray, lit fireplace, more glassware, paint & tiles).
- Opening and closing routine, last orders, autosave plus an atomic, versioned save with a backup.
- Settings: sensitivity, invert look, button opacity, HUD scale, vibration, five volume sliders,
  subtitles, quality preset, FPS limit, render scale, reduced motion/effects, high contrast,
  pour assist, day length, performance overlay.

Planned next (not in 0.1, not claimed): lager/ale/cider/spirits serving mechanics, live trad music
nights and the bodhrán rhythm game, darts, the "Split the Knot" precision drinking challenge, staff,
food, furniture placement and expansions. See `docs/ROADMAP.md`.

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
