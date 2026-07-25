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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local baseFolder = Workspace:WaitForChild(string.format("Base_%d", player.UserId))

local remotesFolder = ReplicatedStorage:WaitForChild("InventoryRemotes")
local placeSlimeRemote = remotesFolder:WaitForChild("PlaceSlime") :: RemoteEvent
local removeSlimeRemote = remotesFolder:WaitForChild("RemoveSlime") :: RemoteEvent
local sellSlimeRemote = remotesFolder:WaitForChild("SellSlime") :: RemoteEvent
local inventoryActionResultRemote = remotesFolder:WaitForChild("InventoryActionResult") :: RemoteEvent

local function incomeText(perSecond: number): string
	return MoneyFormat.format(perSecond) .. "/s"
end

local function sellValue(perSecond: number, quantity: number): number
	return perSecond * InventoryConfig.SELL_VALUE_INCOME_MULTIPLIER * quantity
end

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
panel.Size = UDim2.new(0, 520, 0, 560)
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
baseSectionLabel.Position = UDim2.new(0.04, 0, 0.13, 0)
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
baseListFrame.Position = UDim2.new(0.5, 0, 0.17, 0)
baseListFrame.Size = UDim2.new(1, -24, 0.33, 0)
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
invSectionLabel.Position = UDim2.new(0.04, 0, 0.52, 0)
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
invListFrame.Position = UDim2.new(0.5, 0, 0.56, 0)
invListFrame.Size = UDim2.new(1, -24, 0.42, 0)
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

local function makeSmallButton(parent: Instance, size: UDim2, position: UDim2, text: string, color: Color3, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.ZIndex = 10
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button

	button.MouseButton1Click:Connect(callback)
	return button
end

local function buildBaseRow(slotNumber: number, globalIndex: number?)
	local row = Instance.new("Frame")
	row.LayoutOrder = slotNumber
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = Color3.new(0.12, 0.12, 0.15)
	row.ZIndex = 10
	row.Parent = baseListFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local slime = if globalIndex then SlimeData.SLIMES[globalIndex] else nil

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0.03, 0, 0.5, 0)
	label.Size = UDim2.new(0.65, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 10
	label.Parent = row

	if slime then
		label.TextColor3 = slime.color
		label.Text = string.format("Slot %d: %s -- %s", slotNumber, slime.name, incomeText(slime.incomePerSecond))

		makeSmallButton(row, UDim2.new(0.32, 0, 0.75, 0), UDim2.new(0.97, 0, 0.5, 0), "Remove", Color3.new(0.55, 0.4, 0.15), function()
			removeSlimeRemote:FireServer(slotNumber)
		end)
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

	local slotsJson = baseFolder:GetAttribute("Slots")
	local slotsByNumber: { [number]: number } = {}
	if typeof(slotsJson) == "string" and slotsJson ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, slotsJson)
		if ok and typeof(decoded) == "table" then
			for _, entry in decoded do
				if typeof(entry) == "table" and typeof(entry.slot) == "number" and typeof(entry.globalIndex) == "number" then
					slotsByNumber[entry.slot] = entry.globalIndex
				end
			end
		end
	end
	for slotNumber = 1, 10 do
		buildBaseRow(slotNumber, slotsByNumber[slotNumber])
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

baseFolder:GetAttributeChangedSignal("Slots"):Connect(refresh)
baseFolder:GetAttributeChangedSignal("Inventory"):Connect(refresh)
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
