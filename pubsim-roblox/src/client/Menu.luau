-- The menu: upgrades, staff (rota, raises, morale, new applicants), stock, prices, the ledger,
-- live music bookings and settings. Everyone can look; only the landlord can change things.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local Ui = require(script.Parent.Ui)

local Menu = {}

local player = Players.LocalPlayer
local Ask = Remotes:WaitForChild("Ask")
local Act = Remotes:WaitForChild("Act")

local gui, panel, content, tabRow, titleLabel
local current = "upgrades"
local confirmLetGo = nil
local bookDay = nil
local TABS = { { "upgrades", "Upgrades" }, { "staff", "Staff" }, { "stock", "Stock" }, { "prices", "Prices" },
	{ "ledger", "Ledger" }, { "music", "Live music" }, { "settings", "Settings" } }
local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local ROLE = { bartender = "Bar staff", collector = "Glass collector" }

local function card(green)
	local f = Ui.panel(content, UDim2.new(1, -8, 0, 0), nil, if green then 0.15 else 0.35)
	if green then
		f.BackgroundColor3 = Color3.fromRGB(16, 44, 28)
	end
	f.AutomaticSize = Enum.AutomaticSize.Y
	Ui.pad(f, 14, 10)
	Ui.list(f, 6)
	return f
end

local function row(parent)
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, 0)
	r.AutomaticSize = Enum.AutomaticSize.Y
	local l = Ui.list(r, 8, true)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Wraps = true
	r.Parent = parent
	return r
end

local function text(parent, t, size, color, font)
	return Ui.label(parent, t, size or 17, color or Ui.CREAM, font)
end

local function skillText(k)
	local n = math.clamp(math.floor(k * 5 + 0.5), 1, 5)
	return string.format("Skill %d/5 (%s)", n, ({ "green", "learning", "capable", "good", "a natural" })[n])
end

local function act(...)
	Act:FireServer(...)
	task.delay(0.25, function()
		Menu.show(current, true)
	end)
end

local render = {}

render.upgrades = function(d)
	local byCat = {}
	local order = {}
	for _, u in d.items do
		if not byCat[u.category] then
			byCat[u.category] = {}
			table.insert(order, u.category)
		end
		table.insert(byCat[u.category], u)
	end
	text(content, string.format("Cash %s  ·  Reputation %d (%s)", Ui.money(d.cash), math.floor(d.rep), d.tier), 18, Ui.GOLD, Enum.Font.GothamBold)
	for _, cat in order do
		text(content, cat, 22, Ui.GOLD, Enum.Font.GothamBold)
		for _, u in byCat[cat] do
			local c = card(u.owned)
			local r = row(c)
			local info = Instance.new("Frame")
			info.BackgroundTransparency = 1
			info.Size = UDim2.new(1, -170, 0, 0)
			info.AutomaticSize = Enum.AutomaticSize.Y
			Ui.list(info, 3)
			info.Parent = r
			text(info, u.name, 19, Ui.GOLD, Enum.Font.GothamBold)
			text(info, u.desc, 15, Ui.MUTED)
			if u.owned then
				text(r, "Owned", 17, Ui.GOOD, Enum.Font.GothamBold).Size = UDim2.fromOffset(150, 30)
			else
				local b = Ui.button(r, string.format("Buy €%d", u.cost), function()
					act("buy", u.id)
				end, if u.block == "" then "accent" else nil, UDim2.fromOffset(150, 44))
				b.Active = u.block == "" and d.landlord
				b.AutoButtonColor = b.Active
				if u.block ~= "" then
					b.Text = u.block
					b.TextSize = 14
				end
			end
		end
	end
end

render.staff = function(d)
	text(content, string.format("Cash %s  ·  Tonight's wages €%d (paid at closing)", Ui.money(d.cash), math.floor(d.wages)), 18, Ui.GOLD, Enum.Font.GothamBold)
	text(content, "Staff are paid only for the nights they're on the rota. They learn on the job and ask for more as they get better. Keep them happy with nights off and fair pay, or they'll walk. Bar staff pick up orders left waiting.", 15, Ui.MUTED)
	local fc = card(false)
	text(fc, "The week ahead", 18, Ui.GOLD, Enum.Font.GothamBold)
	local fr = row(fc)
	for k = 0, 6 do
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Size = UDim2.fromOffset(78, 40)
		Ui.list(col, 0)
		col.Parent = fr
		local dl = text(col, if k == 0 then "Tonight" else DAYS[(d.weekday + k) % 7 + 1], 14, if k == 0 then Ui.GOLD else Ui.CREAM, Enum.Font.GothamBold)
		dl.TextXAlignment = Enum.TextXAlignment.Center
		local w = d.forecast[k + 1]
		local wl = text(col, w, 13, ({ Quiet = Ui.MUTED, Steady = Ui.CREAM, Busy = Color3.fromRGB(255, 205, 115), Packed = Ui.RED })[w])
		wl.TextXAlignment = Enum.TextXAlignment.Center
	end
	if #d.staff > 0 then
		text(content, "On the payroll", 22, Ui.GOLD, Enum.Font.GothamBold)
	end
	for _, e in d.staff do
		local c = card(true)
		local first = string.split(e.name, " ")[1]
		local tr = d.traits[e.trait]
		text(c, string.format("%s  [%s]%s", e.name, ROLE[e.role] or e.role, if tr then "  ·  " .. tr.name else ""), 19, Ui.GOLD, Enum.Font.GothamBold)
		local cap = math.clamp(math.floor(e.potential * 5 + 0.5), 1, 5)
		local lvl = math.clamp(math.floor(e.skill * 5 + 0.5), 1, 5)
		text(c, string.format("%s%s  ·  €%d a night  ·  %s", skillText(e.skill), if cap > lvl then string.format("  (could reach %d/5)", cap) else "  (at their best)", math.floor(e.wage), e.moraleWord), 16,
			Ui.RED:Lerp(Ui.GOOD, math.clamp(e.morale, 0, 1)))
		text(c, string.format("Since day %d · %d nights · %d served · %d glasses washed%s", e.hiredDay or 1, e.totals.nights or 0, e.totals.served or 0, e.totals.glasses or 0, if tr then "  ·  " .. tr.desc else ""), 14, Ui.MUTED)
		if (e.raiseAsk or 0) > 0 then
			local r = row(c)
			text(r, string.format("%s asks for a raise to €%d a night.", first, math.floor(e.raiseAsk)), 16, Color3.fromRGB(255, 215, 130)).Size = UDim2.new(1, -290, 0, 0)
			Ui.button(r, "Agree", function()
				act("raise", e.id, true)
			end, "accent", UDim2.fromOffset(130, 42))
			Ui.button(r, "Not now", function()
				act("raise", e.id, false)
			end, nil, UDim2.fromOffset(130, 42))
		end
		if (e.notice or 0) > 0 or e.morale < 0.3 then
			local r = row(c)
			local msg = if (e.notice or 0) > 0 then string.format("%s has handed in their notice: %d more night%s.", first, e.notice, if e.notice == 1 then "" else "s") else first .. " is fed up. A night off or a raise would help."
			text(r, msg, 16, Ui.RED).Size = UDim2.new(1, -260, 0, 0)
			Ui.button(r, string.format("A word and a bonus (€%d)", math.floor(e.bonus)), function()
				act("bonus", e.id)
			end, nil, UDim2.fromOffset(250, 42))
		end
		local rr = row(c)
		text(rr, "Works", 15, Ui.CREAM).Size = UDim2.fromOffset(56, 24)
		for k = 0, 6 do
			local wd = (d.weekday + k) % 7
			local on = e.rota[wd + 1]
			local b = Ui.button(rr, (if k == 0 then "Tonight" else DAYS[wd + 1]) .. (if on then "" else " off"), function()
				act("rota", e.id, wd, not on)
			end, if on then "accent" else nil, UDim2.fromOffset(if k == 0 then 86 else 66, 38))
			b.TextSize = 14
			b.Active = d.landlord and not (k == 0 and d.phase ~= "prep")
		end
		local sure = confirmLetGo == e.id
		local lb = Ui.button(c, if sure then string.format("Sure? Pays €%d notice", math.floor(e.wage)) else "Let go", function()
			if confirmLetGo == e.id then
				confirmLetGo = nil
				act("fire", e.id)
			else
				confirmLetGo = e.id
				Menu.show("staff", true)
			end
		end, if sure then "danger" else nil, UDim2.fromOffset(if sure then 230 else 120, 40))
		lb.Active = d.landlord
	end
	if #d.seekers > 0 then
		text(content, "Looking for work", 22, Ui.GOLD, Enum.Font.GothamBold)
		text(content, "New faces answer the card in the window every Monday.", 14, Ui.MUTED)
	end
	for _, s in d.seekers do
		local c = card(false)
		local tr = d.traits[s.trait]
		local r = row(c)
		local info = Instance.new("Frame")
		info.BackgroundTransparency = 1
		info.Size = UDim2.new(1, -170, 0, 0)
		info.AutomaticSize = Enum.AutomaticSize.Y
		Ui.list(info, 3)
		info.Parent = r
		text(info, string.format("%s  [%s]%s%s", s.name, ROLE[s.role] or s.role, if tr then "  ·  " .. tr.name else "", if s.applicant then "  ·  new this week" else ""), 18, Ui.GOLD, Enum.Font.GothamBold)
		local cap = math.clamp(math.floor(s.potential * 5 + 0.5), 1, 5)
		text(info, string.format("%s%s  ·  €%d a night  ·  €%d agency fee", skillText(s.skill), if cap > math.clamp(math.floor(s.skill * 5 + 0.5), 1, 5) then string.format("  (could reach %d/5)", cap) else "", math.floor(s.wage), math.floor(s.fee)), 15, Color3.fromRGB(160, 230, 170))
		text(info, s.blurb .. (if tr then "  " .. tr.name .. ": " .. tr.desc .. "." else ""), 14, Ui.MUTED)
		if s.block ~= "" then
			text(info, s.block, 14, Ui.RED)
		end
		local b = Ui.button(r, "Hire", function()
			act("hire", s.id)
		end, if s.block == "" then "accent" else nil, UDim2.fromOffset(150, 46))
		b.Active = s.block == "" and d.landlord
	end
end

render.stock = function(d)
	text(content, string.format("Cash %s  ·  Deliveries arrive tomorrow morning (€%d per order). Change empty or stale kegs in the cellar.", Ui.money(d.cash), math.floor(d.fee)), 16, Ui.GOLD)
	for _, it in d.items do
		local c = card(false)
		text(c, it.name, 19, Ui.GOLD, Enum.Font.GothamBold)
		text(c, string.format("On tap: %d serves (%d%% fresh)  ·  Spare: %d %s  ·  Arriving: %d", math.floor(it.left), math.floor(it.fresh * 100), it.spare, it.unit, it.arriving), 16)
		if it.stale then
			text(c, "Gone stale: customers can taste it. " .. (if it.spare > 0 then "Swap it for the spare in the cellar." else "Order a fresh one, then swap it in the cellar."), 15, Ui.RED)
		end
		local r = row(c)
		for _, n in { 1, 3 } do
			local cost = it.cost * n + d.fee
			local b = Ui.button(r, if n == 1 and d.emergency and d.cash < cost then string.format("On the slate (€%d)", cost) else string.format("Order %d (€%d)", n, cost), function()
				act("order", it.id, n)
			end, nil, UDim2.fromOffset(190, 42))
			b.Active = d.landlord
		end
	end
end

render.prices = function(d)
	text(content, "Charge too much and people walk out; too little and you're giving it away.", 16, Ui.MUTED)
	for _, it in d.items do
		local c = card(false)
		local r = row(c)
		text(r, string.format("%s  ·  %s (usual %s)", it.name, Ui.money(it.price), Ui.money(it.base)), 17).Size = UDim2.new(1, -230, 0, 0)
		for _, step in { -0.1, 0.1 } do
			local b = Ui.button(r, if step < 0 then "−10c" else "+10c", function()
				act("price", it.id, it.price + step)
			end, nil, UDim2.fromOffset(100, 42))
			b.Active = d.landlord
		end
	end
end

render.ledger = function(d)
	local t = d.today
	local c = card(false)
	text(c, "Today so far", 19, Ui.GOLD, Enum.Font.GothamBold)
	for _, line in { { "Sales", t.sales }, { "Tips", t.tips }, { "Prizes", t.prizes }, { "Stock", -t.stock_spend },
		{ "Upgrades", -t.upgrade_spend }, { "Wages", -t.wages }, { "Live music", -t.event_fees } } do
		text(c, string.format("%s   %s", line[1], Ui.money(line[2])), 16, if line[2] >= 0 then Ui.GOOD else Ui.RED)
	end
	text(c, string.format("Served %d · Walk-outs %d · Wasted %.1f serves", t.served, t.walkouts, t.wasted_units), 15, Ui.MUTED)
	if #d.history > 0 then
		local h = card(false)
		text(h, "Recent days", 19, Ui.GOLD, Enum.Font.GothamBold)
		for i = #d.history, 1, -1 do
			local x = d.history[i]
			text(h, string.format("Day %d   sales %s   tips %s   profit %s   served %d", x.day, Ui.money(x.sales), Ui.money(x.tips), Ui.money(x.profit), x.served), 15, if x.profit >= 0 then Ui.CREAM else Ui.RED)
		end
	end
	local s = d.stats
	text(content, string.format("All time: %d served, %d perfect pints, best pour %d, %d kegs changed, %d glasses washed.", s.served, s.perfectPints, s.bestPour, s.kegsChanged, s.glassesWashed), 15, Ui.MUTED)
end

render.music = function(d)
	text(content, "Book a live act for a night this week. They play from eight; the fee is paid now.", 16, Ui.MUTED)
	local r = row(content)
	bookDay = bookDay or (d.bookings[1] and d.bookings[1].day)
	for _, b in d.bookings do
		local btn = Ui.button(r, string.sub(b.weekday, 1, 3) .. (if b.event then " ♪" else ""), function()
			bookDay = b.day
			Menu.show("music", true)
		end, if bookDay == b.day then "accent" else nil, UDim2.fromOffset(76, 38))
		btn.TextSize = 14
	end
	for _, b in d.bookings do
		if b.day == bookDay and b.event then
			text(content, "Already booked that night.", 15, Ui.GOOD)
		end
	end
	for _, ev in d.events do
		local c = card(false)
		local rr = row(c)
		local info = Instance.new("Frame")
		info.BackgroundTransparency = 1
		info.Size = UDim2.new(1, -170, 0, 0)
		info.AutomaticSize = Enum.AutomaticSize.Y
		Ui.list(info, 3)
		info.Parent = rr
		text(info, string.format("%s  ·  €%d", ev.name, ev.fee), 18, Ui.GOLD, Enum.Font.GothamBold)
		text(info, ev.kind .. ". " .. ev.desc, 14, Ui.MUTED)
		if ev.requires ~= "" or ev.minRep > 0 then
			text(info, string.format("Needs %s%s", if ev.requires ~= "" then ev.requires .. " " else "", if ev.minRep > 0 then "reputation " .. ev.minRep else ""), 13, Ui.MUTED)
		end
		local btn = Ui.button(rr, "Book", function()
			act("book", bookDay, ev.id)
		end, "accent", UDim2.fromOffset(150, 44))
		btn.Active = d.landlord
	end
end

render.settings = function(d)
	local c = card(false)
	text(c, "Length of a day", 18, Ui.GOLD, Enum.Font.GothamBold)
	local r = row(c)
	for _, m in { 6, 10, 15, 20 } do
		local b = Ui.button(r, string.format("%d min", m), function()
			act("setting", "dayLength", m)
		end, if d.dayLength == m then "accent" else nil, UDim2.fromOffset(100, 42))
		b.Active = d.landlord
	end
	local c2 = card(false)
	text(c2, "How busy it gets", 18, Ui.GOLD, Enum.Font.GothamBold)
	local r2 = row(c2)
	for _, k in { "relaxed", "balanced", "busier" } do
		local b = Ui.button(r2, k:sub(1, 1):upper() .. k:sub(2), function()
			act("setting", "difficulty", k)
		end, if d.difficulty == k then "accent" else nil, UDim2.fromOffset(130, 42))
		b.Active = d.landlord
	end
	local c3 = card(false)
	text(c3, "The pub's name", 18, Ui.GOLD, Enum.Font.GothamBold)
	local r3 = row(c3)
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(300, 42)
	box.Text = d.pubName
	box.TextSize = 17
	box.Font = Enum.Font.GothamMedium
	box.TextColor3 = Ui.CREAM
	box.BackgroundColor3 = Color3.fromRGB(40, 36, 32)
	box.ClearTextOnFocus = false
	Ui.corner(box, 10)
	box.Parent = r3
	local save = Ui.button(r3, "Rename", function()
		act("setting", "pubName", box.Text)
	end, "accent", UDim2.fromOffset(120, 42))
	save.Active = d.landlord
	box.TextEditable = d.landlord
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PubMenu"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	panel = Ui.panel(Ui.root(gui), UDim2.new(0.9, 0, 0.84, 0), UDim2.new(0.05, 0, 0.08, 0), 0.12)
	Ui.pad(panel, 18, 14)
	titleLabel = Ui.label(panel, "", 26, Ui.GOLD, Enum.Font.Garamond)
	titleLabel.Size = UDim2.new(1, -170, 0, 34)
	titleLabel.AutomaticSize = Enum.AutomaticSize.None
	Ui.button(panel, if Ui.gamepad() then "Back to the bar (B)" else "Back to the bar", function()
		Menu.close()
	end, nil, UDim2.fromOffset(160, 40)).Position = UDim2.new(1, -160, 0, 0)
	local tabs = Instance.new("ScrollingFrame")
	tabs.Size = UDim2.new(1, 0, 0, 48)
	tabs.Position = UDim2.fromOffset(0, 44)
	tabs.BackgroundTransparency = 1
	tabs.ScrollBarThickness = 0
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new()
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.Parent = panel
	Ui.list(tabs, 8, true)
	tabRow = tabs
	content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, 0, 1, -100)
	content.Position = UDim2.fromOffset(0, 100)
	content.BackgroundTransparency = 1
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = panel
	Ui.list(content, 8)
	for _, t in TABS do
		local id = t[1]
		Ui.button(tabRow, t[2], function()
			Menu.show(id, false)
		end, nil, UDim2.fromOffset(120, 40)).Name = id
	end
end

function Menu.show(tab, keepScroll)
	if not gui then
		build()
	end
	current = tab or current
	gui.Enabled = true
	for _, b in tabRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == current then Ui.GREEN else Color3.fromRGB(40, 36, 32)
		end
	end
	local y = content.CanvasPosition
	-- on a controller, remember which button was picked so a re-render keeps the place
	local sel = GuiService.SelectedObject
	local selText = if sel and sel:IsDescendantOf(content) and sel:IsA("TextButton") then sel.Text else nil
	local ok, d = pcall(function()
		return Ask:InvokeServer(current)
	end)
	for _, ch in content:GetChildren() do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	titleLabel.Text = if d and not d.landlord then "The pub (you're helping out)" else "Your pub"
	if ok and d and render[current] then
		render[current](d)
	end
	if keepScroll then
		task.defer(function()
			content.CanvasPosition = y
		end)
	else
		content.CanvasPosition = Vector2.zero
	end
	if Ui.gamepad() then
		local pick = tabRow:FindFirstChild(current)
		if selText then
			for _, d2 in content:GetDescendants() do
				if d2:IsA("TextButton") and d2.Text == selText then
					pick = d2
					break
				end
			end
		end
		Ui.select(pick)
	end
end

function Menu.close()
	if gui then
		gui.Enabled = false
		local sel = GuiService.SelectedObject
		if sel and sel:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
	end
	confirmLetGo = nil
end

function Menu.isOpen()
	return gui ~= nil and gui.Enabled
end

return Menu
