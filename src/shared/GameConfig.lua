--!strict
--[[
	GameConfig
	----------
	Single source of truth for every tunable value in Underground Arena Fighters.
	Designers should only ever need to touch this file to rebalance the game.

	NOTE: Replace every `0` placeholder in `Monetization` with the real asset IDs
	from the Roblox Creator Dashboard once your gamepasses / dev products exist.
]]

local GameConfig = {}

-- How fast the world feels. Tuned for snappy, skill-based exchanges.
GameConfig.Combat = {
	MaxHealth = 100,
	MaxStamina = 100,
	StaminaRegenPerSecond = 14,
	StaminaRegenDelay = 0.6, -- seconds after spending stamina before regen kicks in

	-- Light attacks / combos
	PunchDamage = 8,
	PunchStaminaCost = 5,
	PunchCooldown = 0.32, -- minimum server-enforced time between punches
	ComboWindow = 1.1, -- chain a punch within this window to grow the combo
	MaxCombo = 4, -- 4th hit is the finisher
	ComboFinisherMultiplier = 1.9,

	-- Defense
	BlockDamageReduction = 0.8, -- 80% damage absorbed while blocking
	BlockStaminaCostPerSecond = 12, -- holding block drains stamina
	BlockBreakKnockback = 28,

	-- Mobility
	DodgeStaminaCost = 25,
	DodgeCooldown = 1.25,
	DodgeDistance = 20,
	DodgeDuration = 0.28, -- i-frames window

	-- Hit detection (server raycast / spherecast)
	HitRange = 6.5, -- studs in front of attacker
	HitRadius = 4.0, -- spherecast radius

	-- Physics feel
	KnockbackForce = 36,
	FinisherKnockbackForce = 70,

	-- Special meter (builds as you fight, spend on a heavy move)
	SpecialMeterMax = 100,
	SpecialMeterGainPerHitLanded = 14,
	SpecialMeterGainPerHitTaken = 9,
	SpecialDamage = 34,
	SpecialStaminaCost = 0,
	SpecialKnockbackForce = 90,
	SpecialRange = 9,
	SpecialRadius = 6,
}

-- Round / match flow.
GameConfig.Round = {
	BestOf = 3, -- first to ceil(BestOf/2) round wins
	RoundTime = 90, -- seconds
	SuddenDeathTime = 30, -- if no KO when timer expires, lowest HP loses; tie => extend
	IntermissionTime = 4, -- between rounds
	StartCountdown = 3, -- "3..2..1..FIGHT"
}

-- Matchmaking queue behaviour.
GameConfig.Matchmaking = {
	QueueTickInterval = 1.5,
	LaunchCountdown = 5, -- seconds shown to matched players before teleport-in
	TeamSize = 1, -- 1 = 1v1. Set to 2 for 2v2 (party support handled in service).
	AllowParties = true,
}

-- Player progression curve & rewards.
GameConfig.Progression = {
	BaseXP = 100, -- XP needed for level 2
	XPGrowth = 1.22, -- each level needs this multiple of the previous
	MaxLevel = 100,

	Rewards = {
		WinXP = 60,
		LossXP = 20,
		PerRoundWonXP = 15,
		PerKOXP = 8,

		WinCoins = 120,
		LossCoins = 35,
		PerRoundWonCoins = 20,
	},
}

-- Monetization. Fill these IDs in from the Creator Dashboard.
GameConfig.Monetization = {
	Gamepasses = {
		VIP = 0, -- rewards boost + exclusive arena access
		DoubleRewards = 0, -- 2x XP & coins
		SkinPack = 0, -- unlocks the premium cosmetic set
	},
	-- Gameplay effects of owning a pass:
	VIPRewardMultiplier = 1.25,
	DoubleRewardsMultiplier = 2.0,

	Products = {
		-- Developer Products grant Fight Coins on purchase.
		Coins500 = 0,
		Coins1200 = 0,
		Coins3000 = 0,
	},
	-- ProductId -> coin amount. Filled at runtime from the Products table above.
	ProductCoinGrants = {
		Coins500 = 500,
		Coins1200 = 1200,
		Coins3000 = 3000,
	},
}

GameConfig.Data = {
	StoreName = "UAF_PlayerData_v2",
	AutoSaveInterval = 120, -- seconds
	SessionLockStore = "UAF_SessionLock_v2",
	MaxRetries = 5,
	RetryBackoff = 2, -- seconds, exponential
}

-- Underground neon ambience applied to Lighting on the server boot.
GameConfig.Atmosphere = {
	ClockTime = 0, -- midnight
	Brightness = 1.5,
	OutdoorAmbient = Color3.fromRGB(20, 16, 30),
	Ambient = Color3.fromRGB(35, 25, 50),
	FogColor = Color3.fromRGB(12, 10, 22),
	FogEnd = 350,
	FogStart = 60,
	NeonAccent = Color3.fromRGB(180, 40, 255),
}

return GameConfig
