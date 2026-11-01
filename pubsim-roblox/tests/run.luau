-- Unit tests for the game's rules (pour physics and scoring, the economy, staff, order pacing).
-- Run with the plain Luau interpreter: luau tests/run.luau (after tools/build_place.py has written
-- build/Data.luau). They need no Roblox: the modules under test are pure Luau.

local Contents = require("../src/shared/Contents")
local PubState = require("../src/shared/PubState")
local Dispatcher = require("../src/shared/Dispatcher")
local Data = require("../build/Data")

local passed, failed = 0, 0
local function check(ok, name)
	if ok then
		passed += 1
		print("  PASS  " .. name)
	else
		failed += 1
		print("  FAIL  " .. name)
	end
end

-- a careful two-part stout: 45° to three-quarters, settle, top up upright
local function perfectStout()
	local c = Contents.new()
	local tilt = 45
	local guard = 0
	while c:total() < 0.75 and guard < 2000 do
		guard += 1
		if c:total() > 0.45 then
			tilt = math.max(4, tilt - 2)
		end
		c:pour(0.05, 1, tilt, "stout", "stout")
	end
	c:stopPour()
	for _ = 1, 600 do
		c:settle(0.1, 12)
	end
	guard = 0
	while c:total() < 1.0 and guard < 2000 do
		guard += 1
		c:pour(0.05, 0.6, 0, "stout", "stout")
		c:settle(0.05, 12)
	end
	c:stopPour()
	for _ = 1, 600 do
		c:settle(0.1, 12)
	end
	return c
end

print("Pouring")
do
	local c = perfectStout()
	local r = c:evaluate(0, 0, false)
	check(r.score >= 80, string.format("a careful two-part stout scores well (%d, %s)", r.score, r.verdict))
	check(c.stage == 3 and c.topup >= 0 and c.topup < 0.12, "the top-up came after it settled")
	local u = Contents.new()
	u:pour(2, 1, 45, "stout", "stout")
	u:stopPour()
	for _ = 1, 300 do
		u:settle(0.1, 12)
	end
	check(u:evaluate(0, 0, false).verdict == "Underfilled", "a short pint is called underfilled")
	local o = Contents.new()
	for _ = 1, 400 do
		o:pour(0.05, 1, 10, "lager", "lager")
	end
	check(o.spilled > 0.05, "pouring on past the brim spills")
	local h = Contents.new()
	h:pour(5, 1, 45, "stout", "stout")
	h:stopPour()
	h:pour(4, 1, 0, "stout", "stout")
	check(h.hurried, "topping up before it settles is hurried")
	local t = Contents.fromTable(perfectStout():toTable())
	check(math.abs(t:total() - perfectStout():total()) < 1e-6, "contents survive a trip to the client and back")
	local d = perfectStout():evaluate(0.6, 0, false)
	check(d.verdict == "Dirty Glass", "a dirty glass is noticed")
end

print("The pub's money and stock")
do
	local s = PubState.new(Data)
	s:newGame("career", "Test")
	check(s.cash == Data.economy.start_cash and s.phase == "prep" and s.day == 1, "a new game starts in the morning with the starting cash")
	check(s:drinkAvailable("stout") and not s:drinkAvailable("lager"), "stout from the start; lager needs its tap")
	local before = s.cash
	s:earn(5.2, "sales")
	check(math.abs(s.cash - before - 5.2) < 1e-9 and s.today.sales == 5.2, "sales go in the till and the books")
	check(not s:spend(1e6, "other") and s:spend(1, "other"), "spending stops at what's in the till")
	check(s:drawUnits("stout", 1) and math.abs(s:servesLeft("stout") - (Data.drinks[1].units_per_stock - 1)) < 1e-9, "a serve comes out of the keg")
	s.kegDay.stout = s.day - 6
	check(s:kegStale("stout"), "an old keg goes stale")
	local waste = s.today.wasted_units
	check(s:changeKeg("stout") and s:freshness("stout") == 1 and s.today.wasted_units > waste, "swapping a stale keg pours the rest away")
	s.cash = 1000
	check(s:buyUpgrade("lamps") and s:hasUpgrade("lamps") and s:getMod("atmosphere") > 0, "an upgrade is bought and takes effect")
	check(not s:buyUpgrade("lamps"), "and can't be bought twice")
	check(s:orderStock("stout", 1) and s:pendingDelivery("stout") == 1, "stock is ordered for tomorrow")
	s:openPub()
	check(s.phase == "open" and s.hour >= 16, "flipping the sign opens the pub")
	local goals = s:dailyGoals()
	check(#goals == 3, "three goals a day")
	local summary = s:endDay()
	check(summary.day == 1 and s.day == 2 and s.phase == "prep" and s.stock.stout >= 1, "closing up moves to tomorrow, and the delivery arrives")
	check(summary.rent == Data.economy.rent_per_day, "rent is paid at close")
	local saved = s:toSave()
	local s2 = PubState.new(Data)
	s2:fromSave(saved)
	check(s2.day == s.day and math.abs(s2.cash - s.cash) < 1e-6 and s2:hasUpgrade("lamps"), "a saved pub loads back the same")
end

print("Staff")
do
	local s = PubState.new(Data)
	s:newGame("career", "Staff")
	s.cash = 2000
	s.reputation = 60
	check(s:hireBlock("ciaran") == "" and s:hire("ciaran"), "Ciarán can be taken on")
	local e = s:staffEntry("ciaran")
	check(#e.rota == 7 and e.trait == "keen" and e.potential > e.skill, "staff carry a rota, a trait and their potential")
	check(s:wagesToday() == e.wage, "tonight's wages")
	s:setRota("ciaran", s:weekday(), false)
	check(s:wagesToday() == 0 and #s:staffOnToday() == 0, "a night off costs nothing")
	s:setRota("ciaran", s:weekday(), true)
	e.skill = 0.69
	e.potential = 0.9
	for _ = 1, 6 do
		s:staffNote("ciaran", "served")
	end
	check(PubState.staffLevel(e.skill) == 4 and e.raiseAsk > e.wage, "experience brings a level and a request for a raise")
	local w0 = e.wage
	s:agreeRaise("ciaran")
	check(e.wage > w0, "agreeing a raise")
	e.morale = 0.1
	s:staffEndOfNight()
	check(e.notice == 2, "someone fed up hands in their notice")
	check(s:giveBonus("ciaran") and e.notice == 0, "a bonus keeps them on")
	s:refreshApplicants(true)
	check(#s.applicants == 3 and s.applicants[1].trait ~= nil, "new applicants every week")
	local saturday = (5 - s:weekday() + 7) % 7
	local monday = (0 - s:weekday() + 7) % 7
	check(s:busyForecast(saturday) > s:busyForecast(monday), "Saturday looks busier than Monday")
	local cash0 = s.cash
	s:fire("ciaran")
	check(not s:isHired("ciaran") and cash0 - s.cash == e.wage, "letting someone go pays a night's notice")
end

print("Order pacing")
do
	local s = PubState.new(Data)
	s:newGame("career", "Pace")
	local d = Dispatcher.new(s)
	check(d:orderInterval(1, false) > 30, "orders come at a manageable pace on day one")
	d:add("a")
	d:add("b")
	local sent = d:tick(0.1, 0, 1, false, function()
		return true
	end)
	check(sent == "a", "the first waiting customer is called up")
	local again = d:tick(0.1, 0, 1, false, function()
		return true
	end)
	check(again == nil, "the next waits for the pace to allow")
	local _, hard = d:caps(1)
	check(d:tick(1000, hard, 1, false, function()
		return true
	end) == nil, "nobody's called up when the bar is at its limit")
end

print(string.format("RESULT: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
