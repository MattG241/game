--!strict
--[[
	PlayerService
	-------------
	Owns the player lifecycle: load data on join, build leaderstats, push the
	profile snapshot to the client, apply equipped cosmetics to the character,
	and award match rewards / coins.

	Other services call into this for any profile mutation so that every change
	funnels through one place that also replicates to the owning client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local Progression = require(Shared.Progression)

local DataService = require(script.Parent.DataService)

local PlayerService = {}

-- Set by MonetizationService.start so we can read live multipliers without a require cycle.
local rewardMultiplierFn: ((Player) -> number)? = nil
function PlayerService.setRewardMultiplierProvider(fn: (Player) -> number)
	rewardMultiplierFn = fn
end

local function pushProfile(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local resolved = Progression.resolve(profile.xp)
	Remotes.get("ProfileChanged"):FireClient(player, {
		coins = profile.coins,
		xp = profile.xp,
		level = resolved.level,
		xpIntoLevel = resolved.xpIntoLevel,
		xpForNext = resolved.xpForNext,
		stats = profile.stats,
		cosmetics = profile.cosmetics,
		settings = profile.settings,
	})
end
PlayerService.pushProfile = pushProfile

local function updateLeaderstats(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local resolved = Progression.resolve(profile.xp)
	;(stats:FindFirstChild("Level") :: IntValue).Value = resolved.level
	;(stats:FindFirstChild("Wins") :: IntValue).Value = profile.stats.wins
	;(stats:FindFirstChild("Coins") :: IntValue).Value = profile.coins
end

-- Visually apply a cosmetic to a player's current character.
function PlayerService.applyCosmetic(player: Player)
	local profile = DataService.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end
	local cosmetic = Cosmetics.get(profile.cosmetics.equipped) or Cosmetics.get(Cosmetics.DefaultId)
	if not cosmetic then
		return
	end

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			-- Keep the head a touch lighter so faces read.
			if part.Name == "Head" then
				part.Color = cosmetic.accent
				part.Material = cosmetic.material
			else
				part.Color = cosmetic.bodyColor
				part.Material = cosmetic.material
			end
		end
	end

	-- Accent highlight for that neon arena look.
	local existing = character:FindFirstChild("CosmeticGlow")
	if existing then
		existing:Destroy()
	end
	local hl = Instance.new("Highlight")
	hl.Name = "CosmeticGlow"
	hl.FillTransparency = 1
	hl.OutlineColor = cosmetic.accent
	hl.OutlineTransparency = 0.2
	hl.Parent = character
end

-- ---------------------------------------------------------------------------
-- Profile mutations (all funnel through here so the client stays in sync)
-- ---------------------------------------------------------------------------

function PlayerService.addCoins(player: Player, amount: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	profile.coins = math.max(0, profile.coins + amount)
	updateLeaderstats(player)
	pushProfile(player)
end

function PlayerService.trySpendCoins(player: Player, amount: number): boolean
	local profile = DataService.get(player)
	if not profile or profile.coins < amount then
		return false
	end
	profile.coins -= amount
	updateLeaderstats(player)
	pushProfile(player)
	return true
end

-- Award the result of a finished match.
function PlayerService.awardMatch(player: Player, outcome: string, roundsWon: number, kos: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local multiplier = rewardMultiplierFn and rewardMultiplierFn(player) or 1
	local rewards = Progression.matchRewards(outcome, roundsWon, kos, multiplier)

	local beforeLevel = Progression.resolve(profile.xp).level
	profile.xp += rewards.xp
	profile.coins += rewards.coins
	profile.stats.matches += 1
	profile.stats.kos += kos
	if outcome == "win" then
		profile.stats.wins += 1
	else
		profile.stats.losses += 1
	end
	local afterLevel = Progression.resolve(profile.xp).level

	updateLeaderstats(player)
	pushProfile(player)

	Remotes.get("Notify"):FireClient(player, {
		text = ("%s  +%d XP  +%d Coins"):format(outcome == "win" and "VICTORY!" or "Defeat", rewards.xp, rewards.coins),
		color = outcome == "win" and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 110, 110),
	})

	if afterLevel > beforeLevel then
		Remotes.get("Notify"):FireClient(player, {
			text = ("LEVEL UP!  You are now Level %d"):format(afterLevel),
			color = GameConfig.Atmosphere.NeonAccent,
		})
	end

	return rewards
end

-- Equip a cosmetic the player owns. Returns ok.
function PlayerService.equipCosmetic(player: Player, cosmeticId: string): boolean
	local profile = DataService.get(player)
	local cosmetic = Cosmetics.get(cosmeticId)
	if not profile or not cosmetic then
		return false
	end
	if not profile.cosmetics.owned[cosmeticId] then
		return false
	end
	profile.cosmetics.equipped = cosmeticId
	PlayerService.applyCosmetic(player)
	pushProfile(player)
	return true
end

-- Grant ownership of a cosmetic (from a coin purchase or gamepass).
function PlayerService.grantCosmetic(player: Player, cosmeticId: string): boolean
	local profile = DataService.get(player)
	local cosmetic = Cosmetics.get(cosmeticId)
	if not profile or not cosmetic then
		return false
	end
	profile.cosmetics.owned[cosmeticId] = true
	pushProfile(player)
	return true
end

-- Unlock any level-gated cosmetics the player now qualifies for.
local function syncLevelUnlocks(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local level = Progression.resolve(profile.xp).level
	local changed = false
	for _, c in Cosmetics.List do
		if c.unlock == "level" and c.level and level >= c.level and not profile.cosmetics.owned[c.id] then
			profile.cosmetics.owned[c.id] = true
			changed = true
		end
	end
	if changed then
		pushProfile(player)
	end
end
PlayerService.syncLevelUnlocks = syncLevelUnlocks

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = GameConfig.Combat.MaxHealth
	humanoid.Health = GameConfig.Combat.MaxHealth
	-- Defer one frame so all limbs exist before recoloring.
	task.defer(function()
		PlayerService.applyCosmetic(player)
	end)
end

local function onPlayerAdded(player: Player)
	-- Load persistent data (yields).
	DataService.load(player)

	-- Build leaderstats.
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Level", "Wins", "Coins" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = stats
	end
	stats.Parent = player

	updateLeaderstats(player)
	syncLevelUnlocks(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	-- Initial profile push (client may also pull via RequestProfile).
	pushProfile(player)

	-- Spawn them into the lobby (CharacterAutoLoads is off — we own spawning).
	player:LoadCharacter()
end

local function onPlayerRemoving(player: Player)
	DataService.release(player)
end

function PlayerService.start()
	-- Handle the RequestProfile RemoteFunction.
	local requestProfile = Remotes.get("RequestProfile") :: RemoteFunction
	requestProfile.OnServerInvoke = function(player)
		local profile = DataService.get(player)
		if not profile then
			return nil
		end
		local resolved = Progression.resolve(profile.xp)
		return {
			coins = profile.coins,
			xp = profile.xp,
			level = resolved.level,
			xpIntoLevel = resolved.xpIntoLevel,
			xpForNext = resolved.xpForNext,
			stats = profile.stats,
			cosmetics = profile.cosmetics,
			settings = profile.settings,
		}
	end

	-- Equip cosmetic event.
	Remotes.get("EquipCosmetic").OnServerEvent:Connect(function(player, cosmeticId)
		if typeof(cosmeticId) == "string" then
			PlayerService.equipCosmetic(player, cosmeticId)
		end
	end)

	-- Buy cosmetic with coins (RemoteFunction so client gets a result).
	local purchaseCosmetic = Remotes.get("PurchaseCosmetic") :: RemoteFunction
	purchaseCosmetic.OnServerInvoke = function(player, cosmeticId)
		if typeof(cosmeticId) ~= "string" then
			return { ok = false, reason = "bad request" }
		end
		local profile = DataService.get(player)
		local cosmetic = Cosmetics.get(cosmeticId)
		if not profile or not cosmetic then
			return { ok = false, reason = "unknown cosmetic" }
		end
		if profile.cosmetics.owned[cosmeticId] then
			return { ok = false, reason = "already owned" }
		end
		if cosmetic.unlock ~= "coins" or not cosmetic.price then
			return { ok = false, reason = "not for sale" }
		end
		if not PlayerService.trySpendCoins(player, cosmetic.price) then
			return { ok = false, reason = "not enough coins" }
		end
		PlayerService.grantCosmetic(player, cosmeticId)
		PlayerService.equipCosmetic(player, cosmeticId)
		return { ok = true }
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerService
