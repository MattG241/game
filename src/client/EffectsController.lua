--!strict
--[[
	EffectsController
	-----------------
	Pure juice. Listens to CombatFeedback and spawns hit sparks, special-move
	bursts, dodge trails, sound effects, and camera shake. None of this affects
	gameplay — it just makes the combat feel good and clip-worthy.

	SOUND IDS: placeholders are left blank. Drop real asset ids into the SOUNDS
	table and they'll play automatically. Missing ids fail silently.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

local EffectsController = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Fill these with real rbxassetid:// strings to enable audio.
local SOUNDS = {
	punch = "", -- e.g. "rbxassetid://0000000000"
	finisher = "",
	special = "",
	dodge = "",
	block = "",
}

local function playSound(kind: string, position: Vector3?)
	local id = SOUNDS[kind]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.6
	if position then
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Position = position
		part.Parent = workspace
		sound.Parent = part
		sound:Play()
		Debris:AddItem(part, 3)
	else
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 3)
	end
end

local function characterRoot(userId: number): BasePart?
	local p = Players:GetPlayerByUserId(userId)
	local character = p and p.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Camera shake (decaying random offset applied for `duration`).
local shakeMagnitude = 0
local shakeDecay = 0
local function shake(magnitude: number)
	shakeMagnitude = math.max(shakeMagnitude, magnitude)
	shakeDecay = magnitude
end

local function spawnHitSpark(position: Vector3, color: Color3, count: number, speed: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = part
	emitter:Emit(count)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 5
	light.Range = 12
	light.Parent = part
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()

	Debris:AddItem(part, 1)
end

local function onFeedback(data)
	local victimRoot = data.victim and characterRoot(data.victim)
	local attackerRoot = data.attacker and characterRoot(data.attacker)
	local isLocalAttacker = data.attacker == player.UserId
	local isLocalVictim = data.victim == player.UserId

	if data.kind == "punch" or data.kind == "finisher" then
		local pos = victimRoot and victimRoot.Position or (attackerRoot and attackerRoot.Position)
		if pos then
			local big = data.kind == "finisher"
			spawnHitSpark(pos, big and Color3.fromRGB(255, 120, 40) or Color3.fromRGB(255, 240, 180), big and 30 or 14, big and 30 or 18)
			playSound(big and "finisher" or "punch", pos)
		end
		if isLocalAttacker or isLocalVictim then
			shake(data.kind == "finisher" and 1.6 or 0.6)
		end
	elseif data.kind == "special" then
		if victimRoot then
			spawnHitSpark(victimRoot.Position, Color3.fromRGB(220, 40, 255), 50, 40)
			playSound("special", victimRoot.Position)
		end
		if isLocalAttacker or isLocalVictim then
			shake(2.2)
		end
	elseif data.kind == "special_cast" then
		if attackerRoot then
			spawnHitSpark(attackerRoot.Position, Color3.fromRGB(220, 40, 255), 40, 24)
			playSound("special", attackerRoot.Position)
		end
	elseif data.kind == "dodge" then
		if attackerRoot then
			spawnHitSpark(attackerRoot.Position, Color3.fromRGB(120, 200, 255), 12, 10)
			playSound("dodge", attackerRoot.Position)
		end
	end
end

function EffectsController.start()
	camera = workspace.CurrentCamera
	Remotes.get("CombatFeedback").OnClientEvent:Connect(onFeedback)

	-- Apply decaying camera shake each frame.
	RunService.RenderStepped:Connect(function(dt)
		if shakeMagnitude > 0.01 then
			local offset = Vector3.new(
				(math.random() - 0.5) * shakeMagnitude,
				(math.random() - 0.5) * shakeMagnitude,
				0
			)
			camera = workspace.CurrentCamera
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			shakeMagnitude = math.max(0, shakeMagnitude - shakeDecay * dt * 3)
		end
	end)
end

return EffectsController
