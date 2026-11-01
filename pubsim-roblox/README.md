# The Irish Pub Simulator: Roblox edition

The same pub as the Android game, built for Roblox. Each player runs their own pub (it saves to
their account), and friends who join the server help out behind the bar. It plays on computers,
phones, tablets, Xbox and PlayStation.

Everything here is built automatically: GitHub turns the code into a Roblox place file, uploads
the songs and voices, and publishes the game every time this folder changes. You only have to
do the first-time setup below once.

## Getting it on Roblox (one time, about 10 minutes)

**1. Open the place in Roblox Studio and publish it**

1. Install Roblox Studio (free) from https://create.roblox.com and sign in.
2. Download the place file:
   https://github.com/MattG241/game/releases/download/roblox-latest/IrishPubSimulator.rbxlx
3. Double-click the file to open it in Studio.
4. Choose **File → Publish to Roblox**, pick **New experience**, call it
   *The Irish Pub Simulator*, and click **Create**.
5. Open the game in the Creator Dashboard (https://create.roblox.com/dashboard/creations).
   Click its **Start Place**. The long number in the address bar is the **place ID**; copy it.

**2. Make a key so GitHub can update the game for you**

1. Go to https://create.roblox.com/dashboard/credentials and click **Create API Key**.
2. Name it `pub-simulator`. Under **Access Permissions**, add:
   - **universe-places**: pick your game, tick **Write**
   - **universe**: pick your game, tick **Write** (turns on phones, tablets and consoles)
   - **assets**: tick **Read** and **Write** (uploads the songs and voices)
3. Under **Security**, add `0.0.0.0/0` as an allowed IP address (GitHub's computers change).
4. Click **Save & Generate Key** and copy the key. You only see it once.

**3. Give both to GitHub**

On https://github.com/MattG241/game/settings/secrets/actions, click **New repository secret**
twice:

| Name | Value |
|---|---|
| `ROBLOX_API_KEY` | the key from step 2 |
| `ROBLOX_PLACE_ID` | the place ID from step 1 |

Then open the **Actions** tab, choose **Irish Pub Simulator - Roblox**, and click
**Run workflow**. It uploads the audio and publishes the game in about 10 minutes.

**4. Let people play (18+ only: it's a pub)**

Roblox only allows games that show alcohol or a pub to ID-verified players aged 18+, and the
game must not show it before it has that label. Keep the game **Private** until both are done:

1. Verify your Roblox account with ID (Settings → Account Info → Verify my age).
2. In the Creator Dashboard, open the game → **Publish settings → Content rating**, answer the
   questionnaire honestly (Alcohol: yes). The game gets the **Restricted** label.
3. Tell Claude (or set `"restricted_label": true` in `publish.json`): from then on CI publishes
   each update. Then click **Make Public**.

See [ROBLOX_RULES.md](ROBLOX_RULES.md) for every Roblox rule this project follows.

That's it. From now on, every change pushed to this folder updates the live game on its own.

## Playing

| | Computer | Phone / tablet | Xbox / PlayStation |
|---|---|---|---|
| Move | WASD | thumbstick on screen | left stick |
| Use (pour, take order, flip sign) | E on the prompt | tap the prompt | the button shown on the prompt |
| Menu | Menu button or M | Menu button | Y (Triangle), B (Circle) to close |
| Goals | Goals button | Goals button | D-pad down |
| Tilt the glass | drag TILT or W/S | drag TILT | left stick |
| Pull the tap | drag TAP or hold Space | drag TAP | right trigger (gently = slow) |
| Done / leave to settle | buttons | buttons | B / Y |
| Auto tilt | button | button | X (Square) |

The screen scales itself to the device, so the same layout reads on a phone and on a TV.

## About the audio

Roblox limits how much audio a new account can upload each month, and checks every file. The
uploader sends the voices and sound effects first, then the songs. If the monthly limit is hit,
the game still works (without the missing songs) and the next run picks up where it stopped.
A verified Roblox account (ID or phone) gets a much higher limit.

## It looks like the phone game

The pub you walk round in Roblox is the phone game's own pub, not a copy built from blocks:

- **The room, the bar and every fitting** are exported from the Godot project by
  `pubsim/tools/roblox/export_world.tscn`. Every surface is baked with the phone game's own
  shaders and textures (the tiles, plaster, oak, stone, brass, bottles, beer mats, posters,
  shading in the corners) into textured meshes in `assets/world/`, with a manifest of where each
  piece goes, which upgrade it belongs to, the lights, the lettering and the floor plan. The
  Roblox scripts use that floor plan, so the seats, taps and bar line up with what you see.
- **The people** are not the phone game's characters: their texture maps broke Roblox's rules
  when uploaded (see ROBLOX_RULES.md), so they are not uploaded.
- **First person** behind the bar, with the glass you're holding in view, and the phone game's
  HUD layout and warm, low light.

To refresh the pub after changing it in the phone game, run the export (in `pubsim/`):

```
OUT=../pubsim-roblox/assets/world xvfb-run godot --rendering-driver opengl3 res://tools/roblox/export_world.tscn
```

and push: CI uploads anything new and publishes.

## What's in the Roblox version

- Pouring with the two-part stout, settling on the drip tray, the head and fill scoring, and the
  other drinks (lager, ale, cider, whiskey, soda), with stale kegs and keg changes in the cellar
- Customers who arrive, chat, order, wait, tip and leave, paced to how fast you serve
- Staff: hiring, the rota, skill and morale, raises and bonuses, traits, bar staff, glass
  collectors and cellar hands
- Upgrades, stock, prices, the ledger, daily goals and reputation
- Live music bookings, the jukebox, rain and the fire
- Saving to your Roblox account, with co-op helpers

These are still only in the Android version: darts, Split the G, the fireside pint, the bodhrán
session, stories, festivals, match days, lock-ins, beer-line cleaning and ice.

## For developers

- `src/shared` holds the game rules (no Roblox APIs), tested in CI with `luau tests/run.luau`
- `src/server` builds the pub and runs customers, staff, music and saving
- `src/client` holds the HUD, menus and pour close-up
- `tools/build_place.py` writes `build/IrishPubSimulator.rbxlx` (no Rojo needed)
- `tools/pack_audio.py` packs the clips into a few long files to stay under upload limits
- `tools/roblox_cloud.py` uploads audio and publishes through Roblox Open Cloud

The API key only ever lives in GitHub's secrets. It is never written into the code or the game.
