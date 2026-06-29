--!strict
--[[
	MenuController
	--------------
	The out-of-combat interface, built from code:
	  * Top bar: level + XP progress + coin balance
	  * FIGHT button -> joins / leaves the matchmaking queue (with live status)
	  * Tabbed panel: SHOP (cosmetics + coin packs), INVENTORY (owned skins),
	    LEADERBOARD (live ranking by level/wins)

	The menu auto-hides when a match is active and reappears in the lobby.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local Progression = require(Shared.Progression)
local GameConfig = require(Shared.GameConfig)

local HUDController = require(script.Parent.HUDController)

local MenuController = {}
local player = Players.LocalPlayer

local FONT = Enum.Font.GothamBold
local NEON = Color3.fromRGB(220, 40, 255)
local DARK = Color3.fromRGB(16, 15, 24)
local PANEL = Color3.fromRGB(24, 22, 34)

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

local function corner(inst: Instance, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
end

local function stroke(inst: Instance, color: Color3, thickness: number?)
	make("UIStroke", { Color = color, Thickness = thickness or 1.5 }, inst)
end

-- State --------------------------------------------------------------------

local gui: ScreenGui
local profile: any = nil
local inQueue = false

local levelLabel: TextLabel
local coinLabel: TextLabel
local xpFill: Frame
local fightButton: TextButton
local queueStatus: TextLabel
local contentArea: Frame
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Shop"

-- Rebuilders for each tab (set in build()).
local renderShop, renderInventory, renderLeaderboard

-- Top bar ------------------------------------------------------------------

local function refreshTopBar()
	if not profile then
		return
	end
	levelLabel.Text = ("LVL %d"):format(profile.level)
	coinLabel.Text = ("%d"):format(profile.coins)
	local resolved = Progression.resolve(profile.xp)
	TweenService:Create(xpFill, TweenInfo.new(0.3), { Size = UDim2.new(resolved.progress, 0, 1, 0) }):Play()
end

-- Generic card builder for cosmetics ---------------------------------------

local function cosmeticCard(parent: Instance, cosmetic: Cosmetics.Cosmetic)
	local owned = profile and profile.cosmetics.owned[cosmetic.id]
	local equipped = profile and profile.cosmetics.equipped == cosmetic.id

	local card = make("Frame", {
		Size = UDim2.new(0, 150, 0, 190),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
	}, parent)
	corner(card, 10)
	stroke(card, equipped and Color3.fromRGB(80, 255, 120) or cosmetic.accent, equipped and 2.5 or 1.2)

	-- Swatch preview.
	local swatch = make("Frame", {
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.new(0, 10, 0, 10),
		BackgroundColor3 = cosmetic.bodyColor,
		BorderSizePixel = 0,
	}, card)
	corner(swatch, 8)
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -10),
		BackgroundColor3 = cosmetic.accent,
		BorderSizePixel = 0,
	}, swatch)

	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0, 8, 0, 86),
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = cosmetic.name,
	}, card)

	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.new(0, 8, 0, 108),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = cosmetic.accent,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = cosmetic.rarity,
	}, card)

	-- Action button.
	local btn = make("TextButton", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.new(0, 10, 1, -50),
		BackgroundColor3 = NEON,
		BorderSizePixel = 0,
		Font = FONT,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		AutoButtonColor = true,
		Text = "",
	}, card)
	corner(btn, 8)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, btn)

	local function setButtonState()
		if equipped then
			btn.Text = "EQUIPPED"
			btn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
		elseif owned then
			btn.Text = "EQUIP"
			btn.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
		elseif cosmetic.unlock == "coins" then
			btn.Text = ("BUY  %d"):format(cosmetic.price or 0)
			btn.BackgroundColor3 = NEON
		elseif cosmetic.unlock == "level" then
			btn.Text = ("LVL %d"):format(cosmetic.level or 0)
			btn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
		elseif cosmetic.unlock == "gamepass" then
			btn.Text = "GAMEPASS"
			btn.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
		end
	end
	setButtonState()

	btn.Activated:Connect(function()
		if equipped then
			return
		elseif owned then
			Remotes.get("EquipCosmetic"):FireServer(cosmetic.id)
		elseif cosmetic.unlock == "coins" then
			local result = (Remotes.get("PurchaseCosmetic") :: RemoteFunction):InvokeServer(cosmetic.id)
			if result and not result.ok then
				HUDController.showToast("Can't buy: " .. tostring(result.reason), Color3.fromRGB(255, 110, 110))
			end
		elseif cosmetic.unlock == "gamepass" then
			Remotes.get("PromptPurchase"):FireServer({ kind = "gamepass", key = "SkinPack" })
		end
	end)

	return card
end

-- Tab content --------------------------------------------------------------

local function clearContent()
	for _, child in contentArea:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function scrollGrid(): ScrollingFrame
	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, contentArea)
	make("UIGridLayout", {
		CellSize = UDim2.new(0, 150, 0, 190),
		CellPadding = UDim2.new(0, 12, 0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 10) }, scroll)
	return scroll
end

renderShop = function()
	clearContent()
	local scroll = scrollGrid()
	-- Coin packs first as banner buttons.
	local packs = {
		{ key = "Coins500", label = "500 Coins", color = Color3.fromRGB(120, 200, 255) },
		{ key = "Coins1200", label = "1,200 Coins", color = Color3.fromRGB(180, 140, 255) },
		{ key = "Coins3000", label = "3,000 Coins", color = Color3.fromRGB(255, 200, 60) },
	}
	for _, pack in packs do
		local card = make("Frame", { BackgroundColor3 = PANEL, BorderSizePixel = 0 }, scroll)
		corner(card, 10)
		stroke(card, pack.color, 1.5)
		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 90),
			Position = UDim2.new(0, 8, 0, 10),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextColor3 = pack.color,
			TextScaled = true,
			Text = "💰",
		}, card)
		make("TextLabel", {
			Size = UDim2.new(1, -16, 0, 24),
			Position = UDim2.new(0, 8, 0, 104),
			BackgroundTransparency = 1,
			Font = FONT,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			Text = pack.label,
		}, card)
		local btn = make("TextButton", {
			Size = UDim2.new(1, -20, 0, 40),
			Position = UDim2.new(0, 10, 1, -50),
			BackgroundColor3 = pack.color,
			BorderSizePixel = 0,
			Font = FONT,
			TextColor3 = Color3.fromRGB(20, 20, 20),
			TextScaled = true,
			Text = "BUY (Robux)",
		}, card)
		corner(btn, 8)
		make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, btn)
		btn.Activated:Connect(function()
			Remotes.get("PromptPurchase"):FireServer({ kind = "product", key = pack.key })
		end)
	end
	-- Then cosmetics for sale / locked.
	for _, cosmetic in Cosmetics.List do
		cosmeticCard(scroll, cosmetic)
	end
end

renderInventory = function()
	clearContent()
	local scroll = scrollGrid()
	for _, cosmetic in Cosmetics.List do
		if profile and profile.cosmetics.owned[cosmetic.id] then
			cosmeticCard(scroll, cosmetic)
		end
	end
end

renderLeaderboard = function()
	clearContent()
	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	}, contentArea)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, scroll)

	-- Gather + sort by level then wins from live leaderstats.
	local rows = {}
	for _, p in Players:GetPlayers() do
		local ls = p:FindFirstChild("leaderstats")
		local level = ls and ls:FindFirstChild("Level") and (ls.Level :: IntValue).Value or 0
		local wins = ls and ls:FindFirstChild("Wins") and (ls.Wins :: IntValue).Value or 0
		table.insert(rows, { name = p.DisplayName, level = level, wins = wins, isYou = p == player })
	end
	table.sort(rows, function(a, b)
		if a.level == b.level then
			return a.wins > b.wins
		end
		return a.level > b.level
	end)

	for i, row in rows do
		local entry = make("Frame", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = row.isYou and Color3.fromRGB(45, 30, 60) or PANEL,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, scroll)
		corner(entry, 8)
		if row.isYou then
			stroke(entry, NEON, 1.5)
		end
		make("TextLabel", {
			Size = UDim2.new(0, 40, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextColor3 = i <= 3 and Color3.fromRGB(255, 215, 60) or Color3.fromRGB(200, 200, 220),
			TextScaled = true,
			Text = "#" .. i,
		}, entry)
		make("TextLabel", {
			Size = UDim2.new(1, -200, 1, 0),
			Position = UDim2.new(0, 56, 0, 0),
			BackgroundTransparency = 1,
			Font = FONT,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = row.name,
		}, entry)
		make("TextLabel", {
			Size = UDim2.new(0, 130, 1, 0),
			Position = UDim2.new(1, -138, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextColor3 = Color3.fromRGB(200, 200, 220),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = ("Lv %d  •  %d W"):format(row.level, row.wins),
		}, entry)
		make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, entry)
	end

	if #rows == 0 then
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Font = FONT,
			TextColor3 = Color3.fromRGB(160, 160, 180),
			TextScaled = true,
			Text = "No fighters yet — be the first!",
		}, scroll)
	end
end

local function selectTab(name: string)
	currentTab = name
	for tabName, button in tabButtons do
		button.BackgroundColor3 = tabName == name and NEON or Color3.fromRGB(40, 38, 52)
	end
	if name == "Shop" then
		renderShop()
	elseif name == "Inventory" then
		renderInventory()
	else
		renderLeaderboard()
	end
end

-- Queue button -------------------------------------------------------------

local function setQueueVisual()
	if inQueue then
		fightButton.Text = "LEAVE QUEUE"
		fightButton.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
	else
		fightButton.Text = "FIGHT"
		fightButton.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
		queueStatus.Text = ""
	end
end

-- Build the whole menu -----------------------------------------------------

local function build()
	gui = make("ScreenGui", {
		Name = "UAF_Menu",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	}, player:WaitForChild("PlayerGui"))

	-- Top bar.
	local top = make("Frame", {
		Size = UDim2.new(0, 360, 0, 60),
		Position = UDim2.new(0, 24, 0, 20),
		BackgroundColor3 = DARK,
		BorderSizePixel = 0,
	}, gui)
	corner(top, 12)
	stroke(top, NEON, 1.5)

	levelLabel = make("TextLabel", {
		Size = UDim2.new(0, 90, 0, 30),
		Position = UDim2.new(0, 12, 0, 6),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = NEON,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "LVL 1",
	}, top)

	local xpBack = make("Frame", {
		Size = UDim2.new(0, 230, 0, 12),
		Position = UDim2.new(0, 14, 1, -18),
		BackgroundColor3 = Color3.fromRGB(10, 10, 16),
		BorderSizePixel = 0,
	}, top)
	corner(xpBack, 6)
	xpFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = NEON,
		BorderSizePixel = 0,
	}, xpBack)
	corner(xpFill, 6)

	coinLabel = make("TextLabel", {
		Size = UDim2.new(0, 110, 0, 30),
		Position = UDim2.new(1, -120, 0, 6),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 215, 60),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0",
	}, top)
	make("TextLabel", {
		Size = UDim2.new(0, 80, 0, 14),
		Position = UDim2.new(1, -120, 1, -20),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(180, 160, 90),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "FIGHT COINS",
	}, top)

	-- FIGHT button (bottom-center).
	fightButton = make("TextButton", {
		Size = UDim2.new(0, 220, 0, 64),
		Position = UDim2.new(0.5, -110, 1, -90),
		BackgroundColor3 = Color3.fromRGB(80, 200, 120),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		Text = "FIGHT",
	}, gui)
	corner(fightButton, 14)
	stroke(fightButton, Color3.fromRGB(0, 0, 0), 2)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }, fightButton)

	queueStatus = make("TextLabel", {
		Size = UDim2.new(0, 360, 0, 26),
		Position = UDim2.new(0.5, -180, 1, -120),
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		TextScaled = true,
		Text = "",
	}, gui)

	fightButton.Activated:Connect(function()
		if inQueue then
			Remotes.get("LeaveQueue"):FireServer()
		else
			Remotes.get("JoinQueue"):FireServer()
		end
	end)

	-- Side panel with tabs.
	local panel = make("Frame", {
		Name = "Panel",
		Size = UDim2.new(0, 540, 0, 420),
		Position = UDim2.new(0, 24, 0.5, -180),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, gui)
	corner(panel, 14)
	stroke(panel, NEON, 1.5)

	local tabBar = make("Frame", {
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0, 10, 0, 10),
		BackgroundTransparency = 1,
	}, panel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, tabBar)

	for _, name in { "Shop", "Inventory", "Leaderboard" } do
		local b = make("TextButton", {
			Size = UDim2.new(0, 160, 1, 0),
			BackgroundColor3 = Color3.fromRGB(40, 38, 52),
			BorderSizePixel = 0,
			Font = FONT,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			Text = name,
		}, tabBar)
		corner(b, 8)
		make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, b)
		tabButtons[name] = b
		b.Activated:Connect(function()
			selectTab(name)
		end)
	end

	contentArea = make("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -20, 1, -70),
		Position = UDim2.new(0, 10, 0, 62),
		BackgroundTransparency = 1,
	}, panel)

	selectTab("Shop")
end

-- Visibility: hide menu during a match, show it in the lobby.
local function setMenuVisible(visible: boolean)
	if not gui then
		return
	end
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			child.Visible = visible
		end
	end
end

function MenuController.start()
	build()

	-- Profile snapshot (initial pull + live updates).
	local function applyProfile(data)
		if data then
			profile = data
			refreshTopBar()
			-- Re-render the active tab so owned/equipped states refresh.
			if currentTab == "Shop" then
				renderShop()
			elseif currentTab == "Inventory" then
				renderInventory()
			end
		end
	end

	Remotes.get("ProfileChanged").OnClientEvent:Connect(applyProfile)
	task.spawn(function()
		local initial = (Remotes.get("RequestProfile") :: RemoteFunction):InvokeServer()
		applyProfile(initial)
	end)

	-- Queue state.
	Remotes.get("QueueStateChanged").OnClientEvent:Connect(function(data)
		inQueue = data.inQueue == true
		setQueueVisual()
		if data.matched then
			queueStatus.Text = ("Match found! Starting in %d..."):format(data.countdown or 0)
		elseif data.inQueue then
			queueStatus.Text = ("In queue  (%d/%d)"):format(data.queueSize or 1, data.needed or 2)
		end
	end)

	-- Hide the lobby menu while fighting.
	Remotes.get("MatchStateChanged").OnClientEvent:Connect(function(data)
		if data.phase == "ended" then
			task.delay(3, function()
				setMenuVisible(true)
				-- Refresh leaderboard ranking after a match.
				if currentTab == "Leaderboard" then
					renderLeaderboard()
				end
			end)
		elseif data.phase == "intro" or data.phase == "countdown" then
			inQueue = false
			setQueueVisual()
			setMenuVisible(false)
		end
	end)
end

return MenuController
