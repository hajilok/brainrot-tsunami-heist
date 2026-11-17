--!strict
-- init.server.luau
-- The server bootstrap for Brainrot Tsunami Heist. It brings the world and the
-- hazard loop online, opens the two remotes the client talks over, owns the
-- per-player state lifecycle, routes client actions into BaseStateStore and
-- pushes a fresh state snapshot to every player once a second.
--
-- It begins on the cover preset so the eight vault pedestals and their 3D rigs
-- are populated the moment the server starts, which is what the first tour
-- screenshot captures.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseStateStore = require(Shared:WaitForChild("BaseStateStore"))

local WorldAndRigBuilder = require(script.Parent:WaitForChild("WorldAndRigBuilder"))
local HeistAndTsunamiService = require(script.Parent:WaitForChild("HeistAndTsunamiService"))

-- ---------------------------------------------------------------- remotes

local remotes = Instance.new("Folder")
remotes.Name = "BrainrotRemotes"

local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = "BrainrotAction"
actionRemote.Parent = remotes

local syncRemote = Instance.new("RemoteEvent")
syncRemote.Name = "BrainrotStateSync"
syncRemote.Parent = remotes

remotes.Parent = ReplicatedStorage

-- ---------------------------------------------------------------- state helpers

local featuredPlayer: Player? = nil

-- The client snapshot plus the live hazard phase, so the HUD can raise its
-- tsunami banner without polling the world itself.
local function buildPayload(state: any): any
	local payload = BaseStateStore.buildClientSnapshot(state)
	payload.tsunamiPhase = HeistAndTsunamiService.getPhase()
	payload.tsunamiSweep = HeistAndTsunamiService.getSweepProgress()
	return payload
end

local function syncPlayer(player: Player, state: any): ()
	syncRemote:FireClient(player, buildPayload(state))
end

-- Repaints the shared world from one player's state. The world shows a single
-- vault, so it mirrors the featured player while others play around it.
local function refreshWorldFor(state: any): ()
	WorldAndRigBuilder.refreshVaultPedestals(state)
	WorldAndRigBuilder.updateLaserGateVisuals(BaseStateStore.isLaserLocked(state))
end

-- ---------------------------------------------------------------- action routing

local function handleAction(player: Player, action: string, data: any): ()
	local state = BaseStateStore.getPlayerState(player)
	if not state then
		state = BaseStateStore.initPlayerState(player)
	end

	if action == "HeistAction" then
		local mode = if type(data) == "table" then data.mode else nil
		if mode == "deposit" then
			BaseStateStore.depositCarriedBrainrotToPedestal(state)
		elseif mode == "drop" then
			BaseStateStore.dropCarriedBrainrot(state)
		else
			HeistAndTsunamiService.tryPickupNearestConveyorBrainrot(player)
		end
	elseif action == "LockLaser" then
		BaseStateStore.activateLaserLock(state, 10, "heist")
	elseif action == "BuyUpgrade" then
		local upgradeId = if type(data) == "table" then data.upgradeId else nil
		if type(upgradeId) == "string" then
			BaseStateStore.purchaseUpgrade(state, upgradeId)
		end
	elseif action == "AttemptRebirth" then
		BaseStateStore.attemptRebirth(state)
	elseif action == "SellPedestal" then
		local index = if type(data) == "table" then data.index else nil
		if type(index) == "number" then
			BaseStateStore.sellPedestalBrainrot(state, index)
		end
	elseif action == "ApplyPreset" then
		local preset = if type(data) == "table" then data.preset else nil
		if type(preset) == "string" then
			HeistAndTsunamiService.applyTourPreset(preset, player)
			state = BaseStateStore.getPlayerState(player) or state
		end
	end

	if featuredPlayer == nil then
		featuredPlayer = player
	end
	refreshWorldFor(state)
	syncPlayer(player, state)
end

actionRemote.OnServerEvent:Connect(function(player, action, data)
	if type(action) ~= "string" then
		return
	end
	handleAction(player, action, data)
end)

-- ---------------------------------------------------------------- lifecycle

Players.PlayerAdded:Connect(function(player)
	local state = BaseStateStore.initPlayerState(player)

	if featuredPlayer == nil then
		featuredPlayer = player
		-- Give the first player the cover showcase so the world stays
		-- populated and their HUD opens on a rich state.
		HeistAndTsunamiService.applyTourPreset("cover", player)
		state = BaseStateStore.getPlayerState(player) or state
	end

	player.CharacterAdded:Connect(function(character)
		task.wait(0.15)
		if character.Parent then
			character:PivotTo(CFrame.new(0, 4, 46))
		end
	end)

	-- CharacterAutoLoads is false in the project, so the server spawns them.
	pcall(function()
		player:LoadCharacter()
	end)

	refreshWorldFor(state)
	syncPlayer(player, state)
end)

Players.PlayerRemoving:Connect(function(player)
	if featuredPlayer == player then
		featuredPlayer = nil
	end
	BaseStateStore.removePlayerState(player)
end)

-- ---------------------------------------------------------------- startup

WorldAndRigBuilder.ensureWorldBuilt()
HeistAndTsunamiService.initHeistLane()
HeistAndTsunamiService.startHazardLoop()
HeistAndTsunamiService.applyTourPreset("cover")

-- ---------------------------------------------------------------- passive cash tick

task.spawn(function()
	while true do
		task.wait(1)

		for _, player in ipairs(Players:GetPlayers()) do
			local state = BaseStateStore.getPlayerState(player)
			if state then
				BaseStateStore.tickPassiveCash(state, 1)
				syncPlayer(player, state)
			end
		end

		if featuredPlayer ~= nil then
			local featuredState = BaseStateStore.getPlayerState(featuredPlayer)
			if featuredState then
				WorldAndRigBuilder.refreshVaultPedestals(featuredState)
			end
		end
	end
end)
