--!strict
--[[
	Remotes
	-------
	Central registry for every RemoteEvent / RemoteFunction in the game.

	The server calls `Remotes.init()` once at boot to build the folder.
	Both server and client then call `Remotes.get(name)` to fetch a remote
	(the client yields until it replicates). Keeping the list in one place
	means typos surface immediately and there's a single audit point for the
	client -> server surface area (important for anti-cheat reasoning).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- name -> "Event" | "Function"
local DEFINITIONS = {
	-- Combat (client requests an action; server is authoritative over the result)
	RequestPunch = "Event",
	RequestBlock = "Event", -- payload: boolean (held down?)
	RequestDodge = "Event", -- payload: Vector3 direction
	RequestSpecial = "Event",

	-- Server -> client combat feedback (effects, hud)
	CombatFeedback = "Event", -- {kind, attacker, victim, position, damage, combo}
	StatsChanged = "Event", -- {health, stamina, special, combo}

	-- Matchmaking / rounds
	JoinQueue = "Event",
	LeaveQueue = "Event",
	QueueStateChanged = "Event", -- {state, inQueue, queueSize, countdown}
	MatchStateChanged = "Event", -- {phase, roundNumber, scores, timeLeft, message}

	-- Progression / profile
	ProfileChanged = "Event", -- full profile snapshot to the owning client
	RequestProfile = "Function", -- client pulls its profile on join

	-- Cosmetics / shop
	EquipCosmetic = "Event", -- payload: cosmeticId
	PurchaseCosmetic = "Function", -- buy with coins -> {ok, reason}
	PromptPurchase = "Event", -- client asks server to prompt a robux purchase {kind, id}

	-- Misc UI
	Notify = "Event", -- {text, color}
}

local FOLDER_NAME = "Remotes"
local cachedFolder: Folder? = nil

local function classFor(kind: string): string
	return kind == "Function" and "RemoteFunction" or "RemoteEvent"
end

-- Server-only: create the folder and all remotes.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init() must be called from the server")

	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	for name, kind in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(classFor(kind))
			remote.Name = name
			remote.Parent = folder
		end
	end

	cachedFolder = folder
	return folder
end

local function getFolder(): Folder
	if cachedFolder then
		return cachedFolder
	end
	if RunService:IsServer() then
		cachedFolder = Remotes.init()
	else
		cachedFolder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) :: Folder
	end
	return cachedFolder :: Folder
end

-- Fetch a remote by name (yields on the client until replicated).
function Remotes.get(name: string): Instance
	assert(DEFINITIONS[name], "Unknown remote requested: " .. tostring(name))
	local folder = getFolder()
	local remote = folder:WaitForChild(name, 30)
	assert(remote, "Remote did not replicate in time: " .. name)
	return remote
end

return Remotes
