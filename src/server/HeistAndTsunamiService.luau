--!strict
-- HeistAndTsunamiService
-- Runs the two live systems that define a round of Brainrot Tsunami Heist:
-- the heist lane (a conveyor of brainrots a rival thief bot also races for)
-- and the tsunami hazard (a calm > warning > sweeping wave that wipes out any
-- carrier caught outside a safe shelter).
--
-- It also owns applyTourPreset, the entry point TOUR.json's `call` names: each
-- preset writes a canonical player state through BaseStateStore and then asks
-- WorldAndRigBuilder to repaint the vault, the carried item, the laser gate
-- and the wave to match the screenshot being taken.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BrainrotCatalog = require(Shared:WaitForChild("BrainrotCatalog"))
local BaseStateStore = require(Shared:WaitForChild("BaseStateStore"))

local WorldAndRigBuilder = require(script.Parent:WaitForChild("WorldAndRigBuilder"))

local HeistAndTsunamiService = {}

-- ---------------------------------------------------------------- tuning

local LANE_START_Z = -70
local LANE_END_Z = 18
local CONVEYOR_SPEED = 8
local MAX_CONVEYOR_ITEMS = 6
local MIN_CONVEYOR_ITEMS = 3
local PICKUP_RANGE = 12
local THIEF_SPEED = 10
local THIEF_LANE_X = -10

local WAVE_CALM_SECONDS = 12
local WAVE_WARNING_SECONDS = 4
local WAVE_SWEEP_SECONDS = 6

-- ---------------------------------------------------------------- types

type ConveyorItem = {
	model: Model,
	character: any,
	mutation: any,
	incomePerSec: number,
	laneX: number,
	position: number,
}

type LaneState = {
	items: { ConveyorItem },
	thief: Model?,
	thiefPosition: number,
	phase: string,
	phaseTimer: number,
	sweepProgress: number,
	running: boolean,
	connection: RBXScriptConnection?,
}

local lane: LaneState = {
	items = {},
	thief = nil,
	thiefPosition = LANE_START_Z,
	phase = "calm",
	phaseTimer = 0,
	sweepProgress = 0,
	running = false,
	connection = nil,
}

-- A stable, non-Player host used only when a tour preset runs with no player
-- in the game: it gives BaseStateStore somewhere to keep the demo state.
local tourHost = { UserId = -1, Name = "TourHost" }
local featuredState: any = nil

-- ---------------------------------------------------------------- generic helpers

local function findOrCreate(parent: Instance, name: string, className: string): Instance
	local found = parent:FindFirstChild(name)
	if found then
		return found
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local function clearChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

local function moveToward(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + (if target > current then maxDelta else -maxDelta)
end

-- ---------------------------------------------------------------- thief bot

local function buildThiefBot(): Model
	local model = Instance.new("Model")
	model.Name = "RivalThief"

	local function part(name: string, size: Vector3, color: Color3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Position = offset
		p.Parent = model
		return p
	end

	local skin = Color3.fromRGB(52, 20, 30)
	local cloth = Color3.fromRGB(30, 30, 38)
	local mask = Color3.fromRGB(210, 60, 70)

	local torso = part("Torso", Vector3.new(2, 2, 1), cloth, Vector3.new(0, 3, 0))
	part("Head", Vector3.new(1.4, 1.4, 1.4), skin, Vector3.new(0, 4.7, 0))
	part("Mask", Vector3.new(1.5, 0.5, 0.3), mask, Vector3.new(0, 4.8, 0.7))
	part("LegL", Vector3.new(0.7, 2, 0.7), cloth, Vector3.new(-0.5, 1, 0))
	part("LegR", Vector3.new(0.7, 2, 0.7), cloth, Vector3.new(0.5, 1, 0))
	part("ArmL", Vector3.new(0.5, 1.8, 0.5), skin, Vector3.new(-1.2, 3.1, 0))
	part("ArmR", Vector3.new(0.5, 1.8, 0.5), skin, Vector3.new(1.2, 3.1, 0))

	model.PrimaryPart = torso
	return model
end

-- ---------------------------------------------------------------- shelters

-- True when a world position sits under either safe-zone roof, i.e. the rain
-- of the tsunami cannot reach the character there.
local function isInSafeShelter(position: Vector3): boolean
	local world = WorldAndRigBuilder.ensureWorldBuilt()
	local conveyor = world.HeistConveyorLane
	for _, shelterName in ipairs({ "ShelterNorth", "ShelterSouth" }) do
		local shelter = conveyor:FindFirstChild(shelterName)
		if shelter then
			local roof = shelter:FindFirstChild(shelterName .. "Roof")
			if roof and roof:IsA("BasePart") then
				local p = roof.Position
				local s = roof.Size
				if math.abs(position.X - p.X) <= s.X / 2 and math.abs(position.Z - p.Z) <= s.Z / 2 then
					return true
				end
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------- lane setup

local function currentItemsFolder(): Instance
	local world = WorldAndRigBuilder.ensureWorldBuilt()
	return world.ConveyorItems
end

local function clearLaneItems()
	clearChildren(currentItemsFolder())
	lane.items = {}
end

-- Builds the lane in a fresh, calm state: no items left over, the rival thief
-- back at the conveyor's far end and the wave parked at its start line.
function HeistAndTsunamiService.initHeistLane(): LaneState
	WorldAndRigBuilder.ensureWorldBuilt()
	clearLaneItems()

	lane.thiefPosition = LANE_START_Z
	lane.phase = "calm"
	lane.phaseTimer = 0
	lane.sweepProgress = 0
	lane.running = true

	if lane.thief then
		lane.thief:Destroy()
	end
	lane.thief = buildThiefBot()
	lane.thief:PivotTo(CFrame.new(THIEF_LANE_X, 1, LANE_START_Z))
	lane.thief.Parent = currentItemsFolder().Parent

	WorldAndRigBuilder.updateLaserGateVisuals(false)
	WorldAndRigBuilder.updateTsunamiWavePosition(0)

	for _ = 1, MIN_CONVEYOR_ITEMS do
		HeistAndTsunamiService.spawnConveyorBrainrot()
	end
	return lane
end

-- ---------------------------------------------------------------- conveyor

-- Rolls a fresh character and mutation, builds its sculpture and places it at
-- the conveyor's far end. Returns nil when the lane is already full.
function HeistAndTsunamiService.spawnConveyorBrainrot(): Model?
	if #lane.items >= MAX_CONVEYOR_ITEMS then
		return nil
	end

	local character = BrainrotCatalog.pickConveyorSpawn(nil, 0)
	local mutation = BrainrotCatalog.rollMutationForLuck(0)
	local income = BrainrotCatalog.computeCharacterIncomePerSec(character, mutation, 1)

	local model = WorldAndRigBuilder.buildBrainrotRigModel(character, mutation, income)
	local laneX = math.random(-9, 9)
	model:PivotTo(CFrame.new(laneX, 1, LANE_START_Z))
	model.Parent = currentItemsFolder()

	lane.items[#lane.items + 1] = {
		model = model,
		character = character,
		mutation = mutation,
		incomePerSec = income,
		laneX = laneX,
		position = LANE_START_Z,
	}
	return model
end

local function removeItem(item: ConveyorItem)
	for index, existing in ipairs(lane.items) do
		if existing == item then
			table.remove(lane.items, index)
			return
		end
	end
end

local function nearestItemTo(z: number): ConveyorItem?
	local best: ConveyorItem? = nil
	local bestDistance = math.huge
	for _, item in ipairs(lane.items) do
		local distance = math.abs(item.position - z)
		if distance < bestDistance then
			best, bestDistance = item, distance
		end
	end
	return best
end

-- Advances every item one step, retires the ones that ride off the end, walks
-- the thief toward the nearest item it can snatch, and tops the lane back up.
function HeistAndTsunamiService.stepConveyorAndThiefAI(dt: number): ()
	if not lane.running then
		return
	end

	local index = 1
	while index <= #lane.items do
		local item = lane.items[index]
		item.position += CONVEYOR_SPEED * dt
		if item.position > LANE_END_Z then
			item.model:Destroy()
			table.remove(lane.items, index)
		else
			item.model:PivotTo(CFrame.new(item.laneX, 1, item.position))
			index += 1
		end
	end

	local thief = lane.thief
	if thief then
		local target = nearestItemTo(lane.thiefPosition)
		if target then
			lane.thiefPosition = moveToward(lane.thiefPosition, target.position, THIEF_SPEED * dt)
			if math.abs(lane.thiefPosition - target.position) < 2 then
				target.model:Destroy()
				removeItem(target)
			end
		else
			lane.thiefPosition = moveToward(lane.thiefPosition, LANE_END_Z, THIEF_SPEED * dt)
		end
		thief:PivotTo(CFrame.new(THIEF_LANE_X, 1, lane.thiefPosition))
	end

	if #lane.items < MIN_CONVEYOR_ITEMS and math.random() < 0.4 then
		HeistAndTsunamiService.spawnConveyorBrainrot()
	end
end

-- The player's pickup: the closest conveyor brainrot within reach is swept up
-- into their hands, unless they are already carrying one.
function HeistAndTsunamiService.tryPickupNearestConveyorBrainrot(player: Player): (boolean, ConveyorItem?)
	local state = BaseStateStore.getPlayerState(player) or BaseStateStore.initPlayerState(player)
	if state.carrying then
		return false, nil
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, nil
	end

	local origin = root.Position
	local bestIndex: number? = nil
	local bestDistance = PICKUP_RANGE
	for index, item in ipairs(lane.items) do
		local distance = (item.model:GetPivot().Position - origin).Magnitude
		if distance <= bestDistance then
			bestIndex, bestDistance = index, distance
		end
	end
	if not bestIndex then
		return false, nil
	end

	local item = lane.items[bestIndex]
	local ok = BaseStateStore.startCarryingBrainrot(state, item.character.id, item.mutation.id)
	if not ok then
		return false, nil
	end

	item.model:Destroy()
	table.remove(lane.items, bestIndex)
	return true, item
end

-- ---------------------------------------------------------------- tsunami

-- Drops the carried brainrot of every player standing outside a shelter while
-- the wave is sweeping, and returns how many were washed away.
local function washExposedCarriers(): number
	local washed = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local state = BaseStateStore.getPlayerState(player)
		if state and state.carrying then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and not isInSafeShelter(root.Position) then
				BaseStateStore.dropCarriedBrainrot(state)
				washed += 1
			end
		end
	end
	return washed
end

-- Cycles calm (wave parked), warning (wave about to break) and sweeping (wave
-- crosses the lane, washing carriers), returning the phase it ends in.
function HeistAndTsunamiService.stepTsunamiHazard(dt: number): string
	if not lane.running then
		return lane.phase
	end

	lane.phaseTimer += dt

	if lane.phase == "calm" then
		if lane.phaseTimer >= WAVE_CALM_SECONDS then
			lane.phase = "warning"
			lane.phaseTimer = 0
		end
	elseif lane.phase == "warning" then
		if lane.phaseTimer >= WAVE_WARNING_SECONDS then
			lane.phase = "sweeping"
			lane.phaseTimer = 0
			lane.sweepProgress = 0
		end
	elseif lane.phase == "sweeping" then
		lane.sweepProgress = math.clamp(lane.phaseTimer / WAVE_SWEEP_SECONDS, 0, 1)
		WorldAndRigBuilder.updateTsunamiWavePosition(lane.sweepProgress)
		washExposedCarriers()
		if lane.phaseTimer >= WAVE_SWEEP_SECONDS then
			lane.phase = "calm"
			lane.phaseTimer = 0
			lane.sweepProgress = 0
			WorldAndRigBuilder.updateTsunamiWavePosition(0)
		end
	end

	return lane.phase
end

-- Read-only accessors so the bootstrap can publish the hazard state beside
-- each player snapshot, letting the HUD's tsunami banner read the real phase.
function HeistAndTsunamiService.getPhase(): string
	return lane.phase
end

function HeistAndTsunamiService.getSweepProgress(): number
	return lane.sweepProgress
end

-- ---------------------------------------------------------------- loop

function HeistAndTsunamiService.startHazardLoop(): ()
	if lane.connection then
		return
	end
	lane.running = true
	lane.connection = RunService.Heartbeat:Connect(function(dt)
		HeistAndTsunamiService.stepConveyorAndThiefAI(dt)
		HeistAndTsunamiService.stepTsunamiHazard(dt)
	end)
end

function HeistAndTsunamiService.stopHazardLoop(): ()
	if lane.connection then
		lane.connection:Disconnect()
		lane.connection = nil
	end
	lane.running = false
end

-- ---------------------------------------------------------------- tour presets

local function resolveTourState(player: Player?): any
	if player then
		return BaseStateStore.getPlayerState(player) or BaseStateStore.initPlayerState(player)
	end
	if not featuredState then
		featuredState = BaseStateStore.initPlayerState(tourHost :: any)
	end
	return featuredState
end

-- Puts the carried brainrot's sculpture overhead so a screenshot shows what the
-- player is holding; with no carrier, the spot in front of the plaza is clear.
local function updateCarriedVisual(state: any, player: Player?): ()
	local world = WorldAndRigBuilder.ensureWorldBuilt()
	local folder = findOrCreate(world.World, "CarriedRigs", "Folder")
	clearChildren(folder)

	if not state.carrying then
		return
	end

	local character = BrainrotCatalog.getCharacterById(state.carrying.characterId)
	local mutation = BrainrotCatalog.getMutationInfo(state.carrying.mutationId)
	if not character then
		return
	end

	local model = WorldAndRigBuilder.buildBrainrotRigModel(character, mutation, state.carrying.incomePerSec)
	model.Name = "CarriedRig"
	model.Parent = folder

	local target = Vector3.new(0, 4, -18)
	local humanoid = player and player.Character
	if humanoid then
		local root = humanoid:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			target = root.Position + Vector3.new(0, 2, 3)
		end
	end
	model:PivotTo(CFrame.new(target))
end

-- The function TOUR.json calls with arg cover / heist / rebirth. It writes the
-- preset into BaseStateStore, then repaints the whole scene from that state.
function HeistAndTsunamiService.applyTourPreset(preset: string, player: Player?): boolean
	local state = resolveTourState(player)
	BaseStateStore.applyPresetState(state, preset)

	WorldAndRigBuilder.refreshVaultPedestals(state)
	WorldAndRigBuilder.updateLaserGateVisuals(BaseStateStore.isLaserLocked(state))
	updateCarriedVisual(state, player)

	if preset == "heist" then
		-- Mid-heist: gate armed, wave on the way in, conveyor loaded.
		lane.phase = "warning"
		lane.phaseTimer = 0
		lane.sweepProgress = 0
		WorldAndRigBuilder.updateTsunamiWavePosition(0.15)
		clearLaneItems()
		for _ = 1, MIN_CONVEYOR_ITEMS do
			HeistAndTsunamiService.spawnConveyorBrainrot()
		end
	elseif preset == "rebirth" then
		-- Calm showcase at the altar, vault maxed, nothing in flight.
		lane.phase = "calm"
		lane.phaseTimer = 0
		lane.sweepProgress = 0
		WorldAndRigBuilder.updateTsunamiWavePosition(0)
		clearLaneItems()
	else
		-- Cover: calm lane, wave parked, full vault on display.
		lane.phase = "calm"
		lane.phaseTimer = 0
		lane.sweepProgress = 0
		WorldAndRigBuilder.updateTsunamiWavePosition(0)
	end

	return true
end

return HeistAndTsunamiService
