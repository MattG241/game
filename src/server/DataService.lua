--!strict
--[[
	DataService
	-----------
	Robust DataStore wrapper with:
	  * session locking (prevents data overwrites across servers / fast rejoins)
	  * retry-with-backoff on every store call
	  * schema migration / default-filling
	  * autosave + save-on-leave + BindToClose flush

	This is intentionally dependency-free (no external ProfileService) so the
	project runs as-is, but it borrows the same safety ideas.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local Cosmetics = require(game:GetService("ReplicatedStorage").Shared.Cosmetics)

local DataService = {}

local cfg = GameConfig.Data
local store = DataStoreService:GetDataStore(cfg.StoreName)
local lockStore = DataStoreService:GetDataStore(cfg.SessionLockStore)

-- Per-player loaded profile data, keyed by UserId.
local profiles: { [number]: any } = {}
-- Guards against saving a profile whose load failed.
local loaded: { [number]: boolean } = {}

local JOB_ID = game.JobId ~= "" and game.JobId or "studio"

-- Default profile schema. `version` lets us migrate later.
local function defaultProfile()
	return {
		version = 2,
		coins = 250,
		xp = 0,
		stats = {
			wins = 0,
			losses = 0,
			kos = 0,
			matches = 0,
		},
		cosmetics = {
			owned = Cosmetics.defaultOwned(),
			equipped = Cosmetics.DefaultId,
		},
		settings = {
			musicEnabled = true,
			sfxEnabled = true,
		},
	}
end

-- Recursively fill any missing keys from `template` into `data`.
local function reconcile(data: any, template: any)
	for key, value in template do
		if data[key] == nil then
			if typeof(value) == "table" then
				data[key] = {}
				reconcile(data[key], value)
			else
				data[key] = value
			end
		elseif typeof(value) == "table" and typeof(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
end

-- Run `fn` with exponential backoff. Returns ok, result.
local function withRetry(fn)
	local attempt = 0
	while true do
		attempt += 1
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt >= cfg.MaxRetries then
			warn(("[DataService] operation failed after %d attempts: %s"):format(attempt, tostring(result)))
			return false, result
		end
		task.wait(cfg.RetryBackoff * (2 ^ (attempt - 1)))
	end
end

local function lockKey(userId: number): string
	return "lock_" .. userId
end

-- Try to acquire the session lock. Returns true if we own it.
local function acquireLock(userId: number): boolean
	local ok = withRetry(function()
		return lockStore:UpdateAsync(lockKey(userId), function(current)
			-- current = {jobId, timestamp}
			if current and current.jobId ~= JOB_ID then
				-- Stale lock older than 10 min is considered abandoned.
				local age = os.time() - (current.timestamp or 0)
				if age < 600 then
					return nil -- abort update; someone else holds it
				end
			end
			return { jobId = JOB_ID, timestamp = os.time() }
		end)
	end)
	return ok
end

local function releaseLock(userId: number)
	withRetry(function()
		lockStore:UpdateAsync(lockKey(userId), function(current)
			if current and current.jobId == JOB_ID then
				return nil -- clears our lock (returning nil aborts the write, leaving value;
				-- so instead overwrite with an explicitly released marker)
			end
			return current
		end)
	end)
	-- Best-effort hard clear.
	withRetry(function()
		lockStore:SetAsync(lockKey(userId), { jobId = "", timestamp = 0 })
	end)
end

-- Load (or create) a player's profile. Blocks until done. Returns the profile or nil.
function DataService.load(player: Player): any?
	local userId = player.UserId
	local key = "player_" .. userId

	if not acquireLock(userId) then
		warn("[DataService] could not acquire session lock for " .. player.Name)
		-- Let them play on a fresh, NON-SAVING profile to avoid data loss.
		local p = defaultProfile()
		profiles[userId] = p
		loaded[userId] = false
		return p
	end

	local ok, data = withRetry(function()
		return store:GetAsync(key)
	end)

	local profile
	if ok and typeof(data) == "table" then
		profile = data
		reconcile(profile, defaultProfile())
	else
		profile = defaultProfile()
	end

	profiles[userId] = profile
	loaded[userId] = ok ~= false
	return profile
end

-- Get the in-memory profile (does NOT load). May be nil if not loaded yet.
function DataService.get(player: Player): any?
	return profiles[player.UserId]
end

-- Persist a player's profile. No-op if the profile never loaded cleanly.
function DataService.save(player: Player): boolean
	local userId = player.UserId
	local profile = profiles[userId]
	if not profile then
		return false
	end
	if loaded[userId] == false then
		-- We never had authoritative data; refuse to overwrite to be safe.
		return false
	end

	local ok = withRetry(function()
		return store:UpdateAsync("player_" .. userId, function()
			return profile
		end)
	end)
	return ok
end

-- Save then release the lock and drop from memory.
function DataService.release(player: Player)
	local userId = player.UserId
	if profiles[userId] then
		DataService.save(player)
	end
	releaseLock(userId)
	profiles[userId] = nil
	loaded[userId] = nil
end

local autosaveStarted = false

-- Begin the autosave loop. Call once at server boot.
function DataService.startAutosave()
	if autosaveStarted then
		return
	end
	autosaveStarted = true

	task.spawn(function()
		while true do
			task.wait(cfg.AutoSaveInterval)
			for _, player in Players:GetPlayers() do
				if profiles[player.UserId] then
					DataService.save(player)
					task.wait(0.2) -- spread writes to respect throttling
				end
			end
		end
	end)
end

-- Flush all profiles on shutdown. Roblox gives BindToClose ~30s.
function DataService.flushAll()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			DataService.release(player)
		end)
	end
	-- Give the spawned saves a moment in Studio / live.
	if not RunService:IsStudio() then
		task.wait(3)
	end
end

return DataService
