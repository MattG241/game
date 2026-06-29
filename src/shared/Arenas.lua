--!strict
--[[
	Arenas
	------
	Arena definitions + a lightweight procedural builder so the game is fully
	playable WITHOUT any hand-modelled maps. Once you build proper arenas in
	Studio, drop them under Workspace/Arenas/<id> and set `prebuilt = true`;
	the builder will use your model instead of generating one.

	Each arena is a flat fighting platform with neon trim, spawn pads, and an
	out-of-bounds kill plane below it.
]]

local GameConfig = require(script.Parent.GameConfig)

local Arenas = {}

export type ArenaDef = {
	id: string,
	name: string,
	floorColor: Color3,
	accent: Color3,
	floorMaterial: Enum.Material,
	size: number, -- square platform side length in studs
	vipOnly: boolean,
	prebuilt: boolean,
}

Arenas.List = {
	{
		id = "classic_pit",
		name = "Classic Pit",
		floorColor = Color3.fromRGB(45, 42, 50),
		accent = Color3.fromRGB(255, 80, 80),
		floorMaterial = Enum.Material.Concrete,
		size = 90,
		vipOnly = false,
		prebuilt = false,
	},
	{
		id = "neon_cyber",
		name = "Neon Cyber",
		floorColor = Color3.fromRGB(18, 18, 35),
		accent = Color3.fromRGB(80, 180, 255),
		floorMaterial = Enum.Material.Glass,
		size = 100,
		vipOnly = false,
		prebuilt = false,
	},
	{
		id = "industrial",
		name = "Industrial Yard",
		floorColor = Color3.fromRGB(60, 55, 45),
		accent = Color3.fromRGB(255, 170, 40),
		floorMaterial = Enum.Material.DiamondPlate,
		size = 95,
		vipOnly = false,
		prebuilt = false,
	},
	{
		id = "vip_skyline",
		name = "Skyline (VIP)",
		floorColor = Color3.fromRGB(25, 10, 40),
		accent = Color3.fromRGB(220, 40, 255),
		floorMaterial = Enum.Material.Neon,
		size = 110,
		vipOnly = true,
		prebuilt = false,
	},
}

local byId: { [string]: ArenaDef } = {}
for _, a in Arenas.List do
	byId[a.id] = a
end
Arenas.ById = byId

function Arenas.get(id: string): ArenaDef?
	return byId[id]
end

-- Build the spawn positions for `teamSize` players per side, given an origin
-- and arena size. Returns two arrays of CFrames facing each other.
function Arenas.spawnPoints(origin: Vector3, arena: ArenaDef, teamSize: number)
	local half = arena.size / 2 - 12
	local sideA, sideB = {}, {}
	for i = 1, teamSize do
		local spread = (i - (teamSize + 1) / 2) * 8
		local aPos = origin + Vector3.new(spread, 4, -half)
		local bPos = origin + Vector3.new(spread, 4, half)
		table.insert(sideA, CFrame.new(aPos, Vector3.new(aPos.X, aPos.Y, aPos.Z + 1)))
		table.insert(sideB, CFrame.new(bPos, Vector3.new(bPos.X, bPos.Y, bPos.Z - 1)))
	end
	return sideA, sideB
end

-- Procedurally construct an arena model at `origin`. Server-only.
-- Returns the Model (parented to the given container).
function Arenas.build(arena: ArenaDef, origin: Vector3, container: Instance): Model
	-- Reuse a hand-built model if the developer provided one.
	if arena.prebuilt then
		local existing = container:FindFirstChild(arena.id)
		if existing and existing:IsA("Model") then
			existing:PivotTo(CFrame.new(origin))
			return existing
		end
	end

	local model = Instance.new("Model")
	model.Name = arena.id

	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, anchored: boolean?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = anchored ~= false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	-- Floor
	part("Floor", Vector3.new(arena.size, 2, arena.size), CFrame.new(origin), arena.floorColor, arena.floorMaterial)

	-- Neon border trim (four strips)
	local s = arena.size
	local trims = {
		{ Vector3.new(s, 1, 2), Vector3.new(0, 1.2, -s / 2) },
		{ Vector3.new(s, 1, 2), Vector3.new(0, 1.2, s / 2) },
		{ Vector3.new(2, 1, s), Vector3.new(-s / 2, 1.2, 0) },
		{ Vector3.new(2, 1, s), Vector3.new(s / 2, 1.2, 0) },
	}
	for i, t in trims do
		part("Trim" .. i, t[1], CFrame.new(origin + t[2]), arena.accent, Enum.Material.Neon)
	end

	-- Corner light pillars
	local c = s / 2 - 4
	for i, off in { Vector3.new(c, 0, c), Vector3.new(-c, 0, c), Vector3.new(c, 0, -c), Vector3.new(-c, 0, -c) } do
		local pillar = part("Pillar" .. i, Vector3.new(3, 28, 3), CFrame.new(origin + off + Vector3.new(0, 14, 0)), arena.floorColor, Enum.Material.Metal)
		local top = part("PillarLight" .. i, Vector3.new(3.4, 3, 3.4), CFrame.new(origin + off + Vector3.new(0, 28, 0)), arena.accent, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = arena.accent
		light.Brightness = 4
		light.Range = 40
		light.Parent = top
		pillar.Name = "Pillar" .. i
	end

	-- Out-of-bounds kill plane well below the platform.
	local kill = part("KillPlane", Vector3.new(s * 4, 2, s * 4), CFrame.new(origin - Vector3.new(0, 60, 0)), Color3.fromRGB(10, 0, 0), Enum.Material.Neon)
	kill.Transparency = 0.7
	kill.CanCollide = false
	kill:SetAttribute("KillPlane", true)

	model.Parent = container
	model.PrimaryPart = model:FindFirstChild("Floor") :: BasePart
	return model
end

return Arenas
