--!strict
--[[
	Progression
	-----------
	Pure functions describing the XP curve and level lookups. No side effects,
	safe to require on both client (for UI prediction) and server (authority).
]]

local GameConfig = require(script.Parent.GameConfig)

local Progression = {}

-- XP required to advance FROM `level` TO `level + 1`.
function Progression.xpForLevel(level: number): number
	local cfg = GameConfig.Progression
	if level < 1 then
		level = 1
	end
	return math.floor(cfg.BaseXP * (cfg.XPGrowth ^ (level - 1)) + 0.5)
end

-- Given a running total of lifetime XP, resolve {level, xpIntoLevel, xpForNext}.
function Progression.resolve(totalXP: number): { level: number, xpIntoLevel: number, xpForNext: number, progress: number }
	local cfg = GameConfig.Progression
	local level = 1
	local remaining = math.max(0, math.floor(totalXP))

	while level < cfg.MaxLevel do
		local need = Progression.xpForLevel(level)
		if remaining < need then
			break
		end
		remaining -= need
		level += 1
	end

	local xpForNext = (level >= cfg.MaxLevel) and 0 or Progression.xpForLevel(level)
	local progress = xpForNext > 0 and (remaining / xpForNext) or 1
	return {
		level = level,
		xpIntoLevel = remaining,
		xpForNext = xpForNext,
		progress = progress,
	}
end

-- Compute the reward bundle for a finished match.
-- `outcome` is "win" | "loss". `multiplier` folds in gamepass boosts.
function Progression.matchRewards(outcome: string, roundsWon: number, kos: number, multiplier: number)
	local r = GameConfig.Progression.Rewards
	multiplier = multiplier or 1

	local xp, coins
	if outcome == "win" then
		xp = r.WinXP + roundsWon * r.PerRoundWonXP + kos * r.PerKOXP
		coins = r.WinCoins + roundsWon * r.PerRoundWonCoins
	else
		xp = r.LossXP + roundsWon * r.PerRoundWonXP + kos * r.PerKOXP
		coins = r.LossCoins + roundsWon * r.PerRoundWonCoins
	end

	return {
		xp = math.floor(xp * multiplier),
		coins = math.floor(coins * multiplier),
	}
end

return Progression
