-- First person, like the phone game: the glass you're holding is shown in the lower right of
-- your view (the real one stays in your character's hand, where everyone else sees it).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HeldView = {}

local player = Players.LocalPlayer
local source, copy = nil, nil
local lastCopy = 0
local OFFSET = CFrame.new(1.05, -1.05, -2.3) * CFrame.Angles(0, math.rad(-12), 0)

local function heldModel()
	local ch = player.Character
	if not ch then
		return nil
	end
	for _, m in ch:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Held") then
			return m
		end
	end
	return nil
end

local function makeCopy(m)
	if copy then
		copy:Destroy()
		copy = nil
	end
	if not m or not m.PrimaryPart then
		return
	end
	local ok, c = pcall(function()
		return m:Clone()
	end)
	if not ok or not c then
		return
	end
	for _, d in c:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	c.Name = "HeldView"
	c.Parent = workspace.CurrentCamera
	copy = c
end

function HeldView.start(isPouring)
	RunService:BindToRenderStep("PubHeldView", Enum.RenderPriority.Camera.Value + 5, function()
		local m = if isPouring() then nil else heldModel()
		if m ~= source then
			source = m
			makeCopy(m)
			lastCopy = os.clock()
		elseif m and os.clock() - lastCopy > 0.25 then
			-- re-copied a few times a second, so the copy fills, settles and empties with the real one
			makeCopy(m)
			lastCopy = os.clock()
		end
		if copy and copy.PrimaryPart then
			-- held upright, turned with the view
			local cam = workspace.CurrentCamera.CFrame
			local look = cam.LookVector
			local target = CFrame.new((cam * OFFSET).Position) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
			copy:PivotTo(target * copy.PrimaryPart.CFrame:ToObjectSpace(copy:GetPivot()))
		end
	end)
end

return HeldView
