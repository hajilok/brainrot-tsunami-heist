--!strict
-- WorldAndRigBuilder
-- Builds and keeps in sync the 3D world that lives under Workspace.BrainrotWorld:
-- the vault pedestals, the brainrot character sculptures with their overhead
-- info cards, the laser gate's armed/unlocked look and the moving tsunami wall.
--
-- The place itself is authored in default.project.json, so every "ensure" call
-- here is idempotent: it finds the part Rojo already built and only creates a
-- placeholder when one is genuinely missing, which makes the module safe to run
-- on a hand-edited place too.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BrainrotCatalog = require(Shared:WaitForChild("BrainrotCatalog"))
local BaseStateStore = require(Shared:WaitForChild("BaseStateStore"))

local WorldAndRigBuilder = {}

-- ---------------------------------------------------------------- constants

local PEDESTAL_COUNT = 8
local PEDESTAL_SPACING = 12
local PEDESTAL_START_X = -42

local LASER_BEAM_NAMES = { "LaserBeamLower", "LaserBeamMidLow", "LaserBeamMidHigh", "LaserBeamUpper" }
local LASER_BEAM_HEIGHTS = { 2, 4, 6, 8 }

local ARMED_COLOR = Color3.fromRGB(0, 255, 240)
local ARMED_TRANSPARENCY = 0.15
local UNLOCKED_COLOR = Color3.fromRGB(18, 74, 74)
local UNLOCKED_TRANSPARENCY = 0.82

local WAVE_LANE_START_Z = -140
local WAVE_LANE_END_Z = 40

-- ---------------------------------------------------------------- types

type RigPart = {
	name: string,
	size: Vector3,
	tone: string,
	offset: Vector3,
	neon: boolean?,
}

-- The refs table is deliberately loosely typed: callers reach straight for the
-- named children they need and Luau treats the lookup as dynamic.
local worldRefs: { [string]: any } = {}

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

local function getOrCreatePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Part") then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.Locked = true
	part.Parent = parent
	return part
end

local function makePart(parent: Instance, name: string, size: Vector3, color: Color3, offset: Vector3, neon: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Position = offset
	part.Parent = parent
	return part
end

local function findFirstPart(container: Instance): BasePart?
	if container:IsA("BasePart") then
		return container
	end
	for _, child in ipairs(container:GetChildren()) do
		local part = findFirstPart(child)
		if part then
			return part
		end
	end
	return nil
end

-- ---------------------------------------------------------------- world skeleton

local function ensurePedestals(vault: Instance)
	for index = 1, PEDESTAL_COUNT do
		local x = PEDESTAL_START_X + (index - 1) * PEDESTAL_SPACING
		getOrCreatePart(vault, "Pedestal" .. index, Vector3.new(4, 6, 4), Vector3.new(x, 3, 0), Color3.fromRGB(128, 140, 158))
		local trim = getOrCreatePart(vault, "NeonTrim" .. index, Vector3.new(4.4, 0.4, 4.4), Vector3.new(x, 6.2, 0), Color3.fromRGB(26, 255, 230))
		trim.Material = Enum.Material.Neon
	end
end

local function ensureLaserBeams(gate: Instance)
	getOrCreatePart(gate, "GatePostWest", Vector3.new(2, 10, 2), Vector3.new(-12, 5, 40), Color3.fromRGB(51, 51, 61))
	getOrCreatePart(gate, "GatePostEast", Vector3.new(2, 10, 2), Vector3.new(12, 5, 40), Color3.fromRGB(51, 51, 61))
	getOrCreatePart(gate, "GateFrame", Vector3.new(26, 2, 2), Vector3.new(0, 10, 40), Color3.fromRGB(51, 51, 61))
	for index, name in ipairs(LASER_BEAM_NAMES) do
		getOrCreatePart(gate, name, Vector3.new(24, 0.4, 0.4), Vector3.new(0, LASER_BEAM_HEIGHTS[index], 40), UNLOCKED_COLOR)
	end
end

local function ensureTsunamiParts(wave: Instance)
	local wall = getOrCreatePart(wave, "WaveWall", Vector3.new(200, 40, 4), Vector3.new(0, 20, WAVE_LANE_START_Z), Color3.fromRGB(26, 102, 230))
	getOrCreatePart(wave, "WaveCrestWest", Vector3.new(40, 6, 6), Vector3.new(-60, 42, WAVE_LANE_START_Z), Color3.fromRGB(179, 242, 255))
	getOrCreatePart(wave, "WaveCrestCenter", Vector3.new(50, 8, 6), Vector3.new(0, 44, WAVE_LANE_START_Z), Color3.fromRGB(179, 242, 255))
	getOrCreatePart(wave, "WaveCrestEast", Vector3.new(40, 6, 6), Vector3.new(60, 42, WAVE_LANE_START_Z), Color3.fromRGB(179, 242, 255))
	wave.PrimaryPart = wall
	if wall:GetAttribute("BaseZ") == nil then
		wall:SetAttribute("BaseX", wall.Position.X)
		wall:SetAttribute("BaseY", wall.Position.Y)
		wall:SetAttribute("BaseZ", wall.Position.Z)
	end
end

function WorldAndRigBuilder.ensureWorldBuilt(): { [string]: any }
	local workspaceWorld = findOrCreate(Workspace, "BrainrotWorld", "Folder")
	local refs = worldRefs
	refs.World = workspaceWorld
	refs.Plaza = findOrCreate(workspaceWorld, "Plaza", "Model")
	refs.VaultPedestals = findOrCreate(workspaceWorld, "VaultPedestals", "Model")
	refs.LaserBarrierGate = findOrCreate(workspaceWorld, "LaserBarrierGate", "Model")
	refs.HeistConveyorLane = findOrCreate(workspaceWorld, "HeistConveyorLane", "Model")
	refs.TsunamiHazardWall = findOrCreate(workspaceWorld, "TsunamiHazardWall", "Model")
	refs.RebirthAltarShrine = findOrCreate(workspaceWorld, "RebirthAltarShrine", "Model")
	refs.VaultRigs = findOrCreate(workspaceWorld, "VaultRigs", "Folder")
	refs.ConveyorItems = findOrCreate(workspaceWorld, "ConveyorItems", "Folder")

	ensurePedestals(refs.VaultPedestals)
	ensureLaserBeams(refs.LaserBarrierGate)
	ensureTsunamiParts(refs.TsunamiHazardWall)
	return refs
end

-- ---------------------------------------------------------------- rig specs

-- A sculpture is a list of boxes placed at offsets from the model origin,
-- tinted with either the character's primary or accent colour. One spec per
-- rigStyle in the catalog; adding a style means adding a branch here.
local function getRigSpec(rigStyle: string): { RigPart }
	if rigStyle == "Quadruped" then
		return {
			{ name = "Body", size = Vector3.new(3, 1.4, 1.4), tone = "primary", offset = Vector3.new(0, 1.6, 0) },
			{ name = "Head", size = Vector3.new(1.2, 1.2, 1.2), tone = "primary", offset = Vector3.new(1.9, 1.9, 0) },
			{ name = "Tail", size = Vector3.new(0.4, 0.4, 1.6), tone = "accent", offset = Vector3.new(-1.9, 1.8, 0), neon = true },
			{ name = "LegFL", size = Vector3.new(0.5, 1.2, 0.5), tone = "primary", offset = Vector3.new(-1.1, 0.6, 0.45) },
			{ name = "LegFR", size = Vector3.new(0.5, 1.2, 0.5), tone = "primary", offset = Vector3.new(-1.1, 0.6, -0.45) },
			{ name = "LegBL", size = Vector3.new(0.5, 1.2, 0.5), tone = "primary", offset = Vector3.new(1.1, 0.6, 0.45) },
			{ name = "LegBR", size = Vector3.new(0.5, 1.2, 0.5), tone = "primary", offset = Vector3.new(1.1, 0.6, -0.45) },
		}
	elseif rigStyle == "Avian" then
		return {
			{ name = "Body", size = Vector3.new(1.6, 1.6, 2), tone = "primary", offset = Vector3.new(0, 1.5, 0) },
			{ name = "Head", size = Vector3.new(1.1, 1.1, 1.1), tone = "primary", offset = Vector3.new(0, 2.5, 0.9) },
			{ name = "Beak", size = Vector3.new(0.4, 0.4, 0.7), tone = "accent", offset = Vector3.new(0, 2.4, 1.7), neon = true },
			{ name = "WingL", size = Vector3.new(0.3, 1.4, 1.6), tone = "accent", offset = Vector3.new(-1, 1.7, 0) },
			{ name = "WingR", size = Vector3.new(0.3, 1.4, 1.6), tone = "accent", offset = Vector3.new(1, 1.7, 0) },
			{ name = "LegL", size = Vector3.new(0.4, 1, 0.4), tone = "primary", offset = Vector3.new(-0.4, 0.5, 0) },
			{ name = "LegR", size = Vector3.new(0.4, 1, 0.4), tone = "primary", offset = Vector3.new(0.4, 0.5, 0) },
		}
	elseif rigStyle == "Serpentine" then
		return {
			{ name = "Head", size = Vector3.new(1.1, 1.1, 1.1), tone = "primary", offset = Vector3.new(0, 1.2, 2.2) },
			{ name = "Seg1", size = Vector3.new(1, 1, 0.9), tone = "primary", offset = Vector3.new(0, 1.1, 1.2) },
			{ name = "Seg2", size = Vector3.new(0.95, 0.95, 0.9), tone = "primary", offset = Vector3.new(0.4, 1, 0.25) },
			{ name = "Seg3", size = Vector3.new(0.9, 0.9, 0.9), tone = "primary", offset = Vector3.new(0, 0.9, -0.7) },
			{ name = "Seg4", size = Vector3.new(0.8, 0.8, 0.9), tone = "primary", offset = Vector3.new(-0.4, 0.8, -1.6) },
			{ name = "Fin", size = Vector3.new(0.2, 0.8, 0.9), tone = "accent", offset = Vector3.new(0, 1.9, 1.2), neon = true },
		}
	elseif rigStyle == "Amorphous" then
		return {
			{ name = "Core", size = Vector3.new(2, 1.8, 2), tone = "primary", offset = Vector3.new(0, 1.6, 0) },
			{ name = "Head", size = Vector3.new(1.4, 1.4, 1.4), tone = "primary", offset = Vector3.new(0, 3.1, 0) },
			{ name = "BlobL", size = Vector3.new(0.9, 0.9, 0.9), tone = "accent", offset = Vector3.new(-1.2, 1.4, 0.3) },
			{ name = "BlobR", size = Vector3.new(0.9, 0.9, 0.9), tone = "accent", offset = Vector3.new(1.2, 1.7, -0.3) },
			{ name = "BlobBack", size = Vector3.new(0.8, 0.8, 0.8), tone = "accent", offset = Vector3.new(0, 1.2, -1.2), neon = true },
			{ name = "EyeL", size = Vector3.new(0.2, 0.2, 0.2), tone = "accent", offset = Vector3.new(-0.3, 3.2, 0.7), neon = true },
			{ name = "EyeR", size = Vector3.new(0.2, 0.2, 0.2), tone = "accent", offset = Vector3.new(0.3, 3.2, 0.7), neon = true },
		}
	elseif rigStyle == "Flying" then
		return {
			{ name = "Body", size = Vector3.new(1.8, 1.4, 2.4), tone = "primary", offset = Vector3.new(0, 2, 0) },
			{ name = "Head", size = Vector3.new(1.2, 1.2, 1.2), tone = "primary", offset = Vector3.new(0, 2.6, 1.3) },
			{ name = "WingL", size = Vector3.new(2.6, 0.3, 1.4), tone = "accent", offset = Vector3.new(-1.8, 2.2, 0), neon = true },
			{ name = "WingR", size = Vector3.new(2.6, 0.3, 1.4), tone = "accent", offset = Vector3.new(1.8, 2.2, 0), neon = true },
			{ name = "Tail", size = Vector3.new(0.5, 0.5, 1.6), tone = "accent", offset = Vector3.new(-1.4, 2, 0) },
		}
	elseif rigStyle == "Titan" then
		return {
			{ name = "Body", size = Vector3.new(3.2, 3.2, 2), tone = "primary", offset = Vector3.new(0, 2.8, 0) },
			{ name = "Head", size = Vector3.new(1.8, 1.8, 1.8), tone = "primary", offset = Vector3.new(0, 5.1, 0) },
			{ name = "ShoulderL", size = Vector3.new(1.4, 1.4, 2), tone = "accent", offset = Vector3.new(-2.2, 4.2, 0) },
			{ name = "ShoulderR", size = Vector3.new(1.4, 1.4, 2), tone = "accent", offset = Vector3.new(2.2, 4.2, 0) },
			{ name = "ArmL", size = Vector3.new(0.9, 2.4, 0.9), tone = "primary", offset = Vector3.new(-2.6, 2.4, 0) },
			{ name = "ArmR", size = Vector3.new(0.9, 2.4, 0.9), tone = "primary", offset = Vector3.new(2.6, 2.4, 0) },
			{ name = "LegL", size = Vector3.new(1, 2.4, 1), tone = "primary", offset = Vector3.new(-0.9, 1.2, 0) },
			{ name = "LegR", size = Vector3.new(1, 2.4, 1), tone = "primary", offset = Vector3.new(0.9, 1.2, 0) },
			{ name = "Crown", size = Vector3.new(1.4, 0.6, 1.4), tone = "accent", offset = Vector3.new(0, 6.2, 0), neon = true },
		}
	end

	-- Biped is the default, and the fallback for any unknown style.
	return {
		{ name = "Body", size = Vector3.new(2, 2.2, 1), tone = "primary", offset = Vector3.new(0, 2.2, 0) },
		{ name = "Head", size = Vector3.new(1.6, 1.6, 1.6), tone = "primary", offset = Vector3.new(0, 4.1, 0) },
		{ name = "Belt", size = Vector3.new(2.2, 0.3, 1.2), tone = "accent", offset = Vector3.new(0, 1.1, 0), neon = true },
		{ name = "LegL", size = Vector3.new(0.6, 2, 0.6), tone = "primary", offset = Vector3.new(-0.55, 0.9, 0) },
		{ name = "LegR", size = Vector3.new(0.6, 2, 0.6), tone = "primary", offset = Vector3.new(0.55, 0.9, 0) },
		{ name = "ArmL", size = Vector3.new(0.5, 1.8, 0.5), tone = "primary", offset = Vector3.new(-1.3, 2.3, 0) },
		{ name = "ArmR", size = Vector3.new(0.5, 1.8, 0.5), tone = "primary", offset = Vector3.new(1.3, 2.3, 0) },
	}
end

-- ---------------------------------------------------------------- rig + card

local function buildRigBody(model: Model, character: any): BasePart
	local primaryColor = character.primaryColor
	local accentColor = character.accentColor
	local head: BasePart? = nil

	for _, spec in ipairs(getRigSpec(character.rigStyle)) do
		local color = if spec.tone == "accent" then accentColor else primaryColor
		local part = makePart(model, spec.name, spec.size, color, spec.offset, spec.neon)
		if spec.name == "Head" and head == nil then
			head = part
		end
	end

	local primaryPart = head or findFirstPart(model)
	if not primaryPart then
		primaryPart = makePart(model, "Origin", Vector3.new(1, 1, 1), primaryColor, Vector3.new(0, 0, 0))
	end
	model.PrimaryPart = primaryPart
	return primaryPart
end

-- The overhead card: "[RARITY • MUTATION]" on top, the character's name in its
-- rarity colour, then the brainrot's income per second in large green text.
local function buildInfoCard(character: any, mutation: any, incomePerSec: number): BillboardGui
	local rarity = BrainrotCatalog.getRarityInfo(character.rarity)
	local rarityColor = if rarity then rarity.color else Color3.fromRGB(200, 200, 200)

	local card = Instance.new("BillboardGui")
	card.Name = "InfoCard"
	card.Size = UDim2.fromOffset(240, 104)
	card.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	card.AlwaysOnTop = true
	card.LightInfluence = 0
	card.MaxDistance = 300
	card.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = mutation.color
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = frame

	local rarityLine = Instance.new("TextLabel")
	rarityLine.Name = "RarityLine"
	rarityLine.Size = UDim2.new(1, -16, 0, 24)
	rarityLine.Position = UDim2.new(0, 8, 0, 6)
	rarityLine.BackgroundTransparency = 1
	rarityLine.Text = string.upper(character.rarity) .. " • " .. string.upper(mutation.id)
	rarityLine.TextColor3 = mutation.color
	rarityLine.TextSize = 17
	rarityLine.TextXAlignment = Enum.TextXAlignment.Left
	rarityLine.Font = Enum.Font.GothamBold
	rarityLine.Parent = frame

	local nameLine = Instance.new("TextLabel")
	nameLine.Name = "NameLine"
	nameLine.Size = UDim2.new(1, -16, 0, 28)
	nameLine.Position = UDim2.new(0, 8, 0, 30)
	nameLine.BackgroundTransparency = 1
	nameLine.Text = character.name
	nameLine.TextColor3 = rarityColor
	nameLine.TextSize = 21
	nameLine.TextXAlignment = Enum.TextXAlignment.Left
	nameLine.Font = Enum.Font.GothamSemibold
	nameLine.TextTruncate = Enum.TextTruncate.AtEnd
	nameLine.Parent = frame

	local incomeLine = Instance.new("TextLabel")
	incomeLine.Name = "IncomeLine"
	incomeLine.Size = UDim2.new(1, -16, 0, 34)
	incomeLine.Position = UDim2.new(0, 8, 0, 62)
	incomeLine.BackgroundTransparency = 1
	incomeLine.Text = "+" .. BrainrotCatalog.formatDollars(incomePerSec) .. "/s"
	incomeLine.TextColor3 = Color3.fromRGB(120, 255, 180)
	incomeLine.TextSize = 30
	incomeLine.TextXAlignment = Enum.TextXAlignment.Left
	incomeLine.Font = Enum.Font.GothamBold
	incomeLine.Parent = frame

	return card
end

-- Builds one complete brainrot sculpture: the multi-part body for its rigStyle,
-- plus the billboard card parented to the head so it follows the model.
function WorldAndRigBuilder.buildBrainrotRigModel(character: any, mutation: any, incomePerSec: number?): Model
	local income = incomePerSec or BrainrotCatalog.computeCharacterIncomePerSec(character, mutation, 1)

	local model = Instance.new("Model")
	model.Name = character.name
	local head = buildRigBody(model, character)

	local card = buildInfoCard(character, mutation, income)
	card.Adornee = head
	card.Parent = head

	model:SetAttribute("CharacterId", character.id)
	model:SetAttribute("Mutation", mutation.id)
	model:SetAttribute("IncomePerSec", income)
	return model
end

-- ---------------------------------------------------------------- vault

-- Rebuilds the eight vault rigs from a player state: each occupied pedestal
-- gets a rig sitting on top, each empty one loses its rig. Rigs are rebuilt
-- only when the character or mutation changed, so a passive refresh is cheap.
function WorldAndRigBuilder.refreshVaultPedestals(state: any): any
	local world = WorldAndRigBuilder.ensureWorldBuilt()
	local snapshot = BaseStateStore.buildClientSnapshot(state)
	local rigs = world.VaultRigs
	local wanted: { [number]: boolean } = {}

	for _, entry in ipairs(snapshot.pedestals) do
		wanted[entry.index] = true
		local rig = rigs:FindFirstChild("Rig_" .. entry.index)
		local unchanged = rig ~= nil
			and rig:GetAttribute("CharacterId") == entry.characterId
			and rig:GetAttribute("Mutation") == entry.mutation

		if not unchanged then
			if rig then
				rig:Destroy()
			end
			local character = BrainrotCatalog.getCharacterById(entry.characterId)
			local mutation = BrainrotCatalog.getMutationInfo(entry.mutation)
			if character then
				rig = WorldAndRigBuilder.buildBrainrotRigModel(character, mutation, entry.incomePerSec)
				rig.Name = "Rig_" .. entry.index
				rig.Parent = rigs
			end
		end

		if rig then
			local pedestal = world.VaultPedestals:FindFirstChild("Pedestal" .. entry.index)
			local baseX, baseZ = 0, 0
			local topY = 3
			if pedestal and pedestal:IsA("BasePart") then
				baseX = pedestal.Position.X
				baseZ = pedestal.Position.Z
				topY = pedestal.Position.Y + pedestal.Size.Y / 2
			end
			rig:PivotTo(CFrame.new(baseX, topY, baseZ))
		end
	end

	-- Drop any rig whose pedestal is now empty.
	for _, child in ipairs(rigs:GetChildren()) do
		if child:IsA("Model") and child.Name:match("^Rig_%d+$") then
			local index = tonumber(child.Name:match("%d+"))
			if index and not wanted[index] then
				child:Destroy()
			end
		end
	end

	return snapshot
end

-- ---------------------------------------------------------------- gate + wave

-- Armed beams glow neon cyan and read as solid; unlocked beams fade to a dim
-- teal so the gate visibly opens.
function WorldAndRigBuilder.updateLaserGateVisuals(locked: boolean): boolean
	local world = WorldAndRigBuilder.ensureWorldBuilt()
	local gate = world.LaserBarrierGate
	for _, name in ipairs(LASER_BEAM_NAMES) do
		local beam = gate:FindFirstChild(name)
		if beam and beam:IsA("BasePart") then
			if locked then
				beam.Color = ARMED_COLOR
				beam.Transparency = ARMED_TRANSPARENCY
				beam.Material = Enum.Material.Neon
			else
				beam.Color = UNLOCKED_COLOR
				beam.Transparency = UNLOCKED_TRANSPARENCY
				beam.Material = Enum.Material.SmoothPlastic
			end
		end
	end
	return locked
end

-- progress 0 keeps the wall at its start line; progress 1 drives it past the
-- lane. The wall's original CFrame is remembered in attributes so repeated
-- calls always sweep from the same place.
function WorldAndRigBuilder.updateTsunamiWavePosition(progress: number): number
	local world = WorldAndRigBuilder.ensureWorldBuilt()
	local wave = world.TsunamiHazardWall
	local primary = wave.PrimaryPart
	if not primary then
		return 0
	end

	local baseX = primary:GetAttribute("BaseX")
	local baseY = primary:GetAttribute("BaseY")
	local baseZ = primary:GetAttribute("BaseZ")
	if typeof(baseX) ~= "number" or typeof(baseY) ~= "number" or typeof(baseZ) ~= "number" then
		baseX, baseY, baseZ = primary.Position.X, primary.Position.Y, primary.Position.Z
		primary:SetAttribute("BaseX", baseX)
		primary:SetAttribute("BaseY", baseY)
		primary:SetAttribute("BaseZ", baseZ)
	end

	local clamped = math.clamp(progress, 0, 1)
	local z = baseZ + (WAVE_LANE_END_Z - WAVE_LANE_START_Z) * clamped
	wave:PivotTo(CFrame.new(baseX, baseY, z))
	return z
end

-- ---------------------------------------------------------------- constants

WorldAndRigBuilder.PEDESTAL_COUNT = PEDESTAL_COUNT
WorldAndRigBuilder.WAVE_LANE_START_Z = WAVE_LANE_START_Z
WorldAndRigBuilder.WAVE_LANE_END_Z = WAVE_LANE_END_Z

return WorldAndRigBuilder
