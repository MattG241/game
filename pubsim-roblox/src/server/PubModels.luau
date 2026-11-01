-- The APK's pub, loaded around the gameplay.
--
-- The phone game's pub is exported from the Godot project (pubsim/tools/roblox/export_world):
-- every surface is baked with the phone game's own shaders and textures into chunks of mesh,
-- uploaded as models by CI. Here each chunk is loaded and put exactly where it is in the phone
-- game (sized from the export's bounds, so it doesn't matter how Roblox's importer scales it),
-- with the phone game's lights and lettering. The pub PubBuilder makes from parts stays for its
-- collisions, seats and prompts, but is turned invisible.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.ApkWorld)
local Layout = require(Shared.Layout)
local M = Layout.M

local PubModels = {}

local function v3(t)
	return Vector3.new(t[1] * M, t[2] * M, t[3] * M)
end

local function dir3(t)
	return Vector3.new(t[1], t[2], t[3])
end

-- Pieces that only show with (show:id) or without (hide:id) an upgrade go in a folder the
-- builder's upgrade switching moves in and out of the pub.
local function tagged(root, folders, tag, info)
	if tag == nil or tag == "" then
		return root
	end
	local f = folders[tag]
	if f then
		return f
	end
	f = Instance.new("Folder")
	f.Name = tag
	f.Parent = root
	local kind, id = string.match(tag, "^(%a+):(.+)$")
	local key = if kind == "hide" then "upgradeHide" else "upgradeShow"
	info[key][id] = info[key][id] or {}
	table.insert(info[key][id], f)
	info.homes[f] = root
	folders[tag] = f
	return f
end

local function place(mp, entry, parent)
	local mn, mx = v3(entry.min), v3(entry.max)
	local size = mx - mn
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = true
	mp.Size = Vector3.new(math.max(size.X, 0.002), math.max(size.Y, 0.002), math.max(size.Z, 0.002))
	mp.CFrame = CFrame.new((mn + mx) / 2)
	mp.Parent = parent
end

-- the export's names (c012, g003) survive the import, perhaps with something added
local function chunkName(name)
	return string.match(name, "^([cg]%d%d%d)")
end

local function loadModels(root, folders, info)
	local placed, missing = 0, 0
	for _, file in World.files do
		if (file.asset or 0) == 0 then
			missing += #file.chunks
			continue
		end
		local ok, model = pcall(function()
			return InsertService:LoadAsset(file.asset)
		end)
		if not ok or not model then
			warn(string.format("PubModels: couldn't load %s (%d): %s", file.file, file.asset, tostring(model)))
			missing += #file.chunks
			continue
		end
		local parts = {}
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				local n = chunkName(d.Name)
				if n then
					parts[n] = d
				end
			end
		end
		-- if the importer renamed the pieces, fall back to their order in the file
		if next(parts) == nil then
			local list = {}
			for _, d in model:GetDescendants() do
				if d:IsA("MeshPart") then
					table.insert(list, d)
				end
			end
			for i, name in file.chunks do
				parts[name] = list[i]
			end
		end
		for _, name in file.chunks do
			local mp = parts[name]
			local entry = World.chunks[name] or World.clear[name]
			if mp and entry then
				if World.clear[name] then
					local c = entry.color
					mp.TextureID = ""
					mp.Color = Color3.new(c[1], c[2], c[3])
					mp.Material = Enum.Material.Glass
					mp.Transparency = entry.transparency
					mp.CastShadow = false
				else
					mp.Material = Enum.Material.SmoothPlastic
					mp.Color = Color3.new(1, 1, 1)
				end
				place(mp, entry, tagged(root, folders, entry.tag, info))
				placed += 1
			else
				missing += 1
			end
		end
		model:Destroy()
	end
	return placed, missing
end

local function addLights(root, folders, info)
	for _, l in World.lights do
		local parent = tagged(root, folders, l.tag, info)
		local pos = v3(l.pos)
		local p = Instance.new("Part")
		p.Name = "Light"
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local light
		if l.kind == "spot" then
			local d = dir3(l.dir)
			p.CFrame = CFrame.lookAt(pos, pos + d, if math.abs(d.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis)
			light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Angle = math.clamp((l.angle or 45) * 2, 10, 180)
		else
			p.CFrame = CFrame.new(pos)
			light = Instance.new("PointLight")
		end
		light.Color = Color3.new(l.color[1], l.color[2], l.color[3])
		light.Brightness = math.clamp((l.energy or 1) * 1.3, 0.1, 8)
		light.Range = math.clamp((l.range or 5) * M, 4, 60)
		light.Shadows = l.shadow == true
		light.Parent = p
		p.Parent = parent
	end
end

local function addLabels(root, folders, info)
	for _, lb in World.labels do
		local parent = tagged(root, folders, lb.tag, info)
		local x, y = dir3(lb.x), dir3(lb.y)
		local sx, sy = x.Magnitude, y.Magnitude
		local px = (lb.pixel or 0.005) * M
		local lines = string.split(lb.text, "\n")
		local longest = 0
		for _, line in lines do
			longest = math.max(longest, utf8.len(line) or #line)
		end
		local fs = lb.font_size or 32
		local h = #lines * fs * px * 1.2 * sy
		local w = math.max(longest, 1) * fs * px * 0.58 * sx
		local p = Instance.new("Part")
		p.Name = "Lettering"
		p.Size = Vector3.new(math.max(w, 0.05), math.max(h, 0.05), 0.02)
		p.CFrame = CFrame.fromMatrix(v3(lb.pos), x.Unit, y.Unit)
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		-- a Godot label reads from the side its +Z faces: a Roblox part's Back face
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 60
		sg.LightInfluence = 0.4
		sg.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = lb.text
		t.TextScaled = true
		t.TextWrapped = true
		local font = string.lower(lb.font or "")
		t.Font = if string.find(font, "title") or string.find(font, "serif") or string.find(font, "uncial") then Enum.Font.Garamond
			else Enum.Font.GothamMedium
		local c = lb.color or { 1, 1, 1, 1 }
		t.TextColor3 = Color3.new(c[1], c[2], c[3])
		t.TextTransparency = 1 - (c[4] or 1)
		t.TextXAlignment = if lb.align == 0 then Enum.TextXAlignment.Left elseif lb.align == 2 then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Center
		if (lb.outline or 0) > 0 then
			t.TextStrokeTransparency = 0.4
		end
		t.Parent = sg
		p.Parent = parent
	end
end

-- The pub made from parts: still there for walking into, sitting on and the prompts, but unseen.
local function hideBuilder(info)
	local keep = {}
	if info.door then
		keep[info.door] = true
	end
	local function kept(inst)
		local a = inst
		while a and a ~= info.root do
			if keep[a] or a:GetAttribute("Keep") then
				return true
			end
			a = a.Parent
		end
		return false
	end
	for _, d in info.root:GetDescendants() do
		if kept(d) then
			continue
		end
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CastShadow = false
		elseif (d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")) and d ~= info.fireLight then
			d.Enabled = false
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		end
	end
	info.lamps = {}
end

-- Loads the APK's pub. Returns true when it is in place.
function PubModels.load(info)
	if not World.files or #World.files == 0 then
		return false
	end
	local root = Instance.new("Model")
	root.Name = "ApkPub"
	root.Parent = workspace
	local folders = {}
	local placed, missing = loadModels(root, folders, info)
	print(string.format("PubModels: %d pieces of the APK pub placed, %d missing", placed, missing))
	if placed == 0 then
		root:Destroy()
		return false
	end
	hideBuilder(info)
	addLights(root, folders, info)
	addLabels(root, folders, info)
	info.apkRoot = root
	return true
end

return PubModels
