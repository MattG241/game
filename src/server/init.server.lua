--!strict
--[[
	Server bootstrap
	----------------
	Single entry point. Runs once when the server starts:
	  1. Build the Remotes folder (must happen before clients require anything).
	  2. Apply the underground-neon atmosphere to Lighting.
	  3. Build the lobby + matchmaking pad.
	  4. Start every service in dependency order.
	  5. Hook autosave + graceful shutdown.

	Service start order matters:
	  Data -> Player -> Monetization (needs Player) -> Combat -> Matchmaking
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

-- 1. Remotes first so clients can WaitForChild them.
Remotes.init()

-- Take full control of spawning: the match system loads characters explicitly,
-- so Roblox's auto-respawn-on-death must be off or it would yank fighters out
-- of the stage mid-match. PlayerService spawns players into the lobby on join.
Players.CharacterAutoLoads = false

-- Floaty platform-fighter gravity (Smash-style hang time + recovery).
workspace.Gravity = GameConfig.Combat.Gravity

-- 2. Atmosphere.
local function applyAtmosphere()
	local a = GameConfig.Atmosphere
	Lighting.ClockTime = a.ClockTime
	Lighting.Brightness = a.Brightness
	Lighting.OutdoorAmbient = a.OutdoorAmbient
	Lighting.Ambient = a.Ambient
	Lighting.FogColor = a.FogColor
	Lighting.FogStart = a.FogStart
	Lighting.FogEnd = a.FogEnd
	Lighting.GlobalShadows = true

	local function ensure(className: string, name: string)
		local inst = Lighting:FindFirstChild(name)
		if not inst then
			inst = Instance.new(className)
			inst.Name = name
			inst.Parent = Lighting
		end
		return inst
	end

	-- Bright, vivid sky (the default Roblox sky is sunny + cloudy — perfect for
	-- the arcade look). Punchy sun angle for nice rim light on fighters.
	local sky = ensure("Sky", "ArenaSky") :: Sky
	sky.SunAngularSize = 21
	sky.CelestialBodiesShown = true

	-- Post-processing tuned BRIGHT and saturated (arcade pop, not gritty).
	local bloom = ensure("BloomEffect", "ArenaBloom") :: BloomEffect
	bloom.Intensity = 0.8
	bloom.Size = 20
	bloom.Threshold = 1.4 -- only the brightest highlights bloom

	local cc = ensure("ColorCorrectionEffect", "ArenaColor") :: ColorCorrectionEffect
	cc.Saturation = 0.35 -- candy colors
	cc.Contrast = 0.08
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(255, 252, 245)

	local atmos = ensure("Atmosphere", "ArenaAtmosphere") :: Atmosphere
	atmos.Density = 0.28
	atmos.Haze = 1.0
	atmos.Color = a.FogColor
	atmos.Decay = Color3.fromRGB(245, 235, 255)

	-- Drifting cartoon clouds for depth.
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = workspace.Terrain
end
applyAtmosphere()

-- 3. Lobby: a neon platform with a glowing matchmaking pad in the middle.
local function buildLobby()
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"

	local floor = Instance.new("Part")
	floor.Name = "LobbyFloor"
	floor.Size = Vector3.new(120, 2, 120)
	floor.Position = Vector3.new(0, 47, 0)
	floor.Anchored = true
	floor.Color = Color3.fromRGB(95, 170, 255) -- bright sky-blue arcade floor
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = lobby

	-- Spawn location.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(120, 1, 120)
	spawn.Position = Vector3.new(0, 48.5, 0)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Parent = lobby

	-- Glowing matchmaking pad (purely cosmetic; the UI button drives the queue).
	local pad = Instance.new("Part")
	pad.Name = "MatchPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, 24, 24)
	pad.CFrame = CFrame.new(0, 49, 0) * CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.Color = GameConfig.Atmosphere.NeonAccent
	pad.Material = Enum.Material.Neon
	pad.CanCollide = false
	pad.Parent = lobby

	local padLight = Instance.new("PointLight")
	padLight.Color = GameConfig.Atmosphere.NeonAccent
	padLight.Brightness = 6
	padLight.Range = 50
	padLight.Parent = pad

	-- A couple of neon perimeter pillars for vibe.
	for i, off in { Vector3.new(55, 0, 55), Vector3.new(-55, 0, 55), Vector3.new(55, 0, -55), Vector3.new(-55, 0, -55) } do
		local pillar = Instance.new("Part")
		pillar.Name = "LobbyPillar" .. i
		pillar.Size = Vector3.new(4, 40, 4)
		pillar.Position = Vector3.new(0, 68, 0) + off
		pillar.Anchored = true
		pillar.Color = ({ Color3.fromRGB(255, 110, 60), Color3.fromRGB(120, 230, 255), Color3.fromRGB(120, 255, 150), Color3.fromRGB(255, 220, 60) })[i]
		pillar.Material = Enum.Material.Neon
		pillar.Parent = lobby
		local l = Instance.new("PointLight")
		l.Color = GameConfig.Atmosphere.NeonAccent
		l.Range = 30
		l.Brightness = 3
		l.Parent = pillar
	end

	lobby.Parent = workspace
end
buildLobby()

-- 4. Start services in order.
local Server = script
local DataService = require(Server.DataService)
local PlayerService = require(Server.PlayerService)
local MonetizationService = require(Server.MonetizationService)
local CombatService = require(Server.CombatService)
local MatchmakingService = require(Server.MatchmakingService)

PlayerService.start()
MonetizationService.start()
CombatService.start()
MatchmakingService.start()

-- 5. Persistence lifecycle.
DataService.startAutosave()
game:BindToClose(function()
	DataService.flushAll()
end)

-- Kill plane handler: anything tagged falls off => take the player out.
workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("BasePart") and inst:GetAttribute("KillPlane") then
		inst.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = 0
				end
			end
		end)
	end
end)

print("[UAF] Server started — Underground Arena Fighters is live.")
