-- What's in one glass, and how good it is. A port of the phone game's GlassContents.
-- Volumes are fractions of the glass's brim volume.
--
-- Stout: everything poured enters as an unsettled nitro "cascade". Over the settle time the
-- cascade separates into dark body and a creamy head; how much head it makes depends on how
-- roughly it was poured (the angle, hurrying the top-up).
--
-- Pure Luau (no Roblox APIs), so the same code runs on the server, the client's pour screen,
-- and the plain-Luau unit tests.

local Contents = {}
Contents.__index = Contents

local RIM_K = 0.28
local DOME = 0.035
local FIRST_POUR_IDEAL = { 0.68, 0.82 }
local HEAD_IDEAL = { 0.085, 0.16 }
local FILL_IDEAL = { 0.975, 1.035 }

local function clamp(v: number, a: number, b: number): number
	return math.max(a, math.min(b, v))
end

function Contents.new()
	local self = setmetatable({}, Contents)
	self:reset()
	return self
end

function Contents.reset(self)
	self.drinkId = ""
	self.serve = ""
	self.body = 0
	self.cascade = 0
	self.foam = 0
	self.ice = 0
	self.headRatio = 0
	self.spilled = 0
	self.stage = 0
	self.firstPour = 0
	self.angleSum = 0
	self.angleVol = 0
	self.topup = -1
	self.hurried = false
	self.pouring = false
	self.age = 0
	self.freshness = 1
	self.wrongMix = false
end

function Contents.total(self): number
	return self.body + self.cascade + self.foam
end

function Contents.liquidLevel(self): number
	return self.body + self.cascade
end

function Contents.isEmpty(self): boolean
	return self:total() < 0.005 and self.ice < 0.01
end

-- Highest the liquid can reach at this tilt before it runs over the rim.
function Contents.rimLimit(tiltDeg: number): number
	return 1 - RIM_K * math.tan(math.rad(clamp(tiltDeg, 0, 85)))
end

-- Pours for dt seconds. flow is 0..1 (the tap handle), tilt in degrees from upright.
-- Returns the volume drawn from the keg.
function Contents.pour(self, dt: number, flow: number, tiltDeg: number, id: string, serveType: string): number
	if flow <= 0.001 or dt <= 0 then
		if self.pouring then
			self:stopPour()
		end
		return 0
	end
	if self.drinkId ~= "" and self.drinkId ~= id and self:total() > 0.02 then
		self.wrongMix = true
	end
	self.drinkId = id
	self.serve = serveType
	self.pouring = true
	local rate = 0.1
	if serveType == "stout" then
		rate = 0.082
	elseif serveType == "lager" or serveType == "cider" then
		rate = 0.13
	elseif serveType == "soda" then
		rate = 0.16
	end
	local dv = flow * rate * dt
	local dev = clamp(math.abs(tiltDeg - 45) / 45, 0, 1)
	if serveType == "stout" then
		self:_pourStout(dv, flow, tiltDeg, dev)
	elseif serveType == "lager" or serveType == "cider" then
		-- the head forms straight away; an upright pour foams far more
		local ratio = 0.03 + 0.42 * dev ^ 1.4 + (if flow < 0.4 then 0.05 else 0)
		if serveType == "cider" then
			ratio *= 0.35
		end
		self.body += dv * (1 - ratio)
		self.foam += dv * ratio * 1.6
	elseif serveType == "soda" then
		self.body += dv * 0.97
		self.foam += dv * 0.03
	else
		self.body += dv
	end
	self.age = 0
	self:_spillCheck(tiltDeg)
	return dv
end

function Contents._pourStout(self, dv: number, flow: number, tiltDeg: number, dev: number)
	if self.stage == 0 then
		self.stage = 1
	elseif self.stage == 2 then
		self.stage = 3
		local lvl = math.max(self:liquidLevel() + self.foam, 0.001)
		self.topup = self.cascade / lvl
		if self.topup > 0.12 then
			self.hurried = true
		end
	end
	local ratio
	if self.stage == 1 then
		ratio = 0.07 + 0.30 * dev ^ 1.3
		if self:total() < 0.4 then
			self.angleSum += tiltDeg * dv
			self.angleVol += dv
		end
	else
		-- topping up: under the head, a gentle flow builds a tight dome
		ratio = 0.18 + 0.28 * flow + 0.25 * clamp(tiltDeg / 45, 0, 1)
		if self.hurried then
			ratio += 0.1
		end
	end
	local newTotal = self.cascade + dv
	self.headRatio = (self.headRatio * self.cascade + ratio * dv) / math.max(newTotal, 0.0001)
	self.cascade = newTotal
end

function Contents.stopPour(self)
	if not self.pouring then
		return
	end
	self.pouring = false
	if self.serve == "stout" and self.stage == 1 then
		self.firstPour = self:total()
		self.stage = 2
	end
	self.age = 0
end

function Contents._spillCheck(self, tiltDeg: number)
	local limit = Contents.rimLimit(tiltDeg) + (if tiltDeg < 8 then DOME else 0)
	local over = self:total() - limit
	if over <= 0 then
		return
	end
	-- foam runs over first, then liquid
	local fromFoam = math.min(self.foam, over)
	self.foam -= fromFoam
	over -= fromFoam
	local fromCasc = math.min(self.cascade, over)
	self.cascade -= fromCasc
	over -= fromCasc
	self.body = math.max(0, self.body - over)
	self.spilled += fromFoam * 0.4 + fromCasc + over
end

-- Lets the nitro cascade settle and the head slowly age.
function Contents.settle(self, dt: number, settleSeconds: number)
	if self.cascade > 0 then
		local tau = math.max(settleSeconds / 4, 0.1)
		if self.pouring then
			tau *= 4
		end
		local ds = self.cascade * (1 - math.exp(-dt / tau))
		if self.cascade < 0.0005 and not self.pouring then
			ds = self.cascade
		end
		self.body += ds * (1 - self.headRatio)
		self.foam += ds * self.headRatio
		self.cascade -= ds
	end
	if not self.pouring and self:total() > 0 then
		self.age += dt
		local decay = if self.serve == "stout" then 0.0006 else 0.0025
		local lost = self.foam * decay * dt
		self.foam -= lost
		self.body += lost * 0.25
	end
end

function Contents.settledFraction(self): number
	local lvl = self:liquidLevel()
	if lvl <= 0 then
		return 1
	end
	return 1 - self.cascade / lvl
end

-- The head and fill once the cascade has finished settling.
function Contents.predicted(self): (number, number)
	return self.foam + self.cascade * self.headRatio, self:total()
end

local function band(v: number, b: { number }, soft: number): number
	if v < b[1] then
		return clamp(1 - (b[1] - v) / soft, 0, 1)
	elseif v > b[2] then
		return clamp(1 - (v - b[2]) / soft, 0, 1)
	end
	return 1
end
Contents.band = band

-- Scores the drink 0..100 and returns {score, verdict, notes, head, fill, spilled}.
-- iceExpected: cider is served over ice when the drink says so.
function Contents.evaluate(self, glassDirt: number, bonus: number?, iceExpected: boolean?): { [string]: any }
	local extra = bonus or 0
	if self.serve == "stout" then
		return self:_evaluateStout(glassDirt, extra)
	elseif self.serve == "lager" then
		return self:_evaluateSimple(glassDirt, extra, { 0.06, 0.13 }, false)
	elseif self.serve == "cider" then
		return self:_evaluateSimple(glassDirt, extra, { 0, 0.06 }, iceExpected == true)
	end
	return self:_evaluateSimple(glassDirt, extra, { 0, 0.05 }, false)
end

function Contents._evaluateStout(self, glassDirt: number, bonus: number): { [string]: any }
	local notes = {}
	local head, fill = self:predicted()
	local score = 0
	local avgAngle = if self.angleVol > 0 then self.angleSum / self.angleVol else 0
	local anglePts = 15 * clamp(1 - math.max(0, math.abs(avgAngle - 45) - 7) / 30, 0, 1)
	score += anglePts
	if anglePts < 8 then
		table.insert(notes, "Tilt to 45° for the first pour")
	end
	score += 15 * band(self.firstPour, FIRST_POUR_IDEAL, 0.25)
	if self.topup >= 0 then
		score += 15 * clamp(1 - (self.topup - 0.06) / 0.4, 0, 1)
		if self.topup > 0.12 then
			table.insert(notes, "Let it settle before topping up")
		end
	else
		table.insert(notes, "Two-part pour: stop at ¾, settle, then top up")
	end
	score += 20 * band(fill, FILL_IDEAL, 0.15)
	score += 20 * band(head, HEAD_IDEAL, 0.08)
	score += 10 * clamp(1 - self.spilled / 0.08, 0, 1)
	if self.cascade / math.max(self:liquidLevel(), 0.001) > 0.25 then
		score -= 12
		table.insert(notes, "Served before it settled")
	end
	return self:_finish(score, self:_verdict(score, head, fill, HEAD_IDEAL), notes, glassDirt, bonus, head, fill)
end

function Contents._evaluateSimple(self, glassDirt: number, bonus: number, headBand: { number }, iceExpected: boolean): { [string]: any }
	local notes = {}
	local head = self.foam
	local fill = self:total() + self.ice * 0.5
	local score = 40 * band(fill, { 0.93, 1.03 }, 0.2) + 35 * band(head, headBand, 0.08)
		+ 15 * clamp(1 - self.spilled / 0.08, 0, 1) + 10
	if iceExpected and self.ice < 0.1 then
		score -= 15
		table.insert(notes, "Cider is served over ice")
	end
	return self:_finish(score, self:_verdict(score, head, fill, headBand), notes, glassDirt, bonus, head, fill)
end

function Contents._finish(self, score: number, verdict: string, notes: { string }, glassDirt: number, bonus: number, head: number, fill: number): { [string]: any }
	if glassDirt > 0.2 then
		score -= 30 * glassDirt
		table.insert(notes, "That glass wasn't clean!")
		verdict = "Dirty Glass"
	end
	if self.wrongMix then
		score -= 40
		table.insert(notes, "Two drinks mixed in one glass")
	end
	score *= 0.85 + 0.15 * self.freshness
	if self.freshness < 0.8 then
		table.insert(notes, "The keg is past its best")
	end
	if self.age > 150 then
		score -= 15
		table.insert(notes, "Gone flat waiting on the bar")
		verdict = "Flat"
	elseif self.age > 70 then
		score -= 5
	end
	score = clamp(score + bonus, 0, 100)
	return { score = math.floor(score + 0.5), verdict = verdict, notes = notes, head = head, fill = fill, spilled = self.spilled }
end

function Contents._verdict(self, score: number, head: number, fill: number, headBand: { number }): string
	if self.spilled > 0.06 then
		return "Messy, Spilled"
	end
	if self.serve == "whiskey" or self.serve == "soda" then
		local w = self.serve == "whiskey"
		if fill < 0.9 then
			return if w then "Short Measure" else "Underfilled"
		elseif score >= 90 then
			return if w then "Spot-on Measure" else "Perfect Fill"
		elseif score >= 75 then
			return if w then "Good Measure" else "Good Fill"
		end
		return if w then "Sloppy Measure" else "Poor Fill"
	end
	if fill < 0.9 then
		return "Underfilled"
	elseif head > headBand[2] + 0.06 then
		return "Too Much Foam"
	elseif head < headBand[1] - 0.04 and headBand[1] > 0 then
		return "Thin Head"
	elseif self.hurried and self.serve == "stout" then
		return "Rushed Pint"
	elseif score >= 90 then
		if band(head, headBand, 0.08) >= 0.999 and band(fill, FILL_IDEAL, 0.15) >= 0.999 then
			return "Perfect Head"
		end
		return "Beautiful Pint"
	elseif score >= 75 then
		return "Good Pint"
	elseif score >= 55 then
		return "Decent Pint"
	end
	return "Poor Pint"
end

local FIELDS = { "drinkId", "serve", "body", "cascade", "foam", "ice", "headRatio", "spilled", "stage",
	"firstPour", "angleSum", "angleVol", "topup", "hurried", "age", "freshness", "wrongMix" }

-- A plain table for sending between the server and the pour screen.
function Contents.toTable(self): { [string]: any }
	local t = {}
	for _, k in FIELDS do
		t[k] = self[k]
	end
	return t
end

function Contents.fromTable(t: { [string]: any }?)
	local c = Contents.new()
	if t then
		for _, k in FIELDS do
			if t[k] ~= nil then
				c[k] = t[k]
			end
		end
	end
	c.pouring = false
	return c
end

return Contents
