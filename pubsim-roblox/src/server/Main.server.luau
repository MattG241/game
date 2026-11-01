-- The Irish Pub Simulator on Roblox: the server runs the pub.
--
-- One pub per server. The first player in is the landlord: it's their pub (saved to their Roblox
-- account) and only they manage it (upgrades, staff, stock, prices, music). Friends who join are
-- helpers: they can pour, serve, collect and wash, and the takings go in the landlord's till.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.Data)
local Layout = require(Shared.Layout)
local PubState = require(Shared.PubState)
local Contents = require(Shared.Contents)
local Dispatcher = require(Shared.Dispatcher)

local Builder = require(script.Parent.PubBuilder)
local Glasses = require(script.Parent.Glasses)
local Customers = require(script.Parent.Customers)
local StaffNpc = require(script.Parent.StaffNpc)
local Music = require(script.Parent.Music)
local Audio = require(script.Parent.Audio)

-- ---------------------------------------------------------------- remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local Push = Instance.new("RemoteEvent")
Push.Name = "Push"
Push.Parent = remotes
local Act = Instance.new("RemoteEvent")
Act.Name = "Act"
Act.Parent = remotes
local Ask = Instance.new("RemoteFunction")
Ask.Name = "Ask"
Ask.Parent = remotes
remotes.Parent = ReplicatedStorage

-- ---------------------------------------------------------------- the look: warm lamplight on a wet night
local function setupLighting()
	Lighting.ClockTime = 20.5
	Lighting.Brightness = 1.2
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.32
	atm.Offset = 0.1
	atm.Color = Color3.fromRGB(170, 160, 150)
	atm.Decay = Color3.fromRGB(90, 80, 70)
	atm.Glare = 0
	atm.Haze = 1.4
	atm.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.02
	cc.Contrast = 0.12
	cc.Saturation = 0.06
	cc.TintColor = Color3.fromRGB(255, 244, 228)
	cc.Parent = Lighting
end
setupLighting()
Audio.setup()

local info = Builder.build(workspace)
local people = Instance.new("Folder")
people.Name = "People"
people.Parent = workspace

local state = PubState.new(Data)
state:newGame("career", "The Crooked Shamrock")
local G = { state = state, info = info, folder = people }
G.dispatcher = Dispatcher.new(state)
Customers.init(G)
StaffNpc.init(G)
Music.init(G)

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("IrishPubSimulator_v1")
end)
local landlord = nil -- the Player whose pub this is
local rackClean = 0
local holding = {} -- player -> {glass = g} or {empties = n, model = m}
local pouring = {} -- player -> {glass, drink, total, spilled, speed}
local settleSlots = {} -- index -> {part, prompt, glass}
local empties = {} -- {glass, pos, prompt part}
local spills = {} -- {part, pos}
local streak = 0
local doorAngle, doorTarget, doorTimer = 0, 0, 0
local signAngle, signTarget = math.pi, math.pi

-- ---------------------------------------------------------------- messages to the players
local function notify(text, kind, player)
	if player then
		Push:FireClient(player, "notify", { text = text, kind = kind or "info" })
	else
		Push:FireAllClients("notify", { text = text, kind = kind or "info" })
	end
end
G.notify = notify

function G.subtitle(name, text)
	Push:FireAllClients("say", { name = name, text = text })
end

local function flushMessages()
	for _, m in state.messages do
		notify(m.text, m.kind)
	end
	table.clear(state.messages)
end

function G.customers()
	return Customers.list
end

function G.staffServing(c)
	return StaffNpc.serving(c)
end

-- the door swings open for whoever's going through, then shuts behind them
function G.doorUse()
	doorTarget = math.rad(80)
	doorTimer = 1.6
	if Audio.has("sfx/door_bell") then
		Audio.play("sfx/door_bell", info.door.PrimaryPart, 0.5)
	end
end

-- ---------------------------------------------------------------- glasses
local function drawRack()
	Glasses.drawRack(info.rack, rackClean)
end

function G.rackClean()
	return rackClean
end

function G.takeGlassFromRack(kind)
	if rackClean <= 0 then
		return nil
	end
	rackClean -= 1
	drawRack()
	return Glasses.make(kind, Data)
end

-- A glass that's done with (a dropped one, or one somebody walked off with) goes back clean.
function G.dropGlass(g)
	if g and g.model then
		g.model:Destroy()
	end
	rackClean += 1
	drawRack()
end

function G.washed(n)
	rackClean += n
	state:bump("washed", n)
	state.stats.glassesWashed += n
	drawRack()
	if Audio.has("sfx/clink") then
		Audio.play("sfx/clink", info.sink, 0.5)
	end
end

local function makeEmptyPrompt(e)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = "Collect the empty"
	p.ObjectText = "Glass"
	p.MaxActivationDistance = 8
	p.RequiresLineOfSight = false
	p.Parent = e.glass.model.PrimaryPart
	p.Triggered:Connect(function(player)
		local h = holding[player]
		if h and h.glass then
			notify("Your hands are full.", "info", player)
			return
		end
		if h and h.empties >= 8 then
			notify("That's as many as you can carry. Wash them at the sink.", "info", player)
			return
		end
		if G.pickUpEmpty(e) then
			holding[player] = { empties = (if h then h.empties else 0) + 1 }
		end
	end)
end

-- An empty left on a table (or the nearest ledge).
function G.leaveEmpty(g, tablePos)
	g.contents:reset()
	g.dirty = 0.8
	local pos = tablePos or (Layout.v(2.0, 1.08, -1.9) + Vector3.new(math.random() * 2, 0, 0))
	Glasses.place(g, CFrame.new(pos + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.6), info.root)
	local e = { glass = g, pos = pos }
	table.insert(empties, e)
	makeEmptyPrompt(e)
end

function G.nearestEmpty(from, worker)
	local best, bd = nil, math.huge
	for _, e in empties do
		if not e.claim or e.claim == worker then
			local d = (e.pos - from).Magnitude
			if d < bd then
				best, bd = e, d
			end
		end
	end
	return best
end

function G.pickUpEmpty(e)
	local i = table.find(empties, e)
	if not i then
		return false
	end
	table.remove(empties, i)
	e.glass.model:Destroy()
	return true
end

-- spills on the bar, from an over-poured glass
local function addSpill(pos)
	local p = Builder.cyl(info.root, math.random(30, 50) / 100, 0.03, pos, Color3.fromRGB(60, 36, 20), Enum.Material.Glass, { Transparency = 0.25, CanCollide = false })
	local s = { part = p, pos = pos }
	table.insert(spills, s)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Wipe the spill"
	pr.HoldDuration = 0.8
	pr.MaxActivationDistance = 8
	pr.RequiresLineOfSight = false
	pr.Parent = p
	pr.Triggered:Connect(function()
		if G.wipeSpill(s) then
			state.stats.spillsCleaned += 1
		end
	end)
end

function G.nearestSpill(worker)
	for _, s in spills do
		if not s.claim or s.claim == worker then
			return s
		end
	end
	return nil
end

function G.wipeSpill(s)
	local i = table.find(spills, s)
	if not i then
		return false
	end
	table.remove(spills, i)
	s.part:Destroy()
	return true
end

-- ---------------------------------------------------------------- serving
local function handOver(player)
	local h = holding[player]
	holding[player] = nil
	return h and h.glass
end

-- Gives a glass to whoever's served: scored, paid, tipped. player is nil when staff serve.
function G.serve(player, c, glass, worker)
	local cont = glass.contents
	if cont:isEmpty() then
		return nil
	end
	if cont.drinkId ~= c.drink then
		Customers.refuse(c, "wrong")
		if player then
			Push:FireClient(player, "result", { refused = true, verdict = "Wrong drink", notes = { c.name .. " asked for " .. (state:drink(c.drink).short or c.drink) } })
		end
		return nil
	end
	local res = cont:evaluate(glass.dirty, state:getMod("beer_quality"), false)
	local q = res.score
	if q < 35 and not worker then
		Customers.refuse(c, if glass.dirty > 0.2 then "dirty" else "poor")
		Push:FireClient(player, "result", { refused = true, verdict = res.verdict, notes = res.notes, score = q })
		return nil
	end
	if player then
		handOver(player)
	end
	local price = state:priceOf(c.drink)
	local base = state:drink(c.drink).price or 5
	local fair = math.clamp(1 - math.max(0, price / base - 1) * 2, 0, 1)
	local waitScore = math.clamp(c.patience / c.patienceMax, 0, 1)
	local sat = math.clamp(q * 0.5 + waitScore * 25 + fair * 10 + state:atmosphere() / 100 * 10 + 5, 0, 100)
	local tipRate = if q >= 90 then 0.22 elseif q >= 75 then 0.12 elseif q >= 60 then 0.05 else 0
	tipRate *= c.tipMult * (1 + state:getMod("tips_mult") + state.liveTips) * (0.6 + waitScore * 0.4) * (0.5 + fair * 0.5)
	if worker then
		local e = state:staffEntry(worker.id)
		if e and e.trait == "charmer" then
			tipRate *= 1.2
		end
	else
		-- a run of good pints gets the bar talking: tips grow with the streak
		streak = if q >= 75 then streak + 1 else 0
		state.today.best_streak = math.max(state.today.best_streak, streak)
		tipRate *= 1 + math.min(streak, 10) * 0.03
		if c.orderTime then
			G.dispatcher:recordService(os.clock() - c.orderTime)
		end
		if streak == 3 or streak == 5 or streak == 10 then
			notify(string.format("On a roll! %d good pints in a row. Tips +%d%%", streak, math.min(streak, 10) * 3), "good")
		end
	end
	local tip = math.floor(price * tipRate * 10 + 0.5) / 10
	state:earn(price, "sales")
	state:earn(tip, "tips")
	local t = state.today
	t.served += 1
	t.satisfaction_sum += sat
	t.quality_sum += q
	t.pours += 1
	state.stats.served += 1
	if q >= 90 then
		state:bump("perfect")
		state.stats.perfectPints += 1
	end
	state.stats.bestPour = math.max(state.stats.bestPour, q)
	if worker then
		t.staff_served += 1
		state:staffNote(worker.id, "served")
		state:staffNote(worker.id, "tips", tip)
		if q < 60 or q >= 92 then
			notify(string.format("%s served %s a %s (%d)", worker.first, c.name, string.lower(res.verdict), q), if q >= 92 then "good" else "info")
		end
	end
	state:checkGoals(false)
	if Audio.has("sfx/till") then
		Audio.play("sfx/till", nil, 0.4)
	end
	if player then
		Push:FireClient(player, "result", { score = q, verdict = res.verdict, notes = res.notes, price = price, tip = tip, customer = c.name })
	end
	Customers.served(c, glass, res)
	return res
end

function G.customerPrompt(player, c)
	if c.helper then
		notify(c.helper.first .. " is looking after " .. c.name .. ".", "info", player)
		return
	end
	if c.state == "wait_order" then
		Customers.takeOrder(c)
	elseif c.state == "wait_drink" then
		local h = holding[player]
		if not h or not h.glass or h.glass.contents:isEmpty() then
			notify(string.format("Pour %s's %s at the tap first.", c.name, state:drink(c.drink).short or c.drink), "info", player)
			return
		end
		if h.glass.contents.serve == "stout" and h.glass.contents.stage == 2 then
			notify("That stout still needs topping up.", "info", player)
			return
		end
		G.serve(player, c, h.glass, nil)
	elseif c.regular then
		Customers.chat(c)
	end
end

-- ---------------------------------------------------------------- the things you can use
local function prompt(parent, action, object, hold, dist)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object or ""
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = dist or 8
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function character(player)
	return player.Character
end

local function holdGlass(player, g)
	holding[player] = { glass = g, empties = 0 }
	Glasses.hold(g, character(player))
end

-- the rack: a clean pint glass (or a tumbler for whiskey and soft drinks)
local rackPint = prompt(info.rack, "Take a pint glass", "Glass rack")
rackPint.Triggered:Connect(function(player)
	if holding[player] then
		notify("Your hands are full.", "info", player)
		return
	end
	local g = G.takeGlassFromRack("pint")
	if not g then
		notify("No clean glasses! Collect the empties and wash them at the sink.", "bad", player)
		return
	end
	holdGlass(player, g)
end)
local rackTumbler = prompt(info.rack, "Take a tumbler", "Glass rack")
rackTumbler.KeyboardKeyCode = Enum.KeyCode.R
rackTumbler.UIOffset = Vector2.new(0, 80)
rackTumbler.Triggered:Connect(function(player)
	if holding[player] then
		notify("Your hands are full.", "info", player)
		return
	end
	local g = G.takeGlassFromRack("tumbler")
	if g then
		holdGlass(player, g)
	else
		notify("No clean glasses! Wash some at the sink.", "bad", player)
	end
end)

-- the sink: wash what you're carrying (or pour away a glass you don't want)
local sinkPrompt = prompt(info.sink, "Wash glasses", "Sink", 1.0)
sinkPrompt.Triggered:Connect(function(player)
	local h = holding[player]
	if not h then
		notify("Bring the empties over to wash them.", "info", player)
		return
	end
	if h.glass then
		if not h.glass.contents:isEmpty() then
			state:wasteUnits(h.glass.contents.drinkId, h.glass.contents:total())
		end
		h.glass.model:Destroy()
		holding[player] = nil
		G.washed(1)
		return
	end
	holding[player] = nil
	G.washed(h.empties)
	notify(string.format("Washed %d glasses.", h.empties), "info", player)
end)

-- the taps: pouring happens on the player's own screen, and the result comes back here
for id, tap in info.taps do
	local p = prompt(tap.prompt, "Pour", state:drink(id).short or id, 0, 7)
	p.Triggered:Connect(function(player)
		if pouring[player] then
			return
		end
		local h = holding[player]
		if not h or not h.glass then
			notify("Take a clean glass from the rack first.", "info", player)
			return
		end
		local d = state:drink(id)
		if (d.glass or "pint") ~= h.glass.kind then
			notify(string.format("%s goes in a %s.", d.short or id, if d.glass == "tumbler" then "tumbler" else "pint glass"), "info", player)
			return
		end
		if state:servesLeft(id) < 0.02 then
			notify(string.format("The %s has run dry! Change it in the cellar.", d.stock_unit or "keg"), "bad", player)
			return
		end
		local hum = character(player) and character(player):FindFirstChildOfClass("Humanoid")
		local g = h.glass
		g.contents.freshness = state:freshness(id)
		pouring[player] = { glass = g, drink = id, total = g.contents:total(), spilled = g.contents.spilled, speed = if hum then hum.WalkSpeed else 16 }
		if hum then
			hum.WalkSpeed = 0
		end
		Push:FireClient(player, "pourStart", { drink = id, name = d.name, short = d.short, serve = d.serve, glass = g.kind,
			color = if d.color then Color3.new(d.color[1], d.color[2], d.color[3]) else nil,
			contents = g.contents:toTable(), nozzle = tap.nozzle, glassPos = tap.glassPos, units = state:servesLeft(id),
			settle = state:econ("settle_seconds", 12), freshSlots = (function()
				for _, s in settleSlots do
					if not s.glass then
						return true
					end
				end
				return false
			end)() })
	end)
end

local function sanitize(t)
	if type(t) ~= "table" then
		return nil
	end
	local c = Contents.fromTable(t)
	for _, k in { "body", "cascade", "foam", "ice", "spilled", "firstPour", "angleSum", "angleVol" } do
		local val = tonumber(c[k]) or 0
		if val ~= val or val == math.huge or val == -math.huge then
			val = 0
		end
		c[k] = math.clamp(val, 0, if k == "angleSum" then 1000 else 3)
	end
	c.headRatio = math.clamp(tonumber(c.headRatio) or 0, 0, 1)
	c.topup = math.clamp(tonumber(c.topup) or -1, -1, 1)
	c.stage = math.clamp(math.floor(tonumber(c.stage) or 0), 0, 3)
	return c
end

local function endPour(player, t, toSettle)
	local p = pouring[player]
	if not p then
		return
	end
	pouring[player] = nil
	local hum = character(player) and character(player):FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = p.speed
	end
	local c = sanitize(t)
	local h = holding[player]
	if not c or not h or h.glass ~= p.glass then
		return
	end
	local drawn = math.max(0, (c:total() + c.spilled) - (p.total + p.spilled))
	local left = state:servesLeft(p.drink)
	drawn = math.min(drawn, left)
	if drawn > 0 then
		state:drawUnits(p.drink, drawn)
	end
	local spilt = c.spilled - p.spilled
	if spilt > 0.005 then
		state:wasteUnits(p.drink, spilt)
		if spilt > 0.02 then
			local tap = info.taps[p.drink]
			addSpill(tap.glassPos + Vector3.new((math.random() - 0.5) * 1.5, 0.03, 0.3))
		end
	end
	state.stats.pintsPoured += 1
	p.glass.contents = c
	-- a stout left on the drip tray to settle
	if toSettle then
		for _, s in settleSlots do
			if not s.glass then
				holding[player] = nil
				s.glass = p.glass
				Glasses.place(p.glass, CFrame.new(s.part.Position + Vector3.new(0, 0.05, 0)), info.root)
				return
			end
		end
		notify("The drip tray's full. Hold onto it.", "info", player)
	end
	Glasses.refreshHeld(p.glass)
end

-- the drip tray: stouts left to settle, picked up again to top up
for i, pos in Layout.SETTLE_SLOTS do
	local part = Builder.part(info.root, Vector3.new(0.8, 0.05, 0.8), pos + Vector3.new(0, 0.03, 0), Builder.C.brass, Enum.Material.DiamondPlate)
	local s = { part = part }
	s.prompt = prompt(part, "Put the glass down to settle", "Drip tray", 0, 7)
	s.prompt.Triggered:Connect(function(player)
		local h = holding[player]
		if s.glass then
			if h then
				notify("Your hands are full.", "info", player)
				return
			end
			holdGlass(player, s.glass)
			s.glass = nil
		elseif h and h.glass then
			s.glass = h.glass
			holding[player] = nil
			Glasses.place(s.glass, CFrame.new(part.Position + Vector3.new(0, 0.05, 0)), info.root)
		end
	end)
	settleSlots[i] = s
end

-- the kegs in the cellar: change an empty or stale one for a spare
for id, keg in info.kegs do
	local p = prompt(keg, "Change keg", state:drink(id).short or id, 1.2, 8)
	p.Triggered:Connect(function(player)
		if not state:drinkAvailable(id) then
			return
		end
		local stale = state:kegStale(id)
		if state:servesLeft(id) >= 6 and not stale then
			notify(string.format("%s: about %d serves left, %d%% fresh.", state:drink(id).short, math.floor(state:servesLeft(id)), math.floor(state:freshness(id) * 100)), "info", player)
			return
		end
		if state:changeKeg(id) then
			notify("Fresh " .. state:drink(id).stock_unit .. " connected" .. (if stale then " (the stale one's poured away)." else "."), "info")
			if Audio.has("sfx/keg") then
				Audio.play("sfx/keg", keg, 0.7)
			end
		else
			notify("No spare " .. state:drink(id).stock_unit .. ". Order one from the Stock menu.", "bad", player)
		end
	end)
	local function refresh()
		local d = state:drink(id)
		local left = state:servesLeft(id)
		if state:kegStale(id) then
			p.ActionText = if (state.stock[id] or 0) > 0 then "Swap the stale keg" else "Stale: order a fresh one"
		elseif left < 6 then
			p.ActionText = if (state.stock[id] or 0) > 0 then "Change the keg" else "Empty: order more"
		else
			p.ActionText = string.format("%d serves left", math.floor(left))
		end
		p.ObjectText = string.format("%s · %d spare", d.short or id, state.stock[id] or 0)
	end
	keg:SetAttribute("Refresh", true)
	task.spawn(function()
		while keg.Parent do
			refresh()
			task.wait(1)
		end
	end)
end

-- the sign on the door: open up, call last orders, and close up at the end of the night
local signPart = Builder.part(info.root, Vector3.new(3, 6, 0.4), Layout.DOOR_POS + Vector3.new(0, 3, -1.6), Builder.C.iron, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
local signPrompt = prompt(signPart, "Open the pub (flip the sign)", "Door sign", 0.5, 10)

local function setSign(open)
	signTarget = if open then 0 else math.pi
end

local function resetDay()
	Customers.clear()
	for _, s in settleSlots do
		if s.glass then
			s.glass.model:Destroy()
			s.glass = nil
		end
	end
	for _, e in table.clone(empties) do
		G.pickUpEmpty(e)
	end
	for _, s in table.clone(spills) do
		G.wipeSpill(s)
	end
	for player, h in holding do
		if h.glass then
			h.glass.model:Destroy()
		end
		holding[player] = nil
	end
	table.clear(pouring)
	rackClean = state:glassesTotal()
	drawRack()
	streak = 0
	setSign(false)
	Builder.applyUpgrades(state)
	StaffNpc.refresh()
	G.dispatcher = Dispatcher.new(state)
	Music.newDay()
	if info.fascia then
		info.fascia.Text = state.pubName
	end
end

local function saveNow()
	if not landlord or not store then
		return
	end
	local key = "pub_" .. landlord.UserId
	local ok, err = pcall(function()
		store:SetAsync(key, state:toSave())
	end)
	if not ok then
		warn("Save failed: " .. tostring(err))
	end
end

local function closeUp()
	local summary = state:endDay()
	flushMessages()
	Push:FireAllClients("summary", summary)
	saveNow()
	resetDay()
end

signPrompt.Triggered:Connect(function(player)
	if state.phase == "prep" then
		state:openPub()
		setSign(true)
		G.doorUse()
		local said = Audio.voice("landlord", "welcome", signPart)
		notify(said or "We're open! Customers will start to arrive.", "good")
	elseif state.phase == "open" then
		state.phase = "last_orders"
		local said = Audio.voice("landlord", "last_orders", signPart)
		notify(said or "Last orders!", "info")
	elseif #Customers.list == 0 then
		closeUp()
	else
		notify(string.format("Waiting for the last customers to leave (%d).", #Customers.list), "info", player)
	end
end)

-- the jukebox
local jukePrompt = prompt(info.jukebox, "Play another song", "Jukebox", 0, 8)
jukePrompt.Triggered:Connect(function()
	Music.nextSong()
end)

-- ---------------------------------------------------------------- landlord, helpers and saving
local function loadPub(player)
	local saved = nil
	if store then
		local ok, res = pcall(function()
			return store:GetAsync("pub_" .. player.UserId)
		end)
		if ok then
			saved = res
		end
	end
	if saved then
		state:fromSave(saved)
	else
		state:newGame("career", player.DisplayName .. "'s Local")
	end
	flushMessages()
	resetDay()
end

local function setRoles()
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Role", if p == landlord then "Landlord" else "Helper")
	end
end

local function playerJoined(player)
	if not landlord then
		landlord = player
		loadPub(player)
	else
		notify(player.DisplayName .. " has come to give " .. landlord.DisplayName .. " a hand behind the bar.", "good")
	end
	setRoles()
	player.CharacterRemoving:Connect(function()
		local h = holding[player]
		if h and h.glass then
			G.dropGlass(h.glass)
		end
		holding[player] = nil
		pouring[player] = nil
	end)
end
Players.PlayerAdded:Connect(playerJoined)
for _, p in Players:GetPlayers() do
	task.spawn(playerJoined, p)
end

Players.PlayerRemoving:Connect(function(player)
	local h = holding[player]
	if h and h.glass then
		G.dropGlass(h.glass)
	end
	holding[player] = nil
	pouring[player] = nil
	if player == landlord then
		saveNow()
		landlord = nil
		local others = Players:GetPlayers()
		for _, p in others do
			if p ~= player then
				landlord = p
				break
			end
		end
		if landlord then
			notify(landlord.DisplayName .. " is the landlord now: it's their pub tonight.", "info")
			loadPub(landlord)
		end
		setRoles()
	end
end)

game:BindToClose(function()
	saveNow()
end)

task.spawn(function()
	while true do
		task.wait(120)
		saveNow()
	end
end)

-- ---------------------------------------------------------------- menus
local function isLandlord(player)
	return player == landlord
end

local function seekerView(c)
	return { id = c.id, name = c.name, role = c.role, skill = c.skill, potential = c.potential or c.skill, trait = c.trait,
		wage = c.wage, fee = c.fee or 0, blurb = c.blurb or "", applicant = c.applicant == true, block = state:hireBlock(c.id),
		minRep = c.min_rep or 0 }
end

Ask.OnServerInvoke = function(player, tab)
	local out = { landlord = isLandlord(player), cash = state.cash, rep = state.reputation, tier = state:repTier(), phase = state.phase }
	if tab == "upgrades" then
		out.items = {}
		for _, u in Data.upgrades do
			table.insert(out.items, { id = u.id, name = u.name, desc = u.desc, cost = u.cost, category = u.category,
				owned = state:hasUpgrade(u.id), block = state:upgradeBlock(u.id) })
		end
	elseif tab == "staff" then
		out.wages = state:wagesToday()
		out.weekday = state:weekday()
		out.forecast = {}
		for k = 0, 6 do
			table.insert(out.forecast, PubState.busyWord(state:busyForecast(k)))
		end
		out.staff = {}
		for _, e in state.staff do
			table.insert(out.staff, { id = e.id, name = e.name, role = e.role, skill = e.skill, potential = e.potential, trait = e.trait,
				wage = e.wage, morale = e.morale, moraleWord = PubState.moraleWord(e.morale), rota = e.rota, raiseAsk = e.raiseAsk,
				notice = e.notice, bonus = state:bonusCost(e.id), totals = e.totals, hiredDay = e.hiredDay })
		end
		out.seekers = {}
		for _, c in state:jobSeekers() do
			table.insert(out.seekers, seekerView(c))
		end
		out.traits = PubState.TRAITS
	elseif tab == "stock" then
		out.items = {}
		for _, d in Data.drinks do
			if state:drinkAvailable(d.id) then
				table.insert(out.items, { id = d.id, name = d.name, unit = d.stock_unit, left = state:servesLeft(d.id),
					fresh = state:freshness(d.id), stale = state:kegStale(d.id), spare = state.stock[d.id] or 0,
					arriving = state:pendingDelivery(d.id), cost = d.stock_cost, units = d.units_per_stock })
			end
		end
		out.fee = state:econ("delivery_fee", 6)
		out.emergency = state:stockEmergency()
	elseif tab == "prices" then
		out.items = {}
		for _, d in Data.drinks do
			if state:drinkAvailable(d.id) then
				table.insert(out.items, { id = d.id, name = d.name, price = state:priceOf(d.id), base = d.price })
			end
		end
	elseif tab == "ledger" then
		out.today = state.today
		out.history = state.history
		out.stats = state.stats
	elseif tab == "music" then
		out.events = {}
		for _, ev in Data.events do
			table.insert(out.events, { id = ev.id, name = ev.name, kind = ev.kind, desc = ev.desc, fee = ev.fee,
				requires = ev.requires or "", minRep = ev.min_rep or 0 })
		end
		out.bookings = {}
		for k = 0, 6 do
			local d = state.day + k
			table.insert(out.bookings, { day = d, weekday = Data.economy.weekday_names[(d + 2) % 7 + 1], event = state.bookings[tostring(d)] })
		end
	elseif tab == "settings" then
		out.dayLength = state.settings.dayLength
		out.difficulty = state.settings.difficulty
		out.pubName = state.pubName
	end
	return out
end

Act.OnServerEvent:Connect(function(player, what, a, b, c)
	if what == "pourEnd" then
		endPour(player, a, b == true)
		return
	end
	if not isLandlord(player) then
		notify("Only the landlord can change that.", "info", player)
		return
	end
	if what == "buy" then
		if state:buyUpgrade(tostring(a)) then
			Builder.applyUpgrades(state)
			if string.sub(tostring(a), 1, 8) == "glasses_" then
				local u = nil
				for _, x in Data.upgrades do
					if x.id == a then
						u = x
					end
				end
				rackClean += if u and u.effects then (u.effects.glasses or 0) else 0
				drawRack()
			end
			local said = Audio.voice("landlord", "upgrade", info.rack)
			if said then
				G.subtitle("Landlord", said)
			end
		end
	elseif what == "hire" then
		if state:hire(tostring(a)) then
			StaffNpc.refresh()
		end
	elseif what == "fire" then
		state:fire(tostring(a))
		StaffNpc.refresh()
	elseif what == "rota" then
		state:setRota(tostring(a), tonumber(b) or 0, c == true)
		StaffNpc.refresh()
	elseif what == "raise" then
		if b == true then
			state:agreeRaise(tostring(a))
		else
			state:refuseRaise(tostring(a))
		end
	elseif what == "bonus" then
		state:giveBonus(tostring(a))
	elseif what == "order" then
		if not state:orderStock(tostring(a), math.clamp(tonumber(b) or 1, 1, 3)) then
			notify("Not enough cash for that order.", "bad", player)
		else
			notify("Ordered for tomorrow morning.", "good", player)
		end
	elseif what == "price" then
		state:setPrice(tostring(a), tonumber(b) or 5)
	elseif what == "book" then
		local why = Music.book(tonumber(a) or state.day, tostring(b))
		notify(if why == "" then "Booked!" else why, if why == "" then "good" else "bad", player)
	elseif what == "setting" then
		if a == "dayLength" then
			state.settings.dayLength = math.clamp(tonumber(b) or 10, 4, 30)
		elseif a == "difficulty" and (b == "relaxed" or b == "balanced" or b == "busier") then
			state.settings.difficulty = b
		elseif a == "pubName" and type(b) == "string" then
			local ok, filtered = pcall(function()
				return game:GetService("TextService"):FilterStringAsync(string.sub(b, 1, 30), player.UserId):GetNonChatStringForBroadcastAsync()
			end)
			if ok and filtered ~= "" then
				state.pubName = filtered
				info.fascia.Text = filtered
			end
		end
	end
	flushMessages()
end)

-- ---------------------------------------------------------------- what to do next (for the HUD)
local function nextStep(player)
	local h = holding[player]
	if state.phase == "prep" then
		for _, id in state:availableDrinks() do
			if Layout.KEG_POS[id] and (state.stock[id] or 0) > 0 and (state:servesLeft(id) < 4 or state:kegStale(id)) then
				return string.format("Change the %s keg in the cellar before opening", state:drink(id).short)
			end
		end
		return "Flip the sign by the front door to open up"
	end
	if (state.phase == "last_orders" or state.phase == "closing") and #Customers.list == 0 then
		return "Everyone's gone home: flip the sign to cash up"
	end
	if h and h.empties > 0 then
		return string.format("Wash the %d empties at the sink", h.empties)
	end
	for _, s in settleSlots do
		if s.glass and s.glass.contents:settledFraction() > 0.97 and not h then
			return "The stout has settled: pick it up and top it up"
		end
	end
	if h and h.glass then
		local cont = h.glass.contents
		if cont:isEmpty() then
			for _, c in Customers.list do
				if c.state == "wait_drink" and not c.helper then
					return string.format("Pour %s's %s at the tap", c.name, state:drink(c.drink).short)
				end
			end
			return "Pour a drink at the tap"
		end
		for _, c in Customers.list do
			if c.state == "wait_drink" and c.drink == cont.drinkId then
				return "Serve " .. c.name
			end
		end
		return "Serve the drink to whoever ordered it"
	end
	for _, c in Customers.list do
		if c.state == "wait_order" and not c.helper then
			return "Take " .. c.name .. "'s order"
		end
	end
	for _, c in Customers.list do
		if c.state == "wait_drink" and not c.helper then
			return "Take a glass from the rack for " .. c.name .. "'s " .. state:drink(c.drink).short
		end
	end
	if rackClean <= 1 and #empties > 0 then
		return "Collect the empties and wash them"
	end
	return ""
end

local function holdingText(player)
	local h = holding[player]
	if not h then
		return ""
	end
	if h.glass then
		local cont = h.glass.contents
		if cont:isEmpty() then
			return if h.glass.kind == "tumbler" then "An empty tumbler" else "An empty pint glass"
		end
		return string.format("%s (%d%% full)", state:drink(cont.drinkId).short or "", math.floor(cont:total() * 100))
	end
	return string.format("%d empties", h.empties)
end

local function snapshot(player)
	local goals = {}
	for _, g in state:dailyGoals() do
		table.insert(goals, { text = g.text, done = g.done, value = state:goalValue(g), target = g.target, kind = g.kind })
	end
	return { cash = state.cash, day = state.day, weekday = state:weekdayName(), clock = state:clockText(), phase = state.phase,
		weather = state.weather, rep = state.reputation, tier = state:repTier(), goals = goals, orders = Customers.waiting(),
		role = if player == landlord then "Landlord" else "Helper", landlordName = if landlord then landlord.DisplayName else "",
		next = nextStep(player), holding = holdingText(player), pubName = state.pubName, rack = rackClean }
end

-- ---------------------------------------------------------------- the clock and the room
local arrivals = 0
local settleSeconds = state:econ("settle_seconds", 12)

RunService.Heartbeat:Connect(function(dt)
	-- the door and its sign
	if doorTimer > 0 then
		doorTimer -= dt
		if doorTimer <= 0 then
			doorTarget = 0
		end
	end
	doorAngle += (doorTarget - doorAngle) * math.min(1, dt * 5)
	signAngle += (signTarget - signAngle) * math.min(1, dt * 3)
	if info.door and info.door.PrimaryPart then
		info.door:PivotTo(info.doorClosed * CFrame.Angles(0, -doorAngle, 0))
		info.signBoard.CFrame = info.door:GetPivot() * info.signRel * CFrame.Angles(0, signAngle, 0)
	end
	-- the fire flickers
	if info.fireLight then
		info.fireLight.Brightness = 2.0 + math.sin(os.clock() * 11) * 0.25 + math.sin(os.clock() * 27) * 0.15
	end
end)

local stepAcc = 0
local pushAcc = 0
while true do
	local dt = task.wait(0.1)
	stepAcc += dt
	pushAcc += dt
	local players = #Players:GetPlayers()
	if landlord then
		-- the clock runs once the doors are open
		if state.phase ~= "prep" then
			state.hour += dt / state:secondsPerGameHour()
			local lastH = state:econ("last_orders_hour", 23.5)
			local closeH = state:econ("close_hour", 24)
			if state.phase == "open" and state.hour >= lastH then
				state.phase = "last_orders"
				local said = Audio.voice("landlord", "last_orders", signPart)
				notify(said or "Last orders!", "info")
			end
			if state.phase == "last_orders" and state.hour >= closeH then
				state.phase = "closing"
				Customers.closing()
				local said = Audio.voice("landlord", "closing", signPart)
				notify(said or "Time, ladies and gentlemen!", "info")
			end
			if state.hour >= closeH + 0.75 then
				for _, c in table.clone(Customers.list) do
					Customers.leave(c, false)
				end
			end
		end
		Lighting.ClockTime = math.clamp(state.hour, 15, 23.9)
		-- new arrivals while the pub's open
		if state.phase == "open" then
			local wmult = Data.economy.weekday_mult[state:weekday() + 1] or 1
			local weather = Data.economy.weather_mult and Data.economy.weather_mult[state.weather] or 1
			local live = if Music.live.playing and Music.live.event then (Music.live.event.draw or 1.2) else 1
			local rate = state:econ("base_arrivals_per_hour", 7) * (1 + state:getMod("arrival_mult")) * wmult * weather * live
			arrivals += rate * dt / state:secondsPerGameHour()
			local target = G.dispatcher:targetPopulation(state.hour, live, 14)
			if arrivals >= 1 then
				arrivals -= 1
				if #Customers.list < target then
					task.spawn(Customers.spawn)
				end
			end
		end
		Customers.tick(dt, players)
		Music.tick(dt)
		-- stouts settle wherever they are: on the drip tray, or in a hand
		for _, s in settleSlots do
			if s.glass then
				s.glass.contents:settle(dt, settleSeconds)
			end
		end
		for _, h in holding do
			if h.glass then
				h.glass.contents:settle(dt, settleSeconds)
			end
		end
		if stepAcc >= 0.5 then
			stepAcc = 0
			for _, s in settleSlots do
				if s.glass then
					Glasses.refresh(s.glass)
					s.prompt.ActionText = string.format("Pick up the stout (%d%% settled)", math.floor(s.glass.contents:settledFraction() * 100))
				else
					s.prompt.ActionText = "Put the glass down to settle"
				end
			end
			for p, h in holding do
				if h.glass and p.Character and h.glass.contents.cascade > 0.001 then
					Glasses.refreshHeld(h.glass)
				end
			end
			-- the sign's prompt says what it does now
			if state.phase == "prep" then
				signPrompt.ActionText = "Open the pub (flip the sign)"
			elseif state.phase == "open" then
				signPrompt.ActionText = "Call last orders"
			elseif #Customers.list == 0 then
				signPrompt.ActionText = "Close up and cash up"
			else
				signPrompt.ActionText = string.format("Waiting for %d customers", #Customers.list)
			end
		end
		flushMessages()
	end
	if pushAcc >= 0.5 then
		pushAcc = 0
		for _, p in Players:GetPlayers() do
			Push:FireClient(p, "state", snapshot(p))
		end
	end
end
