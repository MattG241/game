-- The phone game's people on Roblox's NPCs.
--
-- The 16 realistic people from the phone game (MakeHuman bodies, clothes, hair and rig) are
-- uploaded as models by CI. Each NPC keeps its Roblox body for walking, pathfinding and sitting,
-- made invisible, and wears one of these people welded to it. The bones are moved on each
-- player's screen by the client (PeopleAnim), from what the NPC is doing.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local People = require(Shared.ApkPeople)
local Layout = require(Shared.Layout)
local M = Layout.M

local PeopleModels = {}

local HEIGHT = 1.75 -- metres, the phone game's people at height 1.0
local templates = {} -- name -> Model, or false when it couldn't be loaded
local store

local function storage()
	if not store then
		store = Instance.new("Folder")
		store.Name = "PeopleTemplates"
		store.Parent = ServerStorage
	end
	return store
end

local function template(name)
	local t = templates[name]
	if t ~= nil then
		return t or nil
	end
	local entry = People[name]
	if not entry or (entry.asset or 0) == 0 then
		templates[name] = false
		return nil
	end
	local ok, loaded = pcall(function()
		return InsertService:LoadAsset(entry.asset)
	end)
	if not ok or not loaded then
		warn(string.format("PeopleModels: couldn't load %s: %s", name, tostring(loaded)))
		templates[name] = false
		return nil
	end
	-- the imported person (a model inside the loaded asset)
	local person = loaded:FindFirstChildWhichIsA("Model") or loaded
	person.Parent = nil
	loaded:Destroy()
	local biggest, best = nil, 0
	for _, d in person:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = true
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > best then
				biggest, best = d, v
			end
		end
	end
	if not biggest then
		templates[name] = false
		return nil
	end
	person.PrimaryPart = biggest
	local _, size = person:GetBoundingBox()
	if size.Y > 0.01 then
		person:ScaleTo(person:GetScale() * (HEIGHT * M / size.Y))
	end
	person.Name = "Skin"
	person:SetAttribute("Person", name)
	person.Parent = storage()
	templates[name] = person
	return person
end

local function choose(look, rng)
	if look.model and People[look.model] and (People[look.model].asset or 0) ~= 0 then
		return look.model
	end
	local gender = look.gender or (if rng:NextNumber() < 0.5 then "m" else "f")
	local list = {}
	for name, e in People do
		if e.gender == gender and (e.asset or 0) ~= 0 then
			table.insert(list, name)
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list)
	return list[rng:NextInteger(1, #list)]
end

-- Puts one of the phone game's people on the NPC body. Returns true when it did.
function PeopleModels.dress(model, look, rng, heightScale)
	local name = choose(look or {}, rng)
	if not name then
		return false
	end
	local t = template(name)
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not t or not root or not hum then
		return false
	end
	local skin = t:Clone()
	if heightScale and heightScale > 0 then
		skin:ScaleTo(skin:GetScale() * heightScale)
	end
	-- standing on the floor under the body, facing the same way
	local bbox, size = skin:GetBoundingBox()
	local feetY = root.Position.Y - (hum.HipHeight + root.Size.Y / 2)
	local rel = bbox:ToObjectSpace(skin:GetPivot())
	local centre = Vector3.new(root.Position.X, feetY + size.Y / 2, root.Position.Z)
	skin:PivotTo(CFrame.new(centre) * root.CFrame.Rotation * rel)
	for _, d in skin:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end
	skin.Parent = model
	-- the Roblox body: still there (it walks and sits), but unseen
	for _, d in model:GetDescendants() do
		if d:IsDescendantOf(skin) then
			continue
		end
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CastShadow = false
		elseif d:IsA("Decal") then
			d.Transparency = 1
		end
	end
	model:SetAttribute("Person", name)
	return true
end

-- Loads every person once at the start, so the first customers don't wait for it.
function PeopleModels.preload()
	task.spawn(function()
		for name in People do
			template(name)
		end
	end)
end

return PeopleModels
