--!strict
--[[
	Client bootstrap
	----------------
	Single entry point on the client. Waits for the shared modules + remotes to
	replicate, then starts every controller. Wrapped in pcall so one controller
	failing never takes the whole UI down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Make sure the shared modules + remotes have replicated before we start.
local Shared = ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")
require(Shared:WaitForChild("Remotes")) -- warms the remote cache on the client

local Client = script
local controllers = {
	require(Client.HUDController),
	require(Client.MenuController),
	require(Client.CombatController),
	require(Client.EffectsController),
}

for _, controller in controllers do
	local ok, err = pcall(function()
		controller.start()
	end)
	if not ok then
		warn("[UAF] controller failed to start: " .. tostring(err))
	end
end

print("[UAF] Client started.")
