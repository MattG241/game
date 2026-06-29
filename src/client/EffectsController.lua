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

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Cartoon impact burst: bright sparkly "stars" punching outward + a flash light.
local function spawnHitSpark(position: Vector3, color: Color3, count: number, speed: number, size: number?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	part.Parent = workspace

	local sz = size or 1.6
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, sz),
		NumberSequenceKeypoint.new(0.7, sz * 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = part
	emitter:Emit(count)

	-- A quick expanding ring for a "pow" pop.
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Shape = Enum.PartType.Ball
	ring.Size = Vector3.one * (sz * 1.5)
	ring.CFrame = CFrame.new(position)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		Size = Vector3.one * (sz * 6),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.3)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 8
	light.Range = 16
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
			spawnHitSpark(pos, big and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(255, 250, 180), big and 34 or 16, big and 34 or 20, big and 3 or 1.6)
			playSound(big and "finisher" or "punch", pos)
		end
		if isLocalAttacker or isLocalVictim then
			shake(data.kind == "finisher" and 1.8 or 0.6)
		end
	elseif data.kind == "special" then
		if victimRoot then
			spawnHitSpark(victimRoot.Position, Color3.fromRGB(120, 230, 255), 60, 44, 3.5)
			playSound("special", victimRoot.Position)
		end
		if isLocalAttacker or isLocalVictim then
			shake(2.4)
		end
	elseif data.kind == "special_cast" then
		if attackerRoot then
			spawnHitSpark(attackerRoot.Position, Color3.fromRGB(255, 120, 230), 45, 26, 2.4)
			playSound("special", attackerRoot.Position)
		end
	elseif data.kind == "dodge" then
		if attackerRoot then
			spawnHitSpark(attackerRoot.Position, Color3.fromRGB(150, 220, 255), 12, 12, 1.2)
			playSound("dodge", attackerRoot.Position)
		end
	end
end

-- Full-screen colored flash that fades out (KO pop).
local flashFrame: Frame? = nil
local function screenFlash(color: Color3, strength: number)
	if not flashFrame then
		local gui = Instance.new("ScreenGui")
		gui.Name = "UAF_Flash"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 50
		gui.Parent = player:WaitForChild("PlayerGui")
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = gui
		flashFrame = f
	end
	local f = flashFrame :: Frame
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - strength
	TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

-- Local "danger" screen tint that intensifies with the local fighter's %.
local dangerTint: ColorCorrectionEffect? = nil
local function updateDanger(damage: number)
	if not dangerTint then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "UAF_DamageTint"
		cc.Parent = game:GetService("Lighting") -- client-side only; local effect
		dangerTint = cc
	end
	local t = math.clamp(damage / 150, 0, 1)
	local cc = dangerTint :: ColorCorrectionEffect
	cc.TintColor = Color3.fromRGB(255, 255 - math.floor(120 * t), 255 - math.floor(120 * t))
	cc.Contrast = 0.08 * t
end

function EffectsController.start()
	camera = workspace.CurrentCamera
	Remotes.get("CombatFeedback").OnClientEvent:Connect(onFeedback)

	-- KO pop: white flash + a kick of shake when anyone is knocked out.
	Remotes.get("MatchStateChanged").OnClientEvent:Connect(function(data)
		if data.phase == "ko" then
			screenFlash(Color3.fromRGB(255, 255, 255), 0.55)
			shake(1.2)
		elseif data.phase == "go" then
			screenFlash(Color3.fromRGB(120, 255, 160), 0.25)
		elseif data.phase == "ended" then
			updateDanger(0) -- clear the danger tint back in the lobby
		end
	end)

	-- Danger tint follows the local fighter's damage %.
	Remotes.get("StatsChanged").OnClientEvent:Connect(function(data)
		if data.damage then
			updateDanger(data.damage)
		end
	end)

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
