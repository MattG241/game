--!strict
--[[
	MatchmakingService (Stock matches)
	----------------------------------
	Owns the queue + Super Smash-style STOCK matches.

	Flow:
	  JoinQueue -> queue fills to (TeamSize * 2) -> launch countdown ->
	  build a stage at a unique world origin -> spawn fighters -> GO ->
	  fighters knock each other off the stage; each ring-out costs a STOCK and
	  respawns the fighter (with invuln) until their stocks run out -> last team
	  standing (or most stocks / lowest % at timeout) wins -> rewards -> lobby.

	Single-place implementation (no TeleportService) so the whole loop is
	testable in one Studio session.
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
local Match = GameConfig.Match
local MMCfg = GameConfig.Matchmaking

local LOBBY_POSITION = Vector3.new(0, 50, 0)

local queue: { Player } = {}
local playerMatch: { [Player]: any } = {}
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
-- Spawning
-- ---------------------------------------------------------------------------

local function spawnFighterAt(player: Player, cf: CFrame)
	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		humanoid.Health = humanoid.MaxHealth
		root.CFrame = cf
		PlayerService.applyCosmetic(player)
	end
end

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
	stocks: { [Player]: number },
	koCount: { [Player]: number },
	spawnCF: { [Player]: CFrame },
	ended: boolean,
	timeLeft: number,
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

local function teamList(match: Match, team: string): { Player }
	return team == "A" and match.teamA or match.teamB
end

local function teamStocks(match: Match, team: string): number
	local total = 0
	for _, p in teamList(match, team) do
		total += math.max(0, match.stocks[p] or 0)
	end
	return total
end

local function teamFullyEliminated(match: Match, team: string): boolean
	return teamStocks(match, team) <= 0
end

local function teamPercent(match: Match, team: string): number
	local total = 0
	for _, p in teamList(match, team) do
		total += CombatService.getDamage(p)
	end
	return total
end

local function broadcastMatch(match: Match, phase: string, message: string?)
	-- Per-fighter snapshot so the HUD can show both players' % and stock icons.
	local fighterData = {}
	for _, p in fighters(match) do
		table.insert(fighterData, {
			userId = p.UserId,
			name = p.DisplayName,
			team = teamOf(match, p),
			stocks = math.max(0, match.stocks[p] or 0),
			percent = math.floor(CombatService.getDamage(p)),
		})
	end
	for _, player in fighters(match) do
		Remotes.get("MatchStateChanged"):FireClient(player, {
			phase = phase,
			team = teamOf(match, player),
			timeLeft = match.timeLeft,
			message = message,
			fighters = fighterData,
		})
	end
end

local function pickArena(): Arenas.ArenaDef
	local public = {}
	for _, a in Arenas.List do
		if not a.vipOnly then
			table.insert(public, a)
		end
	end
	return public[math.random(1, #public)]
end

-- Respawn a fighter that still has stocks left (drops in from above).
local function respawn(match: Match, player: Player)
	if match.ended or not player.Parent then
		return
	end
	local cf = match.spawnCF[player] or CFrame.new(match.origin + Vector3.new(0, 6, 0))
	spawnFighterAt(player, cf + Vector3.new(0, Match.RespawnHeight, 0))
	CombatService.resetFighter(player, Match.RespawnInvuln)
	broadcastMatch(match, "respawn")
end

local function endMatch(match: Match, winnerTeam: string?)
	local winnerSet: { [Player]: boolean } = {}
	if winnerTeam then
		for _, p in teamList(match, winnerTeam) do
			winnerSet[p] = true
		end
	end

	for _, player in fighters(match) do
		playerMatch[player] = nil
		CombatService.setInCombat(player, false)
		local outcome = winnerSet[player] and "win" or "loss"
		local stocksLeft = math.max(0, match.stocks[player] or 0)
		local kos = match.koCount[player] or 0
		PlayerService.awardMatch(player, outcome, stocksLeft, kos)
		PlayerService.syncLevelUnlocks(player)
	end

	broadcastMatch(match, "ended", winnerTeam and ("Team " .. winnerTeam .. " wins!") or "Draw")
	for _, player in fighters(match) do
		Remotes.get("MatchStateChanged"):FireClient(player, {
			phase = "ended",
			team = teamOf(match, player),
			message = winnerSet[player] and "VICTORY" or "DEFEAT",
		})
		teleportToLobby(player)
	end

	task.delay(3, function()
		if match.model and match.model.Parent then
			match.model:Destroy()
		end
	end)
end

-- KO handler (wired into CombatService): a ring-out costs a stock.
local function onKO(victim: Player, killer: Player?)
	local match = playerMatch[victim]
	if not match or match.ended then
		return
	end

	if killer and killer ~= victim and playerMatch[killer] == match then
		match.koCount[killer] = (match.koCount[killer] or 0) + 1
	end

	match.stocks[victim] = math.max(0, (match.stocks[victim] or 0) - 1)
	local victimTeam = teamOf(match, victim)

	broadcastMatch(match, "ko", victim.DisplayName .. " was KO'd!")

	if (match.stocks[victim] or 0) > 0 then
		-- Still has lives — respawn after a short delay.
		task.delay(Match.RespawnDelay, function()
			respawn(match, victim)
		end)
	else
		-- Out of stocks. If their whole team is gone, the match is over.
		CombatService.setInCombat(victim, false)
		if victimTeam and teamFullyEliminated(match, victimTeam) then
			match.ended = true
			local winner = victimTeam == "A" and "B" or "A"
			task.defer(endMatch, match, winner)
		else
			-- Teammate(s) still alive (2v2): park the eliminated player to spectate.
			task.delay(Match.RespawnDelay, function()
				if not match.ended and victim.Parent then
					spawnFighterAt(victim, CFrame.new(match.origin + Vector3.new(0, 90, 0)))
					local hum = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.WalkSpeed = 0
						hum.JumpPower = 0
					end
				end
			end)
		end
	end
end

local function runMatch(match: Match)
	broadcastMatch(match, "intro", "Stage: " .. match.arena.name)
	task.wait(Match.IntermissionTime)

	-- Initial spawn on the stage.
	local sideA, sideB = Arenas.spawnPoints(match.origin, match.arena, MMCfg.TeamSize)
	for i, player in match.teamA do
		match.spawnCF[player] = sideA[i] or sideA[1]
		spawnFighterAt(player, match.spawnCF[player])
	end
	for i, player in match.teamB do
		match.spawnCF[player] = sideB[i] or sideB[1]
		spawnFighterAt(player, match.spawnCF[player])
	end

	-- Countdown.
	for n = Match.StartCountdown, 1, -1 do
		broadcastMatch(match, "countdown", tostring(n))
		task.wait(1)
	end
	broadcastMatch(match, "go", "GO!")

	for _, player in fighters(match) do
		CombatService.setInCombat(player, true)
	end

	-- Match timer; ends early when a team is eliminated (set in onKO).
	match.timeLeft = Match.MatchTime
	while not match.ended and match.timeLeft > 0 do
		task.wait(1)
		match.timeLeft -= 1

		-- Drop the match if someone left.
		for _, player in fighters(match) do
			if not player.Parent then
				match.ended = true
			end
		end
		if match.ended then
			break
		end
		broadcastMatch(match, "fight")
	end

	if not match.ended then
		-- Timeout: decide by stocks, then by lower total %.
		match.ended = true
		local sA, sB = teamStocks(match, "A"), teamStocks(match, "B")
		local winner
		if sA > sB then
			winner = "A"
		elseif sB > sA then
			winner = "B"
		else
			local pA, pB = teamPercent(match, "A"), teamPercent(match, "B")
			winner = pA < pB and "A" or (pB < pA and "B" or nil)
		end
		endMatch(match, winner)
	end
end

local function createMatch(teamA: { Player }, teamB: { Player })
	nextMatchIndex += 1
	local origin = Vector3.new(1800 * nextMatchIndex, 400, 0)
	local arena = pickArena()
	local model = Arenas.build(arena, origin, arenaContainer)

	local match: Match = {
		id = nextMatchIndex,
		origin = origin,
		arena = arena,
		model = model,
		teamA = teamA,
		teamB = teamB,
		stocks = {},
		koCount = {},
		spawnCF = {},
		ended = false,
		timeLeft = Match.MatchTime,
	}
	for _, player in fighters(match) do
		match.stocks[player] = Match.Stocks
		playerMatch[player] = match
	end

	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn("[Matchmaking] match errored: " .. tostring(err))
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

local function tryFormMatches()
	local needed = MMCfg.TeamSize * 2
	while #queue >= needed do
		local picked = {}
		for _ = 1, needed do
			table.insert(picked, table.remove(queue, 1))
		end
		for _, player in picked do
			Remotes.get("QueueStateChanged"):FireClient(player, { inQueue = true, matched = true, countdown = MMCfg.LaunchCountdown })
		end

		task.spawn(function()
			task.wait(MMCfg.LaunchCountdown)
			local valid = {}
			for _, player in picked do
				if player.Parent then
					table.insert(valid, player)
				end
			end
			if #valid < needed then
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
		playerMatch[player] = nil
	end)
end

return MatchmakingService
