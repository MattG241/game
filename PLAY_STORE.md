# Publishing Lunar Cleanup on Google Play (phone only)

Everything below works in Chrome on an Android phone. Nothing here needs a computer.

## What the build produces

Every push runs `.github/workflows/build-android.yml`, which publishes a GitHub Release with:

| File | What it is | Signed with |
| --- | --- | --- |
| `LunarCleanup.apk` | Install directly on your phone for testing | public development key (`android/`) |
| `LunarCleanup.aab` | Upload this to the Play Console | your **private upload key** (GitHub secrets) |

The `.aab` only appears once the upload-key secrets below exist.

> **Saves:** the Play version and the sideloaded APK are signed by different keys, so
> Android treats them as different signatures. Before you install the game from Play,
> uninstall the sideloaded APK (this deletes its local saves).

## 1. Add the upload key to GitHub (once)

You were sent `PLAY_UPLOAD_KEY_SECRETS.txt` privately. It is **not** in this repo and
never should be. In Chrome: **github.com/MattG241/game > Settings > Secrets and variables >
Actions > New repository secret**, and add the three secrets it lists:

- `PLAY_UPLOAD_KEYSTORE_BASE64`
- `PLAY_UPLOAD_KEYSTORE_ALIAS`
- `PLAY_UPLOAD_KEYSTORE_PASSWORD`

Keep the file safe (e.g. in Google Drive). Then re-run the latest build (Actions tab >
newest run > Re-run all jobs) and the release gets a `LunarCleanup.aab`.

## 2. Google Play Console

1. Create a developer account at <https://play.google.com/console> (one-off USD 25,
   identity verification takes a few days).
2. **Create app**: name *Lunar Cleanup*, Game, Free.
3. **Play App Signing** is on by default: Google holds the real app-signing key, your
   `.aab` is signed with the upload key. If the upload key is ever lost, Play support can
   reset it.
4. **New personal accounts must run a closed test first:** at least 12 testers opted in
   for 14 days before you can apply for production. Use *Test and release > Testing >
   Closed testing*, upload the `.aab`, add testers' Gmail addresses.
5. Upload: download `LunarCleanup.aab` from the GitHub release in Chrome, then in the
   release page tap *Upload* and pick it from Downloads. Every build has a higher version
   code automatically.

### Store listing

Use `store/README.md` (text) and `store/google_play/` (icon, feature graphic, screenshots).

### App content (Policy > App content)

- **Privacy policy URL:** <https://github.com/MattG241/game/blob/claude/slot-symbol-config-3721du/PRIVACY.md>
  (works once this branch is merged; until then use the copy on branch
  `ccr-5f39f0cd-uy7tpf`).
- **Ads:** Yes, the app contains ads.
- **Advertising ID:** Yes, used for *Advertising or marketing* (Google Mobile Ads SDK).
- **Target audience:** 13-15, 16-17 and 18+. Do **not** select under-13 ages: that puts the
  game under the Families policy, which requires different ad settings.
- **Content rating:** fill in the questionnaire (no violence, no user content, no
  gambling). It also asks about ads and purchases.
- **Data safety** (AdMob's declared data, Google's guide:
  <https://developers.google.com/admob/android/privacy/play-data-disclosure>):
  - Data collected: *Device or other IDs*; *App activity: app interactions*;
    *App info and performance: crash logs, diagnostics*; *Location: approximate*.
  - Purposes: Advertising or marketing, Analytics, Fraud prevention/security.
  - Shared with third parties: Yes (Google, for ads). Encrypted in transit: Yes.
    Users can request deletion: No (nothing is stored by the developer).
  - Purchase history is handled by Google Play itself.

## 3. "Remove ads" in-app product

After the first `.aab` is uploaded (to any test track):

1. Set up a payments profile (Play Console > Settings > Payments profile).
2. *Monetize with Play > Products > In-app products > Create product*.
3. Product ID **`remove_ads`** (must match `godot/data/ads.json`), name "Remove ads",
   pick a price, **Activate**.
4. Add your Gmail under *Settings > License testing* to buy it for free while testing.

## 4. AdMob (real ads and real money)

Until this step the game shows Google's **test ads** (safe, no revenue).

1. Sign up at <https://admob.google.com> with the same Google account, add payment info.
2. *Apps > Add app > Android*. If it is not on Play yet, say "No" and link it later.
3. Create two ad units: **Rewarded** and **Interstitial**.
4. Send Claude the **App ID** (`ca-app-pub-...~...`) and both **ad unit IDs**
   (`ca-app-pub-.../...`), or edit them yourself in the GitHub web editor:
   - `godot/data/ads.json`: `rewarded_unit_android`, `interstitial_unit_android`
   - `godot/project.godot`: add under `[admob]`:
     `general/android/app_id="ca-app-pub-XXXX~YYYY"`
5. In AdMob, open *Privacy & messaging* and publish a **GDPR message** (and the US states
   message). The game already shows it to players in regions that need it.
6. Never tap your own live ads. Add your phone as a test device in AdMob
   (*Settings > Test devices*) before playing a build with real IDs.
7. Optional but recommended: publish an `app-ads.txt` file on the website you list in
   Play (AdMob shows the exact line under *Apps > app-ads.txt*).

## How ads behave in the game

- **Rewarded (optional):** after selling at least 25 CR of dust, a "WATCH AD: DOUBLE IT"
  button shows for 8 seconds; with a low battery, "WATCH AD: FULL RECHARGE" appears
  (at most every 3 minutes). Nothing happens if the player ignores them.
- **Interstitial:** only right after selling at the Dust Exchange, never in the first
  10 minutes of play, at most once every 5 minutes, and never within 90 s of a rewarded ad.
- **Remove ads** (menu > GAME) stops interstitials permanently and is restored from Google
  Play on every launch / via *RESTORE PURCHASES*. Rewarded bonuses stay available.
- Offline, or with the SDK unavailable, the game simply shows no ads.

All timings live in `godot/data/ads.json`.
