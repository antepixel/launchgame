--!strict
-- ============================================================
-- TODO: REMOVE BEFORE LAUNCH -- this is the client half of the dev-testing
-- panel. See the written report for the exact list of files/blocks to
-- delete to strip this out entirely; DO NOT ship this in a published place.
-- ============================================================
--
-- Both checks below are COSMETIC ONLY (see DevPanelServer.server.luau for
-- the two gates that actually matter -- a hard RunService:IsStudio() check
-- that keeps the dev remotes from existing at all in a published server,
-- and a UserId allowlist re-checked on every single action). This script
-- just avoids building UI, or wiring up input, for anyone who isn't going
-- to be able to use it anyway: a modified client skipping these checks
-- still hits the server's two real gates and gets nowhere.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DevConfig = require(ReplicatedStorage.Config.DevConfig)
local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)
local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local SlimeUpgradeConfig = require(ReplicatedStorage.Config.SlimeUpgradeConfig)

local player = Players.LocalPlayer

if not table.find(DevConfig.ALLOWLISTED_USER_IDS, player.UserId) then
	return
end

local playerGui = player:WaitForChild("PlayerGui")

-- Only exists because DevPanelServer's own Gate 1 (RunService:IsStudio())
-- passed server-side too -- WaitForChild is safe/expected to resolve
-- quickly here, since client and server IsStudio() can never disagree
-- (Play Solo/Team Test run both inside the same Studio process; a
-- published game is neither).
local devRemotesFolder = ReplicatedStorage:WaitForChild("DevRemotes")
local devActionRemote = devRemotesFolder:WaitForChild("DevAction") :: RemoteEvent

local function fireAction(actionName: string, payload: any)
	devActionRemote:FireServer(actionName, payload)
end

-- Matches the money HUD's own K/M/B style (see BaseClient.client.luau).
local function formatAmount(value: number): string
	local magnitude = math.abs(value)
	local scale, suffix = 1, ""
	if magnitude >= 1e9 then
		scale, suffix = 1e9, "B"
	elseif magnitude >= 1e6 then
		scale, suffix = 1e6, "M"
	elseif magnitude >= 1e3 then
		scale, suffix = 1e3, "K"
	end
	if suffix == "" then
		return string.format("%d", value)
	end
	local formatted = string.format("%.1f", value / scale)
	formatted = formatted:gsub("%.0$", "")
	return formatted .. suffix
end

-- ===== UI shell =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevPanel"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(0.99, 0, 0.5, 0)
panel.Size = UDim2.new(0, 340, 0, 900)
panel.BackgroundColor3 = Color3.new(0.06, 0.06, 0.08)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 10)
panelPadding.PaddingBottom = UDim.new(0, 10)
panelPadding.PaddingLeft = UDim.new(0, 10)
panelPadding.PaddingRight = UDim.new(0, 10)
panelPadding.Parent = panel

local mainLayout = Instance.new("UIListLayout")
mainLayout.FillDirection = Enum.FillDirection.Vertical
mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainLayout.Padding = UDim.new(0, 8)
mainLayout.Parent = panel

-- Every top-level section gets an explicit, ascending LayoutOrder from this
-- counter -- and every ROW below assigns its own children explicit ascending
-- orders too (see makeRow/makeButton) -- Roblox's UIListLayout only
-- guarantees insertion order for EQUAL LayoutOrder when names also match
-- exactly, which default-named instances technically don't guarantee, so
-- nothing here relies on that.
local nextTopOrder = 0
local function topOrder(): number
	nextTopOrder += 1
	return nextTopOrder
end

local titleLabel = Instance.new("TextLabel")
titleLabel.LayoutOrder = topOrder()
titleLabel.BackgroundTransparency = 1
titleLabel.Size = UDim2.new(1, 0, 0, 26)
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
titleLabel.Text = string.format("DEV PANEL  (%s to close)", DevConfig.TOGGLE_KEYCODE.Name)
titleLabel.Parent = panel

local function makeSectionLabel(text: string)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = topOrder()
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(0.65, 0.65, 0.72)
	label.Text = text
	label.Parent = panel
end

-- A horizontal strip of buttons, added to the panel with the next top-level
-- order. Returns a function that appends one button to the row with the
-- next ascending order WITHIN that row.
local function makeRow(height: number): (UDim2, string, Color3, () -> ()) -> TextButton
	local row = Instance.new("Frame")
	row.LayoutOrder = topOrder()
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, height)
	row.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local nextRowOrder = 0
	return function(size: UDim2, text: string, color: Color3, callback: () -> ()): TextButton
		nextRowOrder += 1
		local button = Instance.new("TextButton")
		button.LayoutOrder = nextRowOrder
		button.Size = size
		button.BackgroundColor3 = color
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = text
		button.Parent = row

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		button.MouseButton1Click:Connect(callback)
		return button
	end
end

-- A single full-width button, added directly to the panel with the next
-- top-level order.
local function makeWideButton(text: string, color: Color3, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = topOrder()
	button.Size = UDim2.new(1, 0, 0, 32)
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	button.MouseButton1Click:Connect(callback)
	return button
end

-- ===== Money =====
makeSectionLabel("MONEY")

local addToQuickRow = makeRow(32)
for _, amount in DevConfig.MONEY_QUICK_AMOUNTS do
	addToQuickRow(UDim2.new(1 / 3, -4, 1, 0), "+" .. formatAmount(amount), Color3.new(0.15, 0.55, 0.25), function()
		fireAction("AddMoney", amount)
	end)
end

local amountBox = Instance.new("TextBox")
amountBox.LayoutOrder = topOrder()
amountBox.Size = UDim2.new(1, 0, 0, 32)
amountBox.BackgroundColor3 = Color3.new(0.14, 0.14, 0.17)
amountBox.Font = Enum.Font.Gotham
amountBox.TextScaled = true
amountBox.TextColor3 = Color3.new(1, 1, 1)
amountBox.PlaceholderText = "Custom amount (use - to subtract)"
amountBox.Text = ""
amountBox.ClearTextOnFocus = false
amountBox.Parent = panel

local amountBoxCorner = Instance.new("UICorner")
amountBoxCorner.CornerRadius = UDim.new(0, 6)
amountBoxCorner.Parent = amountBox

local function readAmount(): number?
	return tonumber(amountBox.Text)
end

local addToMoneyActionRow = makeRow(32)
addToMoneyActionRow(UDim2.new(1 / 3, -4, 1, 0), "Add", Color3.new(0.15, 0.45, 0.75), function()
	local amount = readAmount()
	if amount then
		fireAction("AddMoney", amount)
	end
end)
addToMoneyActionRow(UDim2.new(1 / 3, -4, 1, 0), "Set", Color3.new(0.15, 0.45, 0.75), function()
	local amount = readAmount()
	if amount then
		fireAction("SetMoney", amount)
	end
end)
addToMoneyActionRow(UDim2.new(1 / 3, -4, 1, 0), "Zero", Color3.new(0.55, 0.25, 0.15), function()
	fireAction("SetMoney", 0)
end)

-- ===== Slimes =====
makeSectionLabel("GIVE SLIME -- pick a tier, then a slime")

local selectedTier: number? = nil
local tierButtons: { [number]: TextButton } = {}

local slimeListFrame = Instance.new("ScrollingFrame")
slimeListFrame.LayoutOrder = topOrder()
slimeListFrame.Size = UDim2.new(1, 0, 0, 140)
slimeListFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.12)
slimeListFrame.BorderSizePixel = 0
slimeListFrame.ScrollBarThickness = 6
slimeListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
slimeListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
slimeListFrame.Parent = panel

local slimeListLayout = Instance.new("UIListLayout")
slimeListLayout.SortOrder = Enum.SortOrder.LayoutOrder
slimeListLayout.Padding = UDim.new(0, 2)
slimeListLayout.Parent = slimeListFrame

local function populateSlimeList(tier: number)
	-- Destroy only the previous tier's SLIME buttons -- NOT ClearAllChildren,
	-- which would also destroy slimeListLayout itself (a child of this same
	-- frame) and leave it unusable for every list after the first.
	for _, child in slimeListFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local pool = SlimeData.SLIMES_BY_TIER[tier]
	if not pool then
		return
	end
	for i, slime in pool do
		local button = Instance.new("TextButton")
		button.LayoutOrder = i
		button.Size = UDim2.new(1, 0, 0, 24)
		button.BackgroundColor3 = Color3.new(0.16, 0.16, 0.19)
		button.Font = Enum.Font.Gotham
		button.TextScaled = true
		button.TextColor3 = slime.color
		button.Text = slime.name
		button.Parent = slimeListFrame
		button.MouseButton1Click:Connect(function()
			fireAction("GiveSlime", slime.globalIndex)
		end)
	end
end

local function selectTier(tier: number)
	selectedTier = tier
	for t, button in tierButtons do
		button.BackgroundColor3 = if t == tier then SlimeConfig.SLIME_TIER_COLORS[t] else Color3.new(0.16, 0.16, 0.19)
	end
	populateSlimeList(tier)
end

-- Tier buttons are laid out BEFORE the slime list in the panel's own
-- top-level order, but slimeListFrame (created just above, so selectTier's
-- closure can reference it) already reserved its LayoutOrder ahead of
-- these two rows -- fix it up now that the rows exist.
local tierRow1 = makeRow(28)
local tierRow2 = makeRow(28)
slimeListFrame.LayoutOrder = topOrder()
for tier = 1, #SlimeConfig.SLIME_TIER_NAMES do
	local addToRow = if tier <= 4 then tierRow1 else tierRow2
	local shortName = string.sub(SlimeConfig.SLIME_TIER_NAMES[tier], 1, 4)
	local button = addToRow(UDim2.new(1 / 4, -4, 1, 0), shortName, Color3.new(0.16, 0.16, 0.19), function()
		selectTier(tier)
	end)
	tierButtons[tier] = button
end

makeWideButton("Give Random In Selected Tier", Color3.new(0.5, 0.35, 0.15), function()
	if selectedTier then
		fireAction("GiveRandomSlimeInTier", selectedTier)
	end
end)

-- ===== Swing tier -- NOT the same "tier" as the slime rarity buttons
-- above (SlimeConfig's Common..Divine, 8 of them). This is the shop's
-- swing progression tier (LaunchConfig.SWING_TIER_DISTANCE_SCALE, 11 of
-- them). Sets it directly via PlayerProfile.devSetSwingTier -- bypasses
-- price and the buy-in-order rule entirely, for testing a tier's feel
-- without grinding or faking money. =====
makeSectionLabel("SET SWING TIER (testing -- skips price/order)")

do
	local swingTierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
	local perRow = 4
	local tier = 1
	while tier <= swingTierCount do
		local addToRow = makeRow(28)
		for _ = 1, perRow do
			if tier > swingTierCount then
				break
			end
			local thisTier = tier
			addToRow(UDim2.new(1 / perRow, -4, 1, 0), tostring(thisTier), Color3.new(0.2, 0.35, 0.55), function()
				fireAction("SetSwingTier", thisTier)
			end)
			tier += 1
		end
	end
end

-- ===== Slime level -- sets the level of whichever slot is picked below
-- directly via PlayerProfile.devSetSlimeLevel, bypassing upgrade cost
-- entirely, for testing income/cost feel at any level without grinding or
-- faking money. Picking a slot is REQUIRED before "Set Level" does anything
-- -- there's no default slot, same "pick before you act" pattern as the
-- slime-tier picker above. =====
makeSectionLabel(string.format("SET SLIME LEVEL (testing -- pick a slot, 1-%d)", SlimeUpgradeConfig.MAX_LEVEL))

local selectedSlot: number? = nil
local slotButtons: { [number]: TextButton } = {}

local function selectSlot(slot: number)
	selectedSlot = slot
	for s, button in slotButtons do
		button.BackgroundColor3 = if s == slot then Color3.new(0.2, 0.55, 0.75) else Color3.new(0.16, 0.16, 0.19)
	end
end

do
	local perRow = 5
	local slot = 1
	while slot <= BaseConfig.SLOT_COUNT do
		local addToRow = makeRow(28)
		for _ = 1, perRow do
			if slot > BaseConfig.SLOT_COUNT then
				break
			end
			local thisSlot = slot
			local button = addToRow(UDim2.new(1 / perRow, -4, 1, 0), tostring(thisSlot), Color3.new(0.16, 0.16, 0.19), function()
				selectSlot(thisSlot)
			end)
			slotButtons[thisSlot] = button
			slot += 1
		end
	end
end

local levelBox = Instance.new("TextBox")
levelBox.LayoutOrder = topOrder()
levelBox.Size = UDim2.new(1, 0, 0, 32)
levelBox.BackgroundColor3 = Color3.new(0.14, 0.14, 0.17)
levelBox.Font = Enum.Font.Gotham
levelBox.TextScaled = true
levelBox.TextColor3 = Color3.new(1, 1, 1)
levelBox.PlaceholderText = string.format("Level (1-%d)", SlimeUpgradeConfig.MAX_LEVEL)
levelBox.Text = ""
levelBox.ClearTextOnFocus = false
levelBox.Parent = panel

local levelBoxCorner = Instance.new("UICorner")
levelBoxCorner.CornerRadius = UDim.new(0, 6)
levelBoxCorner.Parent = levelBox

makeWideButton("Set Level (selected slot)", Color3.new(0.2, 0.35, 0.55), function()
	local level = tonumber(levelBox.Text)
	if selectedSlot and level then
		fireAction("SetSlimeLevel", { slot = selectedSlot, level = level })
	end
end)

-- ===== Base / save =====
makeSectionLabel("BASE / SAVE")

makeWideButton("Clear Base (empty all 10 slots)", Color3.new(0.55, 0.4, 0.15), function()
	fireAction("ClearBase", nil)
end)

makeWideButton("WIPE SAVE (fresh-player reset)", Color3.new(0.6, 0.15, 0.15), function()
	fireAction("WipeSave", nil)
end)

-- ===== Toggle =====
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == DevConfig.TOGGLE_KEYCODE then
		screenGui.Enabled = not screenGui.Enabled
	end
end)
