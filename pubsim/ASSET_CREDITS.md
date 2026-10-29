# Asset credits & licences

| Asset | Source | Licence |
| --- | --- | --- |
| All 3D models (pub, furniture, taps, glasses, customers, street) | Generated procedurally by the game's GDScript (`scripts/world/pub_builder.gd`, `scripts/npc/customer.gd`, `scripts/world/mesh_kit.gd`) | Original work, part of this project |
| Materials: wood, tiles, plaster, stone, cobbles, glass, stout liquid | Original procedural shaders in `assets/shaders/` | Original work |
| Photographs on the walls | Procedurally generated sepia landscapes (`PubBuilder.make_photo`) | Original work |
| Synthesised sound effects (pour, bubbles, coins, bells, bodhrán, footsteps, UI...) and fallbacks for the recorded ones | Synthesised by `tools/gen_audio.py` (numpy oscillators, filtered noise, Karplus-Strong) | Original work |
| Soundtrack: 20 songs in `assets/music/` | Created by the game's owner (MattG241) with Suno; supplied via the `soundtrack-v1` release. Files are unmodified; checksums in `assets/music/SOUNDTRACK_MANIFEST.csv` | Owner's own tracks, subject to the owner's Suno licence. Check commercial rights before any public/commercial release |
| GALAGERS Irish Stout brand art (fiddle emblem, Celtic ring, wordmark, glass print, tap badge, coaster, signs, posters, mirror, keg label, menu) | Drawn by `tools/gen_brand.py` into `assets/brand/`; G-centre measurements in `data/brand.json` | Original work. An original fictional brand: it does not use Guinness's (or any brewery's) wordmark, harp, typefaces or glassware art |
| Recorded voice lines (`assets/voice/*.ogg`) | Generated once with ElevenLabs text-to-speech (model `eleven_v3`, ElevenLabs premade voices with accent tags) by `tools/elevenlabs/el.py` in GitHub Actions; the script is `data/voice_lines.json` and every clip's cost and transcript check is in `tools/elevenlabs/manifest.json` | Generated on the owner's **ElevenLabs free plan**: free-plan output is for **non-commercial use and requires attribution** ("Voices generated with ElevenLabs"). A paid ElevenLabs plan is needed before any commercial release |
| Recorded sound effects (`assets/sfx_el/*.ogg`) | Generated once with ElevenLabs sound effects by the same pipeline; ambience clips made seamless by `tools/make_loops.py` | Same ElevenLabs free-plan terms as the voices (non-commercial, attribution) |
| Reflection panorama (`assets/env/pub_reflection.png`), contact/edge shadow textures | Rendered from the game itself by `tools/bake/` and drawn by script | Original work |
| UI textures (timber, ivory, green lacquer, brass rims) | Drawn by `tools/gen_ui.py` | Original work |
| App icon & splash | Drawn by `tools/gen_icons.py` | Original work |
| Font: Uncial Antiqua | Astigmatic (Brian J. Bonislawsky), via Google Fonts | SIL Open Font License 1.1 (`assets/fonts/OFL-UncialAntiqua.txt`) |
| Font: Nunito | Vernon Adams, Cyreal, Jacques Le Bailly, via Google Fonts | SIL Open Font License 1.1 (`assets/fonts/OFL-Nunito.txt`) |
| Fonts: Cinzel and Cinzel Decorative (GALAGERS wordmark) | Natanael Gama, via Google Fonts | SIL Open Font License 1.1 (`assets/fonts/OFL-Cinzel.txt`, `assets/fonts/OFL-CinzelDecorative.txt`) |
| Engine | Godot Engine 4.4.1 | MIT |

Brands in the game (GALAGERS Irish Stout, Galagers Zero, Lough Glas Lager, Red Fox Ale, Orchard Gate Cider,
Ballyfinn 12, Brannock's Lemonade) and their artwork are fictional and original.
No real brewery's names, logos or glassware artwork are used, and no endorsement is implied.

**Attribution:** voices and recorded sound effects generated with ElevenLabs (free plan, non-commercial).
The API key lives only in the repository's `ELEVENLABS_API_KEY` Actions secret; it is never in the
game, the APK, the source, logs or screenshots, and the game never contacts ElevenLabs.
