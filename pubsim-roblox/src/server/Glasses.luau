-- Pint glasses and tumblers: a clear shell with the drink, the cascade and the head drawn inside,
-- held in a hand, settling on the drip tray, or left empty on a table. And the rack of clean ones.

local Shared = game:GetService("ReplicatedStorage").Shared
local Contents = require(Shared.Contents)

local Glasses = {}

local SIZE = { pint = { h = 0.85, r = 0.26 }, tumbler = { h = 0.5, r = 0.3 } }
local CREAM = Color3.fromRGB(238, 222, 186)
local CASCADE = Color3.fromRGB(168, 128, 92)
local nextId = 0

local function cylPart(parent, r, h, color, material, transparency)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(h, r * 2, r * 2)
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Anchored = true
	p.Parent = parent
	return p
end

-- data: the game's Data (drink colours)
function Glasses.make(kind, data)
	nextId += 1
	local s = SIZE[kind] or SIZE.pint
	local m = Instance.new("Model")
	m.Name = if kind == "tumbler" then "Tumbler" else "Pint"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.Massless = true
	root.Anchored = true
	root.Parent = m
	m.PrimaryPart = root
	local shell = cylPart(m, s.r, s.h, Color3.fromRGB(220, 232, 236), Enum.Material.Glass, 0.55)
	shell.Name = "Shell"
	local body = cylPart(m, s.r * 0.88, 0.01, Color3.fromRGB(20, 10, 6), Enum.Material.Glass, 0.05)
	body.Name = "Body"
	local casc = cylPart(m, s.r * 0.885, 0.01, CASCADE, Enum.Material.SmoothPlastic, 0)
	casc.Name = "Cascade"
	local foam = cylPart(m, s.r * 0.89, 0.01, CREAM, Enum.Material.SmoothPlastic, 0)
	foam.Name = "Foam"
	local g = { id = nextId, kind = kind, contents = Contents.new(), dirty = 0, model = m, size = s, data = data }
	Glasses.refresh(g)
	return g
end

local function drinkColor(g)
	local id = g.contents.drinkId
	for _, d in g.data.drinks do
		if d.id == id and d.color then
			return Color3.new(d.color[1], d.color[2], d.color[3])
		end
	end
	return Color3.fromRGB(20, 10, 6)
end

local function drinkFoam(g)
	local id = g.contents.drinkId
	for _, d in g.data.drinks do
		if d.id == id and d.foam then
			return Color3.new(d.foam[1], d.foam[2], d.foam[3])
		end
	end
	return CREAM
end

-- Lays the liquid out inside the glass from its contents (body, then the cascade, then the head).
function Glasses.refresh(g)
	local m, s, c = g.model, g.size, g.contents
	local root = m.PrimaryPart
	local base = root.CFrame
	local up = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; stood upright
	local shell = m.Shell
	shell.CFrame = base * CFrame.new(0, s.h / 2, 0) * up
	shell.Color = if g.dirty > 0.2 then Color3.fromRGB(190, 170, 140) else Color3.fromRGB(220, 232, 236)
	shell.Transparency = if g.dirty > 0.2 then 0.4 else 0.55
	local inner = s.h * 0.93
	local y = s.h * 0.04
	local function layer(part, frac)
		local hgt = math.max(0.001, math.clamp(frac, 0, 1.06) * inner)
		part.Size = Vector3.new(hgt, part.Size.Y, part.Size.Z)
		part.CFrame = base * CFrame.new(0, y + hgt / 2, 0) * up
		part.Transparency = if frac < 0.004 then 1 else (if part.Name == "Body" then 0.05 else 0)
		y += if frac < 0.004 then 0 else hgt
	end
	m.Body.Color = drinkColor(g)
	m.Foam.Color = drinkFoam(g)
	layer(m.Body, c.body)
	layer(m.Cascade, c.cascade)
	layer(m.Foam, c.foam)
end

-- Moves the glass (anchored) so its base sits at `cf`.
function Glasses.place(g, cf, parent)
	for _, p in g.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			local w = p:FindFirstChild("HoldWeld")
			if w then
				w:Destroy()
			end
		end
	end
	g.model.PrimaryPart.CFrame = cf
	Glasses.refresh(g)
	g.model.Parent = parent
end

-- Puts the glass in a character's right hand.
function Glasses.hold(g, character)
	local hand = character and character:FindFirstChild("RightHand")
	if not hand then
		return false
	end
	g.model.PrimaryPart.CFrame = hand.CFrame * CFrame.new(0, -0.1, -0.45)
	Glasses.refresh(g)
	for _, p in g.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			if p ~= g.model.PrimaryPart then
				local w = Instance.new("WeldConstraint")
				w.Name = "HoldWeld"
				w.Part0 = g.model.PrimaryPart
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	local hw = Instance.new("WeldConstraint")
	hw.Name = "HoldWeld"
	hw.Part0 = hand
	hw.Part1 = g.model.PrimaryPart
	hw.Parent = g.model.PrimaryPart
	g.model.Parent = character
	return true
end

-- Liquid layers move with the glass while it's held, so they are re-laid out in place.
function Glasses.refreshHeld(g)
	local m = g.model
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			local w = p:FindFirstChild("HoldWeld")
			if w and w.Part0 == m.PrimaryPart then
				w:Destroy()
			end
			p.Anchored = false
		end
	end
	Glasses.refresh(g)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p ~= m.PrimaryPart then
			local w = Instance.new("WeldConstraint")
			w.Name = "HoldWeld"
			w.Part0 = m.PrimaryPart
			w.Part1 = p
			w.Parent = p
		end
	end
end

-- The rack of clean glasses on the back counter, drawn to match the count.
function Glasses.drawRack(rackPart, count)
	local f = rackPart:FindFirstChild("Glasses") or Instance.new("Folder")
	f.Name = "Glasses"
	f.Parent = rackPart
	f:ClearAllChildren()
	for i = 0, math.min(count, 18) - 1 do
		local col, row = i % 6, math.floor(i / 6)
		local p = cylPart(f, 0.24, 0.8, Color3.fromRGB(220, 232, 236), Enum.Material.Glass, 0.5)
		p.CFrame = rackPart.CFrame * CFrame.new(-1.3 + col * 0.52, 0.47, -0.45 + row * 0.45) * CFrame.Angles(0, 0, math.rad(90))
	end
end

return Glasses
