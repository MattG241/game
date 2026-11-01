-- The pour: a close-up behind the bar where you tilt the glass and work the tap yourself, with the
-- same liquid physics as the phone game (a two-part stout that cascades and settles, a lager's
-- head, spills over the rim). The result goes back to the server, which checks it and the keg.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Contents = require(Shared.Contents)
local Ui = require(script.Parent.Ui)

local Pour = {}

local player = Players.LocalPlayer
local active = nil

local SIZE = { pint = { h = 0.85, r = 0.26 }, tumbler = { h = 0.5, r = 0.3 } }
local CREAM = Color3.fromRGB(238, 222, 186)

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function cyl(parent, r, h, color, material, transparency)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(h, r * 2, r * 2)
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function hideCharacter(on)
	local ch = player.Character
	if not ch then
		return
	end
	for _, p in ch:GetDescendants() do
		if p:IsA("BasePart") or p:IsA("Decal") then
			(p :: any).LocalTransparencyModifier = if on then 1 else 0
		end
	end
end

local function idealTilt(a)
	local c, serve = a.contents, a.serve
	if (serve == "stout" and c.stage >= 2) or serve == "ale" or serve == "whiskey" or serve == "soda" then
		return 0
	end
	local lvl = c:total()
	if serve == "lager" or serve == "cider" then
		return if lvl < 0.65 then 45 else lerp(45, 6, math.clamp((lvl - 0.65) / 0.25, 0, 1))
	end
	if lvl < 0.45 then
		return 45
	end
	return lerp(45, 4, math.clamp((lvl - 0.45) / 0.35, 0, 1))
end

local function statusText(a)
	local c = a.contents
	if a.serve == "stout" then
		if c.stage == 0 then
			return "1. Tilt the glass to 45°   2. Pull the tap"
		elseif c.stage == 1 then
			return "Keep pouring to about three-quarters, straightening as it fills"
		elseif c.stage == 2 then
			local s = c:settledFraction()
			if s < 0.97 then
				return string.format("Settling... %d%%  (leave it on the drip tray and do something else)", math.floor(s * 100))
			end
			return "Settled! Hold the glass upright and top it up gently"
		end
		return "Top up until the head domes just over the rim"
	elseif a.serve == "whiskey" then
		return if c:total() < 0.99 then "Push the glass up to the optic until the measure stops" else "One measure. Done!"
	elseif a.serve == "soda" then
		return "Hold the trigger and stop just under the rim"
	elseif a.serve == "ale" then
		return "Pull the pump steadily until the glass is full"
	elseif a.serve == "cider" then
		return "Tilt the glass and pour; it barely heads, so fill near the brim"
	end
	return "Tilt the glass, pull the tap, straighten near the top"
end

-- A vertical slider (0 at the bottom, 1 at the top). spring: snaps back to 0 when let go.
local function slider(parent, title, x, onChange, spring)
	local box = Ui.panel(parent, UDim2.new(0, 96, 0.55, 0), UDim2.new(x, if x < 0.5 then 24 else -120, 0.2, 0), 0.35)
	local t = Ui.label(box, title, 15, Ui.GOLD, Enum.Font.GothamBold)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.Position = UDim2.fromOffset(0, 6)
	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, 14, 1, -70)
	track.Position = UDim2.new(0.5, -7, 0, 34)
	track.BackgroundColor3 = Color3.fromRGB(70, 64, 58)
	track.BorderSizePixel = 0
	Ui.corner(track, 7)
	track.Parent = box
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = Ui.GREEN
	fill.BorderSizePixel = 0
	Ui.corner(fill, 7)
	fill.Parent = track
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(54, 30)
	knob.Position = UDim2.fromScale(0.5, 1)
	knob.BackgroundColor3 = Ui.GOLD
	knob.BorderSizePixel = 0
	Ui.corner(knob, 15)
	knob.Parent = track
	local valueLabel = Ui.label(box, "", 15, Ui.CREAM, Enum.Font.GothamBold)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Center
	valueLabel.Position = UDim2.new(0, 0, 1, -28)
	local s = { value = 0, label = valueLabel }
	local dragging = nil
	local function set(v)
		s.value = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(1, s.value)
		knob.Position = UDim2.fromScale(0.5, 1 - s.value)
		onChange(s.value)
	end
	s.set = set
	local function fromInput(input)
		local top = track.AbsolutePosition.Y
		local h = track.AbsoluteSize.Y
		set(1 - (input.Position.Y - top) / math.max(h, 1))
	end
	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = box
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = input
			fromInput(input)
		end
	end)
	s.conn1 = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input == dragging or (dragging.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
			fromInput(input)
		end
	end)
	s.conn2 = UserInputService.InputEnded:Connect(function(input)
		if dragging and (input == dragging or input.UserInputType == dragging.UserInputType) then
			dragging = nil
			if spring then
				set(0)
			end
		end
	end)
	return s
end

local function layout(a)
	local s = SIZE[a.glassKind] or SIZE.pint
	local th = math.rad(a.tilt)
	local side = Vector3.new(-1, 0, 0) -- the way the top of the glass leans
	local nozzle = a.nozzle
	local base = nozzle - Vector3.new(0, 0.12 + s.h * math.cos(th), 0) - side * s.h * math.sin(th) * 0.82
	local cf = CFrame.new(base) * CFrame.Angles(0, 0, th)
	local up = CFrame.Angles(0, 0, math.rad(90))
	a.parts.shell.CFrame = cf * CFrame.new(0, s.h / 2, 0) * up
	local inner = s.h * 0.93
	local y = s.h * 0.04
	local c = a.contents
	local function layer(part, frac)
		local hgt = math.max(0.001, math.clamp(frac, 0, 1.06) * inner)
		part.Size = Vector3.new(hgt, part.Size.Y, part.Size.Z)
		part.CFrame = cf * CFrame.new(0, y + hgt / 2, 0) * up
		part.Transparency = if frac < 0.004 then 1 else 0
		if frac >= 0.004 then
			y += hgt
		end
	end
	layer(a.parts.body, c.body)
	layer(a.parts.cascade, c.cascade)
	layer(a.parts.foam, c.foam)
	-- the stream from the nozzle down to the surface (or the glass wall when it's tilted)
	local surface = (cf * CFrame.new(0, y, 0)).Position.Y
	local bottom = math.min(surface, nozzle.Y - 0.05)
	if a.tilt > 15 then
		bottom = math.max(bottom, nozzle.Y - 0.35)
	end
	local len = math.max(0.01, nozzle.Y - bottom)
	a.parts.stream.Transparency = if a.flowVis > 0.03 then 0.2 else 1
	a.parts.stream.Size = Vector3.new(len, 0.05 + a.flowVis * 0.05, 0.05 + a.flowVis * 0.05)
	a.parts.stream.CFrame = CFrame.new(nozzle.X, nozzle.Y - len / 2, nozzle.Z) * up
	return base
end

function Pour.start(data, send)
	if active then
		return
	end
	local a = { drink = data.drink, serve = data.serve or "stout", glassKind = data.glass or "pint",
		contents = Contents.fromTable(data.contents), tilt = 0, tiltInput = 0, lever = 0, unitsLeft = data.units or 0,
		drawn = 0, nozzle = data.nozzle, settleSeconds = data.settle or 12, flowVis = 0, wasFlowing = false,
		assist = false, warned = false, freeSlots = data.freshSlots }
	a.contents.freshness = a.contents.freshness or 1
	active = a
	-- the glass and the beer, drawn locally
	local folder = Instance.new("Folder")
	folder.Name = "PourView"
	folder.Parent = workspace
	a.folder = folder
	local s = SIZE[a.glassKind] or SIZE.pint
	local col = data.color or Color3.fromRGB(20, 10, 6)
	a.parts = {
		shell = cyl(folder, s.r, s.h, Color3.fromRGB(220, 232, 236), Enum.Material.Glass, 0.6),
		body = cyl(folder, s.r * 0.88, 0.01, col, Enum.Material.Glass, 0),
		cascade = cyl(folder, s.r * 0.885, 0.01, Color3.fromRGB(168, 128, 92), Enum.Material.SmoothPlastic, 0),
		foam = cyl(folder, s.r * 0.89, 0.01, CREAM, Enum.Material.SmoothPlastic, 0),
		stream = cyl(folder, 0.03, 0.1, if a.serve == "stout" then Color3.fromRGB(150, 110, 70) else col, Enum.Material.Glass, 1),
	}
	local base = layout(a)
	hideCharacter(true)
	-- the camera: in close from the bartender's side, the glass under the nozzle filling the frame
	local cam = workspace.CurrentCamera
	a.oldType = cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable
	local target = base + Vector3.new(0, 0.55, 0)
	local view = CFrame.lookAt(target + Vector3.new(0.7, 0.75, -2.6), target)
	TweenService:Create(cam, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { CFrame = view }):Play()
	-- the controls
	local gui = Instance.new("ScreenGui")
	gui.Name = "PourGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- so slider positions and touch positions share one origin
	gui.Parent = player:WaitForChild("PlayerGui")
	a.gui = gui
	gui = Ui.root(gui)
	local pad = Ui.gamepad()
	local top = Ui.panel(gui, UDim2.new(0.6, 0, 0, 0), UDim2.new(0.2, 0, 0, 56), 0.35)
	top.AutomaticSize = Enum.AutomaticSize.Y
	Ui.pad(top, 14, 10)
	Ui.list(top, 4)
	local title = Ui.label(top, (data.name or "") .. "  ·  " .. string.format("%d serves left", math.floor(a.unitsLeft)), 15, Ui.GOLD, Enum.Font.GothamBold)
	title.TextXAlignment = Enum.TextXAlignment.Center
	a.status = Ui.label(top, statusText(a), 18, Ui.CREAM)
	a.status.TextXAlignment = Enum.TextXAlignment.Center
	a.tiltSlider = slider(gui, "TILT", 0, function(v)
		a.tiltInput = v
	end, false)
	a.tapSlider = slider(gui, "TAP", 1, function(v)
		a.lever = v
	end, true)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(0, 520, 0, 50)
	row.Position = UDim2.new(0.5, -260, 1, -150)
	row.Parent = gui
	local l = Ui.list(row, 10, true)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local function hint(t, key)
		return if pad then t .. "  (" .. key .. ")" else t
	end
	a.settleBtn = Ui.button(row, hint("Leave to settle", "Y"), function()
		Pour.finish(send, true)
	end, "accent", UDim2.fromOffset(170, 48))
	Ui.button(row, hint("Done", "B"), function()
		Pour.finish(send, false)
	end, nil, UDim2.fromOffset(120, 48))
	local assistBtn
	local function toggleAssist()
		a.assist = not a.assist
		assistBtn.Text = hint(if a.assist then "Auto tilt: on" else "Auto tilt: off", "X")
	end
	assistBtn = Ui.button(row, hint("Auto tilt: off", "X"), toggleAssist, nil, UDim2.fromOffset(150, 48))
	if pad then
		local h = Ui.label(gui, "Left stick: tilt the glass    Right trigger: pull the tap", 15, Ui.MUTED)
		h.TextXAlignment = Enum.TextXAlignment.Center
		h.Size = UDim2.new(1, 0, 0, 20)
		h.AutomaticSize = Enum.AutomaticSize.None
		h.Position = UDim2.new(0, 0, 1, -92)
	end
	-- controllers (Xbox, PlayStation, or a pad on a computer): the left stick tilts, the right
	-- trigger is the tap (pull it gently for a slow pour), B is done, Y leaves it to settle, X
	-- toggles auto tilt. These are taken while pouring so the character doesn't jump or walk.
	a.stickY = 0
	ContextActionService:BindActionAtPriority("PubPour", function(_, state, input)
		local k = input.KeyCode
		if k == Enum.KeyCode.Thumbstick1 then
			a.stickY = if math.abs(input.Position.Y) > 0.15 then input.Position.Y else 0
		elseif k == Enum.KeyCode.ButtonR2 then
			a.tapSlider.set(if state == Enum.UserInputState.End then 0 else input.Position.Z)
		elseif state == Enum.UserInputState.Begin then
			if k == Enum.KeyCode.ButtonB then
				task.defer(Pour.finish, send, false)
			elseif k == Enum.KeyCode.ButtonY then
				if a.settleBtn.Visible then
					task.defer(Pour.finish, send, true)
				end
			elseif k == Enum.KeyCode.ButtonX then
				toggleAssist()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonL2)
	-- keyboard: W/S tilt, Space pulls the tap
	a.keys = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			a.tapSlider.set(1)
		elseif input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
			a.tiltSlider.set(a.tiltInput + 0.1)
		elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
			a.tiltSlider.set(a.tiltInput - 0.1)
		end
	end)
	a.keysUp = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space then
			a.tapSlider.set(0)
		end
	end)
	a.step = RunService.RenderStepped:Connect(function(dt)
		if a.stickY ~= 0 then
			a.tiltSlider.set(a.tiltInput + a.stickY * dt * 0.9)
		end
		local want = if a.assist then idealTilt(a) else a.tiltInput * 90
		local step = dt * 140
		a.tilt += math.clamp(want - a.tilt, -step, step)
		local c = a.contents
		local flow = a.lever
		if flow > 0.01 and a.drawn >= a.unitsLeft - 0.005 then
			flow = 0
			if not a.warned then
				a.warned = true
				a.status.Text = "The keg's run dry! Change it in the cellar."
			end
		end
		if a.serve == "whiskey" and c:total() >= 1 then
			flow = 0 -- the optic gives one measure, then stops
		end
		if flow > 0.01 then
			local dv = c:pour(dt, flow, a.tilt, a.drink, a.serve)
			a.drawn += dv
			a.wasFlowing = true
		elseif a.wasFlowing then
			a.wasFlowing = false
			c:stopPour()
		end
		c:settle(dt, a.settleSeconds)
		a.flowVis += math.clamp(flow - a.flowVis, -dt * 6, dt * 6)
		layout(a)
		if not a.warned then
			a.status.Text = statusText(a)
		end
		a.tiltSlider.label.Text = string.format("%d°", math.floor(a.tilt + 0.5))
		a.tapSlider.label.Text = string.format("%d%%", math.floor(a.lever * 100))
		a.settleBtn.Visible = a.serve == "stout" and c.stage == 2 and a.freeSlots
	end)
end

function Pour.finish(send, toSettle)
	local a = active
	if not a then
		return
	end
	active = nil
	if a.wasFlowing then
		a.contents:stopPour()
	end
	a.step:Disconnect()
	a.keys:Disconnect()
	a.keysUp:Disconnect()
	ContextActionService:UnbindAction("PubPour")
	for _, sl in { a.tiltSlider, a.tapSlider } do
		sl.conn1:Disconnect()
		sl.conn2:Disconnect()
	end
	a.gui:Destroy()
	a.folder:Destroy()
	hideCharacter(false)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	send(a.contents:toTable(), toSettle)
end

function Pour.active()
	return active ~= nil
end

return Pour
