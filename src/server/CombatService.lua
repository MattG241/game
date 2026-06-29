--!strict
--[[
	CombatService
	-------------
	Fully SERVER-AUTHORITATIVE combat. Clients only ever *request* actions; the
	server validates cooldowns, stamina, and hit geometry, then applies damage.
	This means a hacked client can spam requests but cannot deal illegitimate
	damage, ignore cooldowns, or hit through i-frames.

	Per-fighter runtime state lives in `state[player]`. It is created lazily and
	reset on spawn. Stamina + special meter regen on a Heartbeat loop.

	Hit detection uses a spherecast-style overlap (GetPartBoundsInRadius) in
	front of the attacker — cheap and accurate enough for melee.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local CombatService = {}
local C = GameConfig.Combat

type FighterState = {
	stamina: number,
	special: number,
	combo: number,
	comboExpireAt: number,
	lastPunchAt: number,
	lastStaminaSpendAt: number,
	lastDodgeAt: number,
	iFrameUntil: number,
	blocking: boolean,
	inCombat: boolean,
}

local state: { [Player]: FighterState } = {}

-- KO callback wired up by MatchmakingService so it can score rounds.
local onKO: ((victim: Player, killer: Player?) -> ())? = nil
function CombatService.setKOHandler(fn: (Player, Player?) -> ())
	onKO = fn
end

local function now(): number
	return os.clock()
end

local function freshState(): FighterState
	return {
		stamina = C.MaxStamina,
		special = 0,
		combo = 0,
		comboExpireAt = 0,
		lastPunchAt = 0,
		lastStaminaSpendAt = 0,
		lastDodgeAt = 0,
		iFrameUntil = 0,
		blocking = false,
		inCombat = false,
	}
end

local function getState(player: Player): FighterState
	local s = state[player]
	if not s then
		s = freshState()
		state[player] = s
	end
	return s
end

-- MatchmakingService toggles this so combat damage only lands during a match.
function CombatService.setInCombat(player: Player, value: boolean)
	local s = getState(player)
	s.inCombat = value
	if value then
		-- Reset combat resources at the start of a round.
		s.stamina = C.MaxStamina
		s.special = 0
		s.combo = 0
		s.blocking = false
		s.iFrameUntil = 0
	end
end

local function pushStats(player: Player)
	local s = state[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not s or not humanoid then
		return
	end
	Remotes.get("StatsChanged"):FireClient(player, {
		health = humanoid.Health,
		maxHealth = humanoid.MaxHealth,
		stamina = s.stamina,
		maxStamina = C.MaxStamina,
		special = s.special,
		maxSpecial = C.SpecialMeterMax,
		combo = s.combo,
		blocking = s.blocking,
	})
end

local function spendStamina(s: FighterState, amount: number): boolean
	if s.stamina < amount then
		return false
	end
	s.stamina -= amount
	s.lastStaminaSpendAt = now()
	return true
end

local function addSpecial(s: FighterState, amount: number)
	s.special = math.clamp(s.special + amount, 0, C.SpecialMeterMax)
end

-- Get the live character + humanoid + root for a player, if alive.
local function getRig(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- Find enemy fighters within `range`/`radius` in front of the attacker.
local function findTargets(attacker: Player, range: number, radius: number): { Player }
	local _, _, root = getRig(attacker)
	if not root then
		return {}
	end

	local origin = root.Position + root.CFrame.LookVector * (range * 0.5)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker.Character }

	local parts = workspace:GetPartBoundsInRadius(origin, radius, params)
	local seen: { [Player]: boolean } = {}
	local results: { Player } = {}

	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			local victim = Players:GetPlayerFromCharacter(model)
			if victim and victim ~= attacker and not seen[victim] then
				-- Must be roughly in front of the attacker (within ~120° cone).
				local _, _, vroot = getRig(victim)
				if vroot then
					local toTarget = (vroot.Position - root.Position)
					if toTarget.Magnitude <= range + radius then
						local facing = root.CFrame.LookVector:Dot(toTarget.Unit)
						if facing > -0.2 then
							seen[victim] = true
							table.insert(results, victim)
						end
					end
				end
			end
		end
	end
	return results
end

local function applyKnockback(victimRoot: BasePart, fromRoot: BasePart, force: number, up: number?)
	local dir = (victimRoot.Position - fromRoot.Position)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		dir = fromRoot.CFrame.LookVector
	end
	dir = dir.Unit

	-- A short-lived LinearVelocity gives a snappy, network-friendly shove.
	local attachment = Instance.new("Attachment")
	attachment.Parent = victimRoot
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.MaxForce = math.huge
	lv.VectorVelocity = dir * force + Vector3.new(0, up or 14, 0)
	lv.Parent = victimRoot
	game:GetService("Debris"):AddItem(lv, 0.18)
	game:GetService("Debris"):AddItem(attachment, 0.2)
end

-- Tag the victim's humanoid with the attacker so Died can attribute the KO.
local function tagCreator(victimHumanoid: Humanoid, attacker: Player)
	local existing = victimHumanoid:FindFirstChild("creator")
	if existing then
		existing:Destroy()
	end
	local attackerHumanoid = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
	if not attackerHumanoid then
		return
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = attackerHumanoid -- its .Parent is the attacker's character
	tag.Parent = victimHumanoid
	game:GetService("Debris"):AddItem(tag, 5)
end

-- Core damage application. Honours blocking + i-frames. Returns damage dealt.
local function dealDamage(attacker: Player, victim: Player, baseDamage: number, knockback: number, up: number?): number
	local victimState = getState(victim)
	if now() < victimState.iFrameUntil then
		return 0 -- dodged through it
	end
	local _, _, aRoot = getRig(attacker)
	local _, vHum, vRoot = getRig(victim)
	if not aRoot or not vHum or not vRoot then
		return 0
	end

	tagCreator(vHum, attacker)

	local damage = baseDamage
	if victimState.blocking and victimState.stamina > 0 then
		damage *= (1 - C.BlockDamageReduction)
		-- Blocking a hit chips stamina; a fully drained blocker gets stunned.
		victimState.stamina = math.max(0, victimState.stamina - baseDamage * 0.6)
		if victimState.stamina <= 0 then
			-- Guard break: take the knockback and a bit of bonus damage.
			damage = baseDamage * 0.5
			applyKnockback(vRoot, aRoot, C.BlockBreakKnockback, 18)
		end
	else
		applyKnockback(vRoot, aRoot, knockback, up)
	end

	vHum:TakeDamage(damage)
	addSpecial(victimState, C.SpecialMeterGainPerHitTaken)

	pushStats(victim)
	return damage
end

-- ---------------------------------------------------------------------------
-- Action handlers (all triggered by client requests, all validated here)
-- ---------------------------------------------------------------------------

local function handlePunch(player: Player)
	local s = getState(player)
	if not s.inCombat then
		return
	end
	if now() - s.lastPunchAt < C.PunchCooldown then
		return -- cooldown (anti-spam)
	end
	if s.blocking then
		return -- can't punch while blocking
	end
	if not spendStamina(s, C.PunchStaminaCost) then
		return
	end
	s.lastPunchAt = now()

	-- Combo accounting.
	if now() <= s.comboExpireAt then
		s.combo = math.min(s.combo + 1, C.MaxCombo)
	else
		s.combo = 1
	end
	s.comboExpireAt = now() + C.ComboWindow

	local isFinisher = s.combo >= C.MaxCombo
	local damage = C.PunchDamage * (isFinisher and C.ComboFinisherMultiplier or 1)
	local knockback = isFinisher and C.FinisherKnockbackForce or C.KnockbackForce

	local targets = findTargets(player, C.HitRange, C.HitRadius)
	local landed = false
	for _, victim in targets do
		local dealt = dealDamage(player, victim, damage, knockback, isFinisher and 22 or nil)
		if dealt > 0 then
			landed = true
			addSpecial(s, C.SpecialMeterGainPerHitLanded)
		end
		Remotes.get("CombatFeedback"):FireAllClients({
			kind = isFinisher and "finisher" or "punch",
			attacker = player.UserId,
			victim = victim.UserId,
			combo = s.combo,
		})
	end

	if isFinisher then
		s.combo = 0 -- finisher resets the chain
	end

	if landed then
		pushStats(player)
	end
end

local function handleBlock(player: Player, held: boolean)
	local s = getState(player)
	if not s.inCombat then
		return
	end
	s.blocking = held == true and s.stamina > 0
	pushStats(player)
end

local function handleDodge(player: Player, direction: Vector3)
	local s = getState(player)
	if not s.inCombat then
		return
	end
	if now() - s.lastDodgeAt < C.DodgeCooldown then
		return
	end
	if not spendStamina(s, C.DodgeStaminaCost) then
		return
	end
	local _, _, root = getRig(player)
	if not root then
		return
	end
	s.lastDodgeAt = now()
	s.iFrameUntil = now() + C.DodgeDuration
	s.blocking = false

	-- Sanitize client direction; default to backwards.
	local dir = direction
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.1 then
		dir = -root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.MaxForce = math.huge
	lv.VectorVelocity = dir * (C.DodgeDistance / C.DodgeDuration)
	lv.Parent = root
	game:GetService("Debris"):AddItem(lv, C.DodgeDuration)
	game:GetService("Debris"):AddItem(attachment, C.DodgeDuration + 0.05)

	Remotes.get("CombatFeedback"):FireAllClients({
		kind = "dodge",
		attacker = player.UserId,
	})
	pushStats(player)
end

local function handleSpecial(player: Player)
	local s = getState(player)
	if not s.inCombat then
		return
	end
	if s.special < C.SpecialMeterMax then
		return -- meter not full
	end
	if s.blocking then
		return
	end
	s.special = 0

	local targets = findTargets(player, C.SpecialRange, C.SpecialRadius)
	for _, victim in targets do
		dealDamage(player, victim, C.SpecialDamage, C.SpecialKnockbackForce, 34)
		Remotes.get("CombatFeedback"):FireAllClients({
			kind = "special",
			attacker = player.UserId,
			victim = victim.UserId,
		})
	end
	-- Always show the special burst even on a whiff.
	Remotes.get("CombatFeedback"):FireAllClients({
		kind = "special_cast",
		attacker = player.UserId,
	})
	pushStats(player)
end

-- ---------------------------------------------------------------------------
-- Regen + ragdoll-on-KO
-- ---------------------------------------------------------------------------

local function ragdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		humanoid.PlatformStand = true
	end
	for _, motor in character:GetDescendants() do
		if motor:IsA("Motor6D") then
			local a0 = Instance.new("Attachment")
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.Parent = motor.Part0
			motor:Destroy()
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	state[player] = freshState()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.Died:Connect(function()
		local s = state[player]
		if s then
			s.inCombat = false
		end
		ragdoll(character)
		if onKO then
			-- killer attribution is best-effort via the creator tag.
			local creator = humanoid:FindFirstChild("creator") :: ObjectValue?
			local killer = creator and creator.Value and Players:GetPlayerFromCharacter((creator.Value :: Instance).Parent)
			onKO(player, killer)
		end
	end)
end

function CombatService.start()
	Remotes.get("RequestPunch").OnServerEvent:Connect(handlePunch)
	Remotes.get("RequestBlock").OnServerEvent:Connect(function(player, held)
		handleBlock(player, held)
	end)
	Remotes.get("RequestDodge").OnServerEvent:Connect(function(player, dir)
		handleDodge(player, dir)
	end)
	Remotes.get("RequestSpecial").OnServerEvent:Connect(handleSpecial)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)

	-- Stamina / special regen + stat replication tick.
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		for player, s in state do
			if s.inCombat then
				-- Stamina regen (after a short delay since last spend).
				if now() - s.lastStaminaSpendAt >= C.StaminaRegenDelay then
					s.stamina = math.min(C.MaxStamina, s.stamina + C.StaminaRegenPerSecond * dt)
				end
				-- Blocking drains stamina continuously.
				if s.blocking then
					s.stamina = math.max(0, s.stamina - C.BlockStaminaCostPerSecond * dt)
					if s.stamina <= 0 then
						s.blocking = false
					end
				end
				-- Expire combo windows.
				if s.combo > 0 and now() > s.comboExpireAt then
					s.combo = 0
				end
			end
		end

		-- Replicate stats at ~10Hz to keep HUD smooth without spamming.
		accum += dt
		if accum >= 0.1 then
			accum = 0
			for player, s in state do
				if s.inCombat then
					pushStats(player)
				end
			end
		end
	end)
end

return CombatService
