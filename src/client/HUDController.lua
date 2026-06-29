--!strict
--[[
	HUDController
	-------------
	Builds and drives the in-match heads-up display entirely from code (no
	pre-built GUI assets required):
	  * Player health + stamina + special meter (bottom-left)
	  * Combo counter (center, pops on hit)
	  * Round timer + best-of-3 score pips (top-center)
	  * Phase banner ("FIGHT!", "SUDDEN DEATH!", countdown)
	  * Toast notifications (rewards, level-ups, purchases)

	Driven by StatsChanged / MatchStateChanged / Notify remotes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

local HUDController = {}
local player = Players.LocalPlayer

local FONT = Enum.Font.GothamBold
local NEON = Color3.fromRGB(220, 40, 255)

-- Small helpers ------------------------------------------------------------

local function make(class: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function bar(parent: Instance, name: string, color: Color3, yOffset: number): (Frame, Frame, TextLabel)
	local holder = make("Frame", {
		Name = name,
		Size = UDim2.new(0, 280, 0, 22),
		Position = UDim2.new(0, 0, 0, yOffset),
		BackgroundColor3 = Color3.fromRGB(15, 15, 22),
		BorderSizePixel = 0,
	}, parent) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, holder)
	make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5, Transparency = 0.3 }, holder)

	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, holder) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, fill)

	local label = make("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.4,
		TextScaled = true,
		Text = name,
	}, holder) :: TextLabel
	make("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, label)

	return holder, fill, label
end

-- State --------------------------------------------------------------------

local gui: ScreenGui
local healthFill, staminaFill, specialFill: Frame
local healthLabel: TextLabel
local comboLabel: TextLabel
local timerLabel: TextLabel
local scoreLabel: TextLabel
local bannerLabel: TextLabel
local toastHolder: Frame

local lastCombo = 0

local function buildHUD()
	gui = make("ScreenGui", {
		Name = "UAF_HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, player:WaitForChild("PlayerGui")) :: ScreenGui

	-- Bottom-left resource bars.
	local barsHolder = make("Frame", {
		Name = "Bars",
		Size = UDim2.new(0, 280, 0, 84),
		Position = UDim2.new(0, 24, 1, -110),
		BackgroundTransparency = 1,
	}, gui) :: Frame

	local _, hFill, hLabel = bar(barsHolder, "Health", Color3.fromRGB(80, 220, 100), 0)
	local _, sFill = bar(barsHolder, "Stamina", Color3.fromRGB(255, 200, 60), 30)
	local _, spFill = bar(barsHolder, "Special", NEON, 60)
	healthFill, staminaFill, specialFill = hFill, sFill, spFill
	healthLabel = hLabel

	-- Combo counter (center-ish, hidden until a combo exists).
	comboLabel = make("TextLabel", {
		Name = "Combo",
		Size = UDim2.new(0, 300, 0, 80),
		Position = UDim2.new(0.5, -150, 0.45, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = NEON,
		TextStrokeTransparency = 0.2,
		TextScaled = true,
		Text = "",
		Visible = false,
	}, gui) :: TextLabel

	-- Top-center round timer + score.
	local topHolder = make("Frame", {
		Name = "RoundInfo",
		Size = UDim2.new(0, 240, 0, 90),
		Position = UDim2.new(0.5, -120, 0, 16),
		BackgroundColor3 = Color3.fromRGB(15, 15, 22),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, gui) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, topHolder)
	make("UIStroke", { Color = NEON, Thickness = 1.5, Transparency = 0.4 }, topHolder)

	timerLabel = make("TextLabel", {
		Name = "Timer",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		Text = "--",
	}, topHolder) :: TextLabel

	scoreLabel = make("TextLabel", {
		Name = "Score",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 54),
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		TextScaled = true,
		Text = "Best of 3",
	}, topHolder) :: TextLabel

	-- Phase banner.
	bannerLabel = make("TextLabel", {
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.new(0, 0, 0.28, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = NEON,
		TextStrokeTransparency = 0.2,
		TextScaled = true,
		Text = "",
		Visible = false,
	}, gui) :: TextLabel

	-- Toast stack (top-right).
	toastHolder = make("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0, 320, 1, -40),
		Position = UDim2.new(1, -340, 0, 20),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, toastHolder)
end

-- Updates ------------------------------------------------------------------

local function tweenSize(frame: Frame, scale: number)
	scale = math.clamp(scale, 0, 1)
	TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
		Size = UDim2.new(scale, 0, 1, 0),
	}):Play()
end

local function onStats(data)
	if not gui then
		return
	end
	tweenSize(healthFill, data.health / data.maxHealth)
	tweenSize(staminaFill, data.stamina / data.maxStamina)
	tweenSize(specialFill, data.special / data.maxSpecial)
	healthLabel.Text = ("HP  %d"):format(math.ceil(data.health))

	-- Special bar pulses when full.
	if data.special >= data.maxSpecial then
		specialFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	else
		specialFill.BackgroundColor3 = NEON
	end

	-- Combo counter.
	if data.combo and data.combo > 1 then
		comboLabel.Visible = true
		comboLabel.Text = data.combo .. "x COMBO"
		if data.combo ~= lastCombo then
			comboLabel.TextSize = 0
			comboLabel.Size = UDim2.new(0, 360, 0, 96)
			comboLabel.Position = UDim2.new(0.5, -180, 0.43, 0)
			TweenService:Create(comboLabel, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 300, 0, 80),
				Position = UDim2.new(0.5, -150, 0.45, 0),
			}):Play()
		end
	else
		comboLabel.Visible = false
	end
	lastCombo = data.combo or 0
end

local function scorePips(scores, team)
	-- Render "You 1 - 0 Opp" style with the local team first.
	local you = (team == "B") and scores.B or scores.A
	local opp = (team == "B") and scores.A or scores.B
	return ("YOU  %d  -  %d  OPP"):format(you, opp)
end

local function flashBanner(text: string, color: Color3?)
	bannerLabel.Text = text
	bannerLabel.TextColor3 = color or NEON
	bannerLabel.Visible = true
	bannerLabel.TextTransparency = 0
	bannerLabel.Size = UDim2.new(1, 0, 0, 80)
	TweenService:Create(bannerLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 0, 120),
	}):Play()
	task.delay(1.4, function()
		if bannerLabel.Text == text then
			TweenService:Create(bannerLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			task.wait(0.5)
			if bannerLabel.Text == text then
				bannerLabel.Visible = false
			end
		end
	end)
end

local matchActive = false
function HUDController.isMatchActive(): boolean
	return matchActive
end

local function onMatch(data)
	if not gui then
		return
	end

	if data.scores then
		scoreLabel.Text = scorePips(data.scores, data.team)
	end
	if data.timeLeft then
		timerLabel.Text = ("%d"):format(data.timeLeft)
		timerLabel.TextColor3 = data.timeLeft <= 10 and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 255, 255)
	end

	local phase = data.phase
	matchActive = phase ~= "ended"

	if phase == "countdown" then
		flashBanner(data.message or "", Color3.fromRGB(255, 220, 80))
		timerLabel.Text = data.message or "--"
	elseif phase == "fight" and data.message == "FIGHT!" then
		flashBanner("FIGHT!", Color3.fromRGB(80, 255, 120))
	elseif phase == "suddendeath" and data.message then
		flashBanner(data.message, Color3.fromRGB(255, 90, 90))
	elseif phase == "roundover" and data.message then
		flashBanner(data.message, NEON)
	elseif phase == "intro" and data.message then
		flashBanner(data.message, NEON)
	elseif phase == "ended" then
		flashBanner(data.message or "", data.message == "VICTORY" and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 90, 90))
		timerLabel.Text = "--"
	end
end

local function showToast(text: string, color: Color3?)
	if not gui then
		return
	end
	local toast = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 26),
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = -tick() // 1,
	}, toastHolder) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, toast)
	make("UIStroke", { Color = color or NEON, Thickness = 1.5 }, toast)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, toast)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = color or Color3.fromRGB(255, 255, 255),
		TextScaled = false,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
	}, toast)

	toast.BackgroundTransparency = 1
	TweenService:Create(toast, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	task.delay(3.5, function()
		TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		toast:Destroy()
	end)
end
HUDController.showToast = showToast

function HUDController.start()
	buildHUD()
	Remotes.get("StatsChanged").OnClientEvent:Connect(onStats)
	Remotes.get("MatchStateChanged").OnClientEvent:Connect(onMatch)
	Remotes.get("Notify").OnClientEvent:Connect(function(data)
		showToast(data.text, data.color)
	end)

	-- Rebuild on respawn (ResetOnSpawn = false keeps it, but PlayerGui can churn).
	player.CharacterAdded:Connect(function()
		if not player.PlayerGui:FindFirstChild("UAF_HUD") then
			buildHUD()
		end
	end)
end

return HUDController
