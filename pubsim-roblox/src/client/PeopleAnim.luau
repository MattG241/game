-- Moves the phone game's people (PeopleModels on the server) on this player's screen.
--
-- Each person is the phone game's rigged body welded over an unseen Roblox NPC, which walks and
-- sits. Here their bones are posed every frame from what the NPC is doing: a walking stride when
-- it moves, sitting on its seat, a drink held at the chest and raised for a sip, the head moving
-- as they talk, breathing when still. Every turn is described about the person's own axes
-- (right, up, back) and converted into each bone's frame, so the rig's bone axes don't matter.
-- The glass they hold is drawn in their (posed) hand.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PeopleAnim = {}

local player = Players.LocalPlayer
local rigs = {} -- model -> rig
local M = 3.2

local BONES = { "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "upperarm_l", "upperarm_r",
	"lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r" }

local function about(x, y, z)
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

local function setup(model)
	local skin = model:FindFirstChild("Skin")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not skin or not root then
		return nil
	end
	local bones = {}
	for _, d in skin:GetDescendants() do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	if not bones.pelvis then
		return nil
	end
	for _, b in bones do
		b.Transform = CFrame.identity
	end
	local rig = { model = model, skin = skin, root = root, hum = model:FindFirstChildOfClass("Humanoid"), bones = bones,
		rest = {}, phase = math.random() * 6, walk = 0, sit = 0, hold = 0, sip = 0, seed = math.random() * 100 }
	-- each bone's resting orientation, in the person's own frame
	for _, name in BONES do
		local b = bones[name]
		if b then
			rig.rest[name] = root.CFrame:ToObjectSpace(b.WorldCFrame).Rotation
		end
	end
	rig.pelvisY = root.CFrame:PointToObjectSpace(bones.pelvis.WorldPosition).Y
	return rig
end

-- Turns a bone by R (about the person's own axes), and moves it by offset (in the person's frame).
local function pose(rig, name, R, offset)
	local b = rig.bones[name]
	local Rb = rig.rest[name]
	if not b or not Rb then
		return
	end
	local T = Rb:Inverse() * R * Rb
	if offset then
		T = CFrame.new(Rb:VectorToObjectSpace(offset)) * T
	end
	b.Transform = T
end

local function approach(v, target, rate, dt)
	return v + (target - v) * math.min(1, rate * dt)
end

-- the glass in their hand: the real one stays on the unseen body, a copy is drawn in the hand
local function glassOf(rig)
	for _, ch in rig.model:GetChildren() do
		if ch:IsA("Model") and ch ~= rig.skin and ch.PrimaryPart then
			return ch
		end
	end
	return nil
end

local function updateGlass(rig, now)
	local g = glassOf(rig)
	if g ~= rig.glassSource or (g and now - (rig.glassTime or 0) > 0.4) then
		if rig.glassCopy then
			rig.glassCopy:Destroy()
			rig.glassCopy = nil
		end
		rig.glassSource = g
		rig.glassTime = now
		if g then
			for _, p in g:GetDescendants() do
				if p:IsA("BasePart") then
					p.LocalTransparencyModifier = 1
				end
			end
			local ok, c = pcall(function()
				return g:Clone()
			end)
			if ok and c then
				for _, d in c:GetDescendants() do
					if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.LocalTransparencyModifier = 0
					end
				end
				c.Parent = workspace.CurrentCamera
				rig.glassCopy = c
			end
		end
	end
	local hand = rig.bones.hand_r
	if rig.glassCopy and rig.glassCopy.PrimaryPart and hand then
		local rot = rig.root.CFrame.Rotation * about(rig.sip * 0.9, 0, 0)
		local pos = hand.WorldPosition + rig.root.CFrame:VectorToWorldSpace(Vector3.new(-0.02, -0.1, -0.12) * M)
		local c = rig.glassCopy
		c:PivotTo(CFrame.new(pos) * rot * c.PrimaryPart.CFrame:ToObjectSpace(c:GetPivot()))
	end
end

local function animate(rig, dt, now, serverNow)
	local root = rig.root
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local sitting = (rig.hum and rig.hum.Sit) or root.Anchored
	local holding = glassOf(rig) ~= nil
	local sipping = rig.model:GetAttribute("Sipping") == true
	local talking = (rig.model:GetAttribute("TalkUntil") or 0) > serverNow
	rig.walk = approach(rig.walk, if speed > 0.6 and not sitting then 1 else 0, 8, dt)
	rig.sit = approach(rig.sit, if sitting then 1 else 0, 6, dt)
	rig.hold = approach(rig.hold, if holding then 1 else 0, 6, dt)
	rig.sip = approach(rig.sip, if sipping and holding then 1 else 0, 4, dt)
	rig.phase += dt * math.max(speed, 0.001) / (0.75 * M) * math.pi
	local s = math.sin(rig.phase)
	local c = math.cos(rig.phase)
	local w, st = rig.walk, rig.sit
	local t = now + rig.seed
	-- legs: the stride, or bent onto the seat
	local thighL = 0.45 * s * w + 1.5 * st
	local thighR = -0.45 * s * w + 1.5 * st
	local calfL = -(0.55 * math.max(0, -c) + 0.08) * w - 1.5 * st
	local calfR = -(0.55 * math.max(0, c) + 0.08) * w - 1.5 * st
	pose(rig, "thigh_l", about(thighL, 0, 0.04 * st))
	pose(rig, "thigh_r", about(thighR, 0, -0.04 * st))
	pose(rig, "calf_l", about(calfL))
	pose(rig, "calf_r", about(calfR))
	pose(rig, "foot_l", about(0.15 * w * math.max(0, s)))
	pose(rig, "foot_r", about(0.15 * w * math.max(0, -s)))
	-- the hips: a bob in the stride; down onto the seat (the seat top is 1.65 studs under the root)
	local seatDrop = (-1.65 + 0.32) - rig.pelvisY
	local bob = -math.abs(c) * 0.035 * M * w
	pose(rig, "pelvis", about(0, 0.08 * s * w, 0), Vector3.new(0, bob + seatDrop * st, 0.25 * st))
	-- the body: breathing, a slight lean back when seated
	local breath = math.sin(t * 1.7) * 0.012
	pose(rig, "spine_02", about(breath + 0.06 * st - 0.04 * w))
	pose(rig, "spine_03", about(breath, -0.08 * s * w, 0))
	-- the head: looks about now and then, nods while talking, tips back for a sip
	local look = math.sin(t * 0.37) * 0.25 + math.sin(t * 0.13) * 0.15
	local nod = if talking then math.sin(t * 7.0) * 0.06 + math.sin(t * 3.1) * 0.04 else 0
	pose(rig, "neck_01", about(nod * 0.5, look * 0.4 * (1 - w), 0))
	pose(rig, "head", about(nod + 0.3 * rig.sip, look * 0.5 * (1 - w), 0))
	-- arms: swinging in the stride; the right holds the drink at the chest and raises it to sip
	local hold, sip = rig.hold, rig.sip
	pose(rig, "upperarm_l", about(-0.3 * s * w, 0, 0.08 * (1 - w)))
	pose(rig, "lowerarm_l", about(0.25 * w + 0.15 + 0.3 * st))
	local armR = 0.3 * s * w * (1 - hold) + hold * (0.38 + 0.55 * sip)
	local elbowR = (0.25 * w + 0.15) * (1 - hold) + hold * (1.3 + 0.75 * sip)
	pose(rig, "upperarm_r", about(armR, 0, -0.08 * (1 - w) * (1 - hold) - 0.25 * hold))
	pose(rig, "lowerarm_r", about(elbowR, 0.35 * hold, 0))
	pose(rig, "hand_r", about(-0.2 * hold, 0, 0))
	if holding or rig.glassCopy then
		updateGlass(rig, now)
	end
end

function PeopleAnim.start()
	local folder = workspace:WaitForChild("People", 30)
	if not folder then
		return
	end
	RunService:BindToRenderStep("PubPeople", Enum.RenderPriority.Character.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local now = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		for _, model in folder:GetChildren() do
			local rig = rigs[model]
			if rig == nil and model:FindFirstChild("Skin") then
				rig = setup(model) or false
				rigs[model] = rig
			end
			if rig and rig.root.Parent and (rig.root.Position - camPos).Magnitude < 90 then
				animate(rig, dt, now, serverNow)
			end
		end
		for model, rig in rigs do
			if not model.Parent then
				if rig and rig.glassCopy then
					rig.glassCopy:Destroy()
				end
				rigs[model] = nil
			end
		end
	end)
end

return PeopleAnim
