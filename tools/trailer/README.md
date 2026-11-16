# Trailer

All footage is real gameplay rendered by the game (Godot Movie Maker), staged by
`godot/tests/trailer.gd` (one function per shot: `_clip_<name>`).

1. Record each shot at 1080p: `tools/trailer/rechd.sh <clip> <frames> 1920x1080 [--hud] [--from=12.5]`
   (clips: base brush third nugget beam gleam saucer truck machines hex map finale sky).
2. Title cards: `python3 tools/trailer/cards.py`.
3. Cut, grade and score (the game's own ending theme): `python3 tools/trailer/edit.py out.mp4`.

Paths in the scripts point at /tmp/claude-0/trailer; adjust them for another machine.
