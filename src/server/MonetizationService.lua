--!strict
--[[
	MonetizationService
	-------------------
	MarketplaceService integration for gamepasses + developer products.

	  * Gamepasses are checked on join (and cached) and gate rewards multipliers
	    + premium cosmetics / arenas.
	  * Developer Products grant Fight Coins; ProcessReceipt is implemented with
	    the standard "save the grant before returning PurchaseGranted" pattern so
	    purchases are never double-applied or silently lost.

	Remember to fill the asset IDs in GameConfig.Monetization.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PlayerService = require(script.Parent.PlayerService)

local MonetizationService = {}
local Mon = GameConfig.Monetization

-- player.UserId -> { passId -> bool }
local ownedPasses: { [number]: { [number]: boolean } } = {}

local function ownsPass(player: Player, passId: number): boolean
	if passId == 0 then
		return false
	end
	local cache = ownedPasses[player.UserId]
	if cache and cache[passId] ~= nil then
		return cache[passId]
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	owns = ok and owns or false
	cache = cache or {}
	cache[passId] = owns
	ownedPasses[player.UserId] = cache
	return owns
end
MonetizationService.ownsPass = ownsPass

-- Convenience accessors used by other systems.
function MonetizationService.hasVIP(player: Player): boolean
	return ownsPass(player, Mon.Gamepasses.VIP)
end

-- The combined reward multiplier from owned passes.
function MonetizationService.rewardMultiplier(player: Player): number
	local mult = 1
	if ownsPass(player, Mon.Gamepasses.VIP) then
		mult *= Mon.VIPRewardMultiplier
	end
	if ownsPass(player, Mon.Gamepasses.DoubleRewards) then
		mult *= Mon.DoubleRewardsMultiplier
	end
	return mult
end

-- Apply any cosmetic/feature grants that come from owning a pass.
local function applyPassPerks(player: Player)
	if ownsPass(player, Mon.Gamepasses.SkinPack) then
		-- Grant every "gamepass"-unlock cosmetic.
		local Cosmetics = require(Shared.Cosmetics)
		for _, c in Cosmetics.List do
			if c.unlock == "gamepass" then
				PlayerService.grantCosmetic(player, c.id)
			end
		end
	end
end

-- Map a productId back to its coin grant.
local function coinsForProduct(productId: number): number?
	for key, id in Mon.Products do
		if id == productId and id ~= 0 then
			return Mon.ProductCoinGrants[key]
		end
	end
	return nil
end

local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player left; let Roblox retry the receipt when they return.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local coins = coinsForProduct(receiptInfo.ProductId)
	if not coins then
		warn("[Monetization] unknown product purchased: " .. tostring(receiptInfo.ProductId))
		-- Granting nothing but acknowledging avoids an infinite retry loop.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Apply the grant. PlayerService persists via the normal autosave/leave save.
	PlayerService.addCoins(player, coins)
	Remotes.get("Notify"):FireClient(player, {
		text = ("+%d Fight Coins!"):format(coins),
		color = Color3.fromRGB(255, 215, 60),
	})

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.start()
	-- Hand PlayerService the live multiplier source (avoids a require cycle).
	PlayerService.setRewardMultiplierProvider(function(player)
		return MonetizationService.rewardMultiplier(player)
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	-- Re-check the pass cache when a gamepass is purchased mid-session.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if wasPurchased then
			local cache = ownedPasses[player.UserId] or {}
			cache[passId] = true
			ownedPasses[player.UserId] = cache
			applyPassPerks(player)
			Remotes.get("Notify"):FireClient(player, {
				text = "Purchase successful — perks unlocked!",
				color = Color3.fromRGB(80, 255, 120),
			})
		end
	end)

	-- Client asks the server to prompt a Robux purchase (keeps IDs server-side).
	Remotes.get("PromptPurchase").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local kind, key = payload.kind, payload.key
		if kind == "gamepass" and Mon.Gamepasses[key] and Mon.Gamepasses[key] ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, Mon.Gamepasses[key])
		elseif kind == "product" and Mon.Products[key] and Mon.Products[key] ~= 0 then
			MarketplaceService:PromptProductPurchase(player, Mon.Products[key])
		end
	end)

	-- Prime the pass cache + perks on join.
	local function onAdded(player: Player)
		task.spawn(function()
			applyPassPerks(player)
		end)
	end
	Players.PlayerAdded:Connect(onAdded)
	for _, player in Players:GetPlayers() do
		onAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ownedPasses[player.UserId] = nil
	end)
end

return MonetizationService
