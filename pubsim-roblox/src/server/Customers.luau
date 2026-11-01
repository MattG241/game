-- The customers: they come in off the street, find a seat or somewhere to stand, chat until the
-- dispatcher calls them up, wait at the bar to order (their patience only runs there), drink, leave
-- their empty on the table, and either order again or go home. Regulars order their usual.

local Shared = game:GetService("ReplicatedStorage").Shared
local Layout = require(Shared.Layout)
local Data = require(Shared.Data)
local Npc = require(script.Parent.Npc)
local Audio = require(script.Parent.Audio)

local Customers = {}

local G -- the game context (set by init)
local list = {}
local seatTaken = {} -- seat index -> customer
local standTaken = {} -- stand spot index -> customer
local barTaken = {} -- bar spot index -> customer
local rng = Random.new()
local lines = Data.customer_lines

Customers.list = list

function Customers.init(context)
	G = context
end

local function pick(t)
	if type(t) ~= "table" or #t == 0 then
		return ""
	end
	return t[rng:NextInteger(1, #t)]
end

local function alive(c)
	return c.alive and c.n and c.n.model and c.n.model.Parent ~= nil
end

function Customers.count()
	return #list
end

function Customers.atBar()
	local n = 0
	for _, c in list do
		if c.state == "wait_order" or c.state == "wait_drink" then
			n += 1
		end
	end
	return n
end

-- Says something: a recorded line when the speaker has one, otherwise the written words.
local function say(c, tag, fallback, seconds, color)
	local text = nil
	if c.voice then
		text = Audio.voice(c.voice, tag, c.n.head)
	end
	text = text or fallback
	if text and text ~= "" then
		Npc.say(c.n, text, seconds or 3.5, color)
		G.subtitle(c.name, text)
	end
end
Customers.say = say

-- What they'll drink: a regular's usual if it's on, otherwise something that is.
local function chooseDrink(c)
	local avail = G.state:availableDrinks()
	if c.regular and table.find(avail, c.regular.drink) then
		return c.regular.drink
	end
	-- stout is the most popular; everything else shares the rest
	if table.find(avail, "stout") and rng:NextNumber() < 0.5 then
		return "stout"
	end
	return avail[rng:NextInteger(1, #avail)]
end

local function refreshPrompt(c)
	local p = c.prompt
	if not p then
		return
	end
	if c.state == "wait_order" then
		p.ActionText = "Take order"
		p.Enabled = true
	elseif c.state == "wait_drink" then
		p.ActionText = "Serve " .. (G.state:drink(c.drink).short or c.drink)
		p.Enabled = true
	elseif c.regular and (c.state == "drinking" or c.state == "mingle") and not c.chatted then
		p.ActionText = "Chat"
		p.Enabled = true
	else
		p.Enabled = false
	end
end
Customers.refreshPrompt = refreshPrompt

local function setBubble(c)
	local tag = if c.regular then c.name else ""
	if c.state == "wait_order" then
		Npc.setTag(c.n, (if tag ~= "" then tag .. "  " else "") .. "!")
	elseif c.state == "wait_drink" then
		Npc.setTag(c.n, (if tag ~= "" then tag .. " · " else "") .. (G.state:drink(c.drink).short or ""))
	else
		Npc.setTag(c.n, tag)
	end
end

local function freeSeat(c)
	local best, bestScore = nil, math.huge
	for i, s in G.info.seats do
		local ok = not seatTaken[i] and (s.upgrade == nil or G.state:hasUpgrade(s.upgrade)) and s.seat.Parent ~= nil
		if ok then
			local score = (s.seat.Position - c.n.root.Position).Magnitude + rng:NextNumber(0, 12)
			if s.kind == "armchair" and G.state:hasUpgrade("fireplace") then
				score -= 10
			end
			if score < bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best
end

local function freeStand()
	local free = {}
	for i = 1, #Layout.STAND_SPOTS do
		if not standTaken[i] then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[rng:NextInteger(1, #free)]
end

local function release(c)
	if c.seat then
		seatTaken[c.seat] = nil
		c.seat = nil
	end
	if c.stand then
		standTaken[c.stand] = nil
		c.stand = nil
	end
	if c.barSpot then
		barTaken[c.barSpot] = nil
		c.barSpot = nil
	end
end

-- Goes and sits (or stands) somewhere to drink or wait.
local function settle(c)
	local s = freeSeat(c)
	if s then
		seatTaken[s] = c
		c.seat = s
		local seat = G.info.seats[s].seat
		Npc.walkTo(c.n, seat.Position + seat.CFrame.LookVector * -2.2, function()
			return alive(c)
		end)
		if alive(c) then
			Npc.sitOn(c.n, seat)
		end
		return
	end
	local st = freeStand()
	if st then
		standTaken[st] = c
		c.stand = st
		Npc.walkTo(c.n, Layout.STAND_SPOTS[st], function()
			return alive(c)
		end)
	end
end

local function leave(c, angry)
	if c.state == "gone" or c.state == "leaving" then
		return
	end
	c.state = "leaving"
	G.dispatcher:remove(c)
	refreshPrompt(c)
	if c.glass then
		G.dropGlass(c.glass)
		c.glass = nil
	end
	release(c)
	Npc.standUp(c.n)
	Npc.setTag(c.n, if c.regular then c.name else "")
	task.spawn(function()
		if not angry and c.served > 0 then
			say(c, "goodbye", pick(lines.leave), 2.5)
		end
		Npc.walkTo(c.n, Layout.INSIDE_DOOR, function()
			return alive(c)
		end)
		G.doorUse()
		Npc.walkTo(c.n, Layout.OUTSIDE_DOOR, function()
			return alive(c)
		end)
		Npc.walkTo(c.n, if rng:NextNumber() < 0.5 then Layout.STREET_L else Layout.STREET_R, function()
			return alive(c)
		end)
		Customers.remove(c)
	end)
end
Customers.leave = leave

function Customers.remove(c)
	c.alive = false
	c.state = "gone"
	release(c)
	G.dispatcher:remove(c)
	local i = table.find(list, c)
	if i then
		table.remove(list, i)
	end
	if c.n and c.n.model then
		c.n.model:Destroy()
	end
end

local function walkOut(c)
	say(c, "complain", pick(lines.angry), 3, Color3.fromRGB(255, 140, 110))
	G.state.today.walkouts += 1
	G.state.stats.walkouts += 1
	G.notify(c.name .. " gave up waiting and left.", "bad")
	leave(c, true)
end

-- The dispatcher sends them up: to a free spot at the bar.
local function goToBar(c)
	local spot = nil
	for i = 1, #G.info.barSpots do
		if not barTaken[i] then
			spot = i
			break
		end
	end
	if not spot then
		G.dispatcher:add(c)
		return
	end
	barTaken[spot] = c
	if c.seat then
		seatTaken[c.seat] = nil
		c.seat = nil
	end
	if c.stand then
		standTaken[c.stand] = nil
		c.stand = nil
	end
	c.barSpot = spot
	c.state = "walking"
	Npc.standUp(c.n)
	task.spawn(function()
		local p = G.info.barSpots[spot]
		Npc.walkTo(c.n, p, function()
			return alive(c)
		end)
		if not alive(c) or c.state ~= "walking" then
			return
		end
		Npc.face(c.n, p + Vector3.new(0, 0, -5))
		c.state = "wait_order"
		c.waitStart = os.clock()
		c.patience = c.patienceMax
		setBubble(c)
		refreshPrompt(c)
		say(c, "wait", "", 0)
	end)
end

function Customers.spawn()
	local regulars = {}
	for _, r in Data.regulars do
		local here = false
		for _, c in list do
			if c.regular == r then
				here = true
			end
		end
		if not here then
			table.insert(regulars, r)
		end
	end
	local regular = if #regulars > 0 and rng:NextNumber() < 0.45 then regulars[rng:NextInteger(1, #regulars)] else nil
	local name = if regular then regular.name else pick(lines.first_names)
	local look = if regular then regular.look else { gender = if rng:NextNumber() < 0.5 then "m" else "f" }
	local from = if rng:NextNumber() < 0.5 then Layout.STREET_L else Layout.STREET_R
	local n = Npc.spawn(name, look, rng, G.folder, CFrame.new(from + Vector3.new(0, 3, 0)))
	if not n then
		return nil
	end
	local voices = { "old_regular", "cheerful_local", "dubliner", "jordan", "andrew", "colleen", "tourist_uk", "tourist_us" }
	local c = { n = n, name = name, regular = regular, voice = if regular then regular.voice else voices[rng:NextInteger(1, #voices)],
		state = "arriving", alive = true, served = 0, budget = rng:NextInteger(1, 3),
		patienceMax = G.dispatcher:patienceFor(if regular then (regular.patience or 1) else 1),
		tipMult = if regular then (regular.tip or 1) else rng:NextNumber(0.8, 1.2) }
	c.patience = c.patienceMax
	table.insert(list, c)
	Npc.setTag(n, if regular then name else "")
	-- one prompt does the job of the moment: take the order, serve, or have a chat
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = name
	prompt.ActionText = "Take order"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = n.root
	c.prompt = prompt
	prompt.Triggered:Connect(function(player)
		G.customerPrompt(player, c)
	end)
	task.spawn(function()
		Npc.walkTo(n, Layout.OUTSIDE_DOOR, function()
			return alive(c)
		end)
		G.doorUse()
		Npc.walkTo(n, Layout.INSIDE_DOOR, function()
			return alive(c)
		end)
		if not alive(c) then
			return
		end
		-- very expensive drinks put people off
		local d = chooseDrink(c)
		local ratio = G.state:priceOf(d) / (G.state:drink(d).price or 5)
		if ratio > 1 + G.state:econ("price_tolerance", 0.18) * 2.5 and rng:NextNumber() < (ratio - 1.3) * 2 then
			say(c, "", pick(lines.too_dear), 3, Color3.fromRGB(255, 180, 110))
			G.state.today.walkouts += 1
			leave(c, true)
			return
		end
		if regular and rng:NextNumber() < 0.6 and regular.greet then
			say(c, "", pick(regular.greet), 3.5)
		end
		settle(c)
		if alive(c) and c.state == "arriving" then
			c.state = "mingle"
			refreshPrompt(c)
			G.dispatcher:add(c)
		end
	end)
	return c
end

-- The player (or a member of staff) takes their order.
function Customers.takeOrder(c)
	if c.state ~= "wait_order" then
		return false
	end
	c.drink = chooseDrink(c)
	c.state = "wait_drink"
	c.orderTime = os.clock()
	local d = G.state:drink(c.drink)
	local words = pick(lines.order and lines.order[c.drink] or {})
	if words == "" then
		words = "A " .. (d.short or c.drink) .. ", please."
	end
	say(c, if c.drink == "stout" then "order_stout" else "order_other", words, 4)
	setBubble(c)
	refreshPrompt(c)
	return true
end

-- After a serve: back to their seat with the drink, then the empty goes on the table.
function Customers.served(c, glass, res)
	c.served += 1
	c.state = "drinking"
	release(c)
	setBubble(c)
	refreshPrompt(c)
	local score = res.score or 0
	if score >= 85 then
		say(c, "praise", if c.regular and c.regular.praise then pick(c.regular.praise) else pick(lines.praise), 3)
	elseif score >= 60 then
		say(c, "", pick(lines.ok), 2.5)
	else
		say(c, "complain", if c.regular and c.regular.complain then pick(c.regular.complain) else pick(lines.complain), 3, Color3.fromRGB(255, 190, 140))
	end
	c.glass = glass
	Npc.hold(c.n, glass.model)
	task.spawn(function()
		settle(c)
		local drinkFor = rng:NextNumber(60, 120) * G.state.settings.dayLength / 10 * (1 + G.state:getMod("stay_mult"))
		local t0 = os.clock()
		local nextSip = os.clock() + rng:NextNumber(3, 7)
		while alive(c) and c.state == "drinking" and os.clock() - t0 < drinkFor do
			task.wait(1)
			if os.clock() > nextSip and c.n and c.n.model and c.n.model.Parent then
				-- a sip (the client raises the glass)
				local m = c.n.model
				m:SetAttribute("Sipping", true)
				task.delay(1.8, function()
					if m.Parent then
						m:SetAttribute("Sipping", false)
					end
				end)
				nextSip = os.clock() + rng:NextNumber(7, 15)
			end
			if G.state.phase == "closing" then
				break
			end
		end
		if not alive(c) or c.state ~= "drinking" then
			return
		end
		-- the empty goes down on their table (or the nearest ledge)
		if c.glass then
			local where = if c.seat then G.info.seats[c.seat].table else nil
			G.leaveEmpty(c.glass, where)
			c.glass = nil
		end
		if c.served < c.budget and G.state.phase == "open" then
			c.state = "mingle"
			refreshPrompt(c)
			G.dispatcher:add(c)
		else
			leave(c, false)
		end
	end)
end

-- A refused drink: they keep waiting (and the clock keeps running).
function Customers.refuse(c, why)
	local t = if why == "wrong" then pick(lines.wrong_drink) elseif why == "dirty" then pick(lines.dirty) else pick(lines.refuse)
	say(c, "", t, 3, Color3.fromRGB(255, 190, 140))
end

function Customers.chat(c)
	if c.chatted or not c.regular then
		return
	end
	c.chatted = true
	say(c, "chatter", pick(c.regular.chat or lines.music), 5)
	G.state:bump("chats")
	G.state.relationships[c.regular.id] = (G.state.relationships[c.regular.id] or 0) + 1
	refreshPrompt(c)
end

-- Every step: patience at the bar, and sending people up when the pace allows.
function Customers.tick(dt, players)
	local drain = 1 - math.clamp((G.state:atmosphere() - 20) / 160, 0, 0.35)
	for _, c in table.clone(list) do
		if c.state == "wait_order" or c.state == "wait_drink" then
			local helper = G.staffServing and G.staffServing(c)
			if not helper then
				c.patience -= dt * (if c.state == "wait_order" then 1 else 0.85) * drain
			end
			if c.patience <= 0 then
				walkOut(c)
			elseif c.patience < c.patienceMax * 0.3 and rng:NextNumber() < dt / 25 then
				say(c, "wait", pick(lines.waiting), 2.5, Color3.fromRGB(255, 210, 120))
			end
		end
	end
	if G.state.phase == "open" then
		local nextUp = G.dispatcher:tick(dt, Customers.atBar(), players, G.live and G.live.playing, function(c)
			return alive(c) and c.state == "mingle"
		end)
		if nextUp then
			goToBar(nextUp)
		end
	end
end

-- Last orders: anyone waiting to be called up stays put; at closing everyone drinks up and goes.
function Customers.closing()
	for _, c in table.clone(list) do
		if c.state == "mingle" or c.state == "wait_order" or c.state == "arriving" then
			leave(c, false)
		end
	end
end

function Customers.clear()
	for _, c in table.clone(list) do
		Customers.remove(c)
	end
	table.clear(seatTaken)
	table.clear(standTaken)
	table.clear(barTaken)
end

function Customers.waiting()
	local out = {}
	for _, c in list do
		if c.state == "wait_order" or c.state == "wait_drink" then
			table.insert(out, { name = c.name, drink = if c.state == "wait_drink" then (G.state:drink(c.drink).short or c.drink) else nil,
				patience = math.clamp(c.patience / c.patienceMax, 0, 1) })
		end
	end
	return out
end

return Customers
