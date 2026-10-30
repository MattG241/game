class_name PubLayout
extends RefCounted
## Shared coordinates for the pub floor plan (metres; +z towards the street door).

const ROOM_MIN := Vector2(-7.0, -5.0)
const ROOM_MAX := Vector2(7.0, 5.0)
const ROOM_H := 3.3
const BAR_X := Vector2(-7.0, 2.8)
const BAR_FRONT_Z := -1.75
const BAR_BACK_Z := -2.4
const BAR_TOP := 1.08
const BACK_COUNTER_Z := -4.65
const BACK_COUNTER_TOP := 0.95
const PARTITION_X := 3.6

## Every station sits along the bar top, served from behind (stout nearest the till end).
const TAP_X := {"stout": -1.6, "lager": -2.3, "ale": -3.0, "cider": -3.7, "zero": -4.3, "whiskey": -5.0, "soft": -5.7}
const TAP_Z := -2.08
const SETTLE_SLOTS := [Vector3(-1.15, BAR_TOP, -2.2), Vector3(-0.85, BAR_TOP, -2.2), Vector3(-0.55, BAR_TOP, -2.2)]
const RACK_POS := Vector3(-0.2, BACK_COUNTER_TOP, -4.62)
const SINK_POS := Vector3(1.2, BACK_COUNTER_TOP, -4.62)
const TILL_POS := Vector3(1.95, BAR_TOP, -2.05)
const FRIDGE_POS := Vector3(-2.4, 0.0, -4.62)
const OPTICS_X := -4.2
const BAR_SPOT_X := [-4.6, -3.4, -2.2, -1.0, 0.2, 1.4]
const BAR_SPOT_Z := -1.2
const SERVE_Z := -1.95

const DOOR_POS := Vector3(0.0, 0.0, 5.0)
const DOOR_SIGN_POS := Vector3(0.0, 1.58, 4.86)   # the hanging sign in the door's glass
const INSIDE_DOOR := Vector3(0.0, 0.0, 4.2)
const STREET_SPAWN_L := Vector3(-14.0, 0.0, 7.5)
const STREET_SPAWN_R := Vector3(14.0, 0.0, 7.5)
const OUTSIDE_DOOR := Vector3(0.0, 0.0, 6.0)
const QUEUE_POS := [Vector3(-0.5, 0.0, 0.4), Vector3(0.5, 0.0, 1.0), Vector3(-0.5, 0.0, 1.6), Vector3(0.5, 0.0, 2.2)]

const CELLAR_DOOR := Vector3(-6.2, 0.0, -5.0)
const CELLAR_MIN := Vector2(-7.0, -8.6)
const CELLAR_MAX := Vector2(-3.8, -5.0)
const KEG_POS := {"stout": Vector3(-6.5, 0.0, -6.0), "lager": Vector3(-6.5, 0.0, -6.8), "ale": Vector3(-6.5, 0.0, -7.6),
	"cider": Vector3(-5.6, 0.0, -6.8), "zero": Vector3(-5.6, 0.0, -7.6)}
const STOCK_PILE := Vector3(-4.6, 0.0, -7.8)

const FIREPLACE := Vector3(-7.0, 0.0, 2.2)
const DARTBOARD := Vector3(6.85, 1.73, 0.4)
const OCHE_X := 4.6
const STAGE_POS := Vector3(5.7, 0.0, 3.75)
const JUKEBOX_POS := Vector3(-6.45, 0.0, 4.4)
const PLAYER_START := Vector3(-0.6, 0.0, -3.2)
