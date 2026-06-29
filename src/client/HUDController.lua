--!strict
--[[
	HUDController (Smash-style)
	---------------------------
	Builds and drives the in-match HUD entirely from code:
	  * Per-fighter panels (bottom): name, big DAMAGE % (recolors white->red as it
	    climbs), and STOCK icons. Your team sits bottom-left, enemies bottom-right.
	  * Your shield (stamina) + special meter + combo counter.
	  * Match timer (top-center).
	  * Phase banner ("GO!", countdown, "KO!", VICTORY/DEFEAT).
	  * Toast notifications (rewards, level-ups, purchases).

	Driven by StatsChanged (your live %/shield/special) + MatchStateChanged
	(both fighters' %/stocks) + Notify.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local GameConfig = require(Shared.GameConfig)

local HUDController = {}
local player = Players.LocalPlayer
local MAX_STOCKS = GameConfig.Match.Stocks

local FONT = Enum.Font.GothamBold
local NEON = Color3.fromRGB(220, 40, 255)

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- White (0%) -> yellow (60%) -> orange (110%) -> red (160%+).
local function percentColor(pct: number): Color3
	if pct <= 60 then
		return Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 220, 60), pct / 60)
	elseif pct <= 110 then
		return Color3.fromRGB(255, 220, 60):Lerp(Color3.fromRGB(255, 130, 30), (pct - 60) / 50)
	else
		return Color3.fromRGB(255, 130, 30):Lerp(Color3.fromRGB(255, 50, 50), math.clamp((pct - 110) / 60, 0, 1))
	end
end

-- State --------------------------------------------------------------------

local gui: ScreenGui
local panelsLeft: Frame
local panelsRight: Frame
local shieldFill: Frame
local specialFill: Frame
local comboLabel: TextLabel
local timerLabel: TextLabel
local bannerLabel: TextLabel
local toastHolder: Frame

-- userId -> { percentLabel, stockHolder }
local fighterPanels: { [number]: any } = {}
local builtSignature = ""
local lastCombo = 0
local matchActive = false

local function buildHUD()
	gui = make("ScreenGui", {
		Name = "UAF_HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, player:WaitForChild("PlayerGui"))

	-- Fighter panel columns.
	panelsLeft = make("Frame", {
		Name = "PanelsLeft",
		Size = UDim2.new(0, 280, 0, 240),
		Position = UDim2.new(0, 24, 1, -260),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom }, panelsLeft)

	panelsRight = make("Frame", {
		Name = "PanelsRight",
		Size = UDim2.new(0, 280, 0, 240),
		Position = UDim2.new(1, -304, 1, -260),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right }, panelsRight)

	-- Your shield + special meters (just above your panel column).
	local meters = make("Frame", {
		Name = "Meters",
		Size = UDim2.new(0, 280, 0, 26),
		Position = UDim2.new(0, 24, 1, -290),
		BackgroundTransparency = 1,
	}, gui)
	local function meter(name, color, x)
		local back = make("Frame", {
			Size = UDim2.new(0, 134, 1, 0),
			Position = UDim2.new(0, x, 0, 0),
			BackgroundColor3 = Color3.fromRGB(15, 15, 22),
			BorderSizePixel = 0,
		}, meters)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, back)
		local fill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, fill)
		make("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.4,
			TextScaled = true,
			Text = name,
		}, back)
		make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, back:FindFirstChildOfClass("TextLabel"))
		return fill
	end
	shieldFill = meter("SHIELD", Color3.fromRGB(255, 200, 60), 0)
	specialFill = meter("SPECIAL", NEON, 146)

	-- Combo counter.
	comboLabel = make("TextLabel", {
		Name = "Combo",
		Size = UDim2.new(0, 300, 0, 70),
		Position = UDim2.new(0.5, -150, 0.5, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = NEON,
		TextStrokeTransparency = 0.2,
		TextScaled = true,
		Text = "",
		Visible = false,
	}, gui)

	-- Match timer (top-center).
	local topHolder = make("Frame", {
		Name = "Timer",
		Size = UDim2.new(0, 150, 0, 60),
		Position = UDim2.new(0.5, -75, 0, 16),
		BackgroundColor3 = Color3.fromRGB(15, 15, 22),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, topHolder)
	make("UIStroke", { Color = NEON, Thickness = 1.5, Transparency = 0.4 }, topHolder)
	timerLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		Text = "--",
	}, topHolder)
	make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, timerLabel)

	-- Phase banner.
	bannerLabel = make("TextLabel", {
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.new(0, 0, 0.26, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = NEON,
		TextStrokeTransparency = 0.2,
		TextScaled = true,
		Text = "",
		Visible = false,
	}, gui)

	-- Toasts (top-right).
	toastHolder = make("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0, 320, 0, 300),
		Position = UDim2.new(1, -340, 0, 90),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)
end

-- Build one fighter panel into the given column.
local function makePanel(parent: Frame, info: any, isSelf: boolean)
	local panel = make("Frame", {
		Size = UDim2.new(0, isSelf and 280 or 240, 0, isSelf and 110 or 88),
		BackgroundColor3 = Color3.fromRGB(16, 15, 24),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = isSelf and 0 or 1,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
	make("UIStroke", { Color = isSelf and NEON or Color3.fromRGB(255, 90, 90), Thickness = isSelf and 2 or 1.5 }, panel)

	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0, 10, 0, 6),
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.fromRGB(220, 220, 235),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = info.name,
	}, panel)

	local percentLabel = make("TextLabel", {
		Size = UDim2.new(1, -16, 0, isSelf and 54 or 40),
		Position = UDim2.new(0, 10, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = percentColor(info.percent or 0),
		TextStrokeTransparency = 0.3,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = ("%d%%"):format(info.percent or 0),
	}, panel)

	-- Stock icons.
	local stockHolder = make("Frame", {
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 10, 1, -20),
		BackgroundTransparency = 1,
	}, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, stockHolder)

	local function renderStocks(count: number)
		for _, c in stockHolder:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i = 1, MAX_STOCKS do
			local dot = make("Frame", {
				Size = UDim2.new(0, 12, 0, 12),
				BackgroundColor3 = i <= count and (isSelf and NEON or Color3.fromRGB(255, 90, 90)) or Color3.fromRGB(60, 60, 70),
				BorderSizePixel = 0,
			}, stockHolder)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		end
	end
	renderStocks(info.stocks or MAX_STOCKS)

	fighterPanels[info.userId] = {
		percentLabel = percentLabel,
		renderStocks = renderStocks,
	}
end

local function rebuildPanels(fighterData: { any })
	fighterPanels = {}
	for _, c in panelsLeft:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for _, c in panelsRight:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end

	local myTeam
	for _, info in fighterData do
		if info.userId == player.UserId then
			myTeam = info.team
		end
	end

	for _, info in fighterData do
		local isSelf = info.userId == player.UserId
		local isAlly = info.team == myTeam
		makePanel(isAlly and panelsLeft or panelsRight, info, isSelf)
	end
end

-- Updates ------------------------------------------------------------------

local function onStats(data)
	if not gui then
		return
	end
	TweenService:Create(shieldFill, TweenInfo.new(0.15), { Size = UDim2.new(data.stamina / data.maxStamina, 0, 1, 0) }):Play()
	TweenService:Create(specialFill, TweenInfo.new(0.15), { Size = UDim2.new(data.special / data.maxSpecial, 0, 1, 0) }):Play()
	specialFill.BackgroundColor3 = data.special >= data.maxSpecial and Color3.fromRGB(255, 255, 255) or NEON

	-- Live self %.
	local selfPanel = fighterPanels[player.UserId]
	if selfPanel and data.damage then
		selfPanel.percentLabel.Text = ("%d%%"):format(math.floor(data.damage))
		selfPanel.percentLabel.TextColor3 = percentColor(data.damage)
	end

	-- Combo.
	if data.combo and data.combo > 1 then
		comboLabel.Visible = true
		comboLabel.Text = data.combo .. "x COMBO"
		if data.combo ~= lastCombo then
			comboLabel.Size = UDim2.new(0, 360, 0, 84)
			TweenService:Create(comboLabel, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 300, 0, 70),
			}):Play()
		end
	else
		comboLabel.Visible = false
	end
	lastCombo = data.combo or 0
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

function HUDController.isMatchActive(): boolean
	return matchActive
end

local function onMatch(data)
	if not gui then
		return
	end
	matchActive = data.phase ~= "ended"

	if data.fighters then
		-- Only rebuild the panels when the roster actually changes (avoids
		-- per-tick flicker); otherwise just update %/stocks in place.
		local sig = ""
		for _, info in data.fighters do
			sig ..= info.userId .. ","
		end
		if sig ~= builtSignature then
			rebuildPanels(data.fighters)
			builtSignature = sig
		end
		for _, info in data.fighters do
			local panel = fighterPanels[info.userId]
			if panel then
				panel.renderStocks(info.stocks)
				panel.percentLabel.Text = ("%d%%"):format(info.percent or 0)
				panel.percentLabel.TextColor3 = percentColor(info.percent or 0)
			end
		end
	end

	if data.timeLeft then
		local m = math.floor(data.timeLeft / 60)
		local s = data.timeLeft % 60
		timerLabel.Text = ("%d:%02d"):format(m, s)
		timerLabel.TextColor3 = data.timeLeft <= 10 and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 255, 255)
	end

	local phase = data.phase
	if phase == "countdown" then
		flashBanner(data.message or "", Color3.fromRGB(255, 220, 80))
	elseif phase == "go" then
		flashBanner("GO!", Color3.fromRGB(80, 255, 120))
	elseif phase == "ko" and data.message then
		flashBanner(data.message, Color3.fromRGB(255, 130, 40))
	elseif phase == "intro" and data.message then
		flashBanner(data.message, NEON)
	elseif phase == "ended" then
		flashBanner(data.message or "", data.message == "VICTORY" and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 90, 90))
		timerLabel.Text = "--"
		-- Clear the fighter panels so they don't linger in the lobby.
		task.delay(3, function()
			rebuildPanels({})
			builtSignature = ""
		end)
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
	}, toastHolder)
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

	player.CharacterAdded:Connect(function()
		if not player.PlayerGui:FindFirstChild("UAF_HUD") then
			buildHUD()
		end
	end)
end

return HUDController
