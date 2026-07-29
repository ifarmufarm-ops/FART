--[[
	AbilityInput -- reads the ability button and plays the movement.

	The split of work is deliberate:
		this file  -- notices the button, asks the server, moves the character
		the server -- decides whether you actually had the ability, and plays
		              the sound and trail so that EVERYONE sees and hears them

	Nothing here decides anything. Pressing the button when your slot is empty
	sends a request that the server silently ignores.

	Movement is applied here because your own machine owns your character's
	physics -- a velocity set by the server would be overwritten instantly.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local AbilityInput = {}

local ACTION_NAME = "HotPotatoAbility"

local carried: string? = nil
local usesLeft = 0
local onChanged: ((Abilities.Definition?, number) -> ())? = nil

--=============================================================================
-- WHICH BUTTON, ON WHICHEVER THING YOU ARE PLAYING ON
--=============================================================================

--[[
	What to tell the player to press. Worked out from how they last gave input
	rather than from what hardware they own, because plenty of people play on a
	laptop with a controller plugged in and swap between the two mid-round.
]]
function AbilityInput.getPrompt(): string
	local last = UserInputService:GetLastInputType()

	if last == Enum.UserInputType.Touch then
		return "TAP USE"
	end
	if last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2
		or last == Enum.UserInputType.Gamepad3
		or last == Enum.UserInputType.Gamepad4
	then
		return "X"
	end
	return "SHIFT"
end

local function getParts(): (Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid, (if root and root:IsA("BasePart") then root else nil)
end

--=============================================================================
-- PLAYING THE MOVEMENT
--=============================================================================

local function doDash()
	local _, root = getParts()
	if not root then
		return
	end

	-- Direction is locked in at the moment of the dash, so you travel in a
	-- straight line even if you swing the camera mid-flight.
	local forward = root.CFrame.LookVector

	-- Held for a fraction of a second rather than set once. Roblox's character
	-- controller pulls your speed back to walking pace every frame, so a single
	-- shove is gone before it moves you anywhere.
	task.spawn(function()
		local finish = os.clock() + Config.DASH_DURATION
		while os.clock() < finish do
			local _, current = getParts()
			if not current then
				return -- died or respawned mid-dash
			end
			-- Vertical speed is left alone, so dashing off a ledge still arcs
			-- and dashing upwards is not possible.
			local velocity = current.AssemblyLinearVelocity
			current.AssemblyLinearVelocity =
				Vector3.new(forward.X * Config.DASH_SPEED, velocity.Y, forward.Z * Config.DASH_SPEED)
			task.wait()
		end

		-- WAIT UNTIL THEY ARE BACK ON THE FLOOR.
		--
		-- The glide below is a LANDING effect. Applying it the instant the burst
		-- ended meant that dashing off a ledge spent the whole slide in mid-air,
		-- where it does nothing you can feel, and there was no slide left by the
		-- time you touched down. Dashing along flat ground falls straight
		-- through this loop and glides immediately, which is the common case.
		local airborneUntil = os.clock() + 3 -- safety net, never wait forever
		while os.clock() < airborneUntil do
			local humanoid = getParts()
			if not humanoid then
				return
			end
			local state = humanoid:GetState()
			if
				state ~= Enum.HumanoidStateType.Freefall
				and state ~= Enum.HumanoidStateType.Jumping
			then
				break -- feet on the ground
			end
			task.wait()
		end

		-- THE GLIDE. Without this the controller snaps you back to walking pace
		-- the moment you land, which feels like hitting a wall and makes a
		-- second dash start from a standstill. Instead the speed is eased down
		-- to a walk over a fraction of a second, so you slide on landing as if
		-- the floor were briefly icy -- and a dash launched during the slide
		-- carries straight on from the one before.
		local glideStart = os.clock()
		local top = Config.DASH_SPEED * Config.DASH_GLIDE_STRENGTH
		while true do
			local elapsed = os.clock() - glideStart
			if elapsed >= Config.DASH_GLIDE_DURATION then
				break
			end
			local _, current = getParts()
			if not current then
				return
			end
			-- Eased from the glide's top speed down to a normal walk.
			local remaining = 1 - (elapsed / Config.DASH_GLIDE_DURATION)
			local speed = Config.BASE_WALK_SPEED + (top - Config.BASE_WALK_SPEED) * remaining
			if speed <= Config.BASE_WALK_SPEED then
				break -- already at walking pace; let the controller have it back
			end
			local velocity = current.AssemblyLinearVelocity
			current.AssemblyLinearVelocity = Vector3.new(forward.X * speed, velocity.Y, forward.Z * speed)
			task.wait()
		end
	end)
end

local function doFartJump()
	local humanoid, root = getParts()
	if not (humanoid and root) then
		return
	end
	-- Replace vertical speed rather than adding to it, so the boost feels the
	-- same whether you jump at the top of an arc or halfway down.
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, Config.FART_JUMP_POWER, velocity.Z)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

--=============================================================================
-- ASKING THE SERVER
--=============================================================================

local function definitionOf(): Abilities.Definition?
	return Abilities.get(carried)
end

local lastLocalUse = 0

--[[
	Plays the movement immediately and tells the server in the same breath.

	The movement is NOT delayed until the server answers. A round trip is only
	about a tenth of a second, but for a double jump that is the difference
	between working and not: by the time the reply lands you have already fallen
	most of the way back down, so the second jump never beats the height of the
	first and the ability looks like it does nothing.

	Playing it locally first is safe. The server still decides whether the
	charge is actually spent, which is the part worth protecting. If it refuses,
	the worst case is one unearned hop -- and since a player's own machine owns
	their character's physics, they could produce that hop anyway.
]]
local function tryUse(activation: string): boolean
	local definition = definitionOf()
	if not definition or definition.activation ~= activation or usesLeft <= 0 then
		return false
	end

	-- Matches the server's rate limit, so a held key cannot fire repeatedly in
	-- the window before the slot officially clears.
	if os.clock() - lastLocalUse < Config.ABILITY_REQUEST_COOLDOWN then
		return false
	end
	lastLocalUse = os.clock()

	if definition.id == "Dash" then
		doDash()
	elseif definition.id == "FartJump" then
		doFartJump()
	end

	-- Tick the counter down here too, so the pips empty the instant you press
	-- rather than a tenth of a second later when the server's reply lands. The
	-- server's next update overwrites this with the real number, so a wrong
	-- guess corrects itself immediately.
	usesLeft -= 1
	if usesLeft <= 0 then
		carried = nil
	end
	if onChanged then
		onChanged(definitionOf(), usesLeft)
	end

	Remotes.AbilityRequest:FireServer(activation)
	return true
end

local function onAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		tryUse("Key")
	end
	-- Pass it along -- Shift is also shift-lock, and swallowing it would break
	-- that for anyone who uses it.
	return Enum.ContextActionResult.Pass
end

--[[
	Double Jump fires itself: you press jump again while already in the air.
	JumpRequest covers space, gamepad and the mobile jump button in one.

	Two gates, and the second one is the important one:

	  * you must actually be in Freefall -- "Jumping" is the take-off state of
	    an ordinary jump, not a mid-air press

	  * you must be at or past the top of your arc. Without this the charge is
	    spent a fraction of a second after take-off, while you are still flying
	    upwards faster than the boost itself, so nothing visible happens and the
	    ability looks broken. JumpRequest also repeats while the key is held,
	    which makes that the normal case rather than an edge case.
]]
local function onJumpRequest()
	local definition = definitionOf()
	if not definition or definition.activation ~= "AirJump" then
		return
	end

	local humanoid, root = getParts()
	if not (humanoid and root) then
		return
	end
	if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		return
	end
	if root.AssemblyLinearVelocity.Y > Config.FART_JUMP_APEX_SPEED then
		return -- still on the way up; a boost here would do nothing
	end

	tryUse("AirJump")
end

--=============================================================================
-- START
--=============================================================================

--[[
	`slotChanged(definition, usesLeft)` is called whenever what you are carrying
	changes -- including with nil when the last use is spent. The HUD in
	init.client.luau uses it to redraw the slot and its use pips.
]]
function AbilityInput.start(slotChanged: (Abilities.Definition?, number) -> ())
	onChanged = slotChanged

	Remotes.AbilityState.OnClientEvent:Connect(function(abilityId: string?, remaining: number?)
		carried = abilityId
		usesLeft = remaining or 0
		if onChanged then
			onChanged(definitionOf(), usesLeft)
		end
	end)

	-- Confirmation that the charge really was spent. Dash and Double Jump have
	-- already been played locally by tryUse, so nothing is replayed here --
	-- doing so would apply them twice. Sneakers needs nothing either: the
	-- server sets WalkSpeed directly, which replicates on its own.
	Remotes.AbilityUsed.OnClientEvent:Connect(function(_abilityId: string) end)

	-- One binding covering all three platforms:
	--   keyboard -- Shift, either side
	--   gamepad  -- X. A is jump and B is cancel/back, so X is the first free
	--               face button; without it Dash and Sneakers are simply
	--               unusable on a console.
	--   touch    -- the `true` creates an on-screen button automatically
	ContextActionService:BindAction(
		ACTION_NAME,
		onAction,
		true,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:SetTitle(ACTION_NAME, "USE")

	-- Push the touch button up and left of the jump button, which sits in the
	-- bottom-right corner. Left at its default it lands close enough to the
	-- jump button to invite mis-taps.
	ContextActionService:SetPosition(ACTION_NAME, UDim2.new(1, -140, 1, -220))

	UserInputService.JumpRequest:Connect(onJumpRequest)

	-- Redraw the hint when someone swaps between keyboard, pad and touch, so
	-- the prompt always names a button they actually have.
	UserInputService.LastInputTypeChanged:Connect(function()
		if onChanged then
			onChanged(definitionOf(), usesLeft)
		end
	end)
end

return AbilityInput
