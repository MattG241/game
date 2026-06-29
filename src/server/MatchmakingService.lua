--!strict
--[[
	MatchmakingService
	------------------
	Owns the queue, match creation, and the best-of-3 round loop.

	Flow:
	  JoinQueue -> queue fills to (TeamSize * 2) -> launch countdown ->
	  build/assign an arena at a unique world origin -> run rounds ->
	  award rewards via PlayerService -> return fighters to the lobby.

	Multiple matches can run at once; each gets its own world-space origin so
	arenas never overlap. KO attribution comes from CombatService.

	This is a single-place (no TeleportService) implementation so the whole loop
	is testable in one Studio session. Swapping to reserved servers later only
	touches `assignArena` / `returnToLobby`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local Arenas = require(Shared.Arenas)

local CombatService = require(script.Parent.CombatService)
local PlayerService = require(script.Parent.PlayerService)

local MatchmakingService = {}
local RoundCfg = GameConfig.Round
local MMCfg = GameConfig.Matchmaking

local LOBBY_POSITION = Vector3.new(0, 50, 0)

-- Queue of players waiting for a match.
local queue: { Player } = {}
-- player -> match it belongs to (so the KO handler can find it).
local playerMatch: { [Player]: any } = {}
-- Container in Workspace where arenas are built.
local arenaContainer: Folder

local nextMatchIndex = 0

-- ---------------------------------------------------------------------------
-- Queue
-- ---------------------------------------------------------------------------

local function inQueue(player: Player): boolean
	return table.find(queue, player) ~= nil
end

local function broadcastQueue()
	for _, player in queue do
		Remotes.get("QueueStateChanged"):FireClient(player, {
			inQueue = true,
			queueSize = #queue,
			needed = MMCfg.TeamSize * 2,
		})
	end
end

local function removeFromQueue(player: Player)
	local idx = table.find(queue, player)
	if idx then
		table.remove(queue, idx)
		Remotes.get("QueueStateChanged"):FireClient(player, { inQueue = false, queueSize = 0 })
		broadcastQueue()
	end
end

-- ---------------------------------------------------------------------------
-- Character placement helpers
-- ---------------------------------------------------------------------------

-- Force a fresh character and place it at `cf`. Yields until ready.
local function spawnFighterAt(player: Player, cf: CFrame)
	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		humanoid.Health = humanoid.MaxHealth
		root.CFrame = cf + Vector3.new(0, 3, 0)
		PlayerService.applyCosmetic(player)
	end
end

-- Return a player to the lobby with a fresh, full-health character.
-- (CharacterAutoLoads is off, so we always respawn explicitly.)
local function teleportToLobby(player: Player)
	if not player.Parent then
		return
	end
	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if root then
		root.CFrame = CFrame.new(LOBBY_POSITION + Vector3.new(math.random(-12, 12), 5, math.random(-12, 12)))
		PlayerService.applyCosmetic(player)
	end
end

-- ---------------------------------------------------------------------------
-- Match
-- ---------------------------------------------------------------------------

type Match = {
	id: number,
	origin: Vector3,
	arena: Arenas.ArenaDef,
	model: Model,
	teamA: { Player },
	teamB: { Player },
	scores: { A: number, B: number },
	roundResolved: boolean,
	roundWinnerTeam: string?,
	koCount: { [Player]: number },
}

local function fighters(match: Match): { Player }
	local all = {}
	for _, p in match.teamA do
		table.insert(all, p)
	end
	for _, p in match.teamB do
		table.insert(all, p)
	end
	return all
end

local function teamOf(match: Match, player: Player): string?
	if table.find(match.teamA, player) then
		return "A"
	elseif table.find(match.teamB, player) then
		return "B"
	end
	return nil
end

local function teamAlive(match: Match, team: string): boolean
	local list = team == "A" and match.teamA or match.teamB
	for _, player in list do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return true
		end
	end
	return false
end

local function broadcastMatch(match: Match, phase: string, timeLeft: number?, message: string?)
	for _, player in fighters(match) do
		Remotes.get("MatchStateChanged"):FireClient(player, {
			phase = phase,
			roundNumber = match.scores.A + match.scores.B + 1,
			scores = match.scores,
			team = teamOf(match, player),
			timeLeft = timeLeft,
			message = message,
		})
	end
end

-- Choose an arena (respecting VIP gating to whoever's present is irrelevant for the map pick — just pick a public one).
local function pickArena(): Arenas.ArenaDef
	local public = {}
	for _, a in Arenas.List do
		if not a.vipOnly then
			table.insert(public, a)
		end
	end
	return public[math.random(1, #public)]
end

-- Run a single round. Returns the winning team ("A"/"B") or nil on a draw.
local function runRound(match: Match, roundNumber: number): string?
	-- Spawn both fighters at their pads.
	local sideA, sideB = Arenas.spawnPoints(match.origin, match.arena, MMCfg.TeamSize)
	for i, player in match.teamA do
		spawnFighterAt(player, sideA[i] or sideA[1])
	end
	for i, player in match.teamB do
		spawnFighterAt(player, sideB[i] or sideB[1])
	end

	match.roundResolved = false
	match.roundWinnerTeam = nil

	-- Countdown.
	for n = RoundCfg.StartCountdown, 1, -1 do
		broadcastMatch(match, "countdown", n, tostring(n))
		task.wait(1)
	end
	broadcastMatch(match, "fight", RoundCfg.RoundTime, "FIGHT!")

	-- Enable combat.
	for _, player in fighters(match) do
		CombatService.setInCombat(player, true)
	end

	-- Round timer loop; resolves early on a KO (set by onKO handler).
	local timeLeft = RoundCfg.RoundTime
	local suddenDeath = false
	while true do
		task.wait(1)
		timeLeft -= 1

		if match.roundResolved then
			break
		end
		-- A team being fully down also ends the round (covers fall-off-map).
		if not teamAlive(match, "A") then
			match.roundWinnerTeam = "B"
			break
		elseif not teamAlive(match, "B") then
			match.roundWinnerTeam = "A"
			break
		end

		if timeLeft <= 0 then
			if not suddenDeath then
				suddenDeath = true
				timeLeft = RoundCfg.SuddenDeathTime
				broadcastMatch(match, "suddendeath", timeLeft, "SUDDEN DEATH!")
			else
				-- Decide by remaining HP.
				local function teamHealth(team: string): number
					local list = team == "A" and match.teamA or match.teamB
					local total = 0
					for _, player in list do
						local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
						total += h and h.Health or 0
					end
					return total
				end
				local hpA, hpB = teamHealth("A"), teamHealth("B")
				if hpA > hpB then
					match.roundWinnerTeam = "A"
				elseif hpB > hpA then
					match.roundWinnerTeam = "B"
				else
					match.roundWinnerTeam = nil -- true draw
				end
				break
			end
		else
			broadcastMatch(match, suddenDeath and "suddendeath" or "fight", timeLeft)
		end
	end

	-- Disable combat.
	for _, player in fighters(match) do
		CombatService.setInCombat(player, false)
	end

	return match.roundWinnerTeam
end

local function endMatch(match: Match, winnerTeam: string?)
	-- Tally rewards.
	local winnersList = winnerTeam == "A" and match.teamA or (winnerTeam == "B" and match.teamB or {})
	local winnerSet: { [Player]: boolean } = {}
	for _, p in winnersList do
		winnerSet[p] = true
	end

	for _, player in fighters(match) do
		playerMatch[player] = nil
		CombatService.setInCombat(player, false)
		local outcome = winnerSet[player] and "win" or "loss"
		local roundsWon = (teamOf(match, player) == "A") and match.scores.A or match.scores.B
		local kos = match.koCount[player] or 0
		PlayerService.awardMatch(player, outcome, roundsWon, kos)
		PlayerService.syncLevelUnlocks(player)

		broadcastMatch(match, "ended", nil, winnerSet[player] and "VICTORY" or "DEFEAT")
		teleportToLobby(player)
	end

	-- Tear down the arena after a short beat.
	task.delay(3, function()
		if match.model and match.model.Parent then
			match.model:Destroy()
		end
	end)
end

local function runMatch(match: Match)
	local winsNeeded = math.ceil(RoundCfg.BestOf / 2)

	broadcastMatch(match, "intro", nil, "Match starting on " .. match.arena.name)
	task.wait(RoundCfg.IntermissionTime)

	while match.scores.A < winsNeeded and match.scores.B < winsNeeded do
		-- Bail if someone left mid-match.
		local stillHere = true
		for _, player in fighters(match) do
			if not player.Parent then
				stillHere = false
			end
		end
		if not stillHere then
			break
		end

		local roundNumber = match.scores.A + match.scores.B + 1
		local winner = runRound(match, roundNumber)
		if winner == "A" then
			match.scores.A += 1
		elseif winner == "B" then
			match.scores.B += 1
		end

		broadcastMatch(match, "roundover", nil, ("Round %d: %s"):format(roundNumber, winner and ("Team " .. winner .. " wins!") or "Draw"))
		task.wait(RoundCfg.IntermissionTime)
	end

	local finalWinner = nil
	if match.scores.A > match.scores.B then
		finalWinner = "A"
	elseif match.scores.B > match.scores.A then
		finalWinner = "B"
	end
	endMatch(match, finalWinner)
end

-- Build the arena + match object and kick off its round loop.
local function createMatch(teamA: { Player }, teamB: { Player })
	nextMatchIndex += 1
	local origin = Vector3.new(1500 * nextMatchIndex, 300, 0)
	local arena = pickArena()
	local model = Arenas.build(arena, origin, arenaContainer)

	local match: Match = {
		id = nextMatchIndex,
		origin = origin,
		arena = arena,
		model = model,
		teamA = teamA,
		teamB = teamB,
		scores = { A = 0, B = 0 },
		roundResolved = false,
		roundWinnerTeam = nil,
		koCount = {},
	}

	for _, player in teamA do
		playerMatch[player] = match
	end
	for _, player in teamB do
		playerMatch[player] = match
	end

	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn("[Matchmaking] match errored: " .. tostring(err))
			-- Fail-safe: free everyone.
			for _, player in fighters(match) do
				playerMatch[player] = nil
				CombatService.setInCombat(player, false)
				teleportToLobby(player)
			end
			if match.model and match.model.Parent then
				match.model:Destroy()
			end
		end
	end)
end

-- Try to form matches from the queue.
local function tryFormMatches()
	local needed = MMCfg.TeamSize * 2
	while #queue >= needed do
		local picked = {}
		for _ = 1, needed do
			table.insert(picked, table.remove(queue, 1))
		end

		-- Announce launch countdown.
		for _, player in picked do
			Remotes.get("QueueStateChanged"):FireClient(player, { inQueue = true, matched = true, countdown = MMCfg.LaunchCountdown })
		end

		task.spawn(function()
			task.wait(MMCfg.LaunchCountdown)
			-- Drop anyone who left during the countdown.
			local valid = {}
			for _, player in picked do
				if player.Parent then
					table.insert(valid, player)
				end
			end
			if #valid < needed then
				-- Requeue survivors.
				for _, player in valid do
					if not inQueue(player) then
						table.insert(queue, player)
					end
				end
				broadcastQueue()
				return
			end
			local teamA, teamB = {}, {}
			for i = 1, MMCfg.TeamSize do
				table.insert(teamA, valid[i])
				table.insert(teamB, valid[i + MMCfg.TeamSize])
			end
			createMatch(teamA, teamB)
		end)
	end
	broadcastQueue()
end

-- ---------------------------------------------------------------------------
-- KO handling (wired into CombatService)
-- ---------------------------------------------------------------------------

local function onKO(victim: Player, killer: Player?)
	local match = playerMatch[victim]
	if not match then
		return
	end
	if killer and playerMatch[killer] == match then
		match.koCount[killer] = (match.koCount[killer] or 0) + 1
	end

	-- In 1v1 a KO immediately resolves the round.
	local victimTeam = teamOf(match, victim)
	if victimTeam and not teamAlive(match, victimTeam) then
		match.roundWinnerTeam = victimTeam == "A" and "B" or "A"
		match.roundResolved = true
	end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function MatchmakingService.start()
	arenaContainer = Instance.new("Folder")
	arenaContainer.Name = "Arenas"
	arenaContainer.Parent = workspace

	CombatService.setKOHandler(onKO)

	Remotes.get("JoinQueue").OnServerEvent:Connect(function(player)
		if inQueue(player) or playerMatch[player] then
			return
		end
		table.insert(queue, player)
		broadcastQueue()
		tryFormMatches()
	end)

	Remotes.get("LeaveQueue").OnServerEvent:Connect(function(player)
		removeFromQueue(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromQueue(player)
		-- If they were mid-match, the round loop's presence check handles cleanup.
		playerMatch[player] = nil
	end)
end

return MatchmakingService
