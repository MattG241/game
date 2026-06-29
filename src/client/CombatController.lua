--!strict
--[[
	CombatController
	----------------
	Translates player input into combat *requests*. It performs ZERO authority:
	every action just fires a remote and the server decides what actually
	happens. Local prediction is limited to cosmetic feedback (handled by
	EffectsController), keeping us exploit-resistant.

	Controls:
	  PC:      LMB = Punch, RMB/Hold = Block, Q = Dodge (towards move input), E = Special
	  Mobile:  on-screen buttons created via ContextActionService
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

local CombatController = {}
local player = Players.LocalPlayer

local blocking = false

local function moveDirection(): Vector3
	-- Use the humanoid's MoveDirection so dodge respects WASD / thumbstick.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection
	end
	-- Default: dodge backwards relative to facing.
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return -root.CFrame.LookVector
	end
	return Vector3.zero
end

local function punch(actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.get("RequestPunch"):FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function block(actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		blocking = true
		Remotes.get("RequestBlock"):FireServer(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		blocking = false
		Remotes.get("RequestBlock"):FireServer(false)
	end
	return Enum.ContextActionResult.Pass
end

local function dodge(actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.get("RequestDodge"):FireServer(moveDirection())
	end
	return Enum.ContextActionResult.Pass
end

local function special(actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.get("RequestSpecial"):FireServer()
	end
	return Enum.ContextActionResult.Pass
end

function CombatController.start()
	-- Bind actions. `true` => create a mobile touch button automatically.
	ContextActionService:BindAction("UAF_Punch", punch, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("UAF_Block", block, true, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("UAF_Dodge", dodge, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("UAF_Special", special, true, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)

	-- Position + label the mobile buttons.
	ContextActionService:SetTitle("UAF_Punch", "PUNCH")
	ContextActionService:SetTitle("UAF_Block", "BLOCK")
	ContextActionService:SetTitle("UAF_Dodge", "DODGE")
	ContextActionService:SetTitle("UAF_Special", "SPECIAL")

	ContextActionService:SetPosition("UAF_Punch", UDim2.new(1, -130, 1, -160))
	ContextActionService:SetPosition("UAF_Block", UDim2.new(1, -260, 1, -120))
	ContextActionService:SetPosition("UAF_Dodge", UDim2.new(1, -260, 1, -250))
	ContextActionService:SetPosition("UAF_Special", UDim2.new(1, -130, 1, -300))

	-- Recolour the special button so it reads as the "ultimate".
	local button = ContextActionService:GetButton("UAF_Special")
	if button then
		button.ImageColor3 = Color3.fromRGB(220, 40, 255)
	end
end

return CombatController
