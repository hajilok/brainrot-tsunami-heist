--!strict
-- Game.client.luau
-- The client controller for Brainrot Tsunami Heist. It owns the 3D Scriptable
-- camera and its three tour presets, reads movement from UserInputService and
-- discrete actions from ContextActionService, sends them to the server over
-- BrainrotAction, and draws the ScreenGui HUD from the BrainrotStateSync
-- snapshots the server pushes once a second.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BrainrotCatalog = require(Shared:WaitForChild("BrainrotCatalog"))

local remotes = ReplicatedStorage:WaitForChild("BrainrotRemotes")
local actionRemote = remotes:WaitForChild("BrainrotAction") :: RemoteEvent
local syncRemote = remotes:WaitForChild("BrainrotStateSync") :: RemoteEvent

-- ---------------------------------------------------------------- local state

local snapshot: any = {}
local upgradeCursor = 1
local UPGRADE_ORDER = { "SpeedBoots", "MutationLuck", "ExtraPedestals" }

-- ---------------------------------------------------------------- camera presets

-- Key 1 sweeps across the eight vault pedestals, key 2 frames the conveyor and
-- the incoming tsunami, key 3 looks down the altar and mutation shrine.
local PRESETS = {
	{
		key = "cover",
		label = "Vault Cover",
		hint = "1",
		cframe = CFrame.lookAt(Vector3.new(0, 27, 62), Vector3.new(0, 5, 0)),
	},
	{
		key = "heist",
		label = "Heist Lane & Tsunami Chase",
		hint = "2",
		cframe = CFrame.lookAt(Vector3.new(0, 34, -14), Vector3.new(0, 4, -34)),
	},
	{
		key = "rebirth",
		label = "Rebirth Altar & Mutation Shrine",
		hint = "3",
		cframe = CFrame.lookAt(Vector3.new(0, 30, 128), Vector3.new(0, 8, 90)),
	},
}

local activePreset = 1
local cameraTarget = PRESETS[1].cframe

local function presetName(): string
	return PRESETS[activePreset].label
end

local function setPreset(index: number): ()
	index = math.clamp(index, 1, #PRESETS)
	activePreset = index
	cameraTarget = PRESETS[index].cframe

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	actionRemote:FireServer("ApplyPreset", { preset = PRESETS[index].key })
end

-- ---------------------------------------------------------------- gui helpers

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for property, value in pairs(props) do
		(instance :: any)[property] = value
	end
	if parent then
		(instance :: any).Parent = parent
	end
	return instance
end

local function label(parent: Instance, props: { [string]: any }): any
	local merged = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(235, 238, 245),
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in pairs(props) do
		merged[key] = value
	end
	return make("TextLabel", merged, parent)
end

local playerGui = player:WaitForChild("PlayerGui")

local gui = make("ScreenGui", {
	Name = "BrainrotHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- ---------------------------------------------------------------- top banner
-- Anchored at 0.5 with a 0.54 width, so its left edge sits at 0.23: past 0.22,
-- which keeps the top-left Roblox menu corner completely clear.

local topBanner = make("Frame", {
	Name = "TopBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.new(0.54, 0, 0, 62),
	BackgroundColor3 = Color3.fromRGB(14, 16, 26),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, topBanner)
make("UIStroke", { Color = Color3.fromRGB(70, 205, 210), Thickness = 1.5, Transparency = 0.35 }, topBanner)

label(topBanner, {
	Name = "Title",
	Position = UDim2.new(0, 16, 0, 8),
	Size = UDim2.new(0.6, 0, 0, 26),
	Text = "BRAINROT TSUNAMI HEIST",
	TextColor3 = Color3.fromRGB(255, 205, 90),
	TextSize = 22,
	Font = Enum.Font.GothamBlack,
})

local statusLabel = label(topBanner, {
	Name = "Status",
	Position = UDim2.new(0, 16, 0, 34),
	Size = UDim2.new(0.62, 0, 0, 20),
	Text = "Booting...",
	TextColor3 = Color3.fromRGB(170, 190, 210),
	TextSize = 14,
})

local cashLabel = label(topBanner, {
	Name = "Cash",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 6),
	Size = UDim2.new(0.4, 0, 0, 30),
	Text = "$0",
	TextColor3 = Color3.fromRGB(120, 255, 180),
	TextSize = 25,
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Enum.Font.GothamBold,
})

local incomeLabel = label(topBanner, {
	Name = "Income",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 36),
	Size = UDim2.new(0.4, 0, 0, 20),
	Text = "+$0/s",
	TextColor3 = Color3.fromRGB(160, 230, 255),
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Right,
})

-- ---------------------------------------------------------------- tsunami banner

local tsunamiBanner = make("Frame", {
	Name = "TsunamiBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.new(0.42, 0, 0, 44),
	BackgroundColor3 = Color3.fromRGB(120, 70, 15),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, tsunamiBanner)
local tsunamiStroke = make("UIStroke", { Color = Color3.fromRGB(255, 120, 60), Thickness = 2, Transparency = 0.1 }, tsunamiBanner)

local tsunamiLabel = label(tsunamiBanner, {
	Name = "TsunamiText",
	Size = UDim2.fromScale(1, 1),
	Text = "TSUNAMI",
	TextColor3 = Color3.fromRGB(255, 245, 235),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBold,
})

-- ---------------------------------------------------------------- bottom action bar

local actionBar = make("Frame", {
	Name = "ActionBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.new(0.86, 0, 0, 56),
	BackgroundColor3 = Color3.fromRGB(14, 16, 26),
	BackgroundTransparency = 0.18,
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, actionBar)
make("UIStroke", { Color = Color3.fromRGB(70, 150, 210), Thickness = 1.5, Transparency = 0.4 }, actionBar)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, actionBar)

local function makeButton(text: string, order: number, onClick: () -> ()): any
	local button = make("TextButton", {
		Name = text,
		Size = UDim2.new(0, 176, 0, 38),
		BackgroundColor3 = Color3.fromRGB(26, 30, 46),
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Color3.fromRGB(225, 232, 245),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		AutoButtonColor = true,
		LayoutOrder = order,
	}, actionBar)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
	make("UIStroke", { Color = Color3.fromRGB(70, 90, 130), Thickness = 1, Transparency = 0.5 }, button)
	button.Activated:Connect(onClick)
	return button
end

-- ---------------------------------------------------------------- action senders

local function sendGrabOrDeposit(): ()
	if snapshot.carrying then
		actionRemote:FireServer("HeistAction", { mode = "deposit" })
	else
		actionRemote:FireServer("HeistAction", { mode = "grab" })
	end
end

local function sendLockLaser(): ()
	actionRemote:FireServer("LockLaser")
end

local function sendUpgrade(): ()
	local upgradeId = UPGRADE_ORDER[upgradeCursor]
	actionRemote:FireServer("BuyUpgrade", { upgradeId = upgradeId })
	upgradeCursor = upgradeCursor % #UPGRADE_ORDER + 1
end

local function sendRebirth(): ()
	actionRemote:FireServer("AttemptRebirth")
end

-- ---------------------------------------------------------------- index modal

local indexPanel = make("Frame", {
	Name = "IndexPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0.62, 0, 0.74, 0),
	BackgroundColor3 = Color3.fromRGB(18, 16, 28),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, indexPanel)
make("UIStroke", { Color = Color3.fromRGB(255, 205, 90), Thickness = 2, Transparency = 0.25 }, indexPanel)

label(indexPanel, {
	Name = "PanelTitle",
	Position = UDim2.new(0, 18, 0, 12),
	Size = UDim2.new(1, -60, 0, 28),
	Text = "16-BRAINROT CAST INDEX & REBIRTH IV/V SHOP",
	TextColor3 = Color3.fromRGB(255, 205, 90),
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
})

local closeButton = make("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0, 30, 0, 30),
	BackgroundColor3 = Color3.fromRGB(60, 26, 34),
	BorderSizePixel = 0,
	Text = "X",
	TextColor3 = Color3.fromRGB(255, 220, 220),
	TextSize = 18,
	Font = Enum.Font.GothamBold,
}, indexPanel)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, closeButton)
closeButton.Activated:Connect(function()
	indexPanel.Visible = false
end)

local castScroll = make("ScrollingFrame", {
	Name = "CastList",
	Position = UDim2.new(0, 16, 0, 50),
	Size = UDim2.new(0.56, -16, 1, -66),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, indexPanel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, castScroll)

local shopScroll = make("ScrollingFrame", {
	Name = "ShopList",
	Position = UDim2.new(0.56, 8, 0, 50),
	Size = UDim2.new(0.44, -24, 1, -66),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, indexPanel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, shopScroll)

-- One row per brainrot: rarity swatch, name, rarity, income and steal cost.
local castIndex = 1
for _, character in ipairs(BrainrotCatalog.CHARACTERS) do
	local rarity = BrainrotCatalog.getRarityInfo(character.rarity)
	local rarityColor = if rarity then rarity.color else Color3.fromRGB(200, 200, 200)

	local row = make("Frame", {
		Name = character.id,
		Size = UDim2.new(1, -6, 0, 42),
		BackgroundColor3 = Color3.fromRGB(26, 24, 40),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = castIndex,
	}, castScroll)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)

	make("Frame", {
		Name = "Swatch",
		Position = UDim2.new(0, 8, 0, 9),
		Size = UDim2.new(0, 24, 0, 24),
		BackgroundColor3 = character.primaryColor,
		BorderSizePixel = 0,
	}, row)
	make("UIStroke", { Color = character.accentColor, Thickness = 1.5 }, row:FindFirstChild("Swatch"))

	label(row, {
		Name = "Name",
		Position = UDim2.new(0, 40, 0, 4),
		Size = UDim2.new(0.6, 0, 0, 20),
		Text = character.name,
		TextColor3 = rarityColor,
		TextSize = 16,
		Font = Enum.Font.GothamSemibold,
	})
	label(row, {
		Name = "Rarity",
		Position = UDim2.new(0, 40, 0, 22),
		Size = UDim2.new(0.6, 0, 0, 16),
		Text = string.format("%s · %s · steal %s", character.rarity, character.rigStyle, BrainrotCatalog.formatDollars(character.stealCost)),
		TextColor3 = Color3.fromRGB(150, 160, 180),
		TextSize = 12,
	})
	label(row, {
		Name = "Income",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 120, 0, 22),
		Text = "+" .. BrainrotCatalog.formatDollars(character.baseIncomePerSec) .. "/s",
		TextColor3 = Color3.fromRGB(120, 255, 180),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.GothamBold,
	})

	castIndex += 1
end

-- The right column is the rebirth shop: every tier with its cost, multiplier
-- and, for IV and V, what it unlocks.
for order, tier in ipairs(BrainrotCatalog.REBIRTH_TIERS) do
	local unlocks = ""
	if tier.rarityUnlock then
		unlocks ..= (" · unlocks " .. tier.rarityUnlock)
	end
	if tier.mutationUnlock then
		unlocks ..= ("/" .. tier.mutationUnlock)
	end

	local row = make("Frame", {
		Name = "Rebirth" .. order,
		Size = UDim2.new(1, -6, 0, 54),
		BackgroundColor3 = Color3.fromRGB(30, 22, 40),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, shopScroll)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)

	label(row, {
		Name = "Tier",
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -20, 0, 20),
		Text = string.format("%s  ·  x%.2f income", tier.name, tier.incomeMultiplier),
		TextColor3 = Color3.fromRGB(220, 190, 255),
		TextSize = 15,
		Font = Enum.Font.GothamSemibold,
	})
	label(row, {
		Name = "Cost",
		Position = UDim2.new(0, 10, 0, 26),
		Size = UDim2.new(1, -20, 0, 22),
		Text = string.format("Cost %s%s", BrainrotCatalog.formatDollars(tier.cost), unlocks),
		TextColor3 = Color3.fromRGB(160, 150, 190),
		TextSize = 12,
	})
end

-- ---------------------------------------------------------------- buttons + bindings

local grabButton = makeButton("[E] Grab Brainrot", 1, sendGrabOrDeposit)
makeButton("[F] Lock Laser Gate", 2, sendLockLaser)

local upgradeButton: any
local function cycleUpgrade(): ()
	local nextId = UPGRADE_ORDER[upgradeCursor]
	sendUpgrade()
	if upgradeButton then
		upgradeButton.Text = "[U] Buy " .. nextId
	end
end
upgradeButton = makeButton("[U] Buy SpeedBoots", 3, cycleUpgrade)

makeButton("[R] Rebirth", 4, sendRebirth)
makeButton("[I] Cast Index & Shop", 5, function()
	indexPanel.Visible = not indexPanel.Visible
end)
makeButton("[1/2/3] Camera Presets", 6, function()
	setPreset(activePreset % #PRESETS + 1)
end)

local function bindAction(name: string, keyCode: Enum.KeyCode, handler: () -> ()): ()
	ContextActionService:BindAction(name, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			handler()
		end
		return Enum.ContextActionResult.Pass
	end, false, keyCode)
end

bindAction("BrainrotGrab", Enum.KeyCode.E, sendGrabOrDeposit)
bindAction("BrainrotLock", Enum.KeyCode.F, sendLockLaser)
bindAction("BrainrotUpgrade", Enum.KeyCode.U, cycleUpgrade)
bindAction("BrainrotRebirth", Enum.KeyCode.R, sendRebirth)
bindAction("BrainrotIndex", Enum.KeyCode.I, function()
	indexPanel.Visible = not indexPanel.Visible
end)
bindAction("BrainrotPreset1", Enum.KeyCode.One, function()
	setPreset(1)
end)
bindAction("BrainrotPreset2", Enum.KeyCode.Two, function()
	setPreset(2)
end)
bindAction("BrainrotPreset3", Enum.KeyCode.Three, function()
	setPreset(3)
end)

-- ---------------------------------------------------------------- snapshot rendering

local function renderSnapshot(payload: any): ()
	snapshot = payload or {}

	cashLabel.Text = payload.formattedCash or "$0"
	incomeLabel.Text = "+" .. (payload.formattedIncome or "$0/s")
	statusLabel.Text = string.format(
		"%s  ·  Rebirth %d (x%.2f)  ·  Pedestals %d/%d",
		presetName(),
		payload.rebirthCount or 0,
		payload.rebirthMultiplier or 1,
		#(payload.pedestals or {}),
		payload.pedestalCapacity or 8
	)

	local phase = payload.tsunamiPhase
	if phase == "sweeping" then
		tsunamiBanner.Visible = true
		tsunamiBanner.BackgroundColor3 = Color3.fromRGB(150, 25, 25)
		tsunamiStroke.Color = Color3.fromRGB(255, 70, 70)
		tsunamiLabel.Text = "SWEEPING — CARRIERS OUTSIDE SHELTERS WASHED AWAY"
	elseif phase == "warning" then
		tsunamiBanner.Visible = true
		tsunamiBanner.BackgroundColor3 = Color3.fromRGB(120, 70, 15)
		tsunamiStroke.Color = Color3.fromRGB(255, 150, 60)
		tsunamiLabel.Text = "TSUNAMI INCOMING — GET TO A SHELTER"
	else
		tsunamiBanner.Visible = false
	end

	if payload.carrying then
		grabButton.Text = "[E] Deposit " .. payload.carrying.name
	else
		grabButton.Text = "[E] Grab Brainrot"
	end
end

syncRemote.OnClientEvent:Connect(renderSnapshot)

-- ---------------------------------------------------------------- movement + camera

local function updateMovement(): ()
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid:IsA("Humanoid") or humanoid.Health <= 0 then
		return
	end

	local move = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		move += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		move += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		move += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		move += Vector3.new(1, 0, 0)
	end

	if move.Magnitude > 0 then
		humanoid:Move(move.Unit, false)
	end
end

RunService.RenderStepped:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	if camera then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local alpha = math.clamp(dt * 8, 0, 1)
		camera.CFrame = camera.CFrame:Lerp(cameraTarget, alpha)
	end
	updateMovement()
end)

-- ---------------------------------------------------------------- startup

setPreset(1)
