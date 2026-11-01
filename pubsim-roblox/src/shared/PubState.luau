-- The pub's whole state and rules: money, stock, kegs, upgrades, reputation, the day, goals and
-- staff. A port of the phone game's GameState (same numbers, from the shared data files).
-- Pure Luau with no Roblox APIs: the server owns one per pub, and the unit tests drive it too.

local PubState = {}
PubState.__index = PubState

local function clamp(v, a, b)
	return math.max(a, math.min(b, v))
end

local function round(v)
	return math.floor(v + 0.5)
end

-- A small seeded random generator (the same sequence everywhere, for repeatable days).
local function rng(seed)
	local s = (math.floor(seed) % 2147483646) + 1
	return function(a, b)
		s = (s * 48271) % 2147483647
		local r = s / 2147483647
		if a == nil then
			return r
		end
		return a + (b - a) * r
	end
end
PubState.rng = rng

local REP_TIERS = { { 0, "A quiet local" }, { 15, "Known on the street" }, { 30, "Talk of the town" },
	{ 50, "The county's favourite" }, { 70, "Best pint in the west" }, { 90, "A legend of a pub" } }
PubState.REP_TIERS = REP_TIERS

PubState.STAFF_LIMIT = { bartender = 2, collector = 1 }
PubState.SECOND_BARTENDER_REP = 50
PubState.TRAITS = {
	quick = { name = "Quick", desc = "Works about 15% faster" },
	steady = { name = "Steady hand", desc = "Pours closer to perfect" },
	charmer = { name = "Charmer", desc = "Customers tip them a fifth more" },
	tireless = { name = "Tireless", desc = "Needs fewer breaks" },
	cellar = { name = "Cellar hand", desc = "Changes empty and stale kegs without being asked" },
	keen = { name = "Keen learner", desc = "Gets better twice as fast" },
}
PubState.ROLE_TRAITS = { bartender = { "quick", "steady", "charmer", "tireless", "cellar", "keen" },
	collector = { "quick", "tireless", "cellar", "keen" } }
local MORALE_WORDS = { { 0, "fed up" }, { 0.2, "unhappy" }, { 0.4, "getting on with it" }, { 0.6, "content" }, { 0.8, "happy" } }
PubState.STALE_FRESHNESS = 0.9
PubState.FESTIVAL_CYCLE = 28

function PubState.new(data)
	local self = setmetatable({}, PubState)
	self.data = data
	self.drinkById = {}
	for _, d in data.drinks do
		self.drinkById[d.id] = d
	end
	self.upgradeById = {}
	for _, u in data.upgrades do
		self.upgradeById[u.id] = u
	end
	self.staffById = {}
	for _, c in data.staff do
		self.staffById[c.id] = c
	end
	self.settings = { difficulty = "balanced", dayLength = 10 }
	self.messages = {}
	self.liveAtmosphere = 0
	self.liveTips = 0
	self:reset()
	return self
end

function PubState.econ(self, key, default)
	local v = self.data.economy[key]
	if v == nil then
		return default
	end
	return v
end

function PubState.notify(self, text, kind)
	table.insert(self.messages, { text = text, kind = kind or "info" })
end

function PubState.reset(self)
	self.pubName = "The Crooked Shamrock"
	self.mode = "career"
	self.cash = self:econ("start_cash", 55)
	self.day = 1
	self.hour = 15.5
	self.phase = "prep"
	self.reputation = self:econ("reputation_start", 20)
	self.weather = "rain"
	self.upgrades = {}
	self.stock = {}
	self.tapUnits = {}
	self.kegDay = {}
	self.prices = {}
	self.relationships = {}
	self.staff = {}
	self.applicants = {}
	self.applicantsWeek = -1
	self.progress = { linesCleanedDay = 1 }
	self.deliveries = {}
	self.history = {}
	self.bookings = {}
	self.stats = { pintsPoured = 0, perfectPints = 0, served = 0, walkouts = 0, revenue = 0, tips = 0,
		bestPour = 0, days = 0, glassesWashed = 0, spillsCleaned = 0, kegsChanged = 0, eventsHosted = 0,
		serviceTimeEma = 55, serviceSamples = 0 }
	for _, d in self.data.drinks do
		self.prices[d.id] = d.price
		self.stock[d.id] = d.start_stock or 1
		self.tapUnits[d.id] = d.units_per_stock
		self.kegDay[d.id] = 1
	end
	self:resetToday()
end

function PubState.resetToday(self)
	self.today = { sales = 0, tips = 0, cogs = 0, stock_spend = 0, upgrade_spend = 0, rent = 0, utilities = 0,
		wages = 0, event_fees = 0, other = 0, prizes = 0, served = 0, walkouts = 0, satisfaction_sum = 0,
		quality_sum = 0, pours = 0, wasted_units = 0, perfect = 0, washed = 0, chats = 0, best_streak = 0,
		staff_served = 0, staff_log = {} }
end

function PubState.newGame(self, mode, name)
	self:reset()
	self.mode = mode or "career"
	self.pubName = name or self.pubName
	if self.mode == "sandbox" then
		self.cash = self:econ("sandbox_cash", 5000)
	end
	self:startDay()
end

-- ---------------------------------------------------------------- drinks and money
function PubState.drink(self, id)
	return self.drinkById[id] or {}
end

function PubState.drinkAvailable(self, id)
	local d = self.drinkById[id]
	if not d then
		return false
	end
	return (d.unlock or "") == "" or self:hasUpgrade(d.unlock)
end

function PubState.availableDrinks(self)
	local out = {}
	for _, d in self.data.drinks do
		if self:drinkAvailable(d.id) then
			table.insert(out, d.id)
		end
	end
	return out
end

function PubState.earn(self, amount, category)
	if amount <= 0 then
		return
	end
	category = category or "sales"
	self.cash += amount
	self.today[category] = (self.today[category] or 0) + amount
	if category == "sales" then
		self.stats.revenue += amount
	elseif category == "tips" then
		self.stats.tips += amount
	end
end

function PubState.canAfford(self, amount)
	return self.cash + 0.0001 >= amount
end

function PubState.spend(self, amount, category, allowDebt)
	if amount <= 0 then
		return true
	end
	if not allowDebt and not self:canAfford(amount) then
		return false
	end
	self.cash -= amount
	category = category or "other"
	self.today[category] = (self.today[category] or 0) + amount
	return true
end

function PubState.priceOf(self, id)
	return self.prices[id] or self:drink(id).price or 5
end

function PubState.setPrice(self, id, value)
	local base = self:drink(id).price or 5
	self.prices[id] = clamp(round(value * 10) / 10, base * 0.5, base * 2)
end

function PubState.unitCost(self, id)
	local d = self:drink(id)
	return (d.stock_cost or 100) / (d.units_per_stock or 80)
end

-- ---------------------------------------------------------------- kegs and stock
function PubState.servesLeft(self, id)
	return self.tapUnits[id] or 0
end

-- Takes serves from the connected keg; false (taking nothing) if it runs dry.
function PubState.drawUnits(self, id, units)
	local left = self:servesLeft(id)
	local unit = self:drink(id).stock_unit or "keg"
	if left < units - 0.0001 and unit ~= "keg" and unit ~= "cask" and (self.stock[id] or 0) > 0 then
		-- bottles and syrup boxes are swapped behind the bar as soon as one runs out
		self:changeKeg(id)
		left = self:servesLeft(id)
	end
	if left < units - 0.0001 then
		return false
	end
	self.tapUnits[id] = left - units
	self.today.cogs += units * self:unitCost(id)
	return true
end

function PubState.wasteUnits(self, id, units)
	self.today.wasted_units += units
end

function PubState.changeKeg(self, id)
	if (self.stock[id] or 0) <= 0 then
		return false
	end
	self.stock[id] -= 1
	local waste = self:servesLeft(id)
	if waste > 0 then
		self:wasteUnits(id, waste)
	end
	self.tapUnits[id] = self:drink(id).units_per_stock
	self.kegDay[id] = self.day
	self.stats.kegsChanged += 1
	return true
end

-- 1.0 is fresh; falls after a couple of days on tap (Cellar Cooling halves the decay).
function PubState.freshness(self, id)
	local age = self.day - (self.kegDay[id] or self.day)
	local decay = 0.06 * (1 + self:getMod("freshness_decay_mult"))
	return clamp(1 - math.max(0, age - 2) * decay, 0.55, 1)
end

-- A keg with beer still in it that has gone stale (it can be swapped early).
function PubState.kegStale(self, id)
	local unit = self:drink(id).stock_unit or "keg"
	return (unit == "keg" or unit == "cask") and self:servesLeft(id) >= 1 and self:freshness(id) < PubState.STALE_FRESHNESS
end

function PubState.pendingDelivery(self, id)
	local n = 0
	for _, dl in self.deliveries do
		if dl.drink == id then
			n += dl.packs
		end
	end
	return n
end

-- Nothing to pour and nothing coming: the supplier puts one delivery on the slate.
function PubState.stockEmergency(self)
	for _, id in self:availableDrinks() do
		if self:servesLeft(id) >= 1 or (self.stock[id] or 0) > 0 or self:pendingDelivery(id) > 0 then
			return false
		end
	end
	return true
end

function PubState.orderStock(self, id, packs)
	local d = self:drink(id)
	local cost = d.stock_cost * packs + self:econ("delivery_fee", 6)
	if not self:spend(cost, "stock_spend", self:stockEmergency() and packs == 1) then
		return false
	end
	table.insert(self.deliveries, { drink = id, packs = packs, day = self.day + 1 })
	return true
end

-- ---------------------------------------------------------------- upgrades and reputation
function PubState.hasUpgrade(self, id)
	return self.upgrades[id] ~= nil
end

function PubState.upgradeBlock(self, id)
	local u = self.upgradeById[id]
	if not u then
		return "Unknown"
	end
	if self:hasUpgrade(id) then
		return "Owned"
	end
	if (u.requires or "") ~= "" and not self:hasUpgrade(u.requires) then
		local r = self.upgradeById[u.requires]
		return "Needs " .. (if r then r.name else u.requires)
	end
	if self.reputation < (u.min_rep or 0) then
		return string.format("Needs reputation %d", math.floor(u.min_rep))
	end
	if not self:canAfford(u.cost) then
		return string.format("€%d", math.floor(u.cost))
	end
	return ""
end

function PubState.buyUpgrade(self, id)
	if self:upgradeBlock(id) ~= "" then
		return false
	end
	local u = self.upgradeById[id]
	self:spend(u.cost, "upgrade_spend")
	self.upgrades[id] = self.day
	self:notify("Purchased: " .. u.name, "good")
	return true
end

function PubState.festivalToday(self)
	local d = (self.day - 1) % PubState.FESTIVAL_CYCLE + 1
	for _, f in self.data.festivals or {} do
		if f.day == d then
			return f
		end
	end
	return nil
end

-- Sums an effect across the upgrades bought (and today's festival).
function PubState.getMod(self, key)
	local total = 0
	local fest = self:festivalToday()
	if fest and fest.effects and fest.effects[key] then
		total += fest.effects[key]
	end
	for id in self.upgrades do
		local u = self.upgradeById[id]
		if u and u.effects and u.effects[key] then
			total += u.effects[key]
		end
	end
	return total
end

function PubState.glassesTotal(self)
	return self:econ("start_glasses", 6) + math.floor(self:getMod("glasses"))
end

function PubState.atmosphere(self)
	return clamp(20 + self:getMod("atmosphere") + self.liveAtmosphere, 0, 100)
end

function PubState.repTier(self)
	local t = REP_TIERS[1][2]
	for _, r in REP_TIERS do
		if self.reputation >= r[1] then
			t = r[2]
		end
	end
	return t
end

-- ---------------------------------------------------------------- the day
function PubState.weekday(self)
	return (self.day + 2) % 7 -- day 1 is a Thursday; 0 = Monday
end

function PubState.weekdayName(self)
	local names = self:econ("weekday_names", { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" })
	return names[self:weekday() + 1]
end

function PubState.secondsPerGameHour(self)
	return self.settings.dayLength * 60 / 8
end

function PubState.clockText(self)
	local h = math.floor(self.hour) % 24
	local m = math.floor((self.hour - math.floor(self.hour)) * 60)
	return string.format("%02d:%02d", h, m)
end

function PubState.startDay(self)
	self.liveAtmosphere = 0
	self.liveTips = 0
	self.hour = 15.5
	self.phase = "prep"
	self:resetToday()
	local keep = {}
	for _, dl in self.deliveries do
		if dl.day <= self.day then
			self.stock[dl.drink] = (self.stock[dl.drink] or 0) + dl.packs
			self:notify(string.format("Delivery arrived: %d × %s", math.floor(dl.packs), self:drink(dl.drink).name or dl.drink), "info")
		else
			table.insert(keep, dl)
		end
	end
	self.deliveries = keep
	for _, id in self:availableDrinks() do
		if self:kegStale(id) then
			local d = self:drink(id)
			if (self.stock[id] or 0) > 0 then
				self:notify(string.format("The %s %s has gone stale (%d%% fresh). Swap it for a spare in the cellar.", d.short, d.stock_unit, round(self:freshness(id) * 100)), "bad")
			else
				self:notify(string.format("The %s %s has gone stale (%d%% fresh). Order a fresh one from the stock menu.", d.short, d.stock_unit, round(self:freshness(id) * 100)), "bad")
			end
		end
	end
	local r = rng(self.day * 7919)()
	self.weather = if r < 0.45 then "rain" elseif r < 0.75 then "cloudy" elseif r < 0.93 then "clear" else "storm"
	self:refreshApplicants(false)
end

function PubState.openPub(self)
	if self.phase == "prep" then
		self.phase = "open"
		self.hour = math.max(self.hour, self:econ("day_open_hour", 16))
	end
end

function PubState.bump(self, key, n)
	self.today[key] = (self.today[key] or 0) + (n or 1)
end

-- Today's three goals (always a serving target plus two others).
function PubState.dailyGoals(self)
	if self.today.goals then
		return self.today.goals
	end
	local r = rng(self.day * 104729 + 17)
	local always, others = {}, {}
	for _, o in self.data.objectives do
		if o.always then
			table.insert(always, o)
		elseif not (o.id == "chat" and self.day <= 1) then
			table.insert(others, o)
		end
	end
	for i = #others, 2, -1 do
		local j = math.floor(r() * i) + 1
		others[i], others[j] = others[j], others[i]
	end
	local goals = {}
	local pick = table.clone(always)
	for i = 1, 3 - #always do
		table.insert(pick, others[i])
	end
	for _, o in pick do
		local target = 0
		if o.base then
			target = math.min(round(o.base + (o.per_day or 0) * (self.day - 1)), o.max or 99)
		end
		local text = o.text
		if string.find(text, "%%d") then
			text = string.format(text, target)
		end
		table.insert(goals, { id = o.id, text = text, stat = o.stat, kind = o.kind or "count", target = target,
			minServed = o.min_served or 0, reward = o.reward or 10, done = false })
	end
	self.today.goals = goals
	return goals
end

function PubState.goalValue(self, g)
	if g.stat == "avg_quality" then
		return self.today.quality_sum / math.max(1, self.today.pours)
	end
	return self.today[g.stat] or 0
end

-- Counting goals pay out as soon as they're met; "nobody walks out" and averages at closing.
function PubState.checkGoals(self, closing)
	for _, g in self:dailyGoals() do
		if not g.done then
			local met = false
			if g.kind == "count" then
				met = self:goalValue(g) >= g.target
			elseif g.kind == "zero" then
				met = closing and self:goalValue(g) <= 0 and self.today.served >= g.minServed
			elseif g.kind == "avg" then
				met = closing and self:goalValue(g) >= g.target and self.today.pours >= g.minServed
			end
			if met then
				g.done = true
				self:earn(g.reward, "prizes")
				self:notify(string.format("Goal met: %s  +€%d", g.text, round(g.reward)), "good")
			end
		end
	end
end

-- Settles the day's overheads, moves to tomorrow and returns the summary for the end-of-day screen.
function PubState.endDay(self)
	self:checkGoals(true)
	local goals = self:dailyGoals()
	local rent = if self.mode == "sandbox" then 0 else self:econ("rent_per_day", 30)
	self:spend(rent, "rent", true)
	self:spend(self:econ("utilities_per_day", 8) + self:getMod("utilities"), "utilities", true)
	self:spend(self:wagesToday(), "wages", true)
	local staffLines = self:staffEndOfNight()
	local t = self.today
	local income = t.sales + t.tips + t.prizes
	local expenses = t.stock_spend + t.upgrade_spend + t.rent + t.utilities + t.wages + t.event_fees + t.other
	local served = t.served
	local avgSat = if served > 0 then t.satisfaction_sum / served else 0
	local avgQ = t.quality_sum / math.max(1, t.pours)
	local repChange = 0
	if served > 0 then
		repChange += (avgSat - 55) / 12 * clamp(served / 6, 0.3, 2)
	end
	repChange -= t.walkouts * 0.6
	repChange += self:getMod("rep_gain")
	self.reputation = clamp(self.reputation + repChange, 0, 100)
	local summary = { day = self.day, weekday = self:weekdayName(), sales = t.sales, tips = t.tips, prizes = t.prizes,
		cogs = t.cogs, stock_spend = t.stock_spend, upgrade_spend = t.upgrade_spend, rent = t.rent,
		utilities = t.utilities, wages = t.wages, event_fees = t.event_fees, other = t.other, income = income,
		expenses = expenses, profit = income - expenses, served = served, walkouts = t.walkouts,
		avgSatisfaction = avgSat, avgQuality = avgQ, reputation = self.reputation, repChange = repChange,
		repTier = self:repTier(), wasted = t.wasted_units, cash = self.cash, goals = goals,
		bestStreak = t.best_streak, staffLines = staffLines }
	table.insert(self.history, { day = self.day, sales = t.sales, tips = t.tips, profit = income - expenses, served = served })
	while #self.history > 14 do
		table.remove(self.history, 1)
	end
	self.stats.days += 1
	self.day += 1
	self:startDay()
	return summary
end

-- ---------------------------------------------------------------- staff
function PubState.staffEntry(self, id)
	for _, e in self.staff do
		if e.id == id then
			return e
		end
	end
	return nil
end

function PubState.isHired(self, id)
	return self:staffEntry(id) ~= nil
end

function PubState.staffCount(self, role)
	local n = 0
	for _, e in self.staff do
		if e.role == role then
			n += 1
		end
	end
	return n
end

function PubState.candidate(self, id)
	for _, a in self.applicants do
		if a.id == id then
			return a
		end
	end
	return self.staffById[id]
end

function PubState.jobSeekers(self)
	local out = {}
	for _, c in self.data.staff do
		if not self:isHired(c.id) then
			table.insert(out, c)
		end
	end
	for _, a in self.applicants do
		if not self:isHired(a.id) then
			table.insert(out, a)
		end
	end
	return out
end

function PubState.staffLevel(skill)
	return clamp(round(skill * 5), 1, 5)
end

function PubState.moraleWord(m)
	local w = ""
	for _, mw in MORALE_WORDS do
		if m >= mw[1] then
			w = mw[2]
		end
	end
	return w
end

function PubState.hireFee(self, id)
	local c = self:candidate(id)
	return if c then (c.fee or 0) else 0
end

-- Why a candidate can't be taken on right now ("" if they can).
function PubState.hireBlock(self, id)
	local c = self:candidate(id)
	if not c then
		return "Unknown"
	end
	if self:isHired(id) then
		return "Already working here"
	end
	if self.reputation < (c.min_rep or 0) then
		return string.format("Needs reputation %d", math.floor(c.min_rep or 0))
	end
	if self:staffCount(c.role) >= (PubState.STAFF_LIMIT[c.role] or 1) then
		return "No room for another " .. (if c.role == "bartender" then "bartender" else "glass collector")
	end
	if c.role == "bartender" and self:staffCount("bartender") >= 1 and self.reputation < PubState.SECOND_BARTENDER_REP then
		return string.format("A second bartender needs reputation %d", PubState.SECOND_BARTENDER_REP)
	end
	local upfront = self:hireFee(id) + (c.wage or 0)
	if self.cash < upfront then
		return string.format("Need €%d (agency fee and the first night's wages)", math.ceil(upfront))
	end
	return ""
end

function PubState.staffDefaults(self, e, c)
	c = c or self:candidate(e.id) or {}
	if e.trait == nil then
		e.trait = c.trait or ""
	end
	if e.potential == nil then
		e.potential = math.max(e.skill or 0.5, c.potential or ((e.skill or 0.5) + 0.2))
	end
	e.xp = e.xp or 0
	e.raiseAsk = e.raiseAsk or 0
	e.notice = e.notice or 0
	e.inARow = e.inARow or 0
	e.morale = e.morale or 0.75
	if type(e.rota) ~= "table" or #e.rota ~= 7 then
		e.rota = { true, true, true, true, true, true, true }
	end
	e.totals = e.totals or { served = 0, glasses = 0, spills = 0, kegs = 0, nights = 0 }
end

function PubState.hire(self, id)
	if self:hireBlock(id) ~= "" then
		return false
	end
	local c = self:candidate(id)
	self:spend(self:hireFee(id), "wages")
	local e = { id = id, name = c.name, role = c.role, skill = c.skill, wage = c.wage, model = c.model or "",
		gender = c.gender or "m", hiredDay = self.day }
	self:staffDefaults(e, c)
	table.insert(self.staff, e)
	return true
end

-- Letting someone go: a night's wages as notice, and they leave straight away.
function PubState.fire(self, id)
	local e = self:staffEntry(id)
	if not e then
		return
	end
	self:spend(e.wage, "wages", true)
	table.remove(self.staff, table.find(self.staff, e))
end

function PubState.worksOn(self, e, wd)
	return type(e.rota) ~= "table" or #e.rota ~= 7 or e.rota[wd + 1] == true
end

function PubState.worksToday(self, e)
	return self:worksOn(e, self:weekday())
end

function PubState.staffOnToday(self)
	local out = {}
	for _, e in self.staff do
		if self:worksToday(e) then
			table.insert(out, e)
		end
	end
	return out
end

function PubState.setRota(self, id, wd, on)
	local e = self:staffEntry(id)
	if not e or wd < 0 or wd > 6 then
		return
	end
	if wd == self:weekday() and self.phase ~= "prep" then
		return -- tonight's shift is fixed once the doors are open
	end
	e.rota[wd + 1] = on
end

function PubState.wagesToday(self)
	local w = 0
	for _, e in self:staffOnToday() do
		w += e.wage
	end
	return w
end

-- How busy a night looks (1 is ordinary; weekends, match nights and festivals more).
function PubState.busyForecast(self, daysAhead)
	local d = self.day + daysAhead
	local wd = (d + 2) % 7
	local mults = self:econ("weekday_mult", { 1, 1, 1, 1, 1, 1, 1 })
	local f = mults[wd + 1]
	if self:hasUpgrade("big_screen") and (wd == 2 or wd == 6) then
		f += 0.2
	end
	local fd = (d - 1) % PubState.FESTIVAL_CYCLE + 1
	for _, fe in self.data.festivals or {} do
		if fe.day == fd then
			f += 0.35
		end
	end
	return f
end

function PubState.busyWord(f)
	if f >= 1.4 then
		return "Packed"
	elseif f >= 1.15 then
		return "Busy"
	elseif f >= 0.95 then
		return "Steady"
	end
	return "Quiet"
end

-- Records a piece of work: experience (skill grows on the job) and tonight's tally.
function PubState.staffNote(self, id, kind, amount)
	local e = self:staffEntry(id)
	if not e then
		return
	end
	amount = amount or 1
	local log = self.today.staff_log
	log[id] = log[id] or { served = 0, glasses = 0, spills = 0, kegs = 0, tips = 0 }
	log[id][kind] = (log[id][kind] or 0) + amount
	local gain = ({ served = 1, glasses = 0.3, spills = 0.5, kegs = 0.5 })[kind] or 0
	if gain <= 0 then
		return
	end
	if e.trait == "keen" then
		gain *= 2
	end
	e.xp += gain
	local before = PubState.staffLevel(e.skill)
	e.skill = math.min(e.potential, e.skill + gain * 0.0035)
	local after = PubState.staffLevel(e.skill)
	if after > before and e.raiseAsk <= 0 then
		e.raiseAsk = round(e.wage * 1.15 + 1)
		self:notify(string.format("%s is getting good at this (skill %d/5) and would like a raise to €%d a night. See the Staff tab.", string.split(e.name, " ")[1], after, e.raiseAsk), "info")
	end
end

function PubState.agreeRaise(self, id)
	local e = self:staffEntry(id)
	if not e or e.raiseAsk <= 0 then
		return
	end
	e.wage = e.raiseAsk
	e.raiseAsk = 0
	e.morale = math.min(1, e.morale + 0.25)
end

function PubState.refuseRaise(self, id)
	local e = self:staffEntry(id)
	if not e then
		return
	end
	e.raiseAsk = 0
	e.morale = math.max(0, e.morale - 0.25)
end

function PubState.bonusCost(self, id)
	local e = self:staffEntry(id)
	return if e then e.wage * 2 else 0
end

function PubState.giveBonus(self, id)
	local e = self:staffEntry(id)
	if not e or not self:spend(self:bonusCost(id), "wages") then
		return false
	end
	e.morale = math.min(1, e.morale + 0.35)
	e.notice = 0
	return true
end

-- How quickly someone works: their trait and how they feel about the job.
function PubState.staffPace(e)
	local p = 0.88 + (1.08 - 0.88) * clamp(e.morale or 0.75, 0, 1)
	if e.trait == "quick" then
		p *= 1.15
	end
	return p
end

-- The close of the night: totals, morale, notice. Returns one line per person for the summary.
function PubState.staffEndOfNight(self)
	local lines = {}
	local log = self.today.staff_log
	local busy = self.today.served >= 30
	for _, e in table.clone(self.staff) do
		local first = string.split(e.name, " ")[1]
		local rec = log[e.id] or {}
		local m = e.morale
		if self:worksToday(e) then
			e.inARow += 1
			e.totals.nights += 1
			for _, k in { "served", "glasses", "spills", "kegs" } do
				e.totals[k] = (e.totals[k] or 0) + math.floor(rec[k] or 0)
			end
			m -= 0.02 + (if busy then 0.03 else 0)
			if e.inARow > 5 then
				m -= 0.05 -- six or seven nights on the trot wears anyone down
			end
			local bits = {}
			if (rec.served or 0) > 0 then
				table.insert(bits, string.format("served %d", math.floor(rec.served)))
			end
			if (rec.glasses or 0) > 0 then
				table.insert(bits, string.format("washed %d glasses", math.floor(rec.glasses)))
			end
			if (rec.spills or 0) > 0 then
				table.insert(bits, string.format("wiped %d spills", math.floor(rec.spills)))
			end
			if (rec.kegs or 0) > 0 then
				table.insert(bits, string.format("changed %d kegs", math.floor(rec.kegs)))
			end
			table.insert(lines, string.format("%s %s (€%d) · %s", first,
				if #bits > 0 then table.concat(bits, ", ") else "had a quiet one", round(e.wage), PubState.moraleWord(clamp(m, 0, 1))))
		else
			e.inARow = 0
			m += 0.08
		end
		e.morale = clamp(m, 0, 1)
		if e.notice > 0 then
			e.notice -= 1
			if e.notice <= 0 then
				table.remove(self.staff, table.find(self.staff, e))
				self:notify(first .. " has worked their notice and left.", "bad")
				table.insert(lines, first .. " has left")
			end
		elseif e.morale < 0.15 then
			e.notice = 2
			self:notify(first .. " is fed up and has handed in their notice: two more nights. A word and a bonus might change their mind (Staff tab).", "bad")
		end
	end
	return lines
end

local FIRST_NAMES = { m = { "Cian", "Darragh", "Eoin", "Fionn", "Oisín", "Pádraig", "Rory", "Tadhg", "Colm", "Declan", "Liam", "Seán" },
	f = { "Aoife", "Caoimhe", "Clodagh", "Niamh", "Orla", "Saoirse", "Sinéad", "Úna", "Gráinne", "Méabh", "Eimear", "Ciara" } }
local SURNAMES = { "Brennan", "Byrne", "Carroll", "Daly", "Dunne", "Farrell", "Gallagher", "Hayes", "Keane", "Lynch", "Murphy", "Nolan", "O'Brien", "Power", "Quigley", "Walsh" }
local BLURBS = { bartender = { "Pulled pints through college in Galway.", "Two years in a hotel bar in Killarney.", "New to the trade but keen to learn.", "Worked the summer season in Doolin.", "Back from London and looking for a local." },
	collector = { "Wants evening work around school hours.", "Retired, and likes to keep busy.", "Fast on their feet and not afraid of a sink.", "Looking for a few nights a week." } }

-- Every Monday a few new people answer the card in the window.
function PubState.refreshApplicants(self, force)
	local week = math.floor((self.day - 1) / 7)
	if self.applicantsWeek == week and not force then
		return
	end
	self.applicantsWeek = week
	self.applicants = {}
	local r = rng(week * 7717 + 3)
	local function pick(list)
		return list[math.floor(r() * #list) + 1]
	end
	for i = 0, 2 do
		local role = if i < 2 then "bartender" else "collector"
		local g = if r() < 0.5 then "m" else "f"
		local skill = round(clamp(r(0.35, 0.68) + self.reputation * 0.002, 0.3, 0.8) * 100) / 100
		local potential = round(clamp(skill + r(0.12, 0.35), skill, 0.95) * 100) / 100
		local wage = round(if role == "bartender" then 9 + skill * 24 else 7 + skill * 12)
		table.insert(self.applicants, { id = string.format("app_%d_%d", week, i), name = pick(FIRST_NAMES[g]) .. " " .. pick(SURNAMES),
			role = role, skill = skill, potential = potential, trait = pick(PubState.ROLE_TRAITS[role]), wage = wage,
			fee = round(wage * 3), min_rep = if role == "bartender" then 25 else 10, gender = g, blurb = pick(BLURBS[role]),
			applicant = true })
	end
end

-- ---------------------------------------------------------------- saving
local SAVED = { "pubName", "mode", "cash", "day", "reputation", "upgrades", "stock", "tapUnits", "kegDay", "prices",
	"relationships", "staff", "applicants", "applicantsWeek", "progress", "deliveries", "history", "bookings", "stats", "settings" }

function PubState.toSave(self)
	local t = { version = 1 }
	for _, k in SAVED do
		t[k] = self[k]
	end
	return t
end

function PubState.fromSave(self, t)
	self:reset()
	if type(t) ~= "table" then
		return
	end
	for _, k in SAVED do
		if t[k] ~= nil then
			if type(self[k]) == "table" and type(t[k]) == "table" and k ~= "staff" and k ~= "applicants"
				and k ~= "deliveries" and k ~= "history" then
				for kk, vv in t[k] do
					self[k][kk] = vv
				end
			else
				self[k] = t[k]
			end
		end
	end
	for _, e in self.staff do
		self:staffDefaults(e)
	end
	self:startDay()
end

return PubState
