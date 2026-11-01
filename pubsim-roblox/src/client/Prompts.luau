-- The action button, in the phone game's style instead of Roblox's grey prompts.
--
-- Every ProximityPrompt is switched to the custom style on this screen, and the nearest one is
-- shown as one smoked-glass button at the foot of the screen, naming the action ("Pour a
-- stout", "Take the order"). Tap it on a phone; on a computer the key and on a controller the
-- button is shown on it. A hold action fills a gold bar while held.

local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Ui = require(script.Parent.Ui)

local Prompts = {}

local GLYPH = { ButtonX = "X", ButtonY = "Y", ButtonA = "A", ButtonB = "B", ButtonL1 = "LB", ButtonR1 = "RB" }

local function keyText(p)
	if Ui.gamepad() then
		local k = p.GamepadKeyCode.Name
		return GLYPH[k] or k
	elseif Ui.touch() then
		return nil
	end
	return p.KeyboardKeyCode.Name
end

function Prompts.start(parent)
	local holder = Instance.new("Frame")
	holder.Name = "Action"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Size = UDim2.fromOffset(330, 64)
	holder.Position = UDim2.new(1, -24, 1, -110)
	holder.Visible = false
	holder.Parent = parent
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = Ui.PANEL
	btn.BackgroundTransparency = 0.22
	btn.Parent = holder
	Ui.corner(btn, 18)
	Ui.stroke(btn, 0.55)
	local key = Instance.new("TextLabel")
	key.Size = UDim2.fromOffset(40, 40)
	key.Position = UDim2.new(0, 12, 0.5, -20)
	key.BackgroundColor3 = Ui.GOLD
	key.TextColor3 = Ui.PANEL
	key.Font = Enum.Font.GothamBold
	key.TextSize = 18
	key.Parent = btn
	Ui.corner(key, 20)
	local action = Ui.label(btn, "", 19, Ui.CREAM, Enum.Font.GothamBold)
	action.AutomaticSize = Enum.AutomaticSize.None
	action.Size = UDim2.new(1, -72, 0, 24)
	action.Position = UDim2.fromOffset(62, 9)
	action.TextTruncate = Enum.TextTruncate.AtEnd
	local object = Ui.label(btn, "", 14, Ui.MUTED)
	object.AutomaticSize = Enum.AutomaticSize.None
	object.Size = UDim2.new(1, -72, 0, 18)
	object.Position = UDim2.fromOffset(62, 35)
	object.TextTruncate = Enum.TextTruncate.AtEnd
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Ui.GOLD
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0, 0, 0, 4)
	bar.Position = UDim2.new(0, 14, 1, -8)
	bar.Parent = btn
	Ui.corner(bar, 2)

	local shown = nil
	local holdStart = nil

	local function refresh()
		if not shown then
			holder.Visible = false
			return
		end
		holder.Visible = shown.Enabled
		action.Text = shown.ActionText
		object.Text = shown.ObjectText
		local k = keyText(shown)
		key.Visible = k ~= nil
		key.Text = k or ""
		action.Position = UDim2.fromOffset(if k then 62 else 18, if shown.ObjectText ~= "" then 9 else 20)
		object.Position = UDim2.fromOffset(if k then 62 else 18, 35)
		object.Visible = shown.ObjectText ~= ""
	end

	-- every prompt in this style, here
	local function adopt(p)
		if p:IsA("ProximityPrompt") then
			p.Style = Enum.ProximityPromptStyle.Custom
		end
	end
	for _, d in workspace:GetDescendants() do
		adopt(d)
	end
	workspace.DescendantAdded:Connect(adopt)

	ProximityPromptService.PromptShown:Connect(function(p)
		shown = p
		refresh()
	end)
	ProximityPromptService.PromptHidden:Connect(function(p)
		if shown == p then
			shown = nil
			holdStart = nil
			bar.Size = UDim2.new(0, 0, 0, 4)
			refresh()
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(p)
		if p == shown then
			holdStart = os.clock()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(p)
		if p == shown then
			holdStart = nil
			bar.Size = UDim2.new(0, 0, 0, 4)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function()
		holdStart = nil
		bar.Size = UDim2.new(0, 0, 0, 4)
	end)
	UserInputService.LastInputTypeChanged:Connect(refresh)
	-- a tap (or click) on the button
	btn.InputBegan:Connect(function(input)
		if shown and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
			shown:InputHoldBegin()
		end
	end)
	btn.InputEnded:Connect(function(input)
		if shown and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
			shown:InputHoldEnd()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if shown then
			if action.Text ~= shown.ActionText or object.Text ~= shown.ObjectText or holder.Visible ~= shown.Enabled then
				refresh()
			end
			if holdStart and shown.HoldDuration > 0 then
				local f = math.clamp((os.clock() - holdStart) / shown.HoldDuration, 0, 1)
				bar.Size = UDim2.new(f, -28 * f, 0, 4)
			end
		end
	end)
end

return Prompts
