--!strict
--[[
	Remotes -- the two channels the server uses to talk to every player's screen.

	The RemoteEvent objects are created here in code rather than in
	default.project.json. That is deliberate: Rojo only re-reads the project
	file when you restart `rojo serve`, so anything declared there goes stale
	the moment you add to it. Built this way, a plain file save is always enough.

	Nothing here ever takes instructions FROM the client. All of the rules
	(who has the bomb, when it explodes, who is out) are decided on the server,
	and these events only push the results out for display.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- The full picture of the game right now. Sent whenever something changes,
-- not every frame -- the client counts down the timer on its own between
-- updates so it stays smooth.
export type State = {
	phase: "Waiting" | "Intermission" | "Playing" | "RoundOver" | "Sandbox",
	holderUserId: number?, -- who currently has the bomb
	deadline: number?, -- server clock time the timer hits zero
	duration: number?, -- how long this countdown was to begin with
	aliveUserIds: { number }, -- everyone still in the round
}

local FOLDER_NAME = "Remotes"
local EVENT_NAMES =
	{ "StateChanged", "Announce", "AbilityRequest", "AbilityState", "AbilityUsed", "ModifierChanged" }

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		for _, name in EVENT_NAMES do
			if not folder:FindFirstChild(name) then
				local event = Instance.new("RemoteEvent")
				event.Name = name
				event.Parent = folder
			end
		end
		return folder :: Folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local folder = getFolder()

local Remotes = {
	-- Server -> all clients: the State table above.
	StateChanged = folder:WaitForChild("StateChanged") :: RemoteEvent,

	-- Server -> all clients: (text, color, holdSeconds) for the big centre
	-- message, e.g. "Elias was blown up!"
	Announce = folder:WaitForChild("Announce") :: RemoteEvent,

	-- CLIENT -> SERVER. The only one that goes this direction.
	--
	-- Carries a single string: "Key" when the ability button is pressed, or
	-- "AirJump" when the player jumps again in mid-air. It is a REQUEST, never
	-- an instruction -- the server decides whether the player actually has the
	-- ability, is alive, and is off cooldown. See AbilityService.
	AbilityRequest = folder:WaitForChild("AbilityRequest") :: RemoteEvent,

	-- Server -> one client: (abilityId or nil) -- what is in your slot now.
	AbilityState = folder:WaitForChild("AbilityState") :: RemoteEvent,

	-- Server -> one client: (abilityId) -- your request was approved, the
	-- charge is spent, play the movement on your own machine now.
	AbilityUsed = folder:WaitForChild("AbilityUsed") :: RemoteEvent,

	-- Server -> all clients: which beacon events are running right now, as a
	-- list of { id, endsAt, activatorUserId }. Sent on every change rather than
	-- on a timer; the client counts each one down on its own.
	ModifierChanged = folder:WaitForChild("ModifierChanged") :: RemoteEvent,
}

return Remotes
