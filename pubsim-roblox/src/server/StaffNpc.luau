-- Hired staff at work. Bar staff pick up orders left waiting (15 s), go round, take the order, pour
-- (the same pour physics as the player, a little off according to skill, trait and mood) and serve.
-- Glass collectors clear empties to the sink and wipe spills. Cellar hands change empty kegs.
-- Everyone tires and takes a break now and then. Only those on tonight's rota come in.

local Shared = game:GetService("ReplicatedStorage").Shared
local Layout = require(Shared.Layout)
local Contents = require(Shared.Contents)
local PubState = require(Shared.PubState)
local Npc = require(script.Parent.Npc)
local Customers = require(script.Parent.Customers)

local StaffNpc = {}

local G
local rng = Random.new()
local crew = {} -- staff id -> worker
StaffNpc.crew = crew
local OVERFLOW_WAIT = 15
local BREAK_SPOT = Layout.v(2.9, 0, -4.0)

function StaffNpc.init(context)
	G = context
end

local function entry(w)
	return G.state:staffEntry(w.id)
end

local function pace(w)
	local e = entry(w)
	return if e then PubState.staffPace(e) else 1
end

local function working(w)
	return w.alive and w.n.model.Parent ~= nil and entry(w) ~= nil
end

local function walk(w, p)
	return Npc.walkTo(w.n, p, function()
		return working(w)
	end)
end

local function tire(w, amount)
	local e = entry(w)
	local skill = if e then e.skill else 0.5
	w.energy -= amount * (1.3 - 0.6 * skill) * (if e and e.trait == "tireless" then 0.6 else 1)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- A pour by hand: the right technique, a little off in proportion to skill (and steadier when happy).
local function pour(drinkId, e)
	local serve = G.state:drink(drinkId).serve or "stout"
	local c = Contents.new()
	c.freshness = G.state:freshness(drinkId)
	local off = (1 - e.skill) * 1.6 * (if e.trait == "steady" then 0.55 else 1) * lerp(1.35, 0.85, math.clamp(e.morale, 0, 1))
	local function r()
		return (rng:NextNumber() * 2 - 1) * off
	end
	local guard = 0
	if serve == "stout" then
		local angle = 45 + r() * 24
		local first = 0.75 + r() * 0.2
		while c:total() < first and guard < 800 do
			guard += 1
			c:pour(0.05, 1, angle, drinkId, serve)
		end
		c:stopPour()
		for _ = 1, math.floor((12 + r() * 6) / 0.1) do
			c:settle(0.1, 12)
		end
		local target = 1.0 + r() * 0.04
		guard = 0
		while c:total() < target and guard < 800 do
			guard += 1
			c:pour(0.05, 0.6, 0, drinkId, serve)
			c:settle(0.05, 12)
		end
		c:stopPour()
		for _ = 1, 200 do
			c:settle(0.1, 12)
		end
	else
		local angle = if serve == "lager" or serve == "cider" then 45 + r() * 20 else 0
		local target = 0.97 + r() * 0.05
		while c:total() < target and guard < 800 do
			guard += 1
			c:pour(0.05, 1, if c:total() < 0.65 then angle else 6, drinkId, serve)
		end
		c:stopPour()
	end
	return c
end

local function changeKeg(w, id)
	w.task = "keg"
	Npc.say(w.n, "I'll change the " .. (G.state:drink(id).short or id) .. " keg.", 2.5)
	walk(w, Layout.KEG_POS[id] + Vector3.new(3, 0, 0))
	task.wait(3 / pace(w))
	if working(w) and (G.state:servesLeft(id) < 1 or G.state:kegStale(id)) and G.state:changeKeg(id) then
		G.notify(w.first .. " changed the " .. (G.state:drink(id).short or id) .. " keg.", "info")
		G.state:staffNote(w.id, "kegs")
		tire(w, 0.05)
	end
	w.task = nil
end

-- A keg (with a spare) that has run dry, or with stale=true one gone stale, nobody's seeing to.
local function kegToChange(w, stale)
	for id in Layout.KEG_POS do
		if G.state:drinkAvailable(id) and (G.state.stock[id] or 0) > 0 then
			local claimed = false
			for _, o in crew do
				if o ~= w and o.kegId == id then
					claimed = true
				end
			end
			if not claimed and ((not stale and G.state:servesLeft(id) < 1) or (stale and G.state:kegStale(id))) then
				return id
			end
		end
	end
	return nil
end

local function serveOne(w, c)
	local e = entry(w)
	c.helper = w
	Customers.refreshPrompt(c)
	local spotX = G.info.barSpots[c.barSpot or 1].X
	walk(w, Vector3.new(spotX, 0, Layout.BEHIND_Z))
	Npc.face(w.n, Vector3.new(spotX, 0, 0))
	task.wait(lerp(1.2, 0.5, e.skill) / pace(w))
	if not working(w) or c.state ~= "wait_order" then
		c.helper = nil
		return
	end
	Customers.takeOrder(c)
	local id = c.drink
	if G.state:servesLeft(id) < 1 then
		if e.trait == "cellar" and (G.state.stock[id] or 0) > 0 and Layout.KEG_POS[id] then
			w.kegId = id
			changeKeg(w, id)
			w.kegId = nil
		else
			Npc.say(w.n, "The " .. (G.state:drink(id).short or id) .. "'s run dry! Change the keg in the cellar.", 3.5)
			G.notify(w.first .. ": the " .. (G.state:drink(id).short or id) .. " has run dry.", "bad")
			c.helper = nil
			Customers.refreshPrompt(c)
			return
		end
	end
	if G.rackClean() <= 0 then
		Npc.say(w.n, "We're out of clean glasses!", 3)
		c.helper = nil
		Customers.refreshPrompt(c)
		return
	end
	local tapX = Layout.TAP_X[id] or Layout.TAP_X.stout
	walk(w, Vector3.new(tapX, 0, Layout.BEHIND_Z))
	Npc.face(w.n, Vector3.new(tapX, 0, 0))
	local serve = G.state:drink(id).serve or "stout"
	local secs = lerp(6, 4, e.skill) + (if serve == "stout" then 10 else 0)
	task.wait(secs / pace(w))
	if not working(w) then
		c.helper = nil
		return
	end
	local contents = pour(id, e)
	if not G.state:drawUnits(id, contents:total() + contents.spilled) then
		Npc.say(w.n, "Can't pour that, the keg's empty.", 3)
		c.helper = nil
		Customers.refreshPrompt(c)
		return
	end
	local glass = G.takeGlassFromRack(G.state:drink(id).glass or "pint")
	if not glass then
		c.helper = nil
		return
	end
	glass.contents = contents
	Npc.hold(w.n, glass.model)
	walk(w, Vector3.new(G.info.barSpots[c.barSpot or 1].X, 0, Layout.BEHIND_Z))
	task.wait(lerp(1.0, 0.4, e.skill) / pace(w))
	if (c.state :: any) == "wait_drink" and c.alive then -- it may have changed while walking
		G.serve(nil, c, glass, w)
	else
		G.dropGlass(glass)
	end
	c.helper = nil
	tire(w, 0.06)
end

local function collect(w)
	local e = entry(w)
	local carry = 3 + math.floor(e.skill * 3)
	local carried = 0
	while working(w) and carried < carry do
		local empty = G.nearestEmpty(w.n.root.Position, w)
		if not empty then
			break
		end
		empty.claim = w
		walk(w, empty.pos + (w.n.root.Position - empty.pos).Unit * 2)
		task.wait(lerp(1.0, 0.4, e.skill) / pace(w))
		if G.pickUpEmpty(empty) then
			carried += 1
		end
	end
	local spill = G.nearestSpill(w)
	if spill and carried == 0 then
		spill.claim = w
		walk(w, spill.pos + Vector3.new(0, 0, 2))
		task.wait(lerp(2.6, 1.4, e.skill) / pace(w))
		if G.wipeSpill(spill) then
			G.state:staffNote(w.id, "spills")
		end
	end
	if carried > 0 then
		walk(w, Layout.SINK_POS + Vector3.new(0, -Layout.SINK_POS.Y, 2.2))
		for _ = 1, carried do
			task.wait(lerp(2.6, 1.1, e.skill) / pace(w))
			G.washed(1)
			G.state:staffNote(w.id, "glasses")
			tire(w, 0.035)
		end
	end
end

local function home(w)
	if w.role ~= "bartender" then
		return Layout.STAFF_FLOOR_HOME
	end
	local n = 0
	for _, o in crew do
		if o.role == "bartender" and o.order < w.order then
			n += 1
		end
	end
	return Layout.STAFF_BAR_HOME + Vector3.new(4.5 * n, 0, 0)
end

local function run(w)
	while working(w) do
		local e = entry(w)
		if w.energy <= 0 then
			Npc.say(w.n, "Five minutes!", 2.5)
			G.notify(w.first .. " is on a break.", "info")
			Npc.setTag(w.n, w.first .. " · on a break")
			walk(w, BREAK_SPOT)
			task.wait(50)
			w.energy = 1
			Npc.setTag(w.n, w.first .. (if w.role == "bartender" then " · bar" else " · floor"))
		end
		local did = false
		if e.trait == "cellar" then
			local id = kegToChange(w, false) or (if Customers.atBar() == 0 then kegToChange(w, true) else nil)
			if id then
				w.kegId = id
				changeKeg(w, id)
				w.kegId = nil
				did = true
			end
		end
		if not did and w.role == "bartender" and G.state.phase ~= "prep" then
			for _, c in Customers.list do
				if c.state == "wait_order" and not c.helper and c.waitStart and os.clock() - c.waitStart >= OVERFLOW_WAIT then
					serveOne(w, c)
					did = true
					break
				end
			end
		elseif not did and w.role == "collector" then
			if G.nearestEmpty(w.n.root.Position, w) or G.nearestSpill(w) then
				collect(w)
				did = true
			end
		end
		if not did then
			if (w.n.root.Position - home(w)).Magnitude > 3 then
				walk(w, home(w))
			end
			task.wait(0.5)
		end
	end
end

-- Brings in tonight's rota and sends home anyone no longer working.
function StaffNpc.refresh()
	local want = {}
	for _, e in G.state:staffOnToday() do
		want[e.id] = e
	end
	for id, w in crew do
		if not want[id] then
			w.alive = false
			if w.n and w.n.model then
				w.n.model:Destroy()
			end
			crew[id] = nil
		end
	end
	local order = 0
	for id, e in want do
		order += 1
		if not crew[id] then
			local first = string.split(e.name, " ")[1]
			local at = home({ role = e.role, order = order })
			local n = Npc.spawn(e.name, { gender = e.gender, coat = { 0.12, 0.12, 0.14 }, trousers = { 0.1, 0.1, 0.12 } }, rng, G.folder, CFrame.new(at + Vector3.new(0, 3, 0)))
			if n then
				local w = { id = id, first = first, role = e.role, n = n, alive = true, energy = 1, order = order }
				crew[id] = w
				Npc.setTag(n, first .. (if e.role == "bartender" then " · bar" else " · floor"))
				task.spawn(run, w)
			end
		end
	end
end

-- Who is looking after this customer (their patience doesn't run while staff are on it).
function StaffNpc.serving(c)
	return c.helper
end

function StaffNpc.clear()
	for id, w in crew do
		w.alive = false
		if w.n and w.n.model then
			w.n.model:Destroy()
		end
		crew[id] = nil
	end
end

return StaffNpc
