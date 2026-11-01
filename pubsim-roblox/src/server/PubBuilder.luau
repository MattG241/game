-- Builds the pub from Roblox parts when the server starts: the room, the bar and its taps, the back
-- bar, seating, the fireplace, the lamps, the door with its OPEN/CLOSED sign, the cellar and the
-- street outside. Returns `info`: where the interactive things are, for the rest of the server.
-- Parts belonging to an upgrade are tagged so they appear (or disappear) when it's bought.

local ServerStorage = game:GetService("ServerStorage")
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)

local M = Layout.M
local v = Layout.v

local Builder = {}

-- colours
local C = {
	floor = Color3.fromRGB(74, 46, 30), beam = Color3.fromRGB(58, 36, 22), oak = Color3.fromRGB(96, 58, 32),
	darkOak = Color3.fromRGB(52, 30, 17), barTop = Color3.fromRGB(70, 30, 14), plasterOld = Color3.fromRGB(176, 150, 104),
	plasterNew = Color3.fromRGB(214, 196, 156), tileOld = Color3.fromRGB(96, 80, 58), tileGreen = Color3.fromRGB(18, 78, 50),
	brass = Color3.fromRGB(196, 150, 72), iron = Color3.fromRGB(30, 30, 32), cream = Color3.fromRGB(232, 222, 196),
	green = Color3.fromRGB(20, 70, 44), shopGreen = Color3.fromRGB(16, 58, 38), stone = Color3.fromRGB(120, 112, 100),
	gold = Color3.fromRGB(226, 182, 92), glass = Color3.fromRGB(200, 220, 220), leather = Color3.fromRGB(82, 18, 14),
	warm = Color3.fromRGB(255, 196, 128), ceiling = Color3.fromRGB(120, 92, 58),
}
Builder.C = C

local info
local root

local function L_W()
	return Layout.ROOM_MAX.X - Layout.ROOM_MIN.X
end

local function L_D()
	return Layout.ROOM_MAX.Y - Layout.ROOM_MIN.Y
end

local function part(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = if typeof(cf) == "Vector3" then CFrame.new(cf) else cf
	p.Color = color or C.oak
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, val in props do
			(p :: any)[k] = val
		end
	end
	p.Parent = parent
	return p
end
Builder.part = part

local function cyl(parent, radius, height, cf, color, material, props)
	-- Roblox cylinders run along X; turned upright here
	local base = if typeof(cf) == "Vector3" then CFrame.new(cf) else cf
	local p = part(parent, Vector3.new(height, radius * 2, radius * 2), base * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
Builder.cyl = cyl

local function ball(parent, radius, pos, color, material, props)
	local p = part(parent, Vector3.new(radius * 2, radius * 2, radius * 2), pos, color, material, props)
	p.Shape = Enum.PartType.Ball
	return p
end
Builder.ball = ball

local function folder(name, parent)
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = parent or root
	return f
end

-- Lettering on a face of a part (a sign, a badge, a chalkboard).
local function letter(p, face, text, color, font, opts)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = (opts and opts.ppu) or 60
	sg.LightInfluence = (opts and opts.light) or 1
	sg.Brightness = (opts and opts.brightness) or 1
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color or C.gold
	t.Font = font or Enum.Font.Garamond
	t.TextScaled = true
	t.TextWrapped = true
	t.Parent = sg
	return t
end
Builder.letter = letter

-- Parts that only exist once an upgrade is bought (show) or until it is (hide).
local function tag(id, inst, show)
	local key = if show == false then "upgradeHide" else "upgradeShow"
	info[key][id] = info[key][id] or {}
	table.insert(info[key][id], inst)
	return inst
end

-- Shows the pub as it should look with these upgrades.
function Builder.applyUpgrades(state)
	local hidden = ServerStorage:FindFirstChild("PubHidden") or Instance.new("Folder")
	hidden.Name = "PubHidden"
	hidden.Parent = ServerStorage
	for id, list in info.upgradeShow do
		for _, inst in list do
			inst.Parent = if state:hasUpgrade(id) then info.homes[inst] else hidden
		end
	end
	for id, list in info.upgradeHide do
		for _, inst in list do
			inst.Parent = if state:hasUpgrade(id) then hidden else info.homes[inst]
		end
	end
end

local function remember(list)
	for _, group in list do
		for _, inst in group do
			info.homes[inst] = inst.Parent
		end
	end
end

-- ---------------------------------------------------------------- the room
local function buildRoom()
	local g = folder("Room")
	local w = L_W()
	local d = L_D()
	local h = Layout.ROOM_H
	part(g, Vector3.new(w + 2, 1, d + 2), Vector3.new(0, -0.5, 0), C.floor, Enum.Material.WoodPlanks)
	part(g, Vector3.new(w, 1, d), Vector3.new(0, h + 0.5, 0), C.ceiling, Enum.Material.Plaster)
	for i = 0, 5 do
		local x = Layout.ROOM_MIN.X + 1.2 * M + i * 2.3 * M
		part(g, Vector3.new(0.7, 0.8, d), Vector3.new(x, h - 0.4, 0), C.beam, Enum.Material.Wood)
	end
	-- side and back walls: tiles below the dado rail, plaster above (fresh paint and green tiles
	-- with the Renovation upgrade)
	local walls = {
		{ CFrame.new(Layout.ROOM_MIN.X - 0.5, h / 2, 0), Vector3.new(1, h, d), Vector3.new(1, 0, 0) },
		{ CFrame.new(Layout.ROOM_MAX.X + 0.5, h / 2, 0), Vector3.new(1, h, d), Vector3.new(-1, 0, 0) },
	}
	-- the back wall has a doorway to the cellar
	local cdx = Layout.CELLAR_DOOR.X
	local leftW = (cdx - 1.6) - Layout.ROOM_MIN.X
	table.insert(walls, { CFrame.new(Layout.ROOM_MIN.X + leftW / 2, h / 2, Layout.ROOM_MIN.Y - 0.5), Vector3.new(leftW, h, 1), Vector3.new(0, 0, 1) })
	local rightW = Layout.ROOM_MAX.X - (cdx + 1.6)
	table.insert(walls, { CFrame.new(cdx + 1.6 + rightW / 2, h / 2, Layout.ROOM_MIN.Y - 0.5), Vector3.new(rightW, h, 1), Vector3.new(0, 0, 1) })
	part(g, Vector3.new(3.2, h - 7, 1), Vector3.new(cdx, 7 + (h - 7) / 2, Layout.ROOM_MIN.Y - 0.5), C.plasterOld, Enum.Material.Plaster)
	local dado = 1.15 * M
	for _, wd in walls do
		local cf, size, inward = wd[1], wd[2], wd[3]
		part(g, size, cf, C.plasterOld, Enum.Material.Plaster)
		local skin = inward * 0.55
		local lowSize = Vector3.new(if size.X > 1 then size.X else 0.1, dado, if size.Z > 1 then size.Z else 0.1)
		local upSize = Vector3.new(lowSize.X, size.Y - dado, lowSize.Z)
		local base = cf.Position
		local low = Vector3.new(base.X, dado / 2, base.Z) + skin
		local up = Vector3.new(base.X, dado + (size.Y - dado) / 2, base.Z) + skin
		tag("paint", part(g, lowSize, low, C.tileOld, Enum.Material.CeramicTiles), false)
		tag("paint", part(g, upSize, up, C.plasterOld, Enum.Material.Plaster), false)
		tag("paint", part(g, lowSize, low + inward * 0.02, C.tileGreen, Enum.Material.CeramicTiles))
		tag("paint", part(g, upSize, up + inward * 0.02, C.plasterNew, Enum.Material.Plaster))
		-- dado and picture rails
		part(g, Vector3.new(math.max(lowSize.X, 0.35), 0.25, math.max(lowSize.Z, 0.35)), Vector3.new(base.X, dado, base.Z) + inward * 0.65, C.darkOak, Enum.Material.Wood)
		part(g, Vector3.new(math.max(lowSize.X, 0.25), 0.18, math.max(lowSize.Z, 0.25)), Vector3.new(base.X, 2.6 * M, base.Z) + inward * 0.62, C.darkOak, Enum.Material.Wood)
	end
	-- partition behind the end of the bar
	local pz = (Layout.ROOM_MIN.Y + Layout.BAR_BACK_Z) / 2
	part(g, Vector3.new(0.6, h, Layout.BAR_BACK_Z - Layout.ROOM_MIN.Y), Vector3.new(Layout.PARTITION_X, h / 2, pz), C.darkOak, Enum.Material.Wood)
end

-- ---------------------------------------------------------------- the bar
local function buildBar()
	local g = folder("Bar")
	local x0, x1 = Layout.BAR_X.X, Layout.BAR_X.Y
	local len = x1 - x0
	local cx = (x0 + x1) / 2
	local zf, zb = Layout.BAR_FRONT_Z, Layout.BAR_BACK_Z
	local depth = zf - zb
	local cz = (zf + zb) / 2
	local top = Layout.BAR_TOP
	part(g, Vector3.new(len, top - 0.25, depth - 0.3), Vector3.new(cx, (top - 0.25) / 2, cz - 0.1), C.oak, Enum.Material.Wood)
	part(g, Vector3.new(len + 0.4, 0.25, depth + 0.4), Vector3.new(cx, top - 0.125, cz), C.barTop, Enum.Material.Wood, { Reflectance = 0.06 })
	-- raised panels on the customer side
	local panels = math.floor(len / (0.9 * M))
	for i = 0, panels - 1 do
		local px = x0 + (i + 0.5) * (len / panels)
		part(g, Vector3.new(len / panels - 0.5, 1.9, 0.1), Vector3.new(px, 1.6, zf + 0.02), C.darkOak, Enum.Material.Wood)
	end
	-- the foot rail: dull before the Brass Foot Rail upgrade, gleaming after
	tag("brass_rail", cyl(g, 0.08, len, CFrame.new(cx, 0.6, zf + 0.8) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(110, 92, 60), Enum.Material.Metal), false)
	tag("brass_rail", cyl(g, 0.09, len, CFrame.new(cx, 0.6, zf + 0.8) * CFrame.Angles(0, 0, math.rad(90)), C.brass, Enum.Material.Metal, { Reflectance = 0.2 }))
	-- drip tray where stouts settle
	tag("drip_tray", part(g, Vector3.new(4.8, 0.08, 1.0), Vector3.new(-2.0 * M, top + 0.04, -2.15 * M), C.brass, Enum.Material.DiamondPlate))
	-- the till
	local till = part(g, Vector3.new(1.4, 1.0, 1.0), Layout.TILL_POS + Vector3.new(0, 0.5, 0), C.iron, Enum.Material.Metal)
	letter(till, Enum.NormalId.Front, "€", C.gold)
	-- back counter, rack and sink
	local bz = Layout.BACK_COUNTER_Z
	part(g, Vector3.new(x1 - x0 + 2, Layout.BACK_COUNTER_TOP, 1.8), Vector3.new(cx + 1, Layout.BACK_COUNTER_TOP / 2, bz), C.darkOak, Enum.Material.Wood)
	part(g, Vector3.new(x1 - x0 + 2, 0.15, 2.0), Vector3.new(cx + 1, Layout.BACK_COUNTER_TOP, bz), C.barTop, Enum.Material.Wood)
	info.rack = part(g, Vector3.new(3.2, 0.12, 1.4), Layout.RACK_POS + Vector3.new(0, 0.1, 0), C.iron, Enum.Material.Metal)
	info.rack.Name = "GlassRack"
	info.sink = part(g, Vector3.new(2.2, 0.5, 1.4), Layout.SINK_POS + Vector3.new(0, 0.1, 0), Color3.fromRGB(170, 175, 180), Enum.Material.Metal)
	info.sink.Name = "Sink"
	cyl(g, 0.08, 1.0, CFrame.new(Layout.SINK_POS + Vector3.new(0, 0.9, -0.6)), Color3.fromRGB(190, 190, 195), Enum.Material.Metal)
	-- shelves of bottles on the back wall, lit from above
	local wallZ = Layout.ROOM_MIN.Y + 0.6
	local bottleCols = { Color3.fromRGB(110, 60, 20), Color3.fromRGB(40, 90, 40), Color3.fromRGB(150, 110, 40),
		Color3.fromRGB(200, 200, 205), Color3.fromRGB(90, 20, 20), Color3.fromRGB(60, 40, 20) }
	for row = 0, 1 do
		local y = 1.55 * M + row * 0.55 * M
		part(g, Vector3.new(len - 2, 0.15, 1.2), Vector3.new(cx - 0.6, y, wallZ + 0.4), C.darkOak, Enum.Material.Wood)
		for i = 0, math.floor((len - 3) / 0.75) do
			local bx = x0 + 1.2 + i * 0.75
			if bx < x1 - 1.5 then
				local col = bottleCols[(i * 7 + row * 3) % #bottleCols + 1]
				local hgt = 1.2 + ((i * 13 + row) % 4) * 0.12
				cyl(g, 0.2, hgt, Vector3.new(bx, y + 0.08 + hgt / 2, wallZ + 0.45), col, Enum.Material.Glass, { Transparency = 0.15 })
				cyl(g, 0.08, 0.35, Vector3.new(bx, y + 0.08 + hgt + 0.17, wallZ + 0.45), col, Enum.Material.Glass, { Transparency = 0.15 })
			end
		end
	end
	local shelfLight = Instance.new("SurfaceLight")
	shelfLight.Face = Enum.NormalId.Bottom
	shelfLight.Color = C.warm
	shelfLight.Brightness = 1.4
	shelfLight.Range = 9
	shelfLight.Angle = 90
	shelfLight.Parent = part(g, Vector3.new(len - 2, 0.15, 0.6), Vector3.new(cx - 0.6, 2.85 * M, wallZ + 0.4), C.darkOak, Enum.Material.Wood)
	-- the illuminated GALAGERS sign over the back bar
	local sign = part(g, Vector3.new(5, 1.4, 0.2), Vector3.new(-1.8 * M, 2.95 * M, wallZ + 0.1), Color3.fromRGB(14, 12, 10), Enum.Material.SmoothPlastic)
	letter(sign, Enum.NormalId.Back, "GALAGERS", C.gold, Enum.Font.Garamond, { light = 0, brightness = 1.5 })
	local sl = Instance.new("PointLight")
	sl.Color = C.warm
	sl.Brightness = 0.8
	sl.Range = 8
	sl.Parent = sign
end

-- ---------------------------------------------------------------- taps and stations
local DRINK_UNLOCK = { lager = "lager_tap", ale = "ale_pump", cider = "drinks_fridge", zero = "drinks_fridge",
	whiskey = "whiskey_optics", soft = "soda_gun" }
local HANDLE_COL = { stout = Color3.fromRGB(16, 14, 12), lager = Color3.fromRGB(230, 200, 90), ale = Color3.fromRGB(150, 60, 20),
	cider = Color3.fromRGB(120, 160, 60), zero = Color3.fromRGB(40, 40, 44), whiskey = Color3.fromRGB(150, 100, 40), soft = Color3.fromRGB(200, 200, 205) }

local function buildTaps()
	local g = folder("Taps")
	for id, x in Layout.TAP_X do
		local station = folder("Tap_" .. id, g)
		local base = Vector3.new(x, Layout.BAR_TOP, Layout.TAP_Z)
		local nozzleY = Layout.BAR_TOP + 2.6
		if id == "whiskey" then
			-- an optic: the bottle hangs upside down over a measure
			cyl(station, 0.12, 2.8, base + Vector3.new(0, 1.4, -0.6), C.brass, Enum.Material.Metal)
			cyl(station, 0.4, 1.4, CFrame.new(base + Vector3.new(0, 3.7, 0)), Color3.fromRGB(150, 100, 40), Enum.Material.Glass, { Transparency = 0.2 })
			cyl(station, 0.15, 0.5, base + Vector3.new(0, 2.85, 0), C.cream, Enum.Material.Glass, { Transparency = 0.4 })
		else
			-- a brass font with a tap handle
			cyl(station, 0.22, 2.6, base + Vector3.new(0, 1.3, -0.35), C.brass, Enum.Material.Metal, { Reflectance = 0.15 })
			part(station, Vector3.new(0.3, 0.25, 0.7), base + Vector3.new(0, nozzleY - Layout.BAR_TOP + 0.05, -0.05), C.brass, Enum.Material.Metal)
			cyl(station, 0.06, 0.35, base + Vector3.new(0, nozzleY - Layout.BAR_TOP - 0.15, 0.15), C.brass, Enum.Material.Metal)
		end
		local handle = part(station, Vector3.new(0.28, 1.3, 0.28), base + Vector3.new(0, nozzleY - Layout.BAR_TOP + 0.75, -0.3), HANDLE_COL[id] or C.iron, Enum.Material.SmoothPlastic)
		handle.Name = "Handle"
		local badge = part(station, Vector3.new(0.75, 0.75, 0.08), base + Vector3.new(0, nozzleY - Layout.BAR_TOP + 1.2, -0.12), Color3.fromRGB(16, 14, 12), Enum.Material.SmoothPlastic)
		local short = { stout = "GALAGERS", lager = "LAGER", ale = "RED FOX", cider = "CIDER", zero = "ZERO", whiskey = "WHISKEY", soft = "SODA" }
		letter(badge, Enum.NormalId.Front, short[id] or id, C.gold, Enum.Font.Garamond)
		letter(badge, Enum.NormalId.Back, short[id] or id, C.gold, Enum.Font.Garamond)
		local nozzle = base + Vector3.new(0, nozzleY - Layout.BAR_TOP - 0.3, 0.15)
		info.taps[id] = { model = station, handle = handle, nozzle = nozzle, glassPos = Vector3.new(x, Layout.BAR_TOP, Layout.TAP_Z + 0.15), prompt = badge }
		if DRINK_UNLOCK[id] then
			tag(DRINK_UNLOCK[id], station)
		end
	end
end

-- ---------------------------------------------------------------- seating
local function chair(g, pos, lookAt, kind)
	local cf = CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z))
	-- a plain part, not a Seat: nobody gets pulled into a chair by walking past it
	local seat = part(g, if kind == "armchair" then Vector3.new(2.6, 0.6, 2.4) else Vector3.new(1.8, 0.3, 1.8),
		cf * CFrame.new(0, (if kind == "armchair" then 1.3 else 1.45), 0),
		if kind == "armchair" then Color3.fromRGB(40, 70, 46) else C.oak,
		if kind == "armchair" then Enum.Material.Fabric else Enum.Material.Wood)
	seat.Name = "Seat"
	if kind == "armchair" then
		part(g, Vector3.new(2.6, 2.4, 0.5), cf * CFrame.new(0, 2.2, 1.1), Color3.fromRGB(40, 70, 46), Enum.Material.Fabric)
		for sx = -1, 1, 2 do
			part(g, Vector3.new(0.4, 0.9, 2.4), cf * CFrame.new(sx * 1.2, 1.9, 0), Color3.fromRGB(40, 70, 46), Enum.Material.Fabric)
		end
		part(g, Vector3.new(2.6, 1.0, 2.4), cf * CFrame.new(0, 0.5, 0), C.darkOak, Enum.Material.Wood)
	else
		part(g, Vector3.new(1.8, 2.0, 0.2), cf * CFrame.new(0, 2.5, 0.85), C.oak, Enum.Material.Wood)
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				part(g, Vector3.new(0.18, 1.4, 0.18), cf * CFrame.new(sx * 0.75, 0.7, sz * 0.75), C.darkOak, Enum.Material.Wood)
			end
		end
	end
	return seat
end

-- The APK's own seats: an invisible seat exactly where each of its chairs, armchairs and booth
-- benches is (the chairs themselves are part of the APK pub, loaded by ApkWorld).
local SEAT_H = { chair = 0.46, armchair = 0.42, booth = 0.45, stool = 0.74 }
local function buildApkSeats(g)
	for _, st in Layout.SEATS do
		local y = (SEAT_H[st.kind] or 0.46) * M + st.sitY
		local pos = Vector3.new(st.pos.X, y - 0.1, st.pos.Z)
		local look = if st.table then Vector3.new(st.table.X, pos.Y, st.table.Z)
			else pos - Vector3.new(math.sin(st.yaw), 0, math.cos(st.yaw))
		if (look - pos).Magnitude < 0.01 then
			look = pos - Vector3.new(math.sin(st.yaw), 0, math.cos(st.yaw))
		end
		local seat = part(g, Vector3.new(1.6, 0.2, 1.6), CFrame.lookAt(pos, look), C.oak, Enum.Material.Wood, { Transparency = 1 })
		seat.Name = "Seat"
		seat.CanCollide = false
		local entry = { seat = seat, table = st.table or look, kind = if st.kind == "booth" then "booth" else st.kind }
		if st.kind == "booth" then
			entry.upgrade = "booths"
		end
		table.insert(info.seats, entry)
	end
	for i, x in Layout.BAR_SPOT_X do
		info.barSpots[i] = Vector3.new(x, 0, Layout.BAR_SPOT_Z)
	end
end

local function buildSeating()
	local g = folder("Seating")
	if Layout.SEATS then
		buildApkSeats(g)
		return
	end
	for _, t in Layout.TABLES do
		local p, n = t[1], t[2]
		cyl(g, 1.55, 0.18, p + Vector3.new(0, 2.45, 0), C.darkOak, Enum.Material.Wood, { Reflectance = 0.05 })
		cyl(g, 0.15, 2.4, p + Vector3.new(0, 1.2, 0), C.iron, Enum.Material.Metal)
		cyl(g, 0.9, 0.12, p + Vector3.new(0, 0.06, 0), C.iron, Enum.Material.Metal)
		local candle = cyl(g, 0.12, 0.35, p + Vector3.new(0, 2.72, 0), C.cream, Enum.Material.SmoothPlastic)
		local fl = Instance.new("PointLight")
		fl.Color = C.warm
		fl.Brightness = 0.5
		fl.Range = 6
		fl.Parent = candle
		for i = 0, n - 1 do
			local a = (i / n) * math.pi * 2 + 0.4
			local dir = Vector3.new(math.sin(a), 0, math.cos(a))
			local sp = p + dir * 2.6
			local seat = chair(g, sp, p, "chair")
			table.insert(info.seats, { seat = seat, table = p + Vector3.new(0, 2.55, 0) + dir * 0.6, kind = "chair" })
		end
	end
	-- fireside armchairs, facing each other across the hearth
	local fp = Layout.FIREPLACE
	for _, dz in { -1.3, 1.3 } do
		local p = fp + Vector3.new(3.2, 0, dz * M)
		local seat = chair(g, p, fp + Vector3.new(4.5, 0, 0), "armchair")
		table.insert(info.seats, { seat = seat, table = p + Vector3.new(0.6, 2.0, -dz * 0.9), kind = "armchair" })
	end
	-- bar stools between the service spots
	for i = 1, #Layout.BAR_SPOT_X - 1 do
		local x = (Layout.BAR_SPOT_X[i] + Layout.BAR_SPOT_X[i + 1]) / 2
		local sp = Vector3.new(x, 0, Layout.BAR_FRONT_Z + 1.4)
		cyl(g, 0.9, 0.3, sp + Vector3.new(0, 2.5, 0), C.leather, Enum.Material.Leather)
		cyl(g, 0.15, 2.4, sp + Vector3.new(0, 1.2, 0), C.brass, Enum.Material.Metal)
	end
	for i, x in Layout.BAR_SPOT_X do
		info.barSpots[i] = Vector3.new(x, 0, Layout.BAR_SPOT_Z)
	end
	-- booths (upgrade) along the right wall
	local booth = folder("Booths", g)
	local bp = Vector3.new(Layout.ROOM_MAX.X - 4, 0, -1.25 * M)
	part(booth, Vector3.new(3.4, 2.4, 2), bp + Vector3.new(0, 1.2, 0), C.darkOak, Enum.Material.Wood)
	part(booth, Vector3.new(3.6, 0.2, 2.2), bp + Vector3.new(0, 2.45, 0), C.barTop, Enum.Material.Wood)
	for _, sz in { -1, 1 } do
		local cf = CFrame.lookAt(bp + Vector3.new(0, 0, sz * 2.4), bp)
		part(booth, Vector3.new(3.6, 1.4, 1.6), cf * CFrame.new(0, 0.7, 0), C.darkOak, Enum.Material.Wood)
		part(booth, Vector3.new(3.6, 3.5, 0.5), cf * CFrame.new(0, 2.4, 1.0), C.leather, Enum.Material.Leather)
		local seat = part(booth, Vector3.new(3.4, 0.3, 1.6), cf * CFrame.new(0, 1.45, 0), C.leather, Enum.Material.Leather)
		seat.Name = "Seat"
		table.insert(info.seats, { seat = seat, table = bp + Vector3.new(0, 2.55, sz * 0.6), kind = "booth", upgrade = "booths" })
	end
	tag("booths", booth)
end

-- ---------------------------------------------------------------- fireplace, lamps, decor
local function buildFireplace()
	local g = folder("Fireplace")
	local p = Layout.FIREPLACE
	for _, dz in { -2.6, 2.6 } do
		part(g, Vector3.new(1.6, 4.5, 1.1), p + Vector3.new(0.8, 2.25, dz), C.stone, Enum.Material.Slate)
	end
	part(g, Vector3.new(1.8, 1.1, 6.3), p + Vector3.new(0.85, 4.0, 0), C.stone, Enum.Material.Slate)
	part(g, Vector3.new(2.3, 0.3, 7.0), p + Vector3.new(1.1, 4.7, 0), C.darkOak, Enum.Material.Wood)
	part(g, Vector3.new(1.4, 6.0, 6.1), p + Vector3.new(0.7, 7.85, 0), C.stone, Enum.Material.Slate)
	part(g, Vector3.new(0.3, 3.4, 4.0), p + Vector3.new(0.2, 1.7, 0), Color3.fromRGB(12, 10, 8), Enum.Material.SmoothPlastic)
	part(g, Vector3.new(2.8, 0.12, 6.4), p + Vector3.new(1.4, 0.06, 0), Color3.fromRGB(70, 66, 62), Enum.Material.Slate)
	-- the turf fire (upgrade) or a cold grate of ash
	local ash = part(g, Vector3.new(1.2, 0.15, 2.2), p + Vector3.new(1.0, 0.15, 0), Color3.fromRGB(60, 58, 55), Enum.Material.Sand)
	tag("fireplace", ash, false)
	local fireRoot = folder("Fire", g)
	local turf = part(fireRoot, Vector3.new(1.0, 0.5, 2.0), p + Vector3.new(1.0, 0.35, 0), Color3.fromRGB(50, 30, 20), Enum.Material.Ground)
	local fire = Instance.new("Fire")
	fire.Heat = 9
	fire.Size = 5
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 10)
	fire.Parent = turf
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Brightness = 2.2
	light.Range = 18
	light.Shadows = true
	light.Parent = turf
	info.fireLight = light
	tag("fireplace", fireRoot)
	-- a rug in front of it
	part(g, Vector3.new(3.6, 0.05, 5.4), p + Vector3.new(4.6, 0.03, 0), Color3.fromRGB(130, 30, 26), Enum.Material.Fabric)
	-- the mantel clock
	part(g, Vector3.new(0.6, 1.0, 1.2), p + Vector3.new(1.2, 5.35, 1.6), C.darkOak, Enum.Material.Wood)
end

local function buildLamps()
	local g = folder("Lamps")
	local spots = { v(-4.5, 0, 0.9), v(-3.0, 0, 3.4), v(2.5, 0, 1.0), v(2.6, 0, 3.6), v(-3.8, 0, -2.0), v(-0.8, 0, -2.0), v(1.6, 0, -2.0) }
	for _, p in spots do
		local hang = Layout.ROOM_H - 2.4
		cyl(g, 0.04, 2.4, p + Vector3.new(0, Layout.ROOM_H - 1.2, 0), C.iron, Enum.Material.Metal)
		-- a bare dim bulb until the lamps are restored
		local bare = ball(g, 0.25, p + Vector3.new(0, hang - 0.2, 0), Color3.fromRGB(255, 220, 160), Enum.Material.Neon)
		tag("lamps", bare, false)
		local shade = folder("Pendant", g)
		cyl(shade, 0.9, 0.6, p + Vector3.new(0, hang - 0.1, 0), C.brass, Enum.Material.Metal, { Reflectance = 0.1 })
		ball(shade, 0.3, p + Vector3.new(0, hang - 0.45, 0), Color3.fromRGB(255, 226, 170), Enum.Material.Neon)
		tag("lamps", shade)
		-- the light itself, thrown down in a pool over the table (dimmer before restoration)
		local holder = part(g, Vector3.new(0.2, 0.2, 0.2), p + Vector3.new(0, hang - 0.5, 0), C.iron, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 110
		spot.Range = 18
		spot.Brightness = 1.2
		spot.Color = Color3.fromRGB(255, 205, 150)
		spot.Shadows = true
		spot.Parent = holder
		table.insert(info.lamps, spot)
	end
	-- brass wall sconces casting a fan of light up the side walls
	for _, sc in { { v(-6.85, 2.0, -2.6), 1 }, { v(-6.85, 2.0, 3.9), 1 }, { v(6.85, 2.0, 1.5), -1 }, { v(6.85, 2.0, -3.7), -1 } } do
		local p, dir = sc[1], sc[2]
		local s = part(g, Vector3.new(0.6, 0.6, 0.6), p + Vector3.new(dir * 0.2, 0, 0), Color3.fromRGB(255, 220, 170), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 190, 120)
		pl.Brightness = 0.9
		pl.Range = 10
		pl.Parent = s
	end
	-- a soft fill so corners are never pitch black
	local fill = part(g, Vector3.new(0.2, 0.2, 0.2), v(0, 3.0, 1.5), C.iron, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
	local fl = Instance.new("PointLight")
	fl.Color = Color3.fromRGB(255, 210, 170)
	fl.Brightness = 0.35
	fl.Range = 40
	fl.Parent = fill
end

local function buildDecor()
	local g = folder("Decor")
	-- framed photographs (upgrade: Old Photos of the Town)
	local photos = folder("Photos", g)
	for i = 0, 4 do
		local p = Vector3.new(Layout.ROOM_MIN.X + 0.25, 1.9 * M + (i % 2) * 0.8, -0.8 * M + i * 2.4)
		part(photos, Vector3.new(0.15, 1.5, 2.0), p, C.darkOak, Enum.Material.Wood)
		part(photos, Vector3.new(0.05, 1.2, 1.7), p + Vector3.new(0.09, 0, 0), Color3.fromRGB(150, 120, 86), Enum.Material.SmoothPlastic)
	end
	tag("photos", photos)
	-- the chalkboard by the door (upgrade)
	local cb = part(g, Vector3.new(3.0, 3.6, 0.15), Vector3.new(1.9 * M, 1.7 * M, Layout.ROOM_MAX.Y - 0.3), Color3.fromRGB(26, 30, 28), Enum.Material.Slate)
	letter(cb, Enum.NormalId.Back, "Tonight\n~\nGalagers Irish Stout\nperfectly poured\n\nTrad & tunes", Color3.fromRGB(235, 235, 225), Enum.Font.IndieFlower)
	info.chalkboard = cb
	tag("chalkboard", cb)
	-- a big GALAGERS mirror on the right wall
	local mirror = part(g, Vector3.new(0.12, 2.0, 4.6), Vector3.new(Layout.ROOM_MAX.X - 0.3, 1.9 * M, -1.55 * M), Color3.fromRGB(190, 200, 205), Enum.Material.Glass, { Reflectance = 0.5 })
	letter(mirror, Enum.NormalId.Left, "GALAGERS\nIrish Stout", C.gold, Enum.Font.Garamond)
	-- the jukebox (upgrade)
	local jb = folder("Jukebox", g)
	local jp = Layout.JUKEBOX_POS
	local cabinet = part(jb, Vector3.new(2.0, 4.2, 1.6), jp + Vector3.new(0, 2.1, 0), Color3.fromRGB(90, 40, 20), Enum.Material.Wood)
	part(jb, Vector3.new(1.6, 1.4, 0.2), jp + Vector3.new(0, 3.2, 0.75), Color3.fromRGB(255, 170, 60), Enum.Material.Neon)
	for i = 0, 3 do
		part(jb, Vector3.new(0.2, 1.2, 0.2), jp + Vector3.new(-0.6 + i * 0.4, 1.6, 0.8), ({ Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 200, 60), Color3.fromRGB(60, 200, 255), Color3.fromRGB(200, 80, 255) })[i + 1], Enum.Material.Neon)
	end
	info.jukebox = cabinet
	tag("jukebox", jb)
	-- the snug stage (upgrade)
	local st = folder("Stage", g)
	local sp = Layout.STAGE_POS
	part(st, Vector3.new(7.0, 0.7, 6.2), sp + Vector3.new(0, 0.35, 0), C.oak, Enum.Material.WoodPlanks)
	local snug = part(st, Vector3.new(4, 1.0, 0.2), sp + Vector3.new(0, 7.2, -3.2), Color3.fromRGB(14, 12, 10), Enum.Material.SmoothPlastic)
	letter(snug, Enum.NormalId.Front, "The Snug", C.gold, Enum.Font.Garamond)
	info.stage = sp
	tag("snug_stage", st)
	-- the big screen over the fireplace (upgrade)
	local tv = part(g, Vector3.new(0.2, 2.3, 4.0), Layout.FIREPLACE + Vector3.new(1.45, 7.3, 0), Color3.fromRGB(8, 8, 8), Enum.Material.SmoothPlastic)
	info.tv = letter(tv, Enum.NormalId.Right, "", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
	tag("big_screen", tv)
end

-- ---------------------------------------------------------------- the front: door, windows, sign
local function buildFront()
	local g = folder("Front")
	local z = Layout.ROOM_MAX.Y
	local h = Layout.ROOM_H
	local doorW, doorH = 1.3 * M, 2.3 * M
	-- wall pieces round the door and two windows (x -5..-3.4 and 2.8..4.4 m)
	local segs = { { Layout.ROOM_MIN.X, -5 * M }, { -3.4 * M, -doorW / 2 }, { doorW / 2, 2.8 * M }, { 4.4 * M, Layout.ROOM_MAX.X } }
	for _, s in segs do
		local w = s[2] - s[1]
		part(g, Vector3.new(w, h, 1), Vector3.new((s[1] + s[2]) / 2, h / 2, z + 0.5), C.plasterOld, Enum.Material.Plaster)
		part(g, Vector3.new(w, h, 0.1), Vector3.new((s[1] + s[2]) / 2, h / 2, z + 1.05), C.shopGreen, Enum.Material.Wood)
	end
	for _, s in { { -5 * M, -3.4 * M }, { 2.8 * M, 4.4 * M } } do
		local w = s[2] - s[1]
		local cx = (s[1] + s[2]) / 2
		part(g, Vector3.new(w, 2.8, 1), Vector3.new(cx, 1.4, z + 0.5), C.darkOak, Enum.Material.Wood)
		part(g, Vector3.new(w, h - 7.7, 1), Vector3.new(cx, 7.7 + (h - 7.7) / 2, z + 0.5), C.plasterOld, Enum.Material.Plaster)
		part(g, Vector3.new(w, 4.9, 0.2), Vector3.new(cx, 5.25, z + 0.5), C.glass, Enum.Material.Glass, { Transparency = 0.7 })
		part(g, Vector3.new(0.2, 4.9, 0.4), Vector3.new(cx, 5.25, z + 0.5), C.cream, Enum.Material.Wood)
		part(g, Vector3.new(w, 0.2, 0.4), Vector3.new(cx, 6.0, z + 0.5), C.cream, Enum.Material.Wood)
		-- a café curtain on a brass rod
		part(g, Vector3.new(w - 0.2, 2.0, 0.08), Vector3.new(cx, 3.9, z - 0.3), Color3.fromRGB(240, 232, 214), Enum.Material.Fabric, { Transparency = 0.35 })
		cyl(g, 0.05, w - 0.1, CFrame.new(cx, 4.95, z - 0.3) * CFrame.Angles(0, 0, math.rad(90)), C.brass, Enum.Material.Metal)
	end
	part(g, Vector3.new(doorW, h - doorH, 1), Vector3.new(0, doorH + (h - doorH) / 2, z + 0.5), C.plasterOld, Enum.Material.Plaster)
	-- the door: hinged on the left, a glazed panel with the OPEN/CLOSED sign hanging inside the glass
	local door = Instance.new("Model")
	door.Name = "Door"
	local hinge = part(door, Vector3.new(0.2, doorH, 0.2), Vector3.new(-doorW / 2 + 0.1, doorH / 2, z + 0.5), C.shopGreen, Enum.Material.Wood, { Transparency = 1, CanCollide = false })
	door.PrimaryPart = hinge
	local panelCf = CFrame.new(0, doorH / 2, z + 0.5)
	part(door, Vector3.new(doorW - 0.2, doorH * 0.4, 0.3), panelCf * CFrame.new(0, -doorH * 0.3, 0), C.shopGreen, Enum.Material.Wood)
	part(door, Vector3.new(doorW - 0.2, 0.4, 0.3), panelCf * CFrame.new(0, doorH / 2 - 0.2, 0), C.shopGreen, Enum.Material.Wood)
	for sx = -1, 1, 2 do
		part(door, Vector3.new(0.4, doorH * 0.6, 0.3), panelCf * CFrame.new(sx * (doorW / 2 - 0.3), doorH * 0.2, 0), C.shopGreen, Enum.Material.Wood)
	end
	local pane = part(door, Vector3.new(doorW - 0.9, doorH * 0.55, 0.08), panelCf * CFrame.new(0, doorH * 0.2, 0), C.glass, Enum.Material.Glass, { Transparency = 0.65 })
	tag("stained_glass", letter(pane, Enum.NormalId.Front, "", C.gold, Enum.Font.Garamond))
	-- the sign: a board on cords, OPEN on the street side, CLOSED on the other; turned to show the state
	local board = part(door, Vector3.new(1.8, 0.8, 0.06), panelCf * CFrame.new(0, doorH * 0.25, -0.2), Color3.fromRGB(20, 16, 12), Enum.Material.Wood)
	board.Name = "SignBoard"
	letter(board, Enum.NormalId.Back, "OPEN", Color3.fromRGB(120, 240, 140), Enum.Font.Garamond, { light = 0.4 })
	letter(board, Enum.NormalId.Front, "CLOSED", Color3.fromRGB(240, 90, 70), Enum.Font.Garamond, { light = 0.4 })
	for _, inst in door:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CanCollide = false
		end
	end
	door.Parent = g
	info.door = door
	info.doorClosed = door:GetPivot()
	info.signBoard = board
	info.signRel = door:GetPivot():ToObjectSpace(board.CFrame)
	-- outside: the shopfront fascia with the pub's name, lanterns either side of the door
	local fascia = part(g, Vector3.new(L_W() - 1, 1.6, 0.4), Vector3.new(0, 8.5, z + 1.25), Color3.fromRGB(10, 10, 9), Enum.Material.SmoothPlastic)
	info.fascia = letter(fascia, Enum.NormalId.Front, "The Crooked Shamrock", C.gold, Enum.Font.Garamond)
	for sx = -1, 1, 2 do
		local lan = part(g, Vector3.new(0.5, 0.8, 0.5), Vector3.new(sx * (doorW / 2 + 0.8), 6.4, z + 1.4), Color3.fromRGB(255, 200, 120), Enum.Material.Neon)
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 190, 120)
		pl.Brightness = 1.2
		pl.Range = 12
		pl.Parent = lan
	end
	-- the upper storey above the shop
	part(g, Vector3.new(L_W() + 1, 9, 1), Vector3.new(0, h + 4.5, z + 0.5), C.cream, Enum.Material.Plaster)
	for i = -2, 2 do
		part(g, Vector3.new(2.6, 3.4, 0.3), Vector3.new(i * 8, h + 4.6, z + 1.05), (if i % 2 == 0 then Color3.fromRGB(255, 196, 120) else Color3.fromRGB(30, 36, 50)), (if i % 2 == 0 then Enum.Material.Neon else Enum.Material.Glass))
	end
	part(g, Vector3.new(L_W() + 2, 0.6, 3), Vector3.new(0, h + 9.3, z + 0.8), Color3.fromRGB(50, 52, 58), Enum.Material.Slate)
	-- flower baskets (upgrade)
	local baskets = folder("Baskets", g)
	for sx = -1, 1, 2 do
		ball(baskets, 0.8, Vector3.new(sx * 6 * M, 7.3, z + 2), Color3.fromRGB(70, 130, 60), Enum.Material.Grass)
		ball(baskets, 0.5, Vector3.new(sx * 6 * M + 0.4, 7.6, z + 2.4), Color3.fromRGB(220, 60, 120), Enum.Material.SmoothPlastic)
	end
	tag("flower_baskets", baskets)
end

-- ---------------------------------------------------------------- the cellar and the street
local function buildCellar()
	local g = folder("Cellar")
	local mn, mx = Layout.CELLAR_MIN, Layout.CELLAR_MAX
	local w, d = mx.X - mn.X, mx.Y - mn.Y
	local c = Vector3.new((mn.X + mx.X) / 2, 0, (mn.Y + mx.Y) / 2)
	part(g, Vector3.new(w, 1, d), c + Vector3.new(0, -0.5, 0), Color3.fromRGB(90, 88, 84), Enum.Material.Slate)
	part(g, Vector3.new(w, 1, d), c + Vector3.new(0, 8.5, 0), Color3.fromRGB(60, 56, 50), Enum.Material.Concrete)
	part(g, Vector3.new(w + 2, 9, 1), Vector3.new(c.X, 4.5, mn.Y - 0.5), Color3.fromRGB(110, 104, 96), Enum.Material.Brick)
	part(g, Vector3.new(1, 9, d), Vector3.new(mn.X - 0.5, 4.5, c.Z), Color3.fromRGB(110, 104, 96), Enum.Material.Brick)
	part(g, Vector3.new(1, 9, d), Vector3.new(mx.X + 0.5, 4.5, c.Z), Color3.fromRGB(110, 104, 96), Enum.Material.Brick)
	local lamp = ball(g, 0.25, c + Vector3.new(0, 7.8, 0), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 236, 200)
	pl.Brightness = 1.3
	pl.Range = 18
	pl.Parent = lamp
	for id, kp in Layout.KEG_POS do
		local keg = cyl(g, 0.65, 1.9, kp + Vector3.new(0, 0.95, 0), Color3.fromRGB(170, 175, 182), Enum.Material.Metal, { Reflectance = 0.15 })
		keg.Name = "Keg_" .. id
		local band = cyl(g, 0.68, 0.6, kp + Vector3.new(0, 1.0, 0), Color3.fromRGB(14, 12, 10), Enum.Material.SmoothPlastic)
		letter(band, Enum.NormalId.Front, ({ stout = "GALAGERS", lager = "LAGER", ale = "ALE", cider = "CIDER", zero = "ZERO" })[id] or id, C.gold)
		info.kegs[id] = keg
		if DRINK_UNLOCK[id] then
			tag(DRINK_UNLOCK[id], keg)
			tag(DRINK_UNLOCK[id], band)
		end
	end
end

local function buildStreet()
	local g = folder("Street")
	local z = Layout.ROOM_MAX.Y
	part(g, Vector3.new(160, 1, 8), Vector3.new(0, -0.45, z + 5), Color3.fromRGB(120, 116, 110), Enum.Material.Concrete)
	part(g, Vector3.new(160, 1, 24), Vector3.new(0, -0.7, z + 21), Color3.fromRGB(70, 70, 74), Enum.Material.Cobblestone)
	part(g, Vector3.new(160, 1, 6), Vector3.new(0, -0.45, z + 36), Color3.fromRGB(120, 116, 110), Enum.Material.Concrete)
	-- the terrace across the street, windows lit
	local cols = { Color3.fromRGB(200, 180, 140), Color3.fromRGB(40, 70, 60), Color3.fromRGB(150, 60, 50), Color3.fromRGB(60, 70, 110), Color3.fromRGB(190, 150, 60) }
	for i = -6, 6 do
		local hx = i * 12
		part(g, Vector3.new(12, 20, 8), Vector3.new(hx, 10, z + 43), cols[(i + 7) % #cols + 1], Enum.Material.Plaster)
		part(g, Vector3.new(12.5, 1, 9), Vector3.new(hx, 20.3, z + 43), Color3.fromRGB(50, 52, 58), Enum.Material.Slate)
		for wx = -1, 1, 2 do
			for wy = 0, 1 do
				local lit = ((i + wx + wy) % 3) ~= 0
				part(g, Vector3.new(2.4, 3.2, 0.3), Vector3.new(hx + wx * 3, 5 + wy * 8, z + 38.9),
					if lit then Color3.fromRGB(255, 196, 120) else Color3.fromRGB(26, 30, 40), if lit then Enum.Material.Neon else Enum.Material.Glass)
			end
		end
		part(g, Vector3.new(2.4, 5, 0.3), Vector3.new(hx, 2.5, z + 38.9), Color3.fromRGB(40, 30, 24), Enum.Material.Wood)
	end
	-- street lamps
	for i = -2, 2 do
		local x = i * 22 + 11
		cyl(g, 0.25, 14, Vector3.new(x, 7, z + 8), C.iron, Enum.Material.Metal)
		local head = part(g, Vector3.new(1.2, 1.4, 1.2), Vector3.new(x, 14.5, z + 8), Color3.fromRGB(255, 210, 140), Enum.Material.Neon)
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 196, 120)
		pl.Brightness = 1.5
		pl.Range = 26
		pl.Parent = head
	end
	-- rain falling over the street
	local cloud = part(g, Vector3.new(140, 1, 50), Vector3.new(0, 40, z + 22), C.iron, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local rain = Instance.new("ParticleEmitter")
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Rate = 400
	rain.Lifetime = NumberRange.new(1.2, 1.6)
	rain.Speed = NumberRange.new(45, 55)
	rain.Size = NumberSequence.new(0.08)
	rain.Transparency = NumberSequence.new(0.35)
	rain.Color = ColorSequence.new(Color3.fromRGB(200, 210, 230))
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.LightEmission = 0.3
	rain.Squash = NumberSequence.new(3)
	rain.Parent = cloud
	info.rain = rain
end

function Builder.build(parent)
	info = { taps = {}, seats = {}, barSpots = {}, kegs = {}, lamps = {}, upgradeShow = {}, upgradeHide = {}, homes = {} }
	root = Instance.new("Model")
	root.Name = "Pub"
	root.Parent = parent
	buildRoom()
	buildBar()
	buildTaps()
	buildSeating()
	buildFireplace()
	buildLamps()
	buildDecor()
	buildFront()
	buildCellar()
	buildStreet()
	remember(info.upgradeShow)
	remember(info.upgradeHide)
	info.root = root
	return info
end

return Builder
