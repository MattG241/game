-- Roblox characters for the pub's people (customers, staff, musicians): an R15 body coloured from
-- the person's look, simple hair, a name tag and a speech bubble, Roblox's own walk/idle/sit
-- animations, and walking by pathfinding.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local PeopleModels = require(script.Parent.PeopleModels)

local Npc = {}

local SKIN = { Color3.fromRGB(255, 220, 190), Color3.fromRGB(240, 200, 165), Color3.fromRGB(214, 170, 130),
	Color3.fromRGB(176, 128, 92), Color3.fromRGB(120, 82, 58) }
local COATS = { Color3.fromRGB(40, 50, 70), Color3.fromRGB(90, 30, 30), Color3.fromRGB(40, 70, 46), Color3.fromRGB(110, 90, 60),
	Color3.fromRGB(60, 60, 64), Color3.fromRGB(150, 120, 80), Color3.fromRGB(30, 30, 34), Color3.fromRGB(120, 60, 90) }
local TROUSERS = { Color3.fromRGB(40, 46, 70), Color3.fromRGB(30, 30, 32), Color3.fromRGB(90, 80, 64), Color3.fromRGB(56, 60, 70) }
local HAIR = { Color3.fromRGB(40, 28, 20), Color3.fromRGB(90, 60, 30), Color3.fromRGB(150, 90, 40), Color3.fromRGB(200, 170, 110),
	Color3.fromRGB(180, 180, 180), Color3.fromRGB(20, 18, 16), Color3.fromRGB(140, 50, 20) }

local ANIM = { idle = "rbxassetid://507766388", walk = "rbxassetid://507777826", sit = "rbxassetid://2506281703" }

local function rgb(t, fallback)
	if type(t) == "table" and #t >= 3 then
		return Color3.new(t[1], t[2], t[3])
	end
	return fallback
end

-- look: {gender, skin (index), hair {r,g,b}, coat {r,g,b}, trousers {r,g,b}, hair_style, height}
function Npc.spawn(name, look, rng, parent, at)
	look = look or {}
	local pick = function(list)
		return list[rng:NextInteger(1, #list)]
	end
	local skin = SKIN[(tonumber(look.skin) or rng:NextInteger(0, #SKIN - 1)) % #SKIN + 1]
	local coat = rgb(look.coat, pick(COATS))
	local trousers = rgb(look.trousers, pick(TROUSERS))
	local hair = rgb(look.hair, pick(HAIR))
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = skin
	desc.TorsoColor = coat
	desc.LeftArmColor = coat
	desc.RightArmColor = coat
	desc.LeftLegColor = trousers
	desc.RightLegColor = trousers
	local h = tonumber(look.height) or rng:NextNumber(0.95, 1.05)
	desc.HeightScale = h
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("NPC body failed: " .. tostring(model))
		return nil
	end
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.WalkSpeed = rng:NextNumber(8, 10)
	local head = model:FindFirstChild("Head")
	-- hair: a cap of colour over the head, longer at the back for some
	if head then
		local cap = Instance.new("Part")
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(1.32, 0.95, 1.32)
		cap.Color = hair
		cap.Material = Enum.Material.Fabric
		cap.CanCollide = false
		cap.Massless = true
		cap.CFrame = head.CFrame * CFrame.new(0, 0.28, 0.08)
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = cap
		w.Parent = cap
		cap.Parent = model
		local style = look.hair_style or (if look.gender == "f" and rng:NextNumber() < 0.7 then "long" else "short")
		if style == "long" or style == "bun" then
			local back = Instance.new("Part")
			back.Size = if style == "bun" then Vector3.new(0.6, 0.6, 0.6) else Vector3.new(1.2, 1.3, 0.35)
			back.Shape = if style == "bun" then Enum.PartType.Ball else Enum.PartType.Block
			back.Color = hair
			back.Material = Enum.Material.Fabric
			back.CanCollide = false
			back.Massless = true
			back.CFrame = head.CFrame * (if style == "bun" then CFrame.new(0, 0.35, 0.65) else CFrame.new(0, -0.25, 0.55))
			local w2 = Instance.new("WeldConstraint")
			w2.Part0 = head
			w2.Part1 = back
			w2.Parent = back
			back.Parent = model
		end
		-- a name tag and a speech bubble above the head
		local bb = Instance.new("BillboardGui")
		bb.Name = "Bubble"
		bb.Size = UDim2.fromOffset(240, 90)
		bb.StudsOffset = Vector3.new(0, 3.2, 0)
		bb.MaxDistance = 45
		bb.AlwaysOnTop = false
		bb.Adornee = head
		local tagLabel = Instance.new("TextLabel")
		tagLabel.Name = "NameTag"
		tagLabel.Size = UDim2.new(1, 0, 0, 22)
		tagLabel.Position = UDim2.new(0, 0, 1, -22)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = Enum.Font.GothamMedium
		tagLabel.TextSize = 16
		tagLabel.TextColor3 = Color3.fromRGB(240, 226, 196)
		tagLabel.TextStrokeTransparency = 0.5
		tagLabel.Text = ""
		tagLabel.Parent = bb
		local say = Instance.new("TextLabel")
		say.Name = "Say"
		say.Size = UDim2.new(1, 0, 1, -24)
		say.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		say.BackgroundTransparency = 0.25
		say.Font = Enum.Font.GothamMedium
		say.TextSize = 17
		say.TextWrapped = true
		say.TextColor3 = Color3.fromRGB(255, 248, 232)
		say.Visible = false
		say.Text = ""
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = say
		say.Parent = bb
		bb.Parent = head
	end
	model.Parent = parent
	if at then
		model:PivotTo(at)
	end
	-- one of the phone game's people, worn over the (now unseen) Roblox body
	PeopleModels.dress(model, look, rng, h)
	-- animations
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local tracks = {}
	for k, id in ANIM do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok2, tr = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if ok2 then
			tracks[k] = tr
			tr.Looped = true
		end
	end
	local function play(which)
		for k, tr in tracks do
			if k == which then
				if not tr.IsPlaying then
					tr:Play(0.2)
				end
			elseif tr.IsPlaying then
				tr:Stop(0.2)
			end
		end
	end
	hum.Running:Connect(function(speed)
		if hum.Sit then
			return
		end
		play(if speed > 0.5 then "walk" else "idle")
	end)
	play("idle")
	return { model = model, humanoid = hum, root = model:FindFirstChild("HumanoidRootPart"), head = head, play = play }
end

-- Shows a line over the person's head for a few seconds (and the name tag underneath).
function Npc.say(n, text, seconds, color)
	if not n.head then
		return
	end
	local bb = n.head:FindFirstChild("Bubble")
	if not bb then
		return
	end
	local label = bb:FindFirstChild("Say")
	if n.model and text ~= "" then
		-- the client moves their head as they talk
		n.model:SetAttribute("TalkUntil", workspace:GetServerTimeNow() + math.min(seconds or 3, 6))
	end
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 248, 232)
	label.Visible = text ~= ""
	n.sayToken = (n.sayToken or 0) + 1
	local token = n.sayToken
	if seconds and seconds > 0 then
		task.delay(seconds, function()
			if n.sayToken == token and label.Parent then
				label.Visible = false
			end
		end)
	end
end

function Npc.setTag(n, text)
	if n.head and n.head:FindFirstChild("Bubble") then
		n.head.Bubble.NameTag.Text = text
	end
end

-- Walks to a point by pathfinding (round the furniture); falls back to walking straight there.
-- Returns true when it got there.
function Npc.walkTo(n, goal, alive)
	local hum, root = n.humanoid, n.root
	if not hum or not root or not root.Parent then
		return false
	end
	if root.Anchored then
		root.Anchored = false
	end
	hum.Sit = false
	local path = PathfindingService:CreatePath({ AgentRadius = 1.1, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 3 })
	local ok = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)
	local points = {}
	if ok and path.Status == Enum.PathStatus.Success then
		for _, wp in path:GetWaypoints() do
			table.insert(points, wp.Position)
		end
	end
	table.insert(points, goal)
	for _, p in points do
		if alive and not alive() then
			return false
		end
		hum:MoveTo(p)
		local reached = hum.MoveToFinished:Wait()
		if not reached and (root.Position - p).Magnitude > 3 then
			hum:MoveTo(p)
			hum.MoveToFinished:Wait()
		end
	end
	return (root.Position - goal).Magnitude < 4
end

-- Sits down on a seat part, facing the way the seat faces.
function Npc.sitOn(n, seatPart)
	local root = n.root
	if not root then
		return
	end
	n.humanoid.Sit = true
	root.Anchored = true
	root.CFrame = seatPart.CFrame * CFrame.new(0, 1.75, 0.2)
	n.play("sit")
end

function Npc.standUp(n)
	if n.root then
		n.root.Anchored = false
	end
	n.humanoid.Sit = false
	n.play("idle")
end

-- Turns to face a point (keeps upright).
function Npc.face(n, point)
	local root = n.root
	if not root then
		return
	end
	local pos = root.Position
	local look = Vector3.new(point.X, pos.Y, point.Z)
	if (look - pos).Magnitude > 0.1 then
		if root.Anchored then
			root.CFrame = CFrame.lookAt(pos, look)
		else
			root.CFrame = CFrame.lookAt(pos, look)
		end
	end
end

-- Puts something in the right hand (a glass), held upright in front.
function Npc.hold(n, model)
	local hand = n.model:FindFirstChild("RightHand")
	if not hand or not model or not model.PrimaryPart then
		return
	end
	local root = model.PrimaryPart
	-- out of whoever's hand it was in
	for _, w in root:GetChildren() do
		if w.Name == "HoldWeld" then
			w:Destroy()
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.Massless = true
		end
	end
	model:PivotTo(hand.CFrame * CFrame.new(0, -0.15, -0.45))
	-- every part held to the glass's base, and the base to the hand
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root and not p:FindFirstChild("HoldWeld") then
			local lw = Instance.new("WeldConstraint")
			lw.Name = "HoldWeld"
			lw.Part0 = root
			lw.Part1 = p
			lw.Parent = p
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Name = "HoldWeld"
	w.Part0 = hand
	w.Part1 = root
	w.Parent = root
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	model.Parent = n.model
end

return Npc
