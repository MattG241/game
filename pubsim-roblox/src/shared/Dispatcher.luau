-- Paces customer orders to what the bar can actually serve (a port of the phone game's
-- OrderDispatcher). Customers arrive, sit or stand and chat; when they want a drink they join a
-- waiting list, and the dispatcher sends them up to the bar one at a time at an interval taken from
-- the measured serving time and a target utilisation, never past the cap of orders waiting.
-- Pure Luau: the server passes in the pub's PubState.

local Dispatcher = {}
Dispatcher.__index = Dispatcher

local UTILISATION = { relaxed = 0.45, balanced = 0.6, busier = 0.8 }
local PATIENCE_MULT = { relaxed = 3.5, balanced = 2.8, busier = 2.0 }
local BASE_CAP = { relaxed = { 1, 2 }, balanced = { 2, 3 }, busier = { 3, 4 } }
local DEFAULT_SERVICE = 55
local MAX_CAP = 6

local function clamp(v, a, b)
	return math.max(a, math.min(b, v))
end

function Dispatcher.new(state)
	return setmetatable({ state = state, pending = {}, credit = 1, hardCapHit = false, forceNext = false }, Dispatcher)
end

function Dispatcher.difficulty(self)
	local d = self.state.settings.difficulty
	return if UTILISATION[d] then d else "balanced"
end

function Dispatcher.serviceTime(self)
	return clamp(self.state.stats.serviceTimeEma or DEFAULT_SERVICE, 25, 180)
end

-- Bartenders working the bar: the players, plus hired bar staff on tonight.
function Dispatcher.servers(self, players)
	local n = math.max(1, players or 1)
	for _, e in self.state:staffOnToday() do
		if e.role == "bartender" then
			n += e.skill
		end
	end
	return n
end

function Dispatcher.orderInterval(self, players, live)
	local u = UTILISATION[self:difficulty()]
	local servers = self:servers(players)
	local interval = self:serviceTime() / (u * servers)
	local day = self.state.day
	interval *= if day <= 1 then 1.15 elseif day == 2 then 1.07 else 1
	interval /= 1 + clamp((self.state.reputation - 20) / 100, 0, 0.3)
	if live then
		interval /= 1.2
	end
	return clamp(interval, 28 / servers, 200)
end

function Dispatcher.caps(self, players)
	local base = BASE_CAP[self:difficulty()]
	local grow = math.min(math.floor((self.state.day - 1) / 3), 2)
	local bonus = math.floor(self:servers(players) - 1 + 0.5)
	local hard = math.min(base[2] + grow + bonus, MAX_CAP)
	local soft = math.min(base[1] + grow + bonus, hard)
	return soft, hard
end

function Dispatcher.patienceFor(self, factor)
	local p = self:serviceTime() * PATIENCE_MULT[self:difficulty()] + 45
	if self.state.day <= 1 then
		p *= 1.5
	end
	return p * (factor or 1)
end

function Dispatcher.add(self, c)
	if not table.find(self.pending, c) then
		table.insert(self.pending, c)
	end
end

function Dispatcher.remove(self, c)
	local i = table.find(self.pending, c)
	if i then
		table.remove(self.pending, i)
	end
end

-- Called every step with the number of orders at the bar; returns the next customer to send up.
-- stillWaiting(c) says whether a pending customer still wants to order.
function Dispatcher.tick(self, dt, active, players, live, stillWaiting)
	local keep = {}
	for _, c in self.pending do
		if stillWaiting(c) then
			table.insert(keep, c)
		end
	end
	self.pending = keep
	local soft, hard = self:caps(players)
	local interval = self:orderInterval(players, live)
	if active >= soft then
		interval *= 2 -- at the soft cap time runs at half speed; at the hard cap it stops
	end
	if active >= hard then
		self.hardCapHit = true
		return nil
	end
	if self.hardCapHit then
		self.hardCapHit = false
		self.credit = math.min(self.credit, 0.5)
	end
	self.credit = math.min(1, self.credit + dt / interval)
	if #self.pending == 0 then
		return nil
	end
	if self.forceNext or self.credit >= 1 then
		self.forceNext = false
		self.credit = 0
		return table.remove(self.pending, 1)
	end
	return nil
end

-- How many people the pub should hold right now.
function Dispatcher.targetPopulation(self, hour, eventMult, maxCustomers)
	local curve = 0.5
	if hour >= 18 then
		curve = 0.8
	end
	if hour >= 20 then
		curve = 1
	end
	if hour >= 22 then
		curve = 0.8
	end
	local rep = clamp(self.state.reputation / 100, 0, 1)
	local t = 2 + (4 + 10 * rep) * curve * eventMult
	if self.state.day <= 1 then
		t = math.min(t, 5)
	end
	return clamp(math.floor(t + 0.5), 1, maxCustomers)
end

-- Learns how long the bar takes from an order to the handover.
function Dispatcher.recordService(self, seconds)
	if seconds <= 1 or seconds > 600 then
		return
	end
	local stats = self.state.stats
	stats.serviceTimeEma = clamp(self:serviceTime() * 0.75 + seconds * 0.25, 25, 180)
	stats.serviceSamples = (stats.serviceSamples or 0) + 1
end

return Dispatcher
