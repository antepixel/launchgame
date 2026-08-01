--!strict
-- Inventory UI -- place/remove/sell. Pure client-side rendering plus three
-- content-free-except-for-the-one-relevant-number signals to the server;
-- every number shown (which slots are filled, what's in inventory, money)
-- comes from THIS player's own Base_<UserId> folder's attributes (see
-- PlayerProfile.luau's syncClientState), same pattern as the money HUD and
-- the swing shop -- this script never decides ownership or slot
-- availability locally, each button just fires a request and shows
-- whatever the server says happened (see InventoryActionResult below). See
-- InventoryServer.server.luau and PlayerProfile's place/remove/sell
-- functions for the actual server-side validation.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local InventoryConfig = require(ReplicatedStorage.Config.InventoryConfig)
local MoneyFormat = require(ReplicatedStorage.Config.MoneyFormat)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local SlimeUpgrade = require(ReplicatedStorage.Config.SlimeUpgrade)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Bounded wait + visible failure state -- see BaseClient.client.luau's own
-- comment on this exact pattern. Extended to EVERY WaitForChild below, not
-- just the base folder -- see the written report: a folder being bounded
-- doesn't mean the children inside it are, and that one-level-deeper gap
-- was exactly what left LaunchClient hung despite its own folder-level fix.
local BASE_FOLDER_WAIT_TIMEOUT_SECONDS = 10
local INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS = 10

local function failInventoryHud(reason: string)
	warn(string.format(
		"[InventoryClient] %s never appeared after %d seconds -- server-side setup likely failed. Inventory will not render this session; the rest of the client is unaffected.",
		reason, INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS
	))
	local errorGui = Instance.new("ScreenGui")
	errorGui.Name = "InventoryHud"
	errorGui.ResetOnSpawn = false
	errorGui.IgnoreGuiInset = true
	errorGui.Parent = playerGui

	local errorButton = Instance.new("TextButton")
	errorButton.Name = "InventoryUnavailable"
	errorButton.AnchorPoint = Vector2.new(0.5, 1)
	errorButton.Position = UDim2.new(0.5, 0, 0.98, 0)
	errorButton.Size = UDim2.new(0, 260, 0, 44)
	errorButton.BackgroundColor3 = Color3.new(0.5, 0.15, 0.15)
	errorButton.AutoButtonColor = false
	errorButton.Active = false
	errorButton.Font = Enum.Font.GothamBold
	errorButton.TextScaled = true
	errorButton.TextColor3 = Color3.new(1, 1, 1)
	errorButton.Text = "INVENTORY UNAVAILABLE"
	errorButton.Parent = errorGui

	local errorButtonCorner = Instance.new("UICorner")
	errorButtonCorner.CornerRadius = UDim.new(0, 8)
	errorButtonCorner.Parent = errorButton
end

local baseFolder = Workspace:WaitForChild(string.format("Base_%d", player.UserId), BASE_FOLDER_WAIT_TIMEOUT_SECONDS)
if not baseFolder then
	failInventoryHud(string.format("Base_%d", player.UserId))
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild("InventoryRemotes", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
if not remotesFolder then
	failInventoryHud("ReplicatedStorage.InventoryRemotes")
	return
end
local placeSlimeRemoteMaybe = remotesFolder:WaitForChild("PlaceSlime", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
local removeSlimeRemoteMaybe = remotesFolder:WaitForChild("RemoveSlime", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
local sellSlimeRemoteMaybe = remotesFolder:WaitForChild("SellSlime", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
local inventoryActionResultRemoteMaybe = remotesFolder:WaitForChild("InventoryActionResult", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
if not (placeSlimeRemoteMaybe and removeSlimeRemoteMaybe and sellSlimeRemoteMaybe and inventoryActionResultRemoteMaybe) then
	failInventoryHud("one or more remotes inside ReplicatedStorage.InventoryRemotes")
	return
end
local placeSlimeRemote = placeSlimeRemoteMaybe :: RemoteEvent
local removeSlimeRemote = removeSlimeRemoteMaybe :: RemoteEvent
local sellSlimeRemote = sellSlimeRemoteMaybe :: RemoteEvent
local inventoryActionResultRemote = inventoryActionResultRemoteMaybe :: RemoteEvent

-- Separate remotes folder (see UpgradeServer.server.luau) -- upgrading is its
-- own system, not a fourth inventory action, same reasoning as the swing shop
-- getting its own ShopRemotes folder instead of living under this one.
local upgradeRemotesFolder = ReplicatedStorage:WaitForChild("UpgradeRemotes", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
if not upgradeRemotesFolder then
	failInventoryHud("ReplicatedStorage.UpgradeRemotes")
	return
end
local upgradeSlimeRemoteMaybe = upgradeRemotesFolder:WaitForChild("UpgradeSlime", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
local upgradeResultRemoteMaybe = upgradeRemotesFolder:WaitForChild("UpgradeResult", INVENTORY_REMOTES_WAIT_TIMEOUT_SECONDS)
if not (upgradeSlimeRemoteMaybe and upgradeResultRemoteMaybe) then
	failInventoryHud("one or more remotes inside ReplicatedStorage.UpgradeRemotes")
	return
end
local upgradeSlimeRemote = upgradeSlimeRemoteMaybe :: RemoteEvent
local upgradeResultRemote = upgradeResultRemoteMaybe :: RemoteEvent

local function incomeText(perSecond: number): string
	return MoneyFormat.format(perSecond) .. "/s"
end

local function sellValue(perSecond: number, quantity: number): number
	return perSecond * InventoryConfig.SELL_VALUE_INCOME_MULTIPLIER * quantity
end

-- The three buy buttons' nominal level counts -- capped further per-button
-- below (near MAX_LEVEL, an actual purchase buys fewer) but this is what
-- gets sent to the server; PlayerProfile.upgradeSlime does its own capping
-- regardless of what's sent, so this is purely "which button is this."
local UPGRADE_BUTTON_COUNTS = { 1, 10, 100 }

-- ===== UI shell =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Directly below ShopClient's "SWING SHOP" button (same corner, stacked).
local openButton = Instance.new("TextButton")
openButton.Name = "InventoryOpenButton"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(0.98, 0, 0.02, 54)
openButton.Size = UDim2.new(0, 150, 0, 44)
openButton.BackgroundColor3 = Color3.new(0.45, 0.25, 0.65)
openButton.Font = Enum.Font.GothamBold
openButton.TextScaled = true
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.Text = "INVENTORY"
openButton.Parent = screenGui

local openButtonCorner = Instance.new("UICorner")
openButtonCorner.CornerRadius = UDim.new(0, 8)
openButtonCorner.Parent = openButton

local panel = Instance.new("Frame")
panel.Name = "InventoryPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 560, 0, 680)
panel.BackgroundColor3 = Color3.new(0.06, 0.06, 0.09)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 10
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.AnchorPoint = Vector2.new(0.5, 0)
titleLabel.Position = UDim2.new(0.5, 0, 0.02, 0)
titleLabel.Size = UDim2.new(1, -70, 0, 30)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.new(0.75, 0.55, 1)
titleLabel.Text = "INVENTORY"
titleLabel.ZIndex = 10
titleLabel.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.Position = UDim2.new(0.5, 0, 0.075, 0)
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextScaled = true
statusLabel.TextColor3 = Color3.new(0.75, 0.75, 0.8)
statusLabel.Text = ""
statusLabel.ZIndex = 10
statusLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(0.97, 0, 0.02, 0)
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.BackgroundColor3 = Color3.new(0.5, 0.15, 0.15)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.ZIndex = 10
closeButton.Parent = panel

local closeButtonCorner = Instance.new("UICorner")
closeButtonCorner.CornerRadius = UDim.new(0, 6)
closeButtonCorner.Parent = closeButton

-- ===== Section 1: YOUR BASE -- one row per SLOT (not per slime type), in
-- slot-number order, matching the base's own physical 1-10 layout -- this
-- is deliberately NOT income-sorted like the inventory list below (see the
-- written report for why: a slot has a fixed physical position, an
-- inventory stack doesn't).
local baseSectionLabel = Instance.new("TextLabel")
baseSectionLabel.AnchorPoint = Vector2.new(0, 0)
baseSectionLabel.Position = UDim2.new(0.04, 0, 0.1, 0)
baseSectionLabel.Size = UDim2.new(0.92, 0, 0, 20)
baseSectionLabel.BackgroundTransparency = 1
baseSectionLabel.Font = Enum.Font.GothamBold
baseSectionLabel.TextScaled = true
baseSectionLabel.TextXAlignment = Enum.TextXAlignment.Left
baseSectionLabel.TextColor3 = Color3.new(0.65, 0.65, 0.72)
baseSectionLabel.Text = "YOUR BASE (10 slots)"
baseSectionLabel.ZIndex = 10
baseSectionLabel.Parent = panel

local baseListFrame = Instance.new("ScrollingFrame")
baseListFrame.AnchorPoint = Vector2.new(0.5, 0)
baseListFrame.Position = UDim2.new(0.5, 0, 0.14, 0)
baseListFrame.Size = UDim2.new(1, -24, 0.46, 0)
baseListFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.12)
baseListFrame.BorderSizePixel = 0
baseListFrame.ScrollBarThickness = 6
baseListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
baseListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
baseListFrame.ZIndex = 10
baseListFrame.Parent = panel

local baseListLayout = Instance.new("UIListLayout")
baseListLayout.SortOrder = Enum.SortOrder.LayoutOrder
baseListLayout.Padding = UDim.new(0, 4)
baseListLayout.Parent = baseListFrame

-- ===== Section 2: INVENTORY -- one row per HELD SLIME TYPE (stacked, not
-- one row per individual pull -- see the written report for why: a player
-- will eventually hold hundreds of copies across only 65 distinct slimes).
-- Sorted by income per second, DESCENDING, by default -- the one sort this
-- pass implements; no other sort options were added.
local invSectionLabel = Instance.new("TextLabel")
invSectionLabel.AnchorPoint = Vector2.new(0, 0)
invSectionLabel.Position = UDim2.new(0.04, 0, 0.62, 0)
invSectionLabel.Size = UDim2.new(0.92, 0, 0, 20)
invSectionLabel.BackgroundTransparency = 1
invSectionLabel.Font = Enum.Font.GothamBold
invSectionLabel.TextScaled = true
invSectionLabel.TextXAlignment = Enum.TextXAlignment.Left
invSectionLabel.TextColor3 = Color3.new(0.65, 0.65, 0.72)
invSectionLabel.Text = "INVENTORY (sorted by income/s, highest first)"
invSectionLabel.ZIndex = 10
invSectionLabel.Parent = panel

local invListFrame = Instance.new("ScrollingFrame")
invListFrame.AnchorPoint = Vector2.new(0.5, 0)
invListFrame.Position = UDim2.new(0.5, 0, 0.66, 0)
invListFrame.Size = UDim2.new(1, -24, 0.3, 0)
invListFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.12)
invListFrame.BorderSizePixel = 0
invListFrame.ScrollBarThickness = 6
invListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
invListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
invListFrame.ZIndex = 10
invListFrame.Parent = panel

local invListLayout = Instance.new("UIListLayout")
invListLayout.SortOrder = Enum.SortOrder.LayoutOrder
invListLayout.Padding = UDim.new(0, 4)
invListLayout.Parent = invListFrame

-- `enabled` (default true) additionally gates input via Active -- setting it
-- false is what makes an unaffordable/maxed upgrade button actually
-- unclickable, not just dimmed-looking, since a modified client could
-- otherwise still fire the click event on a "greyed out" button; the SERVER
-- re-validates everything regardless (see PlayerProfile.upgradeSlime), so
-- this is purely so a legitimate client can't even try.
local function makeSmallButton(parent: Instance, size: UDim2, position: UDim2, text: string, color: Color3, callback: () -> (), enabled: boolean?): TextButton
	local isEnabled = enabled ~= false
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = if isEnabled then color else Color3.new(0.22, 0.22, 0.25)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = if isEnabled then Color3.new(1, 1, 1) else Color3.new(0.55, 0.55, 0.58)
	button.Text = text
	button.Active = isEnabled
	button.ZIndex = 10
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button

	button.MouseButton1Click:Connect(callback)
	return button
end

-- One of the base's 10 slots -- level, current income, and the three
-- upgrade buttons (+1/+10/+100), each showing the TOTAL cost of however many
-- levels it will actually buy (capped at MAX_LEVEL -- see SlimeUpgrade.
-- totalUpgradeCost) and greyed out if that cost exceeds `money` or the slime
-- is already maxed. `money` is passed in (read once per refresh(), not per
-- row) so every row's affordability check uses the exact same snapshot.
local function buildBaseRow(slotNumber: number, globalIndex: number?, level: number, money: number)
	local row = Instance.new("Frame")
	row.LayoutOrder = slotNumber
	row.Size = UDim2.new(1, 0, 0, 66)
	row.BackgroundColor3 = Color3.new(0.12, 0.12, 0.15)
	row.ZIndex = 10
	row.Parent = baseListFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local slime = if globalIndex then SlimeData.SLIMES[globalIndex] else nil

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.new(0.03, 0, 0.04, 0)
	label.Size = UDim2.new(0.94, 0, 0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 10
	label.Parent = row

	if slime then
		label.TextColor3 = slime.color
		local currentIncome = SlimeUpgrade.incomeForLevel(slime.incomePerSecond, level)
		label.Text = string.format("Slot %d: %s -- Lv %d -- %s", slotNumber, slime.name, level, incomeText(currentIncome))

		makeSmallButton(row, UDim2.new(0.16, 0, 0.42, 0), UDim2.new(0.97, 0, 0.8, 0), "Remove", Color3.new(0.55, 0.4, 0.15), function()
			removeSlimeRemote:FireServer(slotNumber)
		end)

		-- Three buy buttons, right-to-left: +100, +10, +1 -- same nominal
		-- count/cost/enabled logic for all three, just a different requested
		-- count and X position.
		local buttonPositions = { 0.79, 0.55, 0.31 }
		for i, requestedCount in UPGRADE_BUTTON_COUNTS do
			local cost, actualCount = SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, level, requestedCount)
			local atMax = actualCount <= 0
			local affordable = not atMax and money >= cost
			local text = if atMax then "MAX" else string.format("+%d\n(%s)", actualCount, MoneyFormat.format(cost))
			local color = if atMax then Color3.new(0.35, 0.35, 0.38) else Color3.new(0.15, 0.55, 0.25)
			makeSmallButton(row, UDim2.new(0.22, 0, 0.42, 0), UDim2.new(buttonPositions[i], 0, 0.8, 0), text, color, function()
				upgradeSlimeRemote:FireServer(slotNumber, requestedCount)
			end, affordable)
		end
	else
		label.TextColor3 = Color3.new(0.5, 0.5, 0.55)
		label.Text = string.format("Slot %d: Empty", slotNumber)
	end
end

local function buildInventoryRow(order: number, globalIndex: number, count: number)
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return
	end

	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = Color3.new(0.12, 0.12, 0.15)
	row.ZIndex = 10
	row.Parent = invListFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0.03, 0, 0.5, 0)
	label.Size = UDim2.new(0.4, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = slime.color
	label.Text = string.format("%s x%d -- %s", slime.name, count, incomeText(slime.incomePerSecond))
	label.ZIndex = 10
	label.Parent = row

	makeSmallButton(row, UDim2.new(0.16, 0, 0.75, 0), UDim2.new(0.98, 0, 0.5, 0), "Place", Color3.new(0.15, 0.55, 0.25), function()
		placeSlimeRemote:FireServer(globalIndex)
	end)

	makeSmallButton(row, UDim2.new(0.19, 0, 0.75, 0), UDim2.new(0.81, 0, 0.5, 0), string.format("Sell 1\n(%s)", MoneyFormat.format(sellValue(slime.incomePerSecond, 1))), Color3.new(0.55, 0.15, 0.15), function()
		sellSlimeRemote:FireServer(globalIndex, 1)
	end)

	makeSmallButton(row, UDim2.new(0.22, 0, 0.75, 0), UDim2.new(0.61, 0, 0.5, 0), string.format("Sell All\n(%s)", MoneyFormat.format(sellValue(slime.incomePerSecond, count))), Color3.new(0.4, 0.1, 0.1), function()
		sellSlimeRemote:FireServer(globalIndex, count)
	end)
end

local function refresh()
	for _, child in baseListFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, child in invListFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local money = baseFolder:GetAttribute("Money")
	if typeof(money) ~= "number" then
		money = 0
	end

	local slotsJson = baseFolder:GetAttribute("Slots")
	local slotsByNumber: { [number]: number } = {}
	local levelsByNumber: { [number]: number } = {}
	if typeof(slotsJson) == "string" and slotsJson ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, slotsJson)
		if ok and typeof(decoded) == "table" then
			for _, entry in decoded do
				if typeof(entry) == "table" and typeof(entry.slot) == "number" and typeof(entry.globalIndex) == "number" then
					slotsByNumber[entry.slot] = entry.globalIndex
					levelsByNumber[entry.slot] = if typeof(entry.level) == "number" then entry.level else 1
				end
			end
		end
	end
	for slotNumber = 1, 10 do
		buildBaseRow(slotNumber, slotsByNumber[slotNumber], levelsByNumber[slotNumber] or 1, money)
	end

	local inventoryJson = baseFolder:GetAttribute("Inventory")
	local stacks: { { globalIndex: number, count: number } } = {}
	if typeof(inventoryJson) == "string" and inventoryJson ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, inventoryJson)
		if ok and typeof(decoded) == "table" then
			for _, entry in decoded do
				if typeof(entry) == "table" and typeof(entry.globalIndex) == "number" and typeof(entry.count) == "number" then
					table.insert(stacks, { globalIndex = entry.globalIndex, count = entry.count })
				end
			end
		end
	end

	-- DEFAULT SORT: income per second, descending. The only sort this pass
	-- implements -- see the written report.
	table.sort(stacks, function(a, b)
		local slimeA = SlimeData.SLIMES[a.globalIndex]
		local slimeB = SlimeData.SLIMES[b.globalIndex]
		local incomeA = if slimeA then slimeA.incomePerSecond else 0
		local incomeB = if slimeB then slimeB.incomePerSecond else 0
		return incomeA > incomeB
	end)

	for i, stack in stacks do
		buildInventoryRow(i, stack.globalIndex, stack.count)
	end
end

-- Money changes every income tick (once a second, see PlayerProfile's income
-- loop) whether or not this panel is even open -- rebuilding the whole list
-- on every tick regardless would be pure waste while it's closed (affordability
-- is only ever shown while the panel is visible; the open button already
-- calls refresh() itself on open). Slots/Inventory changes are rare enough
-- (only ever on an actual place/remove/sell/upgrade) that they're left
-- rebuilding unconditionally.
local function refreshIfVisible()
	if panel.Visible then
		refresh()
	end
end

baseFolder:GetAttributeChangedSignal("Slots"):Connect(refresh)
baseFolder:GetAttributeChangedSignal("Inventory"):Connect(refresh)
baseFolder:GetAttributeChangedSignal("Money"):Connect(refreshIfVisible)
refresh()

openButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		statusLabel.Text = ""
		refresh()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

inventoryActionResultRemote.OnClientEvent:Connect(function(success: boolean, reason: string?)
	if success then
		statusLabel.Text = "Done!"
		statusLabel.TextColor3 = Color3.new(0.3, 1, 0.4)
	else
		statusLabel.Text = reason or "Action failed"
		statusLabel.TextColor3 = Color3.new(1, 0.4, 0.3)
	end
end)

upgradeResultRemote.OnClientEvent:Connect(function(success: boolean, reason: string?, boughtCount: number?)
	if success then
		statusLabel.Text = string.format("Upgraded +%d level%s!", boughtCount or 0, if boughtCount == 1 then "" else "s")
		statusLabel.TextColor3 = Color3.new(0.3, 1, 0.4)
	else
		statusLabel.Text = reason or "Upgrade failed"
		statusLabel.TextColor3 = Color3.new(1, 0.4, 0.3)
	end
end)
