--[[
	Ragdoll -- turns a normal standing character into a floppy body, and back.

	How it works, in plain terms: a Roblox character is held together by rigid
	joints called Motor6Ds -- that is what keeps the arm attached to the
	shoulder at a fixed angle. This switches every one of those rigid joints off
	and puts a BallSocketConstraint alongside it, which is a joint that still
	holds the limb on but lets it swing freely. The result is a body that flops
	instead of standing.

	Nobody is "killed" here -- health is never touched, exactly as the design
	asks. The character is simply switched into physics mode and then thrown.

	Ragdolling is REVERSIBLE. Nothing is destroyed, only disabled, and every
	original value is remembered -- so recover() can stand a player back up.
	Elimination never calls recover (the body is deleted instead), but the Brain
	Rot NPC's knockdown does.
]]

local PhysicsService = game:GetService("PhysicsService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Ragdoll = {}

-- Collision groups keep exploded bodies from body-blocking players who are
-- still running. Both groups still collide with the arena itself, so corpses
-- land on the floor as normal -- they just cannot shove anybody around.
Ragdoll.LIVE_GROUP = "LivePlayer"
Ragdoll.CORPSE_GROUP = "Ragdoll"
Ragdoll.NPC_GROUP = "NPC"

--[[
	Registers the two groups and the one rule that matters. Call once at server
	start, before any character spawns.
]]
function Ragdoll.setupCollisionGroups()
	for _, name in { Ragdoll.LIVE_GROUP, Ragdoll.CORPSE_GROUP, Ragdoll.NPC_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end

	-- The whole point: a corpse cannot collide with a living player.
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.LIVE_GROUP, Ragdoll.CORPSE_GROUP, false)

	-- Nor can the Brain Rot NPC. It catches people by getting close, not by
	-- barging into them -- and a chaser that can physically shove you would be
	-- able to push players off the map.
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.NPC_GROUP, Ragdoll.LIVE_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.NPC_GROUP, Ragdoll.CORPSE_GROUP, false)

	-- Everything else stays normal: players bump into each other, corpses pile
	-- on each other, and all three land on the arena floor.
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.LIVE_GROUP, Ragdoll.LIVE_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.CORPSE_GROUP, Ragdoll.CORPSE_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.LIVE_GROUP, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.CORPSE_GROUP, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(Ragdoll.NPC_GROUP, "Default", true)
end

--[[
	Puts every part of a character into one of the groups above.
]]
function Ragdoll.setCollisionGroup(character: Model, groupName: string)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

-- What we changed on each ragdolled character, so recover() can put it all
-- back. Weak keys, so a character that gets destroyed mid-ragdoll (the normal
-- elimination path) drops out of here on its own with nothing to clean up.
type SocketLimits = { upper: number, twistLow: number, twistHigh: number }
type PoseState = { torque: number, kinematic: boolean }

type Record = {
	motors: { Motor6D },
	poseState: { [AnimationConstraint]: PoseState },
	sockets: { [BallSocketConstraint]: SocketLimits },
	added: { Instance },
	collide: { [BasePart]: boolean },
	animate: BaseScript?,
}

-- How far a joint may bend while limp. The avatar's own joints are limited to
-- about 20 degrees, which is right for a walking character but leaves a
-- ragdoll standing around like a mannequin. Widening them for the duration is
-- what turns a falling plank into a body that crumples.
local RAGDOLL_JOINT_ANGLE = 65
local RAGDOLL_TWIST = 45

local active: { [Model]: Record } = setmetatable({}, { __mode = "k" }) :: any

function Ragdoll.isRagdolled(character: Model): boolean
	return active[character] ~= nil
end

--[[
	Makes the character floppy. Returns true if it worked.
]]
function Ragdoll.apply(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	if active[character] then
		return true -- already floppy, nothing to do
	end

	local record: Record = { motors = {}, poseState = {}, sockets = {}, added = {}, collide = {} }
	active[character] = record

	-- Roblox kills a character if its neck joint disappears while this is on,
	-- and we are about to replace the neck joint. So: off first.
	pcall(function()
		humanoid.RequiresNeck = false
	end)
	pcall(function()
		humanoid.BreakJointsOnDeath = false
	end)

	-- Stop the character trying to stand back up or play walk animations.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("BaseScript") then
		record.animate = animateScript
		animateScript.Disabled = true
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end

	-- STEP 1 -- newer avatars (Roblox's Avatar Joint Upgrade).
	--
	-- These have no Motor6Ds at all. Limbs are physically held on by
	-- BallSocketConstraints, and AnimationConstraints pose those joints.
	--
	-- The property that matters is IsKinematic. While it is true the joint
	-- rigidly snaps to whatever pose the animation asks for and IGNORES physics
	-- entirely -- which is why weakening or even removing its torque changes
	-- nothing, and the body falls over as one stiff plank.
	--
	-- Switching it to false turns the same joint into a force-based one that
	-- physics can push around. With no torque behind it, every joint then hangs
	-- limp and the character actually ragdolls. This is Roblox's own documented
	-- route for physically-simulated characters.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			record.poseState[descendant] = {
				torque = descendant.MaxTorque,
				kinematic = descendant.IsKinematic,
			}
			descendant.IsKinematic = false -- let physics move this joint at all
			descendant.MaxTorque = 0 -- and give it no strength to resist with
		elseif descendant:IsA("BallSocketConstraint") and descendant.Name ~= "RagdollSocket" then
			-- Loosen the avatar's own joints so the body can actually crumple.
			-- Restored exactly on recovery.
			record.sockets[descendant] = {
				upper = descendant.UpperAngle,
				twistLow = descendant.TwistLowerAngle,
				twistHigh = descendant.TwistUpperAngle,
			}
			descendant.UpperAngle = RAGDOLL_JOINT_ANGLE
			descendant.TwistLowerAngle = -RAGDOLL_TWIST
			descendant.TwistUpperAngle = RAGDOLL_TWIST
		end
	end

	-- STEP 2 -- classic avatars.
	--
	-- Older rigs are held together by rigid Motor6Ds instead, so those get a
	-- swinging BallSocketConstraint added alongside and the motor switched off.
	-- On a newer avatar this loop finds nothing and does nothing. Both kinds
	-- end up ragdolling correctly.
	for _, descendant in character:GetDescendants() do
		if not descendant:IsA("Motor6D") or not descendant.Enabled then
			continue
		end
		local part0, part1 = descendant.Part0, descendant.Part1
		if not part0 or not part1 then
			continue
		end

		local a0 = Instance.new("Attachment")
		a0.Name = "RagdollAttachment0"
		a0.CFrame = descendant.C0
		a0.Parent = part0

		local a1 = Instance.new("Attachment")
		a1.Name = "RagdollAttachment1"
		a1.CFrame = descendant.C1
		a1.Parent = part1

		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "RagdollSocket"
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true -- stop limbs bending inside out
		socket.TwistLimitsEnabled = true
		socket.UpperAngle = 45
		socket.TwistLowerAngle = -45
		socket.TwistUpperAngle = 45
		socket.Parent = part0

		-- Switched off, not destroyed, so standing back up is just a matter of
		-- switching it on again.
		descendant.Enabled = false

		table.insert(record.motors, descendant)
		table.insert(record.added, a0)
		table.insert(record.added, a1)
		table.insert(record.added, socket)
	end

	-- STEP 2.5 -- pin the invisible root part to the body.
	--
	-- Every AnimationConstraint on these rigs has MaxForce = 0: they apply
	-- twist, never pull. While the joints are kinematic that does not matter,
	-- because the whole character moves as one rigid piece. The moment they go
	-- force-based, nothing is holding the HumanoidRootPart in place at all --
	-- it drops away from the body, falls through the floor, and hauls the rest
	-- of the character down after it.
	--
	-- A plain weld to the torso for the duration keeps it where it belongs.
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("LowerTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
	if rootPart and rootPart:IsA("BasePart") and torso and torso:IsA("BasePart") then
		local rootWeld = Instance.new("WeldConstraint")
		rootWeld.Name = "RagdollRootWeld"
		rootWeld.Part0 = rootPart
		rootWeld.Part1 = torso
		rootWeld.Parent = rootPart
		table.insert(record.added, rootWeld)
	end

	-- STEP 3 -- take physics control off the player's own machine.
	--
	-- This has to happen BEFORE the collision changes below, and it is the
	-- difference between a ragdoll and a body half-buried in the floor. While
	-- the client owns the character its Humanoid keeps re-asserting the normal
	-- R15 rule that only the torso collides, undoing whatever the server sets.
	-- The legs then hang straight through the ground.
	--
	-- Handing simulation to the server stops that fight. It also means everyone
	-- watches the same flop rather than each machine inventing its own.
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end

	-- Limbs need collision so the body piles up on the floor instead of sinking
	-- through it. The invisible root part must NOT collide, or it props the
	-- body up like a broom handle.
	--
	-- Only the character's own limbs are touched. Hats and other accessories
	-- are left alone -- giving those collision makes the body jitter and kick
	-- itself around the floor.
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			record.collide[part] = part.CanCollide
			part.CanCollide = part.Name ~= "HumanoidRootPart"
		end
	end

	-- Now that the limbs collide, move them out of the way of live players.
	Ragdoll.setCollisionGroup(character, Ragdoll.CORPSE_GROUP)

	return true
end

--[[
	Stands a ragdolled character back up, undoing everything apply() changed.

	Used by the Brain Rot NPC's knockdown. The elimination path never calls this
	-- eliminated bodies are deleted instead.

	Returns false if the character was not ragdolled in the first place.
]]
function Ragdoll.recover(character: Model): boolean
	local record = active[character]
	if not record then
		return false
	end
	active[character] = nil

	-- Remove the swinging joints first, then switch the rigid ones back on --
	-- the other order leaves the limb briefly held by both at once.
	for _, instance in record.added do
		if instance.Parent then
			instance:Destroy()
		end
	end
	for _, motor in record.motors do
		if motor.Parent then
			motor.Enabled = true
		end
	end

	-- Give the joints their strength back, which is what actually pulls a newer
	-- avatar back into a standing pose.
	for constraint, state in record.poseState do
		if constraint.Parent then
			constraint.MaxTorque = state.torque
			constraint.IsKinematic = state.kinematic -- back to snapping to the animation
		end
	end
	for socket, limits in record.sockets do
		if socket.Parent then
			socket.UpperAngle = limits.upper
			socket.TwistLowerAngle = limits.twistLow
			socket.TwistUpperAngle = limits.twistHigh
		end
	end
	for part, canCollide in record.collide do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end

	if record.animate and record.animate.Parent then
		record.animate.Disabled = false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	end

	-- Stand them back up explicitly rather than trusting the Humanoid to do it.
	-- Left to itself it sits in FallingDown on its back indefinitely, because
	-- the body is lying flat and there is nothing to right it. Keeping the
	-- position but zeroing the tilt puts them on their feet where they fell.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = root.Position
		local facing = root.CFrame.LookVector
		local flat = Vector3.new(facing.X, 0, facing.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.zAxis
		end
		root.CFrame = CFrame.lookAt(position + Vector3.new(0, 2.5, 0), position + Vector3.new(0, 2.5, 0) + flat.Unit)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	Ragdoll.setCollisionGroup(character, Ragdoll.LIVE_GROUP)

	-- Give the character back to its owner, or they would be left unable to
	-- move despite being upright again.
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			pcall(function()
				part:SetNetworkOwnershipAuto()
			end)
		end
	end

	return true
end

--[[
	A shove, for being tackled rather than blown up.

	Slack joints alone do not knock a standing body over -- it just goes limp
	and stays upright like a mannequin. Something has to push it. This is much
	gentler than launch() and keeps the body on the ground.
]]
function Ragdoll.shove(character: Model, direction: Vector3, power: number)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.zAxis
	end
	local velocity = flat.Unit * power + Vector3.new(0, power * 0.35, 0)

	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = velocity
		end
	end
end

--[[
	Throws the ragdolled body. Direction is randomised each time so no two
	eliminations look the same.
]]
function Ragdoll.launch(character: Model)
	-- Pick a random compass direction, then tilt it upwards.
	local horizontal = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	if horizontal.Magnitude < 0.01 then
		horizontal = Vector3.xAxis
	end
	local direction = (horizontal.Unit * Config.LAUNCH_HORIZONTAL + Vector3.yAxis * Config.LAUNCH_VERTICAL).Unit
	local velocity = direction * Config.LAUNCH_SPEED

	for _, part in character:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end

		-- Take physics control away from the player's own machine, so the
		-- launch is simulated on the server and everyone sees the same flight.
		pcall(function()
			part:SetNetworkOwner(nil)
		end)

		part.AssemblyLinearVelocity = velocity
		part.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * Config.LAUNCH_SPIN,
			(math.random() - 0.5) * Config.LAUNCH_SPIN,
			(math.random() - 0.5) * Config.LAUNCH_SPIN
		)
	end
end

--[[
	The visible bang. Deliberately harmless: BlastPressure of zero means the
	explosion deals no damage and applies no force, so it cannot hurt bystanders
	or tear the body apart. We do the throwing ourselves in launch() so it stays
	predictable. The boom sound is built into the Explosion object.
]]
function Ragdoll.explode(position: Vector3)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = Config.EXPLOSION_RADIUS
	explosion.BlastPressure = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace

	game:GetService("Debris"):AddItem(explosion, 4)
end

return Ragdoll
