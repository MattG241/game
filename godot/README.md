# Lunar Cleanup

You're a cleaner for a badly underfunded lunar cleaning company. You start with one toothbrush. Clean the Moon, sell the dust, and build up a self-running lunar cleaning business.

It's a 3D first-person Android game (landscape) built with **Godot 4.7** in GDScript. It's single-player and works offline. It has optional Google AdMob ads (rewarded bonuses plus occasional full-screen ads) and a one-off "Remove ads" purchase - see [`PLAY_STORE.md`](../PLAY_STORE.md).

## Install on your phone (no computer needed)

1. In Chrome on Android, open:
   **https://github.com/MattG241/game/releases/latest/download/LunarCleanup.apk**
2. When the download finishes, tap it. If Android asks, allow Chrome to *install unknown apps*.
3. Tap **Install** (later updates show **Update**, and your saves are kept), then **Open**.

All builds: https://github.com/MattG241/game/releases. Each one comes from the
GitHub Actions workflow `.github/workflows/build-android.yml`, which runs on every push.

## Change the game from your phone

Edit any file on github.com or in the GitHub mobile app and commit. GitHub Actions then:
imports the project → runs the gameplay test suite → exports a signed ARM64 APK →
uploads it as an artifact **and** publishes a Release. The link above always points to the newest build.
You can also open `godot/` in the official Godot Android editor.

## What's in the game

- **Cleaning:** a persistent dirt mask per 32 m chunk (128×128 texels at 0.25 m), blended into the terrain by a shader.
  Tools stamp round, wide or beam shapes along your swipe path. Dust collected matches the dirt removed,
  so ground you've already cleaned gives nothing. Cleaning progress is saved with ZSTD compression.
- **12 tools**, from Toothbrush to Autonomous Swarm Controller. Each has 5 upgrade levels.
- **Suit upgrades:** tank, battery and boots.
- **4 vehicles** that use low-gravity suspension. The Vacuum Buggy and the Cleaning Truck clean the same dirt map as your tools.
- **Automation:** solar power, collectors, storage, conveyors, chargers, drone bays, rover garages,
  processors and shipping depots. Machines link into networks.
- **5 regions** unlocked with permits, **32 missions**, **13 achievements**, a **16-node research** tree, salvage and a crashed probe.
- **Touch controls:** floating joystick and swipe-to-look. Hold CLEAN and slide your thumb to sweep. You can change button
  layout, size and opacity, and turn on aim assist, vibration and a CLEAN toggle mode.
- **Performance:** Compatibility renderer, threaded chunk streaming with 2 LODs, MultiMesh rocks,
  30/60 FPS, quality presets, render scale and a developer overlay (FPS, ms, RAM, draw calls, chunks).
- **Saves:** 3 slots, autosave every 60 s and when the app goes to the background, atomic writes with `.bak` recovery,
  and versioned save data.

Balancing data lives in `godot/data/*.json`.

## Project layout

```
godot/                 Godot project (open project.godot)
  data/                balancing JSON (tools, vehicles, machines, missions, research, regions, economy)
  scripts/autoload/    Settings, GameData, GameState (economy), SaveManager, Audio
  scripts/world/       TerrainGen (deterministic), Terrain (streaming), DirtMap (cleaning), base, landmarks
  scripts/player/      Player, Cleaner (tool rig + stamping), ToolModels
  scripts/vehicles/    LunarVehicle
  scripts/automation/  AutomationSim (rules), Automation (visuals/placement), MachineModels
  scripts/ui/          HUD, TouchControls, GameMenu, MapView, SettingsPanel, MainMenu, UIKit
  shaders/             terrain, sky, earth, hard-surface, energy, brush ring
  tests/               test_runner (headless gameplay tests), shot (screenshot harness)
tools/                 gen_audio.py, gen_images.py (procedural audio/icon generation)
android/               signing key (see android/README.md)
```

## Licences

Godot Engine is MIT. Exo 2 and Rajdhani fonts are SIL OFL 1.1 (licence files are in `assets/fonts`).
All models, textures, sounds and music were generated procedurally for this project.
