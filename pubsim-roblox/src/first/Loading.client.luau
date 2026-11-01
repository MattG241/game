-- The game's own opening card instead of Roblox's loading screen: the title over a dark,
-- warm background until the pub has loaded.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "Opening"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(16, 11, 8)
bg.BorderSizePixel = 0
bg.Parent = gui
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(60, 34, 16), Color3.fromRGB(12, 9, 7))
grad.Rotation = 90
grad.Parent = bg
local function text(t, size, color, font, y)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size + 10)
	l.Position = UDim2.new(0, 0, 0.5, y)
	l.Text = t
	l.TextSize = size
	l.TextColor3 = color
	l.Font = font
	l.Parent = bg
	return l
end
text("The Irish Pub", 64, Color3.fromRGB(240, 196, 108), Enum.Font.Garamond, -110)
text("Simulator", 44, Color3.fromRGB(250, 242, 226), Enum.Font.Garamond, -40)
local status = text("Opening up...", 20, Color3.fromRGB(196, 186, 170), Enum.Font.GothamMedium, 40)
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

if not game:IsLoaded() then
	game.Loaded:Wait()
end
status.Text = "Lighting the fire..."
-- the pub itself (it can take a few seconds to arrive)
workspace:WaitForChild("ApkPub", 15)
task.wait(1.5)
for _, d in gui:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
	end
end
TweenService:Create(bg, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
task.wait(0.9)
gui:Destroy()
