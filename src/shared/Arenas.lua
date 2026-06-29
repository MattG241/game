--!strict
--[[
	Arenas (Stages)
	---------------
	Super Smash Bros-style STAGES + a procedural builder, so the game is fully
	playable WITHOUT any hand-modelled maps.

	A stage = a solid main platform, a couple of smaller floating platforms, and
	BLAST ZONES on every side (left / right / top / bottom). Get launched past a
	blast zone and you're KO'd. There are no walls — the sides are open so you
	can be knocked off.

	Once you build proper stages in Studio, drop them under Workspace/Arenas/<id>
	and set `prebuilt = true`; the builder will reuse your model. A prebuilt stage
	must still tag its blast-zone parts with the `KillPlane` attribute and expose
	a `Main` PrimaryPart fighters spawn on.
]]

local GameConfig = require(script.Parent.GameConfig)

local Arenas = {}

export type ArenaDef = {
	id: string,
	name: string,
	floorColor: Color3,
	accent: Color3,
	floorMaterial: Enum.Material,
	size: number, -- main platform side length in studs
	vipOnly: boolean,
	prebuilt: boolean,
}

Arenas.List = {
	{
		id = "classic_pit",
		name = "Neon Platform",
		floorColor = Color3.fromRGB(45, 42, 50),
		accent = Color3.fromRGB(255, 80, 80),
		floorMaterial = Enum.Material.Concrete,
		size = 90,
		vipOnly = false,
		prebuilt = false,
	},
	{
		id = "neon_cyber",
		name = "Cyber Grid",
		floorColor = Color3.fromRGB(18, 18, 35),
		accent = Color3.fromRGB(80, 180, 255),
		floorMaterial = Enum.Material.Glass,
		size = 100,
		vipOnly = false,
		prebuilt = false,
	},
	{
		id = "industrial",
		name = "Scrapyard",
		floorColor = Color3.fromRGB(60, 55, 45),
		accent = Color3.fromRGB(255, 170, 40),
		floorMaterial = Enum.Material.DiamondPlate,
		size = 96,
		vipOnly = false,
		prebuilt = false,
	},
	{
		id = "vip_skyline",
		name = "Skyline (VIP)",
		floorColor = Color3.fromRGB(25, 10, 40),
		accent = Color3.fromRGB(220, 40, 255),
		floorMaterial = Enum.Material.Neon,
		size = 108,
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

-- Spawn CFrames for `teamSize` per side, on top of the main platform, facing in.
function Arenas.spawnPoints(origin: Vector3, arena: ArenaDef, teamSize: number)
	local half = arena.size / 2 - 14
	local sideA, sideB = {}, {}
	for i = 1, teamSize do
		local spread = (i - (teamSize + 1) / 2) * 10
		local aPos = origin + Vector3.new(-half + spread, 5, 0)
		local bPos = origin + Vector3.new(half + spread, 5, 0)
		table.insert(sideA, CFrame.new(aPos, Vector3.new(aPos.X + 1, aPos.Y, aPos.Z)))
		table.insert(sideB, CFrame.new(bPos, Vector3.new(bPos.X - 1, bPos.Y, bPos.Z)))
	end
	return sideA, sideB
end

-- Procedurally construct a stage at `origin`. Server-only. Returns the Model.
function Arenas.build(arena: ArenaDef, origin: Vector3, container: Instance): Model
	if arena.prebuilt then
		local existing = container:FindFirstChild(arena.id)
		if existing and existing:IsA("Model") then
			existing:PivotTo(CFrame.new(origin))
			return existing
		end
	end

	local model = Instance.new("Model")
	model.Name = arena.id

	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, collide: boolean?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = collide ~= false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local s = arena.size

	-- Main platform (solid).
	local main = part("Main", Vector3.new(s, 4, 28), CFrame.new(origin), arena.floorColor, arena.floorMaterial)

	-- Neon edge accents along the top (purely cosmetic, non-colliding so they
	-- never block a knockback).
	part("EdgeFront", Vector3.new(s, 1, 1.5), CFrame.new(origin + Vector3.new(0, 2.4, 14)), arena.accent, Enum.Material.Neon, false)
	part("EdgeBack", Vector3.new(s, 1, 1.5), CFrame.new(origin + Vector3.new(0, 2.4, -14)), arena.accent, Enum.Material.Neon, false)

	-- Two smaller floating platforms (solid) for verticality.
	local platSize = Vector3.new(s * 0.28, 2, 18)
	part("PlatformL", platSize, CFrame.new(origin + Vector3.new(-s * 0.26, 22, 0)), arena.floorColor, arena.floorMaterial)
	part("PlatformR", platSize, CFrame.new(origin + Vector3.new(s * 0.26, 22, 0)), arena.floorColor, arena.floorMaterial)
	-- A higher centre platform.
	part("PlatformTop", Vector3.new(s * 0.22, 2, 16), CFrame.new(origin + Vector3.new(0, 40, 0)), arena.floorColor, arena.floorMaterial)

	-- Under-stage glow (decorative).
	local glow = part("UnderGlow", Vector3.new(s * 0.8, 3, 20), CFrame.new(origin - Vector3.new(0, 6, 0)), arena.accent, Enum.Material.Neon, false)
	glow.Transparency = 0.3
	local gl = Instance.new("PointLight")
	gl.Color = arena.accent
	gl.Brightness = 5
	gl.Range = 60
	gl.Parent = glow

	-- BLAST ZONES — large non-colliding kill volumes on every side. Get launched
	-- past one and you're KO'd (handled by the server's KillPlane touch hook).
	local blast = s * 1.4 -- distance from centre to each blast zone
	-- Thick slabs (not thin planes) so a fighter launched at top speed can't
	-- tunnel through the kill volume in a single physics step.
	local thin = 80
	local span = s * 4
	local function blastZone(name: string, size: Vector3, offset: Vector3)
		local z = part(name, size, CFrame.new(origin + offset), Color3.fromRGB(120, 0, 0), Enum.Material.Neon, false)
		z.Transparency = 0.85
		z:SetAttribute("KillPlane", true)
	end
	blastZone("BlastLeft", Vector3.new(thin, span, span), Vector3.new(-(s / 2 + blast), 0, 0))
	blastZone("BlastRight", Vector3.new(thin, span, span), Vector3.new(s / 2 + blast, 0, 0))
	blastZone("BlastBottom", Vector3.new(span, thin, span), Vector3.new(0, -(blast + 40), 0))
	blastZone("BlastTop", Vector3.new(span, thin, span), Vector3.new(0, blast + 120, 0))

	model.Parent = container
	model.PrimaryPart = main
	return model
end

return Arenas
