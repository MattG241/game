# Store listing assets

Everything here was captured from the real game (`godot/tests/store_shots.tscn`) and
composed by `tools/make_store_art.py`. Nothing is mocked up.

| Folder / file | Use it for | Size |
| --- | --- | --- |
| `google_play/phone_1920x1080/*.png` | Google Play phone screenshots (2-8 allowed) | 1920 x 1080 |
| `google_play/feature_graphic_1024x500.png` | Google Play feature graphic (required) | 1024 x 500 |
| `google_play/icon_512.png` | Google Play app icon (required) | 512 x 512 |
| `apple/iphone_6.9in_2868x1320/*.png` | App Store iPhone 6.9" screenshots (Apple scales these for smaller iPhones) | 2868 x 1320 |
| `apple/icon_1024.png` | App Store icon (no transparency) | 1024 x 1024 |
| `raw/...` | The same shots without captions, if you prefer plain gameplay | as above |

Order: 01 title, 02 toothbrush, 03 vacuum, 04 buggy, 05 automation, 06 beam, 07 shop.

## Draft listing text

**Name:** Lunar Cleanup

**Short description (Play, max 80 chars):**
Clean the Moon with a toothbrush, then build a lunar cleaning empire.

**Full description:**
You've just been hired by the most underfunded cleaning company in the solar system.
Your equipment: one slightly used toothbrush. Your job: the Moon.

- Scrub real, persistent dust off the lunar surface and watch it disappear stroke by stroke
- Sell every speck at the Dust Exchange and upgrade through 12 tools - from toothbrushes
  to industrial vacuums, rotary scrubbers and a wide-area cleaning beam
- Drive four low-gravity vehicles, including a vacuum buggy and an 8 m cleaning truck
- Build an automated operation: solar power, dust collectors, cleaning drones, rovers,
  conveyors, refineries and rocket shipping depots
- Unlock five regions, research 16 upgrades and complete 30+ contracts
- Every upgrade is earned in-game - no paywalls. Plays fully offline.
- Optional rewarded ads for bonuses; a one-off "Remove ads" purchase turns off the
  occasional full-screen ads.

**Category:** Games > Simulation. **Store labels:** Contains ads, In-app purchases.
**Target audience:** 13+ (see `PLAY_STORE.md` for content rating, ads and Data safety answers).

## Before submitting

- **Google Play:** follow `PLAY_STORE.md`. The workflow builds the Play bundle
  (`LunarCleanup.aab`) once the private upload key is in the repository secrets. A Google
  Play developer account costs a one-off USD 25.
- **Apple App Store** needs an iOS build. Godot can export to iOS, but Apple requires
  Xcode on macOS to compile and sign it, plus an Apple Developer Program membership
  (USD 99/year). GitHub's macOS runners can do the compile in the cloud, so it is
  possible without owning a Mac, but the membership fee cannot be avoided.

## Regenerating

```
# raw captures (needs Xvfb + Godot 4.7); scene = title|brush|wide|buggy|automation|beam|shop
godot --path godot --rendering-driver opengl3 --resolution 1920x1080 \
  res://tests/store_shots.tscn -- --scene=brush --out=store/raw/play_1920x1080/02_toothbrush.png
python3 tools/make_store_art.py
```
