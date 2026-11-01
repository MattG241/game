-- The player's screen: the day at a glance (cash, time, what's next), orders waiting, goals,
-- notices and subtitles, how each pint scored, the end-of-day summary, the menu and the pour.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Push = Remotes:WaitForChild("Push")
local Act = Remotes:WaitForChild("Act")
local Ui = require(script.Parent.Ui)
local Pour = require(script.Parent.Pour)
local Menu = require(script.Parent.Menu)

local player = Players.LocalPlayer
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local screen = Instance.new("ScreenGui")
screen.Name = "PubHud"
screen.ResetOnSpawn = false
screen.Parent = player:WaitForChild("PlayerGui")
local gui = Ui.root(screen) -- scaled to fit phones, tablets, computers and TVs

-- the day at a glance, top centre
local status = Ui.panel(gui, UDim2.fromOffset(330, 0), UDim2.new(0.5, -165, 0, 8), 0.3)
status.AutomaticSize = Enum.AutomaticSize.Y
Ui.pad(status, 14, 8)
Ui.list(status, 2)
local cashLabel = Ui.label(status, "€0.00", 26, Ui.GOLD, Enum.Font.GothamBold)
local dayLabel = Ui.label(status, "", 14, Ui.CREAM)

local nextPill = Ui.panel(gui, UDim2.fromOffset(420, 0), UDim2.new(0.5, -210, 0, 92), 0.3)
nextPill.AutomaticSize = Enum.AutomaticSize.Y
Ui.pad(nextPill, 14, 6)
local nextLabel = Ui.label(nextPill, "", 16, Ui.CREAM)
nextLabel.TextXAlignment = Enum.TextXAlignment.Center

local holdLabel = Ui.label(gui, "", 15, Ui.CREAM, Enum.Font.GothamMedium)
holdLabel.Size = UDim2.fromOffset(360, 22)
holdLabel.AutomaticSize = Enum.AutomaticSize.None
holdLabel.Position = UDim2.new(0.5, -180, 1, -96)
holdLabel.TextXAlignment = Enum.TextXAlignment.Center
holdLabel.TextStrokeTransparency = 0.5

-- the menu button and goals, top right
local function toggleMenu()
	if Menu.isOpen() then
		Menu.close()
	elseif not Pour.active() then
		Menu.show(nil, false)
	end
end
local menuBtn = Ui.button(gui, "Menu", toggleMenu, nil, UDim2.fromOffset(110, 44))
menuBtn.Position = UDim2.new(1, -122, 0, 8)

local goalsBtn
local goalsCard = Ui.panel(gui, UDim2.fromOffset(300, 0), UDim2.new(1, -312, 0, 106), 0.3)
goalsCard.AutomaticSize = Enum.AutomaticSize.Y
goalsCard.Visible = false
Ui.pad(goalsCard, 12, 8)
Ui.list(goalsCard, 4)
goalsBtn = Ui.button(gui, "Goals", function()
	goalsCard.Visible = not goalsCard.Visible
end, nil, UDim2.fromOffset(110, 40))
goalsBtn.Position = UDim2.new(1, -122, 0, 58)

-- orders waiting, down the right
local orders = Instance.new("Frame")
orders.BackgroundTransparency = 1
orders.Size = UDim2.fromOffset(240, 300)
orders.Position = UDim2.new(1, -252, 0, 160)
orders.Parent = gui
Ui.list(orders, 6)

-- notices, under the day panel
local toasts = Instance.new("Frame")
toasts.BackgroundTransparency = 1
toasts.Size = UDim2.fromOffset(440, 200)
toasts.Position = UDim2.new(0.5, -220, 0, 138)
toasts.Parent = gui
Ui.list(toasts, 6)

local KIND = { good = Color3.fromRGB(150, 230, 160), bad = Color3.fromRGB(255, 150, 130), info = Ui.CREAM }

local function toast(text, kind)
	local t = Ui.panel(toasts, UDim2.new(1, 0, 0, 0), nil, 0.25)
	t.AutomaticSize = Enum.AutomaticSize.Y
	Ui.pad(t, 12, 6)
	local l = Ui.label(t, text, 15, KIND[kind] or Ui.CREAM)
	l.TextXAlignment = Enum.TextXAlignment.Center
	while #toasts:GetChildren() > 4 do
		for _, ch in toasts:GetChildren() do
			if ch:IsA("Frame") then
				ch:Destroy()
				break
			end
		end
	end
	task.delay(4.5, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			t:Destroy()
		end
	end)
end

-- subtitles for what people say, bottom centre
local subtitle = Ui.label(gui, "", 17, Ui.CREAM, Enum.Font.GothamMedium)
subtitle.Size = UDim2.new(0.7, 0, 0, 0)
subtitle.Position = UDim2.new(0.15, 0, 1, -150)
subtitle.TextXAlignment = Enum.TextXAlignment.Center
subtitle.TextStrokeTransparency = 0.4
local subToken = 0

-- how the pint went
local result = Ui.panel(gui, UDim2.fromOffset(380, 0), UDim2.new(0.5, -190, 0.3, 0), 0.15)
result.AutomaticSize = Enum.AutomaticSize.Y
result.Visible = false
Ui.pad(result, 16, 12)
Ui.list(result, 4)
local resScore = Ui.label(result, "", 30, Ui.GOLD, Enum.Font.GothamBold)
local resVerdict = Ui.label(result, "", 18, Ui.CREAM, Enum.Font.GothamBold)
local resNotes = Ui.label(result, "", 15, Ui.MUTED)
local resToken = 0

local function showResult(d)
	resToken += 1
	local token = resToken
	if d.refused then
		resScore.Text = if d.score then string.format("%d / 100", d.score) else "Not served"
		resVerdict.Text = (d.verdict or "") .. ": they want it poured again"
		resVerdict.TextColor3 = Ui.RED
	else
		resScore.Text = string.format("%d / 100", d.score)
		resVerdict.Text = string.format("%s  ·  %s + %s tip", d.verdict, Ui.money(d.price or 0), Ui.money(d.tip or 0))
		resVerdict.TextColor3 = if d.score >= 85 then Ui.GOOD elseif d.score >= 60 then Ui.CREAM else Ui.RED
	end
	resNotes.Text = table.concat(d.notes or {}, "\n")
	result.Visible = true
	task.delay(4.5, function()
		if resToken == token then
			result.Visible = false
		end
	end)
end

-- the end-of-day summary
local function showSummary(s)
	local sg = Instance.new("ScreenGui")
	sg.Name = "Summary"
	sg.ResetOnSpawn = false
	sg.Parent = player.PlayerGui
	local p = Ui.panel(sg, UDim2.new(0.7, 0, 0.82, 0), UDim2.new(0.15, 0, 0.09, 0), 0.08)
	Ui.pad(p, 20, 16)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -64)
	scroll.BackgroundTransparency = 1
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.Parent = p
	Ui.list(scroll, 6)
	Ui.label(scroll, string.format("Day %d · %s: closing time", s.day, s.weekday), 26, Ui.GOLD, Enum.Font.Garamond)
	for _, line in { { "Sales", s.sales }, { "Tips", s.tips }, { "Prizes", s.prizes }, { "Stock", -s.stock_spend }, { "Upgrades", -s.upgrade_spend },
		{ "Rent", -s.rent }, { "Utilities", -s.utilities }, { "Wages", -s.wages }, { "Live music", -s.event_fees } } do
		if math.abs(line[2]) > 0.001 then
			Ui.label(scroll, string.format("%s   %s", line[1], Ui.money(line[2])), 17, if line[2] >= 0 then Ui.GOOD else Ui.RED)
		end
	end
	Ui.label(scroll, string.format("Profit today: %s", Ui.money(s.profit)), 24, if s.profit >= 0 then Ui.GOOD else Ui.RED, Enum.Font.GothamBold)
	Ui.label(scroll, string.format("Served %d · Walk-outs %d · Avg satisfaction %d%% · Avg quality %d · Best streak %d",
		s.served, s.walkouts, math.floor(s.avgSatisfaction), math.floor(s.avgQuality), s.bestStreak or 0), 16)
	for _, line in s.staffLines or {} do
		Ui.label(scroll, line, 16, Color3.fromRGB(160, 230, 170))
	end
	local met = 0
	for _, g in s.goals or {} do
		if g.done then
			met += 1
		end
	end
	Ui.label(scroll, string.format("Goals met: %d of %d", met, #(s.goals or {})), 18, Ui.GOLD, Enum.Font.GothamBold)
	for _, g in s.goals or {} do
		Ui.label(scroll, (if g.done then "✓ " else "✗ ") .. g.text, 15, if g.done then Ui.GOOD else Ui.MUTED)
	end
	Ui.label(scroll, string.format("Reputation %d (%+.1f): %s · Cash %s", math.floor(s.reputation), s.repChange, s.repTier, Ui.money(s.cash)), 17, Ui.GOLD)
	local b = Ui.button(p, "Start the next day", function()
		sg:Destroy()
	end, "accent", UDim2.fromOffset(240, 50))
	b.Position = UDim2.new(0.5, -120, 1, -52)
	Ui.select(b)
end

local function updateState(s)
	cashLabel.Text = Ui.money(s.cash)
	local phase = ({ prep = "Closed", open = "Open", last_orders = "Last orders", closing = "Closing" })[s.phase] or s.phase
	dayLabel.Text = string.format("%s · Day %d · %s · %s · %s", s.clock, s.day, string.sub(s.weekday, 1, 3), s.weather:sub(1, 1):upper() .. s.weather:sub(2), phase)
	if s.role ~= "Landlord" and s.landlordName ~= "" then
		dayLabel.Text ..= "\nHelping out at " .. s.landlordName .. "'s pub"
	end
	nextLabel.Text = if s.next ~= "" then "NEXT  " .. s.next else ""
	nextPill.Visible = s.next ~= "" and not Pour.active()
	holdLabel.Text = if s.holding ~= "" then "Holding: " .. s.holding else ""
	-- goals
	local done = 0
	for _, ch in goalsCard:GetChildren() do
		if ch:IsA("TextLabel") then
			ch:Destroy()
		end
	end
	Ui.label(goalsCard, "TODAY'S GOALS", 13, Ui.GOLD, Enum.Font.GothamBold)
	for _, g in s.goals do
		if g.done then
			done += 1
		end
		local progress = if g.kind == "count" then string.format("  %d/%d", math.floor(g.value), g.target) else ""
		Ui.label(goalsCard, g.text .. (if g.done then "  ✓" else progress), 15, if g.done then Ui.GOOD else Ui.CREAM)
	end
	goalsBtn.Text = string.format("Goals %d/%d", done, #s.goals) .. (if Ui.gamepad() then "  (↓)" else "")
	-- orders (only when there's more than one to keep track of)
	for _, ch in orders:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	if #s.orders >= 2 then
		for _, o in s.orders do
			local f = Ui.panel(orders, UDim2.new(1, 0, 0, 40), nil, 0.3)
			local l = Ui.label(f, o.name .. (if o.drink then " · " .. o.drink else " · to order"), 15, Ui.CREAM)
			l.Position = UDim2.fromOffset(10, 4)
			l.Size = UDim2.new(1, -20, 0, 18)
			l.AutomaticSize = Enum.AutomaticSize.None
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(o.patience, -20, 0, 5)
			bar.Position = UDim2.new(0, 10, 1, -11)
			bar.BorderSizePixel = 0
			bar.BackgroundColor3 = Ui.RED:Lerp(Ui.GOOD, o.patience)
			Ui.corner(bar, 3)
			bar.Parent = f
		end
	end
end

Push.OnClientEvent:Connect(function(kind, d)
	if kind == "state" then
		updateState(d)
	elseif kind == "notify" then
		toast(d.text, d.kind)
	elseif kind == "say" then
		subToken += 1
		local token = subToken
		subtitle.Text = d.name .. ": " .. d.text
		task.delay(4, function()
			if subToken == token then
				subtitle.Text = ""
			end
		end)
	elseif kind == "pourStart" then
		Menu.close()
		Pour.start(d, function(contents, toSettle)
			Act:FireServer("pourEnd", contents, toSettle)
		end)
	elseif kind == "result" then
		showResult(d)
	elseif kind == "summary" then
		showSummary(d)
	end
end)

-- controllers: Y opens the menu, B closes it, D-pad down shows the goals. Prompts (pour, take
-- an order, flip the sign) already show the right button on every device.
local function refreshHints()
	local pad = Ui.gamepad()
	menuBtn.Text = if pad then "Menu (Y)" else "Menu"
end
UserInputService.LastInputTypeChanged:Connect(refreshHints)
UserInputService.InputBegan:Connect(function(input, processed)
	if Pour.active() then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.ButtonY or (k == Enum.KeyCode.M and not processed) then
		toggleMenu()
	elseif k == Enum.KeyCode.ButtonB and Menu.isOpen() then
		Menu.close()
	elseif k == Enum.KeyCode.DPadDown and GuiService.SelectedObject == nil then
		goalsCard.Visible = not goalsCard.Visible
	end
end)
refreshHints()

toast("Welcome to the pub! Walk to the front door and flip the sign to open up.", "good")
