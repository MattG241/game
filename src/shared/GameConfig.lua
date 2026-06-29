--!strict
--[[
	GameConfig
	----------
	Single source of truth for every tunable value in Underground Arena Fighters,
	a Super Smash Bros-style platform fighter.

	CORE MODEL (read this before tuning combat):
	  * Attacks DON'T drain health — they add a DAMAGE PERCENT to the victim.
	  * The higher a fighter's %, the farther they get launched by the next hit.
	  * You only get KO'd by being launched off the stage into a BLAST ZONE.
	  * Each fighter has a number of STOCKS (lives); lose them all and you're out.

	Designers should only ever need to touch this file to rebalance the game.

	NOTE: Replace every `0` placeholder in `Monetization` with the real asset IDs
	from the Roblox Creator Dashboard once your gamepasses / dev products exist.
	Animation IDs live in Shared/Animations.lua.
]]

local GameConfig = {}

GameConfig.Combat = {
	-- "Health" is only the instakill pool a blast zone empties on a ring-out.
	-- Attacks never touch it; it exists so Humanoid.Died fires on a KO.
	MaxHealth = 100,

	-- Shield / stamina (drained by shielding, dodging, attacking).
	MaxStamina = 100,
	StaminaRegenPerSecond = 16,
	StaminaRegenDelay = 0.5,

	-- DAMAGE the attacks deal, expressed as PERCENT added to the victim.
	PunchPercent = 3.2,
	-- finisher (4th combo hit) and special multiply off the base punch %.
	ComboFinisherMultiplier = 2.6, -- finisher % and knockback boost
	SpecialPercent = 16,

	-- Combo chain.
	PunchStaminaCost = 4,
	PunchCooldown = 0.3,
	ComboWindow = 1.1,
	MaxCombo = 4, -- 4th hit is the launching finisher

	-- KNOCKBACK MODEL (Smash-style):
	--   launchSpeed = (BaseKnockback + victimPercent * KnockbackGrowth) * moveMult
	-- A fresh (0%) fighter barely moves; a 120% fighter goes flying.
	BaseKnockback = 18,
	KnockbackGrowth = 1.15, -- studs/sec of launch added per 1% damage
	PunchKnockbackMult = 0.9,
	FinisherKnockbackMult = 2.5,
	SpecialKnockbackMult = 3.3,
	LaunchUpRatio = 0.6, -- portion of launch applied upward (pop-ups)
	MaxLaunchSpeed = 320,

	-- Hit-stop (impact freeze) — makes hits feel weighty / clip-worthy.
	HitStop = 0.06,
	HeavyHitStop = 0.13, -- finisher / special

	-- Shield (block).
	BlockKnockbackReduction = 0.7, -- 70% of knockback absorbed while shielding
	BlockPercentReduction = 0.6, -- 60% of incoming % absorbed
	BlockStaminaCostPerSecond = 14,
	BlockBreakKnockbackMult = 1.4, -- shield break => extra launch

	-- Dodge / air-dodge (i-frames).
	DodgeStaminaCost = 22,
	DodgeCooldown = 1.0,
	DodgeDistance = 24,
	DodgeDuration = 0.32,

	-- Hit detection (server spherecast).
	HitRange = 7,
	HitRadius = 4.4,
	SpecialRange = 9,
	SpecialRadius = 6,

	-- Special meter (builds as you fight, spend on a big launcher).
	SpecialMeterMax = 100,
	SpecialMeterGainPerHitLanded = 12,
	SpecialMeterGainPerHitTaken = 8,

	-- Platform-fighter mobility (floaty + high jumps for recovery).
	Gravity = 110,
	WalkSpeed = 26,
	JumpPower = 58,
}

-- Stock match flow (replaces best-of-3 rounds).
GameConfig.Match = {
	Stocks = 3, -- lives per fighter
	MatchTime = 180, -- seconds; on timeout, most stocks (then lowest %) wins
	RespawnDelay = 1.2, -- delay after a KO before respawning
	RespawnInvuln = 2.5, -- i-frames on respawn
	RespawnHeight = 34, -- studs above the stage to drop in from
	IntermissionTime = 4,
	StartCountdown = 3, -- "3..2..1..GO"
}

GameConfig.Matchmaking = {
	QueueTickInterval = 1.5,
	LaunchCountdown = 5,
	TeamSize = 1, -- 1 = 1v1. Set to 2 for 2v2.
	AllowParties = true,
}

GameConfig.Progression = {
	BaseXP = 100,
	XPGrowth = 1.22,
	MaxLevel = 100,

	Rewards = {
		WinXP = 60,
		LossXP = 20,
		PerRoundWonXP = 15, -- awarded per surviving STOCK
		PerKOXP = 8,

		WinCoins = 120,
		LossCoins = 35,
		PerRoundWonCoins = 20, -- per surviving stock
	},
}

GameConfig.Monetization = {
	Gamepasses = {
		VIP = 0,
		DoubleRewards = 0,
		SkinPack = 0,
	},
	VIPRewardMultiplier = 1.25,
	DoubleRewardsMultiplier = 2.0,

	Products = {
		Coins500 = 0,
		Coins1200 = 0,
		Coins3000 = 0,
	},
	ProductCoinGrants = {
		Coins500 = 500,
		Coins1200 = 1200,
		Coins3000 = 3000,
	},
}

GameConfig.Data = {
	StoreName = "UAF_PlayerData_v2",
	AutoSaveInterval = 120,
	SessionLockStore = "UAF_SessionLock_v2",
	MaxRetries = 3,
	RetryBackoff = 1, -- exponential (1s, 2s, 4s) — bounds the join hang if misconfigured
}

-- Bright arcade / Smash-style atmosphere: sunny sky, saturated colors, light haze.
GameConfig.Atmosphere = {
	ClockTime = 14, -- bright afternoon
	Brightness = 2.6,
	OutdoorAmbient = Color3.fromRGB(150, 160, 180),
	Ambient = Color3.fromRGB(120, 125, 145),
	FogColor = Color3.fromRGB(180, 215, 255),
	FogEnd = 1400,
	FogStart = 400,
	-- Vivid accent used for lobby/UI pop.
	NeonAccent = Color3.fromRGB(255, 90, 220),
}

return GameConfig
