--!strict
--[[
	CombatService (Smash-style)
	---------------------------
	Fully SERVER-AUTHORITATIVE platform-fighter combat. Clients only ever
	*request* actions; the server validates cooldowns, stamina, and hit geometry,
	then applies the result.

	DAMAGE MODEL:
	  * Hits add a DAMAGE PERCENT to the victim (they do NOT drain health).
	  * Knockback scales with the victim's CURRENT percent:
	        launchSpeed = (BaseKnockback + percent * KnockbackGrowth) * moveMult
	  * A KO only happens when a launched fighter flies into a blast zone (which
	    sets their Health to 0 -> Humanoid.Died -> onKO -> MatchmakingService
	    handles the stock loss).

	JUICE: every landed hit triggers hit-stop (Animations.freeze) + a server-
	played attack/reaction animation + a CombatFeedback event for VFX/sound.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local Animations = require(Shared.Animations)

local CombatService = {}
local C = GameConfig.Combat

type FighterState = {
	damage: number, -- accumulated % (the Smash damage meter)
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

local onKO: ((victim: Player, killer: Player?) -> ())? = nil
function CombatService.setKOHandler(fn: (Player, Player?) -> ())
	onKO = fn
end

local function now(): number
	return os.clock()
end

local function freshState(): FighterState
	return {
		damage = 0,
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

-- Toggle combat for a fighter and (when enabling) reset all combat resources.
function CombatService.setInCombat(player: Player, value: boolean)
	local s = getState(player)
	s.inCombat = value
	if value then
		s.damage = 0
		s.stamina = C.MaxStamina
		s.special = 0
		s.combo = 0
		s.blocking = false
		s.iFrameUntil = 0
	end
end

-- Reset a fighter on respawn (after losing a stock): fresh %, full shield,
-- spawn invulnerability, combat re-enabled. Keeps nothing from the last life.
function CombatService.resetFighter(player: Player, invulnSeconds: number)
	local s = getState(player)
	s.damage = 0
	s.stamina = C.MaxStamina
	s.special = 0
	s.combo = 0
	s.blocking = false
	s.inCombat = true
	s.iFrameUntil = now() + (invulnSeconds or 0)
end

function CombatService.getDamage(player: Player): number
	local s = state[player]
	return s and s.damage or 0
end

local function pushStats(player: Player)
	local s = state[player]
	if not s then
		return
	end
	Remotes.get("StatsChanged"):FireClient(player, {
		damage = s.damage,
		stamina = s.stamina,
		maxStamina = C.MaxStamina,
		special = s.special,
		maxSpecial = C.SpecialMeterMax,
		combo = s.combo,
		blocking = s.blocking,
		invuln = now() < s.iFrameUntil,
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

-- Enemy fighters within range/radius in front of the attacker.
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
	for _, p in parts do
		local model = p:FindFirstAncestorOfClass("Model")
		if model then
			local victim = Players:GetPlayerFromCharacter(model)
			if victim and victim ~= attacker and not seen[victim] then
				local _, _, vroot = getRig(victim)
				if vroot and (vroot.Position - root.Position).Magnitude <= range + radius then
					local facing = root.CFrame.LookVector:Dot((vroot.Position - root.Position).Unit)
					if facing > -0.3 then
						seen[victim] = true
						table.insert(results, victim)
					end
				end
			end
		end
	end
	return results
end

-- Launch a victim away from the attacker at `speed`, with hitstun.
local function applyLaunch(victim: Player, victimRoot: BasePart, fromRoot: BasePart, speed: number)
	speed = math.min(speed, C.MaxLaunchSpeed)
	local dir = victimRoot.Position - fromRoot.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		dir = fromRoot.CFrame.LookVector
	end
	dir = dir.Unit

	local up = speed * C.LaunchUpRatio
	local duration = math.clamp(speed / 400, 0.16, 0.6)

	-- Hitstun: disable the victim's control for the launch.
	local humanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = victimRoot
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.MaxForce = math.huge
	lv.VectorVelocity = dir * speed + Vector3.new(0, up, 0)
	lv.Parent = victimRoot
	Debris:AddItem(lv, duration)
	Debris:AddItem(attachment, duration + 0.05)

	task.delay(duration + 0.08, function()
		if humanoid and humanoid.Health > 0 then
			humanoid.PlatformStand = false
		end
	end)
end

-- Apply a hit. `percent` is the base damage %, `kbMult` the move's knockback
-- multiplier. Returns true if it landed.
local function dealHit(attacker: Player, victim: Player, percent: number, kbMult: number, heavy: boolean): boolean
	local vs = getState(victim)
	if now() < vs.iFrameUntil then
		return false -- dodged / spawn-invuln
	end
	local _, _, aRoot = getRig(attacker)
	local _, vHum, vRoot = getRig(victim)
	if not aRoot or not vHum or not vRoot then
		return false
	end

	-- Tag for KO attribution (its .Parent is the attacker's character).
	local attackerHum = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
	if attackerHum then
		local old = vHum:FindFirstChild("creator")
		if old then
			old:Destroy()
		end
		local tag = Instance.new("ObjectValue")
		tag.Name = "creator"
		tag.Value = attackerHum
		tag.Parent = vHum
		Debris:AddItem(tag, 6)
	end

	-- Shield (block) absorbs % and knockback; a broken shield punishes hard.
	if vs.blocking and vs.stamina > 0 then
		percent *= (1 - C.BlockPercentReduction)
		kbMult *= (1 - C.BlockKnockbackReduction)
		vs.stamina = math.max(0, vs.stamina - (percent + 6))
		if vs.stamina <= 0 then
			vs.blocking = false
			kbMult = (kbMult / (1 - C.BlockKnockbackReduction)) * C.BlockBreakKnockbackMult
			percent /= (1 - C.BlockPercentReduction)
			heavy = true
		end
	end

	-- Add damage, then launch scaled by the NEW percent.
	vs.damage = math.min(vs.damage + percent, 999)
	local speed = (C.BaseKnockback + vs.damage * C.KnockbackGrowth) * kbMult
	applyLaunch(victim, vRoot, aRoot, speed)
	addSpecial(vs, C.SpecialMeterGainPerHitTaken)

	-- Juice: hit-stop on both fighters + reaction animation.
	local stop = heavy and C.HeavyHitStop or C.HitStop
	Animations.freeze(attackerHum, stop)
	Animations.freeze(vHum, stop)
	if heavy then
		Animations.play(vHum, "hit", { priority = Enum.AnimationPriority.Action4 })
	end

	pushStats(victim)
	return true
end

-- ---------------------------------------------------------------------------
-- Action handlers (client-requested, server-validated)
-- ---------------------------------------------------------------------------

local function handlePunch(player: Player)
	local s = getState(player)
	if not s.inCombat or s.blocking then
		return
	end
	if now() - s.lastPunchAt < C.PunchCooldown then
		return
	end
	if not spendStamina(s, C.PunchStaminaCost) then
		return
	end
	s.lastPunchAt = now()

	if now() <= s.comboExpireAt then
		s.combo = math.min(s.combo + 1, C.MaxCombo)
	else
		s.combo = 1
	end
	s.comboExpireAt = now() + C.ComboWindow

	local isFinisher = s.combo >= C.MaxCombo
	local percent = isFinisher and (C.PunchPercent * C.ComboFinisherMultiplier) or C.PunchPercent
	local kbMult = isFinisher and C.FinisherKnockbackMult or C.PunchKnockbackMult

	-- Attack animation (cycles punch1/2/3, or the finisher).
	local _, aHum = getRig(player)
	if aHum then
		local animName = isFinisher and "finisher" or ("punch" .. (((s.combo - 1) % 3) + 1))
		Animations.play(aHum, animName, { priority = Enum.AnimationPriority.Action })
	end

	local landed = false
	for _, victim in findTargets(player, C.HitRange, C.HitRadius) do
		if dealHit(player, victim, percent, kbMult, isFinisher) then
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
		s.combo = 0
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
	local wantBlock = held == true and s.stamina > 0
	if wantBlock ~= s.blocking then
		s.blocking = wantBlock
		local _, hum = getRig(player)
		if wantBlock then
			Animations.play(hum, "block", { looped = true, priority = Enum.AnimationPriority.Action2 })
		else
			Animations.stop(hum, "block")
		end
	end
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
	local _, hum, root = getRig(player)
	if not root then
		return
	end
	s.lastDodgeAt = now()
	s.iFrameUntil = now() + C.DodgeDuration
	s.blocking = false

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
	Debris:AddItem(lv, C.DodgeDuration)
	Debris:AddItem(attachment, C.DodgeDuration + 0.05)

	Animations.play(hum, "dodge", { priority = Enum.AnimationPriority.Action3 })
	Remotes.get("CombatFeedback"):FireAllClients({ kind = "dodge", attacker = player.UserId })
	pushStats(player)
end

local function handleSpecial(player: Player)
	local s = getState(player)
	if not s.inCombat or s.blocking then
		return
	end
	if s.special < C.SpecialMeterMax then
		return
	end
	s.special = 0

	local _, hum = getRig(player)
	Animations.play(hum, "special", { priority = Enum.AnimationPriority.Action4 })

	for _, victim in findTargets(player, C.SpecialRange, C.SpecialRadius) do
		dealHit(player, victim, C.SpecialPercent, C.SpecialKnockbackMult, true)
		Remotes.get("CombatFeedback"):FireAllClients({
			kind = "special",
			attacker = player.UserId,
			victim = victim.UserId,
		})
	end
	Remotes.get("CombatFeedback"):FireAllClients({ kind = "special_cast", attacker = player.UserId })
	pushStats(player)
end

-- ---------------------------------------------------------------------------
-- Ragdoll on KO (ring-out)
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
			local creator = humanoid:FindFirstChild("creator") :: ObjectValue?
			local killer = nil
			if creator and creator.Value then
				killer = Players:GetPlayerFromCharacter((creator.Value :: Instance).Parent)
			end
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

	-- Regen + stat replication tick.
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, s in state do
			if s.inCombat then
				if now() - s.lastStaminaSpendAt >= C.StaminaRegenDelay and not s.blocking then
					s.stamina = math.min(C.MaxStamina, s.stamina + C.StaminaRegenPerSecond * dt)
				end
				if s.blocking then
					s.stamina = math.max(0, s.stamina - C.BlockStaminaCostPerSecond * dt)
					if s.stamina <= 0 then
						s.blocking = false
					end
				end
				if s.combo > 0 and now() > s.comboExpireAt then
					s.combo = 0
				end
			end
		end
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
