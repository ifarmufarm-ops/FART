--!strict
--[[
	Scoreboard -- the boards on the lobby wall.

	A board is a flat part with text drawn onto one of its faces. The text is a
	SurfaceGui, created on the server, which means it simply appears for everyone
	-- there is no client code in this feature at all.

	IT FINDS THE PARTS BY TAG, never by name or position. Anything wearing
	Config.TAG_SCOREBOARD becomes a board, and two Attributes on the part say
	which one:

	    StatId  -- SurviveSeconds, Passes, AbilityUses, Punches, RobuxSpent
	    Period  -- optional: AllTime, Daily, Weekly, Monthly
	    Face    -- optional: which side the text goes on, default Front

	That is what makes these replaceable without touching code: build a sign,
	tag it, set StatId. The placeholder slabs below are only built when NOTHING
	is tagged yet, so the moment you tag your own the code stops making its own
	and there is nothing to delete twice. Same arrangement as the floor and the
	pickup zones -- see MAP_INTEGRATION.md.

	Boards refresh ONE AT A TIME, in rotation. Reading a sorted board is a
	rationed request and eight at once can exceed what Roblox allows in a single
	moment.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)

local StatsStore = require(script.Parent.StatsStore)

local Scoreboard = {}

local COLOR_SLAB = Color3.fromRGB(30, 32, 40)
local COLOR_FRAME = Color3.fromRGB(126, 214, 255)
local COLOR_HEADING = Color3.fromRGB(255, 255, 255)
local COLOR_ROW = Color3.fromRGB(228, 234, 244)
local COLOR_VALUE = Color3.fromRGB(255, 214, 92)
local COLOR_QUIET = Color3.fromRGB(130, 136, 150)

type Board = {
	part: BasePart,
	statId: string,
	-- nil means "cycle through everything this statistic keeps", which is what
	-- the Robux board does.
	fixedPeriod: Stats.Period?,
	rows: { TextLabel },
	heading: TextLabel,
	-- What was last read, per period, so cycling costs nothing.
	cache: { [string]: { StatsStore.Row }? },
	cachedAt: { [string]: number },
}

local boards: { Board } = {}
local running = false
local nextIndex = 1

--=============================================================================
-- DRAWING ONE
--=============================================================================

local function faceOf(part: BasePart): Enum.NormalId
	local named = part:GetAttribute("Face")
	if typeof(named) == "string" then
		for _, face in Enum.NormalId:GetEnumItems() do
			if face.Name:lower() == (named :: string):lower() then
				return face
			end
		end
	end
	return Enum.NormalId.Front
end

--[[
	Puts the text layer onto a part and hands back the labels to fill in later.
]]
local function dressPart(part: BasePart, statId: string): (TextLabel, { TextLabel })
	local existing = part:FindFirstChild("ScoreboardSurface")
	if existing then
		existing:Destroy()
	end

	local surface = Instance.new("SurfaceGui")
	surface.Name = "ScoreboardSurface"
	surface.Face = faceOf(part)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Adornee = part
	surface.Parent = part

	local backing = Instance.new("Frame")
	backing.Size = UDim2.fromScale(1, 1)
	backing.BackgroundColor3 = COLOR_SLAB
	backing.BackgroundTransparency = 0.15
	backing.BorderSizePixel = 0
	backing.Parent = surface

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = COLOR_FRAME
	stroke.Transparency = 0.3
	stroke.Parent = backing

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = backing

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = backing

	local definition = Stats.get(statId)

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, 0, 0, 46)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.Text = if definition then definition.label else statId
	heading.TextColor3 = COLOR_HEADING
	heading.TextScaled = true
	heading.LayoutOrder = 0
	heading.Parent = backing

	local rows: { TextLabel } = {}
	for index = 1, Config.SCOREBOARD_ROWS do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. index
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.Text = ""
		row.TextColor3 = COLOR_ROW
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = index
		row.Parent = backing
		rows[index] = row
	end

	return heading, rows
end

--[[
	Writes a board's current contents onto its labels.
]]
local function paint(board: Board, period: Stats.Period)
	local definition = Stats.get(board.statId)
	local label = if definition then definition.label else board.statId

	-- Say which slice of time this is, but only when the board has more than
	-- one -- "SURVIVOR (all time)" on a board that is only ever all-time is just
	-- noise.
	if board.fixedPeriod == nil and definition and #definition.periods > 1 then
		local words = {
			AllTime = "all time",
			Daily = "today",
			Weekly = "this week",
			Monthly = "this month",
		}
		board.heading.Text = ("%s  --  %s"):format(label, words[period] or period)
	else
		board.heading.Text = label
	end

	local rows = board.cache[period]

	for index, row in board.rows do
		if rows == nil then
			-- Three honest states, and they say different things. This one means
			-- "we do not know", not "nobody has scored".
			row.Text = if index == 1
				then (if StatsStore.available then "loading..." else "leaderboards need API access turned on")
				else ""
			row.TextColor3 = COLOR_QUIET
		elseif #rows == 0 then
			row.Text = if index == 1 then "nobody yet" else ""
			row.TextColor3 = COLOR_QUIET
		else
			local entry = rows[index]
			if entry then
				row.Text = ("%d. %s  --  %s"):format(index, entry.name, Stats.format(board.statId, entry.value))
				row.TextColor3 = if index == 1 then COLOR_VALUE else COLOR_ROW
			else
				row.Text = ""
			end
		end
	end
end

--=============================================================================
-- FINDING OR BUILDING THE PARTS
--=============================================================================

local function register(part: BasePart)
	local statId = part:GetAttribute("StatId")
	if typeof(statId) ~= "string" or not Stats.get(statId :: string) then
		warn(
			("[Scoreboard] %s is tagged but its StatId attribute is missing or unknown (%s). "):format(
				part:GetFullName(),
				tostring(statId)
			) .. "Set it to one of: " .. table.concat(Stats.ids(), ", ")
		)
		return
	end

	local fixed: Stats.Period? = nil
	local named = part:GetAttribute("Period")
	if typeof(named) == "string" then
		fixed = named :: any
	end

	local heading, rows = dressPart(part, statId :: string)
	local board: Board = {
		part = part,
		statId = statId :: string,
		fixedPeriod = fixed,
		rows = rows,
		heading = heading,
		cache = {},
		cachedAt = {},
	}
	table.insert(boards, board)
	paint(board, fixed or "AllTime")
end

--[[
	Builds the placeholder slabs, ONLY if nothing is tagged yet.

	They are tagged and given their attributes exactly as a hand-built sign would
	be, so there is no second code path -- the placeholders go through the same
	machinery as your own signs will.
]]
local function buildPlaceholders(): number
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		warn("[Scoreboard] no Lobby to put the placeholder boards in")
		return 0
	end

	local folder = lobby:FindFirstChild("Scoreboards")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Scoreboards"
	folder.Parent = lobby

	local centre = Config.LOBBY_CENTER
	local count = #Stats.list
	-- Against the far wall, opposite the practice range so the lobby does not
	-- have everything crowded onto one side.
	local z = centre.Z + (Config.LOBBY_SIZE / 2 - 4)
	local y = centre.Y + Config.SCOREBOARD_HEIGHT / 2 + 1

	for index, definition in Stats.list do
		local x = centre.X + (index - (count + 1) / 2) * Config.SCOREBOARD_SPACING

		local slab = Instance.new("Part")
		slab.Name = "Board_" .. definition.id
		slab.Anchored = true
		slab.CanCollide = true
		slab.Size = Vector3.new(Config.SCOREBOARD_WIDTH, Config.SCOREBOARD_HEIGHT, 1)
		-- Turned to face into the lobby, so its Front is what players see.
		slab.CFrame = CFrame.new(Vector3.new(x, y, z), Vector3.new(x, y, centre.Z))
		slab.Color = COLOR_SLAB
		slab.Material = Enum.Material.SmoothPlastic
		slab.Parent = folder

		slab:SetAttribute("StatId", definition.id)
		-- No Period attribute deliberately: a statistic with several periods
		-- cycles, and one with only all-time simply shows it.
		CollectionService:AddTag(slab, Config.TAG_SCOREBOARD)
	end

	return count
end

--=============================================================================
-- KEEPING THEM CURRENT
--=============================================================================

--[[
	Which slice of time a board should be showing at this moment.
]]
local function periodFor(board: Board): Stats.Period
	if board.fixedPeriod then
		return board.fixedPeriod
	end
	local definition = Stats.get(board.statId)
	if not definition or #definition.periods <= 1 then
		return "AllTime"
	end
	local step = math.floor(os.clock() / Config.SCOREBOARD_CYCLE_SECONDS) % #definition.periods
	return definition.periods[step + 1]
end

--[[
	Refreshes exactly one board's data, then repaints every board from cache.
]]
local function tick()
	if #boards == 0 then
		return
	end

	if nextIndex > #boards then
		nextIndex = 1
	end
	local board = boards[nextIndex]
	nextIndex += 1

	if board.part.Parent then
		local period = periodFor(board)
		local rows = StatsStore.getBoard(board.statId, period, Config.SCOREBOARD_ROWS)
		-- Only replace the cache on a successful read. A failed read should leave
		-- yesterday's names up rather than blanking the board.
		if rows then
			board.cache[period] = rows
			board.cachedAt[period] = os.clock()
		end
	end

	-- Repaint everything, because the cycling boards move on by themselves even
	-- when it is not their turn to be re-read.
	for _, each in boards do
		if each.part.Parent then
			paint(each, periodFor(each))
		end
	end
end

function Scoreboard.build(): number
	boards = {}

	local tagged = CollectionService:GetTagged(Config.TAG_SCOREBOARD)
	local found = 0
	for _, thing in tagged do
		if thing:IsA("BasePart") and thing:IsDescendantOf(workspace) then
			found += 1
		end
	end

	if found == 0 then
		buildPlaceholders()
		tagged = CollectionService:GetTagged(Config.TAG_SCOREBOARD)
	end

	for _, thing in tagged do
		if thing:IsA("BasePart") and thing:IsDescendantOf(workspace) then
			register(thing)
		end
	end

	return #boards
end

function Scoreboard.start()
	if running or not Config.SCOREBOARD_ENABLED then
		return
	end
	running = true

	Scoreboard.build()

	-- A sign tagged while the game is running joins in, so you can build one in
	-- Studio mid-session and watch it fill itself in.
	CollectionService:GetInstanceAddedSignal(Config.TAG_SCOREBOARD):Connect(function(thing)
		if thing:IsA("BasePart") and thing:IsDescendantOf(workspace) then
			register(thing)
		end
	end)

	task.spawn(function()
		-- A moment's grace so the first read is not racing the server's start-up.
		task.wait(2)
		while true do
			tick()
			task.wait(Config.SCOREBOARD_REFRESH_SECONDS / math.max(#boards, 1))
		end
	end)
end

--=============================================================================
-- LOOKING AT IT IN STUDIO
--=============================================================================
--     require(game.ServerScriptService.Server.Lobby).preview()
--     require(game.ServerScriptService.Server.Scoreboard).preview()

function Scoreboard.preview(): number
	local made = Scoreboard.build()
	local lobby = workspace:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Scoreboards")
	if folder then
		folder.Archivable = false
	end
	return made
end

return Scoreboard
