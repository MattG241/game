class_name GlassContents
extends RefCounted
## Liquid model for one glass. Volumes are fractions of the glass's brim volume.
##
## Stout: everything poured enters as an unsettled nitro "cascade". Over the
## settle time the cascade separates into dark body and a creamy head; how much
## head it makes depends on how roughly it was poured (angle, hurrying).

const RIM_K := 0.28        # glass radius / height: how far the surface tilts up the rim
const DOME := 0.035        # how far a creamy head can dome above the rim
const FIRST_POUR_IDEAL := Vector2(0.68, 0.82)
const HEAD_IDEAL := Vector2(0.085, 0.16)
const FILL_IDEAL := Vector2(0.975, 1.035)

var drink_id := ""
var serve := ""            # stout, lager, ale, cider, whiskey, soda
var body := 0.0
var cascade := 0.0
var foam := 0.0
var ice := 0.0
var cascade_head_ratio := 0.0
var spilled := 0.0
var stage := 0             # 0 empty, 1 first pour, 2 settling, 3 topping up
var first_pour_level := 0.0
var angle_sum := 0.0
var angle_vol := 0.0
var topup_cascade := -1.0  # unsettled share when the top-up began
var hurried := false
var pouring := false
var finished_at := -1.0    # game-clock seconds when the glass was last poured into
var age := 0.0             # seconds since finished
var strokes := 0           # ale: hand pump strokes
var measure := 0.0         # whiskey / soda: measure dispensed (1.0 = target)
var freshness := 1.0
var wrong_mix := false


func total() -> float:
	return body + cascade + foam


func liquid_level() -> float:
	return body + cascade


func is_empty() -> bool:
	return total() < 0.005 and ice < 0.01


func reset() -> void:
	drink_id = ""
	serve = ""
	body = 0.0
	cascade = 0.0
	foam = 0.0
	ice = 0.0
	cascade_head_ratio = 0.0
	spilled = 0.0
	stage = 0
	first_pour_level = 0.0
	angle_sum = 0.0
	angle_vol = 0.0
	topup_cascade = -1.0
	hurried = false
	pouring = false
	finished_at = -1.0
	age = 0.0
	strokes = 0
	measure = 0.0
	freshness = 1.0
	wrong_mix = false


## Highest the liquid can reach at this tilt before it runs over the rim.
static func rim_limit(tilt_deg: float) -> float:
	var t := deg_to_rad(clampf(tilt_deg, 0.0, 85.0))
	return 1.0 - RIM_K * tan(t)


## Pours for dt seconds. flow is 0..1 (tap handle), tilt in degrees from upright.
## Returns the volume fraction actually drawn from the keg.
func pour(dt: float, flow: float, tilt_deg: float, id: String, serve_type: String) -> float:
	if flow <= 0.001 or dt <= 0.0:
		if pouring:
			stop_pour()
		return 0.0
	if drink_id != "" and drink_id != id and total() > 0.02:
		wrong_mix = true
	drink_id = id
	serve = serve_type
	pouring = true
	var rate := 0.0
	match serve_type:
		"stout":
			rate = 0.082
		"lager", "cider":
			rate = 0.13
		"soda":
			rate = 0.16
		_:
			rate = 0.1
	var dv := flow * rate * dt
	var dev := clampf(absf(tilt_deg - 45.0) / 45.0, 0.0, 1.0)
	match serve_type:
		"stout":
			_pour_stout(dv, flow, tilt_deg, dev)
		"lager", "cider":
			# head forms immediately; an upright pour foams far more
			var ratio := 0.03 + 0.42 * pow(dev, 1.4) + (0.05 if flow < 0.4 else 0.0)
			if serve_type == "cider":
				ratio *= 0.35
			body += dv * (1.0 - ratio)
			foam += dv * ratio * 1.6
		"soda":
			body += dv * 0.97
			foam += dv * 0.03
		_:
			body += dv
	finished_at = -1.0
	age = 0.0
	_spill_check(tilt_deg)
	return dv


func _pour_stout(dv: float, flow: float, tilt_deg: float, dev: float) -> void:
	if stage == 0:
		stage = 1
	elif stage == 2:
		stage = 3
		var lvl := maxf(liquid_level() + foam, 0.001)
		topup_cascade = cascade / lvl
		if topup_cascade > 0.12:
			hurried = true
	var ratio: float
	if stage == 1:
		ratio = 0.07 + 0.30 * pow(dev, 1.3)
		# record the angle used for the first half of the first pour
		if total() < 0.4:
			angle_sum += tilt_deg * dv
			angle_vol += dv
	else:
		# topping up: liquid goes under the head, a gentle flow builds a tight dome
		ratio = 0.18 + 0.28 * flow + 0.25 * clampf(tilt_deg / 45.0, 0.0, 1.0)
		if hurried:
			ratio += 0.1
	var new_total := cascade + dv
	cascade_head_ratio = (cascade_head_ratio * cascade + ratio * dv) / maxf(new_total, 0.0001)
	cascade = new_total


func stop_pour() -> void:
	if not pouring:
		return
	pouring = false
	if serve == "stout" and stage == 1:
		first_pour_level = total()
		stage = 2
	finished_at = 0.0
	age = 0.0


func _spill_check(tilt_deg: float) -> void:
	var limit := rim_limit(tilt_deg) + (DOME if tilt_deg < 8.0 else 0.0)
	var over := total() - limit
	if over <= 0.0:
		return
	# foam runs over first, then liquid
	var from_foam := minf(foam, over)
	foam -= from_foam
	over -= from_foam
	var from_casc := minf(cascade, over)
	cascade -= from_casc
	over -= from_casc
	body = maxf(0.0, body - over)
	spilled += from_foam * 0.4 + from_casc + over


## Lets the nitro cascade settle and the head slowly age.
func settle(dt: float, settle_seconds: float) -> void:
	if cascade > 0.0:
		var tau := maxf(settle_seconds / 4.0, 0.1)
		if pouring:
			tau *= 4.0  # the running tap keeps the glass churning
		var ds := cascade * (1.0 - exp(-dt / tau))
		if cascade < 0.0005 and not pouring:
			ds = cascade
		body += ds * (1.0 - cascade_head_ratio)
		foam += ds * cascade_head_ratio
		cascade -= ds
	if not pouring and total() > 0.0:
		age += dt
		# heads slowly collapse; lager faster than stout
		var decay := 0.0006 if serve == "stout" else 0.0025
		var lost := foam * decay * dt
		foam -= lost
		body += lost * 0.25


func settled_fraction() -> float:
	var lvl := liquid_level()
	if lvl <= 0.0:
		return 1.0
	return 1.0 - cascade / lvl


## Predicts the final head and fill if the cascade were allowed to finish settling.
func predicted() -> Dictionary:
	return {
		"head": foam + cascade * cascade_head_ratio,
		"fill": total(),
		"body": body + cascade * (1.0 - cascade_head_ratio),
	}


## Scores the drink 0..100 for the given serving conditions and returns feedback.
func evaluate(glass_dirt: float, beer_quality_bonus := 0.0) -> Dictionary:
	match serve:
		"stout":
			return _evaluate_stout(glass_dirt, beer_quality_bonus)
		"lager", "cider":
			return _evaluate_simple(glass_dirt, beer_quality_bonus, Vector2(0.06, 0.13) if serve == "lager" else Vector2(0.0, 0.06))
		_:
			return _evaluate_simple(glass_dirt, beer_quality_bonus, Vector2(0.0, 0.05))


func _evaluate_stout(glass_dirt: float, bonus: float) -> Dictionary:
	var notes: Array[String] = []
	var pred := predicted()
	var head: float = pred["head"]
	var fill: float = pred["fill"]
	var score := 0.0
	# 1. initial angle (15)
	var avg_angle := angle_sum / angle_vol if angle_vol > 0.0 else 0.0
	var angle_pts := 15.0 * clampf(1.0 - maxf(0.0, absf(avg_angle - 45.0) - 7.0) / 30.0, 0.0, 1.0)
	score += angle_pts
	if angle_pts < 8.0:
		notes.append("Tilt to 45° for the first pour")
	# 2. first pour level (15)
	var fp_pts := 15.0 * _band_score(first_pour_level, FIRST_POUR_IDEAL, 0.25)
	score += fp_pts
	if stage <= 2 and topup_cascade < 0.0:
		fp_pts = 0.0
	# 3. let it settle (15)
	var settle_pts := 0.0
	if topup_cascade >= 0.0:
		settle_pts = 15.0 * clampf(1.0 - (topup_cascade - 0.06) / 0.4, 0.0, 1.0)
		if topup_cascade > 0.12:
			notes.append("Let it settle before topping up")
	else:
		notes.append("Two-part pour: stop at ¾, settle, then top up")
	score += settle_pts
	# 4. fill (20)
	var fill_pts := 20.0 * _band_score(fill, FILL_IDEAL, 0.15)
	score += fill_pts
	# 5. head (20)
	var head_pts := 20.0 * _band_score(head, HEAD_IDEAL, 0.08)
	score += head_pts
	# 6. spills (10)
	var spill_pts := 10.0 * clampf(1.0 - spilled / 0.08, 0.0, 1.0)
	score += spill_pts
	# 7. still settling when served
	if cascade / maxf(liquid_level(), 0.001) > 0.25:
		score -= 12.0
		notes.append("Served before it settled")
	var verdict := _verdict(score, head, fill)
	return _finish(score, verdict, notes, glass_dirt, bonus, head, fill)


func _evaluate_simple(glass_dirt: float, bonus: float, head_band: Vector2) -> Dictionary:
	var notes: Array[String] = []
	var head := foam
	var fill := total() + ice * 0.5
	var score := 0.0
	score += 40.0 * _band_score(fill, Vector2(0.93, 1.03), 0.2)
	score += 35.0 * _band_score(head, head_band, 0.08)
	score += 15.0 * clampf(1.0 - spilled / 0.08, 0.0, 1.0)
	score += 10.0
	if serve == "cider" and GameData.drink(drink_id).get("ice", true) and ice < 0.1:
		score -= 15.0
		notes.append("Cider is served over ice")
	var verdict := _verdict(score, head, fill, head_band)
	return _finish(score, verdict, notes, glass_dirt, bonus, head, fill)


func _finish(score: float, verdict: String, notes: Array[String], glass_dirt: float, bonus: float, head: float, fill: float) -> Dictionary:
	if glass_dirt > 0.2:
		score -= 30.0 * glass_dirt
		notes.append("That glass wasn't clean!")
		verdict = "Dirty Glass"
	if wrong_mix:
		score -= 40.0
		notes.append("Two drinks mixed in one glass")
	score *= 0.85 + 0.15 * freshness
	if freshness < 0.8:
		notes.append("The keg is past its best")
	if age > 150.0:
		score -= 15.0
		notes.append("Gone flat waiting on the bar")
		verdict = "Flat"
	elif age > 70.0:
		score -= 5.0
	score += bonus
	score = clampf(score, 0.0, 100.0)
	return {"score": roundi(score), "verdict": verdict, "notes": notes, "head": head, "fill": fill, "spilled": spilled}


func _verdict(score: float, head: float, fill: float, head_band := HEAD_IDEAL) -> String:
	if spilled > 0.06:
		return "Messy, Spilled"
	if fill < 0.9:
		return "Underfilled"
	if head > head_band.y + 0.06:
		return "Too Much Foam"
	if head < head_band.x - 0.04 and head_band.x > 0.0:
		return "Thin Head"
	if hurried and serve == "stout":
		return "Rushed Pint"
	if score >= 90.0:
		if _band_score(head, head_band, 0.08) >= 0.999 and _band_score(fill, FILL_IDEAL, 0.15) >= 0.999:
			return "Perfect Head"
		return "Beautiful Pint"
	if score >= 75.0:
		return "Good Pint"
	if score >= 55.0:
		return "Decent Pint"
	return "Poor Pint"


## 1 inside [band.x, band.y], falling linearly to 0 at `soft` outside it.
static func _band_score(v: float, band: Vector2, soft: float) -> float:
	if v < band.x:
		return clampf(1.0 - (band.x - v) / soft, 0.0, 1.0)
	if v > band.y:
		return clampf(1.0 - (v - band.y) / soft, 0.0, 1.0)
	return 1.0


func to_dict() -> Dictionary:
	return {"drink_id": drink_id, "serve": serve, "body": body, "cascade": cascade, "foam": foam, "ice": ice,
		"ratio": cascade_head_ratio, "spilled": spilled, "stage": stage, "first": first_pour_level,
		"angle_sum": angle_sum, "angle_vol": angle_vol, "topup": topup_cascade, "hurried": hurried}
