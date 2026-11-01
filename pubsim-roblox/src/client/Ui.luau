-- Small helpers for the interface: smoked-glass panels, labels and buttons in the phone game's style.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Ui = {}

Ui.GOLD = Color3.fromRGB(240, 196, 108)
Ui.CREAM = Color3.fromRGB(250, 242, 226)
Ui.MUTED = Color3.fromRGB(196, 186, 170)
Ui.GREEN = Color3.fromRGB(32, 120, 74)
Ui.RED = Color3.fromRGB(240, 120, 100)
Ui.GOOD = Color3.fromRGB(150, 230, 160)
Ui.PANEL = Color3.fromRGB(14, 12, 11)

function Ui.corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = parent
	return c
end

function Ui.stroke(parent, alpha)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 255, 255)
	s.Transparency = alpha or 0.85
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Ui.pad(parent, px, py)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px or 12)
	p.PaddingRight = UDim.new(0, px or 12)
	p.PaddingTop = UDim.new(0, py or 8)
	p.PaddingBottom = UDim.new(0, py or 8)
	p.Parent = parent
	return p
end

function Ui.list(parent, gap, horizontal)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Parent = parent
	return l
end

-- A translucent dark panel with rounded corners and a hairline edge.
function Ui.panel(parent, size, pos, alpha)
	local f = Instance.new("Frame")
	f.Size = size or UDim2.fromOffset(200, 60)
	f.Position = pos or UDim2.new()
	f.BackgroundColor3 = Ui.PANEL
	f.BackgroundTransparency = alpha or 0.3
	f.BorderSizePixel = 0
	Ui.corner(f, 14)
	Ui.stroke(f)
	f.Parent = parent
	return f
end

function Ui.label(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text or ""
	l.TextSize = size or 18
	l.TextColor3 = color or Ui.CREAM
	l.Font = font or Enum.Font.GothamMedium
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Parent = parent
	return l
end

-- A button; style "accent" is the green primary, otherwise smoked glass.
function Ui.button(parent, text, onClick, style, size)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Text = text
	b.TextSize = 18
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Ui.CREAM
	b.TextWrapped = true
	b.Size = size or UDim2.fromOffset(150, 44)
	b.BackgroundColor3 = if style == "accent" then Ui.GREEN elseif style == "danger" then Color3.fromRGB(120, 40, 34) else Color3.fromRGB(40, 36, 32)
	b.BackgroundTransparency = if style == "accent" or style == "danger" then 0.05 else 0.25
	b.BorderSizePixel = 0
	Ui.corner(b, 10)
	if style ~= "accent" then
		Ui.stroke(b, 0.8)
	end
	b.Parent = parent
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- Phones, tablets, computers and TVs: everything inside a screen goes in a frame that is scaled
-- to fit, so the layout made for a 1100x640 screen shrinks neatly onto a phone and stays readable.
local roots = {}
local function fitScale()
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local s = math.min(v.X / 1100, v.Y / 640)
	if GuiService:IsTenFootInterface() then
		s = math.max(s, 1.15) -- a TV across the room wants bigger text
	end
	return math.clamp(s, 0.5, 1.4)
end

local function applyFit(r)
	local s = fitScale()
	r.scale.Scale = s
	r.frame.Size = UDim2.fromScale(1 / s, 1 / s)
end

function Ui.root(screenGui)
	local f = Instance.new("Frame")
	f.Name = "Fit"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = screenGui
	local sc = Instance.new("UIScale")
	sc.Parent = f
	local r = { frame = f, scale = sc }
	table.insert(roots, r)
	applyFit(r)
	return f
end

local function hookCamera()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			for _, r in roots do
				if r.frame.Parent then
					applyFit(r)
				end
			end
		end)
	end
end
hookCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)

-- Is the player on a controller right now? (Xbox, PlayStation, or a pad plugged into a computer)
function Ui.gamepad()
	local t = UserInputService:GetLastInputType()
	return t.Name:sub(1, 7) == "Gamepad"
end

function Ui.touch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not Ui.gamepad()
end

-- Point the controller's selection at a button, so A presses it.
function Ui.select(obj)
	if obj and Ui.gamepad() then
		GuiService.SelectedObject = obj
	end
end

function Ui.money(v)
	local neg = v < 0
	local s = string.format("€%.2f", math.abs(v))
	return if neg then "-" .. s else s
end

return Ui
