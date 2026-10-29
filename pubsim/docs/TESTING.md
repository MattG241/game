# Test status

## Automated (run on every CI build and before every release)
`tests/test_runner.gd`: unit plus integration tests, 113 checks at version 0.1.

| Spec test | Status | How |
| --- | --- | --- |
| 1 Main menu and new game load | Automated: pass | integration |
| 2 Player movement, camera, touch UI | Automated: pass | joystick and look via the real touch router with simulated touch events |
| 3 NPC enters, orders and waits | Automated: pass | first customer walks in, reaches the bar, waits |
| 4 Pick up a clean glass | Automated: pass | rack count decreases, glass is clean |
| 5 Tap only pours when interacted with | Automated: pass | no liquid until the handle is pulled; no glass, no pour |
| 6 Angle and pour rate affect filling | Automated: pass | head formation vs. angle, fill vs. flow |
| 7 Liquid/foam visual responds | Automated (data) + screenshots | shader parameters follow the pour; tilted surface verified visually |
| 8 Under, over and correct fills | Automated: pass | underfilled, overflow spill, tilt spill, perfect pour >= 88 |
| 9 Settling and second top-up | Automated: pass | settle shelf, top-up, hurried top-up penalised |
| 10 Payment, satisfaction, tips | Automated: pass | |
| 11 Stock decreases; no duplication | Automated: pass | keg draw, failed draw takes nothing, glass total conserved at every step |
| 12 Glass cleaned and reused | Automated: pass | |
| 13 Close and new day | Automated: pass | |
| 14 Upgrades remove cash and change systems/visuals | Automated: pass | lamps become visible and the lights brighter |
| 15 Prices/expenses/profit | Automated: pass | rent, utilities, income totals |
| 16 Save/load | Automated: pass | including corrupted-save recovery from the backup |
| 17 Precision drinking mini-game | Not built yet | planned |
| 18 Darts | Not built yet | planned |
| 19 Music events | Not built yet | planned (music tracks exist) |
| 20 Touch-only controls | Automated (router) + design | no keyboard needed anywhere |
| 21 APK exports and is downloadable | CI | signed arm64 APK, signature verified, published as a Release |
| 22 Android launch / orientation / background-resume | **Not run**: no Android device or emulator available to the developer | please report |
| 23 No crashes / placeholder UI | Partial | headless runs and screenshots show no errors; untested on hardware |

## Not verified
- Frame rate and memory on the Galaxy S25 Ultra (or any phone). No FPS figures are claimed.
  Turn on *Settings → Show performance overlay* to see live FPS, draw calls and memory.
- Audio was generated and checked for length and format, but nobody has listened to it on a device.

## Feedback checklist for a phone test
1. Does it install and open in landscape?
2. Is movement and look comfortable? Try the sensitivity and opacity settings.
3. Can you complete a full pour, settle, top-up and serve?
4. Background the app mid-day, return: is the menu shown and the game intact?
5. Note the FPS from the overlay on a busy evening.
