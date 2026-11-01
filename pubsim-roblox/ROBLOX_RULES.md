# Roblox rules this project follows

Roblox reviews every uploaded asset on its own, and a breach puts a strike on the owner's
account. Two character textures broke these rules on 1 November 2026 (see below), so every
change is checked against this list before it goes up, and CI runs `tools/check_assets.py`
before every upload.

Sources: Roblox's Community Standards, Terms of Use, the Content Maturity & Compliance guide
(`production/promotion/content-maturity.md` in Roblox's creator-docs) and Creator Store policy.

## 1. Alcohol: the game is 18+ only (Restricted)

A game that "includes, depicts, or references alcohol, or depicts adult businesses and locations
that provide or sell alcohol, such as characters drinking alcohol at a bar" must disclose it in
the Maturity & Compliance questionnaire, and is only available to **age-verified players aged
18+**. Roblox also says: "You must not add any age-restricted content to your game before
receiving this label."

So:
- The owner verifies their account with ID (18+), then answers the questionnaire with
  Alcohol = yes, which gives the **Restricted** label.
- Until then the game stays **Private**, and CI does not publish (`publish.json`:
  `"restricted_label": false`). Set it to `true` once the label is in place.
- If an update changes any answer (for example more mature content), the questionnaire must be
  answered again.

## 2. No sexual content, in any form, in any asset

Includes textures seen on their own, out of context: Roblox reviews each image separately.
**Never upload** skin texture maps of bodies (even ones always covered by clothes in the game),
MakeHuman or similar character textures, or anything showing anatomy. The phone game's people
are not uploaded at all. `check_assets.py` refuses skinned meshes and any image or mesh named
for skin, bodies or people.

## 3. No off-platform links

No web addresses, e-mail addresses, social handles or invites anywhere a player could read
them: textures, decals, signs, lettering, dialogue, data, UI text, audio. This includes
**watermarks and credits printed on textures** (a "makehuman.org" credit on a shirt texture
counted as a link). `check_assets.py` searches the game data, the pub's lettering and the
scripts' strings.

## 4. Only content we have the right to use

- The pub's surfaces are the phone game's own procedural materials and its own generated
  brand art ("Galagers" is a made-up brand), and the furniture is CC0 (Poly Haven).
- Music, voices and effects were generated for this game (ElevenLabs, with commercial rights)
  or made by its own tools. No commercial songs.
- No real brands, logos or trademarks.

## 5. Text from players is filtered

Anything a player types that others can see goes through `TextService:FilterStringAsync`
(the pub name on the sign). Chat is Roblox's own, which filters itself.

## 6. Uploads are deliberate

- CI only uploads from allowed folders (`assets/world`, the packed audio), only files not
  already uploaded (by content hash), and only after `check_assets.py` passes.
- While the account is under a moderation action Roblox refuses uploads; CI then warns and
  sends nothing.
- New kinds of asset (new textures, models, images) are checked against this list first.

## What was flagged, and why

| Asset | Reason | Cause |
|---|---|---|
| A character skin texture | Sexual Content | A MakeHuman skin map: a flat image of an unclothed body, reviewed on its own |
| A shirt texture | Directing Users Off-Platform | A tiny "makehuman.org" credit printed in its corner |

Both came from the phone game's characters, which are no longer part of the Roblox upload.
