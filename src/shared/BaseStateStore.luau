--!strict
-- BaseStateStore
-- The single source of truth for every player's progress in Brainrot Tsunami
-- Heist. All cash, vault pedestals, carried brainrots, upgrades, rebirths and
-- the laser-lock timer live in one table per player, created by initPlayerState
-- and read everywhere else through getPlayerState.
--
-- The server owns the store. The client never mutates it directly: it asks the
-- server for a serialisable view through buildClientSnapshot. Every mutating
-- function here returns a success flag (and whatever the caller needs) so the
-- networking layer can answer the player accurately.

local BrainrotCatalog = require(script.Parent.BrainrotCatalog)

local BaseStateStore = {}

-- ---------------------------------------------------------------- tuning

local STARTING_CASH = 250
local BASE_PEDESTAL_CAPACITY = 8
local LASER_LOCK_SECONDS = 8
local SELL_INCOME_SECONDS = 25

-- ---------------------------------------------------------------- types

export type PedestalEntry = {
	characterId: string,
	mutationId: string,
	incomePerSec: number,
	lockedUntil: number,
}

export type CarriedBrainrot = {
	characterId: string,
	mutationId: string,
	incomePerSec: number,
}

export type PlayerState = {
	userId: number,
	name: string,
	preset: string?,
	createdAt: number,
	lastTick: number,
	cash: number,
	lifetimeEarned: number,
	incomePerSec: number,
	rebirthCount: number,
	rebirthMultiplier: number,
	laserLockUntil: number,
	laserLockCause: string?,
	carrying: CarriedBrainrot?,
	pedestals: { [number]: PedestalEntry? },
	pedestalCapacity: number,
	upgrades: { [string]: number },
	unlockedRarities: { [string]: boolean },
	unlockedMutations: { [string]: boolean },
	stats: { [string]: number },
}

-- Every player's state, keyed by the Player instance, so it is dropped the
-- moment the player leaves and removePlayerState forgets them.
local states: { [Player]: PlayerState } = {}

-- ---------------------------------------------------------------- private helpers

local function now(): number
	return os.clock()
end

local function findFreePedestal(state: PlayerState): number?
	for index = 1, state.pedestalCapacity do
		if state.pedestals[index] == nil then
			return index
		end
	end
	return nil
end

local function makePedestalEntry(state: PlayerState, characterId: string, mutationId: string): PedestalEntry
	local character = BrainrotCatalog.getCharacterById(characterId)
	local mutation = BrainrotCatalog.getMutationInfo(mutationId)
	local resolvedId = if character then character.id else characterId
	local income = BrainrotCatalog.computeCharacterIncomePerSec(resolvedId, mutation, state.rebirthMultiplier)
	return {
		characterId = resolvedId,
		mutationId = mutation.id,
		incomePerSec = income,
		lockedUntil = 0,
	}
end

local function setPedestal(state: PlayerState, index: number, characterId: string, mutationId: string): ()
	state.pedestals[index] = makePedestalEntry(state, characterId, mutationId)
end

-- Rebuilds the unlocked-rarity and unlocked-mutation sets up to a ceiling,
-- used when a new player joins and when a tour preset is applied.
local function resetUnlocks(state: PlayerState, maxRarityTier: number, maxMutationOrder: number): ()
	local rarities: { [string]: boolean } = {}
	for _, rarity in ipairs(BrainrotCatalog.RARITIES) do
		if rarity.tier <= maxRarityTier then
			rarities[rarity.id] = true
		end
	end

	local mutations: { [string]: boolean } = {}
	for index, mutation in ipairs(BrainrotCatalog.MUTATIONS) do
		if index <= maxMutationOrder then
			mutations[mutation.id] = true
		end
	end

	state.unlockedRarities = rarities
	state.unlockedMutations = mutations
end

local function keysAsArray(map: { [string]: boolean }): { string }
	local out: { string } = {}
	for key, value in pairs(map) do
		if value then
			out[#out + 1] = key
		end
	end
	table.sort(out)
	return out
end

-- ---------------------------------------------------------------- lifecycle

-- Creates and returns the player's state, or returns the one already held.
function BaseStateStore.initPlayerState(player: Player): PlayerState
	local existing = states[player]
	if existing then
		return existing
	end

	local state: PlayerState = {
		userId = player.UserId,
		name = player.Name,
		preset = "default",
		createdAt = now(),
		lastTick = now(),
		cash = STARTING_CASH,
		lifetimeEarned = STARTING_CASH,
		incomePerSec = 0,
		rebirthCount = 0,
		rebirthMultiplier = 1,
		laserLockUntil = 0,
		laserLockCause = nil,
		carrying = nil,
		pedestals = {},
		pedestalCapacity = BASE_PEDESTAL_CAPACITY,
		upgrades = { SpeedBoots = 0, MutationLuck = 0, ExtraPedestals = 0 },
		unlockedRarities = {},
		unlockedMutations = {},
		stats = { steals = 0, stolen = 0, deposits = 0, sells = 0, rebirths = 0 },
	}

	resetUnlocks(state, 2, 2)
	states[player] = state
	return state
end

function BaseStateStore.getPlayerState(player: Player): PlayerState?
	return states[player]
end

function BaseStateStore.removePlayerState(player: Player): boolean
	local existed = states[player] ~= nil
	states[player] = nil
	return existed
end

-- ---------------------------------------------------------------- income

-- Sums every occupied pedestal. A carried brainrot earns nothing until it is
-- safely deposited, which is what makes a dash home under the tsunami matter.
function BaseStateStore.recalculateIncomePerSec(state: PlayerState): number
	local total = 0
	for _, entry in pairs(state.pedestals) do
		if entry then
			total += entry.incomePerSec
		end
	end
	state.incomePerSec = total
	return total
end

function BaseStateStore.tickPassiveCash(state: PlayerState, dt: number): number
	local earned = state.incomePerSec * dt
	state.cash += earned
	state.lifetimeEarned += earned
	state.lastTick = now()
	return earned
end

-- ---------------------------------------------------------------- laser gate

function BaseStateStore.activateLaserLock(state: PlayerState, duration: number?, cause: string?): number
	state.laserLockUntil = now() + (duration or LASER_LOCK_SECONDS)
	state.laserLockCause = cause or "heist"
	return state.laserLockUntil
end

function BaseStateStore.isLaserLocked(state: PlayerState): boolean
	return now() < state.laserLockUntil
end

-- ---------------------------------------------------------------- carrying

function BaseStateStore.startCarryingBrainrot(
	state: PlayerState,
	characterId: string,
	mutationId: string?
): (boolean, CarriedBrainrot?)
	if state.carrying then
		return false, nil
	end

	local character = BrainrotCatalog.getCharacterById(characterId)
	if not character then
		return false, nil
	end

	local mutation = BrainrotCatalog.getMutationInfo(mutationId)
	local carried: CarriedBrainrot = {
		characterId = character.id,
		mutationId = mutation.id,
		incomePerSec = BrainrotCatalog.computeCharacterIncomePerSec(character, mutation, state.rebirthMultiplier),
	}
	state.carrying = carried
	return true, carried
end

function BaseStateStore.dropCarriedBrainrot(state: PlayerState): (boolean, CarriedBrainrot?)
	local carried = state.carrying
	if not carried then
		return false, nil
	end
	state.carrying = nil
	return true, carried
end

-- ---------------------------------------------------------------- vault

function BaseStateStore.depositCarriedBrainrotToPedestal(
	state: PlayerState,
	pedestalIndex: number?
): (boolean, number?)
	local carried = state.carrying
	if not carried then
		return false, nil
	end

	local index = pedestalIndex
	if index == nil then
		index = findFreePedestal(state)
	end
	if index == nil or index < 1 or index > state.pedestalCapacity then
		return false, nil
	end
	if state.pedestals[index] ~= nil then
		return false, nil
	end

	state.pedestals[index] = {
		characterId = carried.characterId,
		mutationId = carried.mutationId,
		incomePerSec = carried.incomePerSec,
		lockedUntil = 0,
	}
	state.carrying = nil
	state.stats.deposits += 1
	BaseStateStore.recalculateIncomePerSec(state)
	return true, index
end

function BaseStateStore.sellPedestalBrainrot(state: PlayerState, pedestalIndex: number): (boolean, number?)
	local entry = state.pedestals[pedestalIndex]
	if not entry then
		return false, nil
	end

	local price = math.floor(entry.incomePerSec * SELL_INCOME_SECONDS)
	state.cash += price
	state.stats.sells += 1
	state.pedestals[pedestalIndex] = nil
	BaseStateStore.recalculateIncomePerSec(state)
	return true, price
end

-- ---------------------------------------------------------------- stealing

-- Lifts a random brainrot from the victim's vault into the stealer's hands.
-- The victim keeps their other pedestals; its passive income is recalculated.
function BaseStateStore.stealRandomPedestalBrainrot(
	stealerState: PlayerState,
	victimState: PlayerState
): (boolean, CarriedBrainrot?, number?)
	if stealerState.carrying then
		return false, nil, nil
	end

	local candidates: { number } = {}
	for index, entry in pairs(victimState.pedestals) do
		if entry then
			candidates[#candidates + 1] = index
		end
	end
	if #candidates == 0 then
		return false, nil, nil
	end

	local chosenIndex = candidates[math.random(1, #candidates)]
	local entry = victimState.pedestals[chosenIndex]
	if not entry then
		return false, nil, nil
	end

	victimState.pedestals[chosenIndex] = nil
	BaseStateStore.recalculateIncomePerSec(victimState)

	local carried: CarriedBrainrot = {
		characterId = entry.characterId,
		mutationId = entry.mutationId,
		incomePerSec = entry.incomePerSec,
	}
	stealerState.carrying = carried
	stealerState.stats.steals += 1
	victimState.stats.stolen += 1
	return true, carried, chosenIndex
end

-- ---------------------------------------------------------------- progression

function BaseStateStore.purchaseUpgrade(state: PlayerState, upgradeId: string): (boolean, number?, number?)
	local upgrade = BrainrotCatalog.UPGRADE_BY_ID[upgradeId]
	if not upgrade then
		return false, nil, nil
	end

	local level = state.upgrades[upgradeId] or 0
	if level >= upgrade.maxLevel then
		return false, nil, nil
	end

	local cost = BrainrotCatalog.getUpgradeCost(upgradeId, level)
	if state.cash < cost then
		return false, nil, nil
	end

	state.cash -= cost
	state.upgrades[upgradeId] = level + 1
	if upgradeId == "ExtraPedestals" then
		state.pedestalCapacity += upgrade.effectPerLevel
	end
	return true, level + 1, cost
end

-- Spends the tier's cost, raises the rebirth multiplier, unlocks whatever the
-- tier grants and resets the vault, exactly like a hard reset should.
function BaseStateStore.attemptRebirth(state: PlayerState): (boolean, any)
	local tier = BrainrotCatalog.getNextRebirthTier(state.rebirthCount)
	if not tier then
		return false, nil
	end
	if state.cash < tier.cost then
		return false, nil
	end

	state.cash -= tier.cost
	state.rebirthCount = tier.order
	state.rebirthMultiplier = tier.incomeMultiplier
	state.carrying = nil
	state.pedestals = {}
	if tier.rarityUnlock then
		state.unlockedRarities[tier.rarityUnlock] = true
	end
	if tier.mutationUnlock then
		state.unlockedMutations[tier.mutationUnlock] = true
	end
	state.stats.rebirths += 1
	BaseStateStore.recalculateIncomePerSec(state)
	return true, tier
end

-- ---------------------------------------------------------------- tour presets

-- Drives the three tour screenshots: a full vault for the cover, a live heist
-- under a locked laser gate, and the rebirth shrine mid-run. Each preset is a
-- self-contained snapshot of a plausible game state.
function BaseStateStore.applyPresetState(state: PlayerState, presetName: string): PlayerState
	state.preset = presetName
	state.pedestals = {}
	state.carrying = nil
	state.stats = { steals = 0, stolen = 0, deposits = 0, sells = 0, rebirths = 0 }
	state.upgrades = { SpeedBoots = 0, MutationLuck = 0, ExtraPedestals = 0 }
	state.pedestalCapacity = BASE_PEDESTAL_CAPACITY
	state.laserLockUntil = 0
	state.laserLockCause = nil

	if presetName == "cover" then
		state.cash = 1250000
		state.lifetimeEarned = 9800000
		state.rebirthCount = 3
		state.rebirthMultiplier = 2.5
		state.upgrades = { SpeedBoots = 3, MutationLuck = 4, ExtraPedestals = 1 }
		state.pedestalCapacity = BASE_PEDESTAL_CAPACITY + 1
		resetUnlocks(state, 6, 5)
		setPedestal(state, 1, "LiriliLarila", "Golden")
		setPedestal(state, 2, "TrippiTroppi", "Diamond")
		setPedestal(state, 3, "BrrBrrPatapim", "Normal")
		setPedestal(state, 4, "BallerinaCappuccina", "Galaxy")
		setPedestal(state, 5, "TralaleroTralala", "Golden")
		setPedestal(state, 6, "TungTungSahur", "Diamond")
		setPedestal(state, 7, "BombardiroCrocodilo", "Galaxy")
		setPedestal(state, 8, "LaVacaSaturnoSaturnita", "Rainbow")
	elseif presetName == "heist" then
		state.cash = 320000
		state.lifetimeEarned = 4600000
		state.rebirthCount = 4
		state.rebirthMultiplier = 3.5
		state.upgrades = { SpeedBoots = 5, MutationLuck = 6, ExtraPedestals = 2 }
		state.pedestalCapacity = BASE_PEDESTAL_CAPACITY + 2
		resetUnlocks(state, 5, 4)
		setPedestal(state, 1, "FrigoCamelo", "Normal")
		setPedestal(state, 2, "GlorboFruttodrillo", "Golden")
		setPedestal(state, 3, "OrangutiniAnanasini", "Normal")
		setPedestal(state, 4, "CapuccinoAssassino", "Diamond")
		setPedestal(state, 5, "TralaleroTralala", "Golden")
		BaseStateStore.startCarryingBrainrot(state, "TungTungSahur", "Galaxy")
		BaseStateStore.activateLaserLock(state, 12, "heist")
	elseif presetName == "rebirth" then
		state.cash = 75000000
		state.lifetimeEarned = 210000000
		state.rebirthCount = 4
		state.rebirthMultiplier = 3.5
		state.pedestalCapacity = BASE_PEDESTAL_CAPACITY
		state.upgrades = { SpeedBoots = 6, MutationLuck = 8, ExtraPedestals = 0 }
		resetUnlocks(state, 6, 5)
		setPedestal(state, 1, "TralaleroTralala", "Diamond")
		setPedestal(state, 2, "TungTungSahur", "Galaxy")
		setPedestal(state, 3, "BombardiroCrocodilo", "Diamond")
		setPedestal(state, 4, "LaVacaSaturnoSaturnita", "Rainbow")
		setPedestal(state, 5, "GaramaMadundung", "Golden")
		setPedestal(state, 6, "GaramaMadundung", "Galaxy")
		setPedestal(state, 7, "GaramaMadundung", "Rainbow")
		setPedestal(state, 8, "LaVacaSaturnoSaturnita", "Galaxy")
	else
		state.cash = STARTING_CASH
		state.lifetimeEarned = STARTING_CASH
		state.rebirthCount = 0
		state.rebirthMultiplier = 1
		resetUnlocks(state, 2, 2)
	end

	BaseStateStore.recalculateIncomePerSec(state)
	return state
end

-- ---------------------------------------------------------------- replication

-- A plain, function-free view of the state the server can hand a client. It
-- carries ids and colours, never the live tables, so a client cannot mutate
-- the source of truth.
function BaseStateStore.buildClientSnapshot(state: PlayerState): { [string]: any }
	local pedestals: { { [string]: any } } = {}
	for index, entry in pairs(state.pedestals) do
		if entry then
			local character = BrainrotCatalog.getCharacterById(entry.characterId)
			local mutation = BrainrotCatalog.getMutationInfo(entry.mutationId)
			pedestals[#pedestals + 1] = {
				index = index,
				characterId = entry.characterId,
				name = if character then character.name else entry.characterId,
				rarity = if character then character.rarity else "Common",
				rarityColor = if character then character.primaryColor else Color3.fromRGB(200, 200, 200),
				accentColor = if character then character.accentColor else Color3.fromRGB(230, 230, 230),
				rigStyle = if character then character.rigStyle else "Biped",
				mutation = mutation.id,
				mutationMultiplier = mutation.multiplier,
				mutationColor = mutation.color,
				incomePerSec = entry.incomePerSec,
			}
		end
	end
	table.sort(pedestals, function(a, b)
		return a.index < b.index
	end)

	local carrying = nil
	if state.carrying then
		local carriedCharacter = BrainrotCatalog.getCharacterById(state.carrying.characterId)
		local carriedMutation = BrainrotCatalog.getMutationInfo(state.carrying.mutationId)
		carrying = {
			characterId = state.carrying.characterId,
			name = if carriedCharacter then carriedCharacter.name else state.carrying.characterId,
			rarity = if carriedCharacter then carriedCharacter.rarity else "Common",
			mutation = carriedMutation.id,
			mutationColor = carriedMutation.color,
			incomePerSec = state.carrying.incomePerSec,
		}
	end

	return {
		userId = state.userId,
		name = state.name,
		preset = state.preset,
		cash = state.cash,
		formattedCash = BrainrotCatalog.formatDollars(state.cash),
		incomePerSec = state.incomePerSec,
		formattedIncome = BrainrotCatalog.formatDollars(state.incomePerSec) .. "/s",
		lifetimeEarned = state.lifetimeEarned,
		rebirthCount = state.rebirthCount,
		rebirthMultiplier = state.rebirthMultiplier,
		laserLocked = BaseStateStore.isLaserLocked(state),
		laserLockRemaining = math.max(0, state.laserLockUntil - now()),
		laserLockCause = state.laserLockCause,
		carrying = carrying,
		pedestals = pedestals,
		pedestalCapacity = state.pedestalCapacity,
		upgrades = state.upgrades,
		unlockedRarities = keysAsArray(state.unlockedRarities),
		unlockedMutations = keysAsArray(state.unlockedMutations),
		stats = state.stats,
	}
end

-- ---------------------------------------------------------------- constants

BaseStateStore.STARTING_CASH = STARTING_CASH
BaseStateStore.BASE_PEDESTAL_CAPACITY = BASE_PEDESTAL_CAPACITY
BaseStateStore.LASER_LOCK_SECONDS = LASER_LOCK_SECONDS
BaseStateStore.SELL_INCOME_SECONDS = SELL_INCOME_SECONDS

return BaseStateStore
