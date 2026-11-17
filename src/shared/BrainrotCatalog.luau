--!strict
-- BrainrotCatalog
-- The data-only heart of Brainrot Tsunami Heist: rarity tiers, mutations,
-- every collectable brainrot, the shop upgrades and the rebirth ladder, plus
-- the pure helper functions that turn that data into numbers the rest of the
-- game reads.
--
-- This module is deterministic and side-effect free, so it lives under
-- ReplicatedStorage.Shared and is required by both the server and the client.
-- Nothing here touches player state; BaseStateStore owns that.

local BrainrotCatalog = {}

-- ---------------------------------------------------------------- types

export type RarityId = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Celestial"
export type MutationId = "Normal" | "Golden" | "Diamond" | "Galaxy" | "Rainbow"
export type UpgradeId = "SpeedBoots" | "MutationLuck" | "ExtraPedestals"

export type Rarity = {
	id: RarityId,
	name: string,
	tier: number,
	color: Color3,
	spawnWeight: number,
}

export type Mutation = {
	id: MutationId,
	name: string,
	multiplier: number,
	color: Color3,
	luckWeight: number,
}

export type Character = {
	id: string,
	name: string,
	rarity: RarityId,
	baseIncomePerSec: number,
	stealCost: number,
	rigStyle: string,
	primaryColor: Color3,
	accentColor: Color3,
	flavorText: string,
}

export type Upgrade = {
	id: UpgradeId,
	name: string,
	description: string,
	baseCost: number,
	costGrowth: number,
	maxLevel: number,
	effectPerLevel: number,
}

export type RebirthTier = {
	order: number,
	roman: string,
	name: string,
	cost: number,
	incomeMultiplier: number,
	rarityUnlock: RarityId?,
	mutationUnlock: MutationId?,
}

-- ---------------------------------------------------------------- rarities
-- Six tiers, cheapest first. spawnWeight is the share of the conveyor's
-- spawn roll each tier takes; they sum to 100.

local RARITIES: { Rarity } = {
	{ id = "Common", name = "Common", tier = 1, color = Color3.fromRGB(176, 184, 196), spawnWeight = 50 },
	{ id = "Rare", name = "Rare", tier = 2, color = Color3.fromRGB(74, 144, 255), spawnWeight = 26 },
	{ id = "Epic", name = "Epic", tier = 3, color = Color3.fromRGB(176, 84, 236), spawnWeight = 14 },
	{ id = "Legendary", name = "Legendary", tier = 4, color = Color3.fromRGB(255, 190, 64), spawnWeight = 7 },
	{ id = "Mythic", name = "Mythic", tier = 5, color = Color3.fromRGB(255, 72, 128), spawnWeight = 2.5 },
	{ id = "Celestial", name = "Celestial", tier = 6, color = Color3.fromRGB(150, 240, 255), spawnWeight = 0.5 },
}

-- ---------------------------------------------------------------- mutations
-- Applied on top of a character's base income. luckWeight is the share of a
-- fresh mutation roll each mutation takes before the luck stat bends it.

local MUTATIONS: { Mutation } = {
	{ id = "Normal", name = "Normal", multiplier = 1, color = Color3.fromRGB(235, 235, 235), luckWeight = 60 },
	{ id = "Golden", name = "Golden", multiplier = 2, color = Color3.fromRGB(255, 200, 64), luckWeight = 24 },
	{ id = "Diamond", name = "Diamond", multiplier = 3.5, color = Color3.fromRGB(120, 230, 255), luckWeight = 10 },
	{ id = "Galaxy", name = "Galaxy", multiplier = 6, color = Color3.fromRGB(130, 80, 235), luckWeight = 4.5 },
	{ id = "Rainbow", name = "Rainbow", multiplier = 10, color = Color3.fromRGB(255, 90, 200), luckWeight = 1.5 },
}

-- ---------------------------------------------------------------- characters
-- All sixteen collectable brainrots, ordered roughly by rarity. baseIncomePerSec
-- is the income at Normal mutation and no rebirth, stealCost is the bounty a
-- thief is paid for lifting the brainrot off another player's pedestal.

local CHARACTERS: { Character } = {
	{
		id = "LiriliLarila",
		name = "Lirili Larila",
		rarity = "Common",
		baseIncomePerSec = 1.5,
		stealCost = 40,
		rigStyle = "Biped",
		primaryColor = Color3.fromRGB(150, 120, 92),
		accentColor = Color3.fromRGB(240, 224, 200),
		flavorText = "Half cat, half larila, all trouble.",
	},
	{
		id = "BonecaAmbalabu",
		name = "Boneca Ambalabu",
		rarity = "Common",
		baseIncomePerSec = 2,
		stealCost = 55,
		rigStyle = "Quadruped",
		primaryColor = Color3.fromRGB(214, 176, 140),
		accentColor = Color3.fromRGB(255, 150, 190),
		flavorText = "A doll that ambals a little too eagerly.",
	},
	{
		id = "FrigoCamelo",
		name = "Frigo Camelo",
		rarity = "Common",
		baseIncomePerSec = 2.5,
		stealCost = 70,
		rigStyle = "Quadruped",
		primaryColor = Color3.fromRGB(230, 236, 244),
		accentColor = Color3.fromRGB(90, 170, 240),
		flavorText = "A fridge-camel hybrid that keeps your loot cold.",
	},
	{
		id = "BurbaloniLuliloli",
		name = "Burbaloni Luliloli",
		rarity = "Rare",
		baseIncomePerSec = 8,
		stealCost = 200,
		rigStyle = "Biped",
		primaryColor = Color3.fromRGB(110, 200, 120),
		accentColor = Color3.fromRGB(250, 230, 90),
		flavorText = "Bubbles first, questions never.",
	},
	{
		id = "ChimpanziniBananini",
		name = "Chimpanzini Bananini",
		rarity = "Rare",
		baseIncomePerSec = 9.5,
		stealCost = 240,
		rigStyle = "Biped",
		primaryColor = Color3.fromRGB(245, 220, 70),
		accentColor = Color3.fromRGB(60, 180, 170),
		flavorText = "Peels bananas at the speed of light.",
	},
	{
		id = "TrippiTroppi",
		name = "Trippi Troppi",
		rarity = "Rare",
		baseIncomePerSec = 11,
		stealCost = 280,
		rigStyle = "Avian",
		primaryColor = Color3.fromRGB(240, 130, 60),
		accentColor = Color3.fromRGB(220, 60, 60),
		flavorText = "A load-bearing shrimp with a jaunty hat.",
	},
	{
		id = "GlorboFruttodrillo",
		name = "Glorbo Fruttodrillo",
		rarity = "Rare",
		baseIncomePerSec = 12.5,
		stealCost = 320,
		rigStyle = "Serpentine",
		primaryColor = Color3.fromRGB(90, 190, 90),
		accentColor = Color3.fromRGB(180, 90, 220),
		flavorText = "A fruit-croc mashup that guards the vault.",
	},
	{
		id = "BrrBrrPatapim",
		name = "Brr Brr Patapim",
		rarity = "Epic",
		baseIncomePerSec = 26,
		stealCost = 650,
		rigStyle = "Amorphous",
		primaryColor = Color3.fromRGB(140, 110, 80),
		accentColor = Color3.fromRGB(120, 200, 90),
		flavorText = "Sings its own entrance music, badly.",
	},
	{
		id = "BallerinaCappuccina",
		name = "Ballerina Cappuccina",
		rarity = "Epic",
		baseIncomePerSec = 30,
		stealCost = 750,
		rigStyle = "Biped",
		primaryColor = Color3.fromRGB(245, 175, 205),
		accentColor = Color3.fromRGB(250, 240, 225),
		flavorText = "Pirouettes while your cash rolls in.",
	},
	{
		id = "OrangutiniAnanasini",
		name = "Orangutini Ananasini",
		rarity = "Epic",
		baseIncomePerSec = 34,
		stealCost = 850,
		rigStyle = "Biped",
		primaryColor = Color3.fromRGB(235, 150, 60),
		accentColor = Color3.fromRGB(90, 190, 110),
		flavorText = "Tiny ape, enormous pineapple energy.",
	},
	{
		id = "CapuccinoAssassino",
		name = "Capuccino Assassino",
		rarity = "Epic",
		baseIncomePerSec = 38,
		stealCost = 950,
		rigStyle = "Flying",
		primaryColor = Color3.fromRGB(150, 100, 70),
		accentColor = Color3.fromRGB(210, 50, 60),
		flavorText = "Steams across the map, foam included.",
	},
	{
		id = "TralaleroTralala",
		name = "Tralalero Tralala",
		rarity = "Legendary",
		baseIncomePerSec = 85,
		stealCost = 2200,
		rigStyle = "Biped",
		primaryColor = Color3.fromRGB(120, 150, 200),
		accentColor = Color3.fromRGB(230, 60, 60),
		flavorText = "Three legs, one shoe, infinite swagger.",
	},
	{
		id = "TungTungSahur",
		name = "Tung Tung Sahur",
		rarity = "Legendary",
		baseIncomePerSec = 95,
		stealCost = 2450,
		rigStyle = "Titan",
		primaryColor = Color3.fromRGB(150, 110, 70),
		accentColor = Color3.fromRGB(255, 210, 120),
		flavorText = "Taps the drum at dawn. Nobody sleeps through a heist.",
	},
	{
		id = "BombardiroCrocodilo",
		name = "Bombardiro Crocodilo",
		rarity = "Legendary",
		baseIncomePerSec = 120,
		stealCost = 3100,
		rigStyle = "Flying",
		primaryColor = Color3.fromRGB(80, 150, 90),
		accentColor = Color3.fromRGB(90, 95, 80),
		flavorText = "Loud, armored, and always airborne.",
	},
	{
		id = "LaVacaSaturnoSaturnita",
		name = "La Vaca Saturno Saturnita",
		rarity = "Mythic",
		baseIncomePerSec = 320,
		stealCost = 8000,
		rigStyle = "Titan",
		primaryColor = Color3.fromRGB(240, 240, 250),
		accentColor = Color3.fromRGB(150, 110, 230),
		flavorText = "A cosmic cow orbiting a ring of pure profit.",
	},
	{
		id = "GaramaMadundung",
		name = "Garama Madundung",
		rarity = "Celestial",
		baseIncomePerSec = 900,
		stealCost = 22000,
		rigStyle = "Amorphous",
		primaryColor = Color3.fromRGB(90, 120, 230),
		accentColor = Color3.fromRGB(255, 220, 110),
		flavorText = "The final form. Reality simply tallies the money.",
	},
}

-- ---------------------------------------------------------------- upgrades

local UPGRADES: { Upgrade } = {
	{
		id = "SpeedBoots",
		name = "Speed Boots",
		description = "Move faster while carrying a brainrot home.",
		baseCost = 1500,
		costGrowth = 1.9,
		maxLevel = 8,
		effectPerLevel = 0.12,
	},
	{
		id = "MutationLuck",
		name = "Mutation Luck",
		description = "Raises the odds of rarer mutations on fresh spawns.",
		baseCost = 5000,
		costGrowth = 2.1,
		maxLevel = 10,
		effectPerLevel = 0.15,
	},
	{
		id = "ExtraPedestals",
		name = "Extra Pedestals",
		description = "Adds another vault pedestal to hold another brainrot.",
		baseCost = 12000,
		costGrowth = 2.4,
		maxLevel = 6,
		effectPerLevel = 1,
	},
}

-- ---------------------------------------------------------------- rebirth

local REBIRTH_TIERS: { RebirthTier } = {
	{ order = 1, roman = "I", name = "Rebirth I", cost = 25000, incomeMultiplier = 1.25 },
	{ order = 2, roman = "II", name = "Rebirth II", cost = 180000, incomeMultiplier = 1.75 },
	{ order = 3, roman = "III", name = "Rebirth III", cost = 1250000, incomeMultiplier = 2.5 },
	{ order = 4, roman = "IV", name = "Rebirth IV", cost = 9000000, incomeMultiplier = 3.5 },
	{
		order = 5,
		roman = "V",
		name = "Rebirth V",
		cost = 60000000,
		incomeMultiplier = 5.5,
		rarityUnlock = "Celestial",
		mutationUnlock = "Rainbow",
	},
}

-- ---------------------------------------------------------------- lookup maps

local RARITY_BY_ID: { [string]: Rarity } = {}
local RARITY_BY_TIER: { [number]: Rarity } = {}
for _, rarity in ipairs(RARITIES) do
	RARITY_BY_ID[rarity.id] = rarity
	RARITY_BY_TIER[rarity.tier] = rarity
end

local MUTATION_BY_ID: { [string]: Mutation } = {}
for _, mutation in ipairs(MUTATIONS) do
	MUTATION_BY_ID[mutation.id] = mutation
end

local CHARACTER_BY_ID: { [string]: Character } = {}
for _, character in ipairs(CHARACTERS) do
	CHARACTER_BY_ID[character.id] = character
end

local UPGRADE_BY_ID: { [string]: Upgrade } = {}
for _, upgrade in ipairs(UPGRADES) do
	UPGRADE_BY_ID[upgrade.id] = upgrade
end

-- Public data tables, so callers can iterate the catalog directly.
BrainrotCatalog.RARITIES = RARITIES
BrainrotCatalog.MUTATIONS = MUTATIONS
BrainrotCatalog.CHARACTERS = CHARACTERS
BrainrotCatalog.UPGRADES = UPGRADES
BrainrotCatalog.REBIRTH_TIERS = REBIRTH_TIERS
BrainrotCatalog.RARITY_BY_ID = RARITY_BY_ID
BrainrotCatalog.MUTATION_BY_ID = MUTATION_BY_ID
BrainrotCatalog.CHARACTER_BY_ID = CHARACTER_BY_ID
BrainrotCatalog.UPGRADE_BY_ID = UPGRADE_BY_ID

-- ---------------------------------------------------------------- lookups

-- Accepts a character id and returns its record, or nil when the id is unknown.
function BrainrotCatalog.getCharacterById(id: string): Character?
	return CHARACTER_BY_ID[id]
end

-- Accepts a rarity id ("Mythic") or a tier number (5) and returns its record.
function BrainrotCatalog.getRarityInfo(idOrTier: string | number): Rarity?
	if type(idOrTier) == "number" then
		return RARITY_BY_TIER[idOrTier]
	end
	return RARITY_BY_ID[idOrTier]
end

-- A mutation by id, always returning one: an unknown id falls back to Normal.
function BrainrotCatalog.getMutationInfo(id: string?): Mutation
	return MUTATION_BY_ID[id or "Normal"] or MUTATIONS[1]
end

-- ---------------------------------------------------------------- maths

-- The income per second a single brainrot earns once placed, folding in its
-- mutation multiplier and the player's rebirth multiplier.
function BrainrotCatalog.computeCharacterIncomePerSec(
	characterOrId: Character | string,
	mutationOrId: Mutation | string?,
	rebirthMultiplier: number?
): number
	local character: Character?
	if type(characterOrId) == "table" then
		character = characterOrId
	else
		character = CHARACTER_BY_ID[characterOrId]
	end
	if not character then
		return 0
	end

	local mutation: Mutation?
	if type(mutationOrId) == "table" then
		mutation = mutationOrId
	else
		mutation = MUTATION_BY_ID[mutationOrId or "Normal"]
	end

	local mutationMultiplier = if mutation then mutation.multiplier else 1
	local rebirth = rebirthMultiplier or 1
	return character.baseIncomePerSec * mutationMultiplier * rebirth
end

-- Rolls a mutation weighting rarer ones more heavily as the luck stat climbs.
function BrainrotCatalog.rollMutationForLuck(luck: number?, rng: Random?): Mutation
	local generator = rng or Random.new()
	local weights: { number } = {}
	local total = 0

	for index, mutation in ipairs(MUTATIONS) do
		local boost = 1 + (luck or 0) * (index - 1) * 0.35
		local weight = mutation.luckWeight * boost
		weights[index] = weight
		total += weight
	end

	local roll = generator:NextNumber() * total
	local running = 0
	for index, mutation in ipairs(MUTATIONS) do
		running += weights[index]
		if roll <= running then
			return mutation
		end
	end
	return MUTATIONS[1]
end

-- Picks the character a fresh conveyor spawn becomes, weighted by rarity.
-- Celestial only enters the pool once the player has reached the last rebirth.
function BrainrotCatalog.pickConveyorSpawn(rng: Random?, rebirthTier: number?): Character
	local generator = rng or Random.new()
	local allowCelestial = (rebirthTier or 0) >= #REBIRTH_TIERS

	local candidates: { Character } = {}
	local weights: { number } = {}
	local total = 0

	for _, character in ipairs(CHARACTERS) do
		local rarity = RARITY_BY_ID[character.rarity]
		if rarity and (allowCelestial or character.rarity ~= "Celestial") then
			candidates[#candidates + 1] = character
			weights[#weights + 1] = rarity.spawnWeight
			total += rarity.spawnWeight
		end
	end

	if #candidates == 0 then
		return CHARACTERS[1]
	end

	local roll = generator:NextNumber() * total
	local running = 0
	for index, character in ipairs(candidates) do
		running += weights[index]
		if roll <= running then
			return character
		end
	end
	return candidates[#candidates]
end

-- The rebirth tier that follows the player's current count, or nil at the top.
function BrainrotCatalog.getNextRebirthTier(currentRebirthCount: number?): RebirthTier?
	return REBIRTH_TIERS[(currentRebirthCount or 0) + 1]
end

-- The cash price of the next level of an upgrade. Reachable max levels are
-- guarded by the caller; an unknown upgrade is infinitely expensive.
function BrainrotCatalog.getUpgradeCost(upgradeId: string, currentLevel: number?): number
	local upgrade = UPGRADE_BY_ID[upgradeId]
	if not upgrade then
		return math.huge
	end
	local level = currentLevel or 0
	return math.floor(upgrade.baseCost * (upgrade.costGrowth ^ level))
end

-- ---------------------------------------------------------------- display

local DOLLAR_STEPS = {
	{ threshold = 1e12, suffix = "T" },
	{ threshold = 1e9, suffix = "B" },
	{ threshold = 1e6, suffix = "M" },
	{ threshold = 1e3, suffix = "K" },
}

-- "$1.2M", "$950", "$4.5K" and so on, for HUD labels and tooltips.
function BrainrotCatalog.formatDollars(amount: number?): string
	local value = amount or 0
	local sign = ""
	if value < 0 then
		sign = "-"
		value = -value
	end

	for _, step in ipairs(DOLLAR_STEPS) do
		if value >= step.threshold then
			local scaled = string.format("%.2f", value / step.threshold)
			scaled = scaled:gsub("%.?0+$", "")
			return string.format("%s$%s%s", sign, scaled, step.suffix)
		end
	end

	return string.format("%s$%d", sign, math.floor(value))
end

return BrainrotCatalog
