-- Where everything is in the pub. The phone game's floor plan (in metres) scaled to Roblox studs,
-- with the gaps widened where Roblox avatars need more room. +Z is towards the street door.

local M = 3.2 -- studs per metre: a 1.7 m person is about the height of a Roblox avatar

local L = {}
L.M = M

local function v(x, y, z)
	return Vector3.new(x * M, y * M, z * M)
end
L.v = v

L.ROOM_MIN = Vector2.new(-7 * M, -5 * M)
L.ROOM_MAX = Vector2.new(7 * M, 5 * M)
L.ROOM_H = 3.4 * M
L.BAR_X = Vector2.new(-7 * M, 2.2 * M) -- the bar ends well short of the partition so avatars fit past
L.BAR_FRONT_Z = -1.75 * M
L.BAR_BACK_Z = -2.45 * M
L.BAR_TOP = 1.08 * M
L.BACK_COUNTER_Z = -4.65 * M
L.BACK_COUNTER_TOP = 0.95 * M
L.PARTITION_X = 3.6 * M

-- the taps along the bar, served from behind
L.TAP_X = { stout = -1.6, lager = -2.3, ale = -3.0, cider = -3.7, zero = -4.3, whiskey = -5.0, soft = -5.7 }
for k, x in L.TAP_X do
	L.TAP_X[k] = x * M
end
L.TAP_Z = -2.08 * M
L.SETTLE_SLOTS = { v(-1.05, 1.08, -2.15), v(-0.65, 1.08, -2.15), v(-0.25, 1.08, -2.15) }
L.RACK_POS = v(0.2, 0.95, -4.55)
L.SINK_POS = v(1.3, 0.95, -4.55)
L.TILL_POS = v(1.8, 1.08, -2.05)
L.BAR_SPOT_X = { -4.6, -3.4, -2.2, -1.0, 0.2, 1.4 }
for i, x in L.BAR_SPOT_X do
	L.BAR_SPOT_X[i] = x * M
end
L.BAR_SPOT_Z = -1.05 * M
L.BEHIND_Z = -3.1 * M

L.DOOR_POS = v(0, 0, 5)
L.INSIDE_DOOR = v(0, 0, 4.1)
L.OUTSIDE_DOOR = v(0, 0, 6.2)
L.STREET_L = v(-14, 0, 7.5)
L.STREET_R = v(14, 0, 7.5)
L.SIGN_POS = v(0, 1.75, 4.86)

L.CELLAR_DOOR = v(-6.2, 0, -5)
L.CELLAR_MIN = Vector2.new(-7 * M, -8.6 * M)
L.CELLAR_MAX = Vector2.new(-3.6 * M, -5 * M)
L.KEG_POS = { stout = v(-6.4, 0, -6.0), lager = v(-6.4, 0, -6.9), ale = v(-6.4, 0, -7.8),
	cider = v(-5.3, 0, -6.9), zero = v(-5.3, 0, -7.8) }

L.FIREPLACE = v(-7, 0, 2.2)
L.STAGE_POS = v(5.6, 0, 3.6)
L.JUKEBOX_POS = v(-6.4, 0, 4.3)
L.STAND_SPOTS = { v(-1.5, 0, 4.0), v(-0.9, 0, 3.4), v(1.6, 0, 4.0), v(2.2, 0, 3.4), v(-2.0, 0, 0.0),
	v(-2.6, 0, 0.6), v(0.9, 0, 0.6), v(3.4, 0, 1.0), v(-5.8, 0, -0.8), v(1.0, 0, -0.2) }
L.STAFF_BAR_HOME = v(-2.0, 0, -3.3)
L.STAFF_FLOOR_HOME = v(3.0, 0, -0.9)
L.PLAYER_START = v(-0.6, 0, -3.3)

-- the tables: centre and number of chairs; seats are built round them
L.TABLES = { { v(-4.4, 0, 0.9), 3 }, { v(-3.0, 0, 3.4), 4 }, { v(2.5, 0, 1.0), 4 }, { v(2.5, 0, 3.6), 3 } }

return L
