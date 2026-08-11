--!strict
-- Swing shop UI -- buy the next swing tier with money. Pure client-side
-- rendering plus a single content-free "buy" signal to the server; every
-- number shown (current tier, money) comes from THIS player's own
-- Base_<UserId> folder's attributes (see PlayerProfile.luau), same as the
-- money HUD -- this script never decides affordability locally, the Buy
-- button just fires the request and shows whatever the server says happened
-- (see BuyTierResult below). See ShopServer.server.luau and
-- PlayerProfile.buyNextTier for the actual server-side validation.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local ShopConfig = require(ReplicatedStorage.Config.ShopConfig)
local MoneyFormat = require(ReplicatedStorage.Config.MoneyFormat)
-- The only module that creates a Sound. The two calls below sit beside status
-- text that was already being set; nothing about the purchase changes.
local SoundPlayer = require(ReplicatedStorage.SoundPlayer)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Named deterministically by UserId (see PlayerProfile.buildBaseFolder) --
-- same lookup BaseClient.client.luau uses for the money HUD. Bounded wait +
-- visible failure state -- see BaseClient.client.luau's own comment on this
-- exact pattern for why an unbounded wait here was never actually load-
-- failure-shaped (the folder is built synchronously before the load evens
-- starts) but still needed a ceiling for the rarer "server-side never built
-- it at all" case.
local BASE_FOLDER_WAIT_TIMEOUT_SECONDS = 10
local SHOP_REMOTES_WAIT_TIMEOUT_SECONDS = 10

-- Shared failure UI -- same "small red disabled button" pattern regardless
-- of WHICH dependency below is the one that went missing (the base folder,
-- the ShopRemotes folder, or a remote inside it -- see the written report:
-- a folder being bounded doesn't mean the children INSIDE it are, and that
-- gap was exactly what left LaunchClient hung one level deeper).
local function failShopHud(reason: string)
	warn(string.format(
		"[ShopClient] %s never appeared after %d seconds -- server-side setup likely failed. Swing shop will not render this session; the rest of the client is unaffected.",
		reason, SHOP_REMOTES_WAIT_TIMEOUT_SECONDS
	))
	local errorGui = Instance.new("ScreenGui")
	errorGui.Name = "ShopHud"
	errorGui.ResetOnSpawn = false
	errorGui.IgnoreGuiInset = true
	errorGui.Parent = playerGui

	local errorButton = Instance.new("TextButton")
	errorButton.Name = "ShopUnavailable"
	errorButton.AnchorPoint = Vector2.new(1, 0)
	errorButton.Position = UDim2.new(0.98, 0, 0.02, 0)
	errorButton.Size = UDim2.new(0, 220, 0, 44)
	errorButton.BackgroundColor3 = Color3.new(0.5, 0.15, 0.15)
	errorButton.AutoButtonColor = false
	errorButton.Active = false
	errorButton.Font = Enum.Font.GothamBold
	errorButton.TextScaled = true
	errorButton.TextColor3 = Color3.new(1, 1, 1)
	errorButton.Text = "SHOP UNAVAILABLE"
	errorButton.Parent = errorGui

	local errorButtonCorner = Instance.new("UICorner")
	errorButtonCorner.CornerRadius = UDim.new(0, 8)
	errorButtonCorner.Parent = errorButton
end

local baseFolder = Workspace:WaitForChild(string.format("Base_%d", player.UserId), BASE_FOLDER_WAIT_TIMEOUT_SECONDS)
if not baseFolder then
	failShopHud(string.format("Base_%d", player.UserId))
	return
end

local shopRemotesFolder = ReplicatedStorage:WaitForChild("ShopRemotes", SHOP_REMOTES_WAIT_TIMEOUT_SECONDS)
if not shopRemotesFolder then
	failShopHud("ReplicatedStorage.ShopRemotes")
	return
end
local buyTierRemoteMaybe = shopRemotesFolder:WaitForChild("BuyTier", SHOP_REMOTES_WAIT_TIMEOUT_SECONDS)
local buyTierResultRemoteMaybe = shopRemotesFolder:WaitForChild("BuyTierResult", SHOP_REMOTES_WAIT_TIMEOUT_SECONDS)
if not buyTierRemoteMaybe or not buyTierResultRemoteMaybe then
	failShopHud("one or more remotes inside ReplicatedStorage.ShopRemotes")
	return
end
local buyTierRemote = buyTierRemoteMaybe :: RemoteEvent
local buyTierResultRemote = buyTierResultRemoteMaybe :: RemoteEvent

local TIER_COUNT = #LaunchConfig.SWING_TIER_DISTANCE_SCALE

-- ===== UI shell =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Top-right, out of the way of the top-center distance readout, the
-- bottom-left money HUD, and the right-side swing bar.
local openButton = Instance.new("TextButton")
openButton.Name = "ShopOpenButton"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(0.98, 0, 0.02, 0)
openButton.Size = UDim2.new(0, 150, 0, 44)
openButton.BackgroundColor3 = Color3.new(0.15, 0.45, 0.75)
openButton.Font = Enum.Font.GothamBold
openButton.TextScaled = true
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.Text = "SWING SHOP"
openButton.Parent = screenGui

local openButtonCorner = Instance.new("UICorner")
openButtonCorner.CornerRadius = UDim.new(0, 8)
openButtonCorner.Parent = openButton

local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 420, 0, 520)
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
titleLabel.Position = UDim2.new(0.5, 0, 0.03, 0)
titleLabel.Size = UDim2.new(1, -70, 0, 34)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
titleLabel.Text = "SWING SHOP"
titleLabel.ZIndex = 10
titleLabel.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.Position = UDim2.new(0.5, 0, 0.1, 0)
statusLabel.Size = UDim2.new(1, -20, 0, 22)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextScaled = true
statusLabel.TextColor3 = Color3.new(0.75, 0.75, 0.8)
statusLabel.Text = ""
statusLabel.ZIndex = 10
statusLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(0.97, 0, 0.03, 0)
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

local listFrame = Instance.new("ScrollingFrame")
listFrame.AnchorPoint = Vector2.new(0.5, 0)
listFrame.Position = UDim2.new(0.5, 0, 0.17, 0)
listFrame.Size = UDim2.new(1, -24, 0.8, 0)
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ZIndex = 10
listFrame.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = listFrame

-- One row per tier -- OWNED tiers (green "OWNED"/"CURRENT"), exactly ONE
-- buyable tier at a time (current + 1, with a live Buy button showing its
-- price), and every tier beyond that LOCKED (greyed out, price shown but no
-- button) -- which is also what visually enforces "tiers must be bought in
-- order": there is never more than one active Buy button on screen.
local function buildRow(tier: number, currentTier: number): Frame
	local row = Instance.new("Frame")
	row.LayoutOrder = tier
	row.Size = UDim2.new(1, 0, 0, 46)
	row.BackgroundColor3 = Color3.new(0.12, 0.12, 0.15)
	row.ZIndex = 10
	row.Parent = listFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local scale = LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier]
	local nameLabel = Instance.new("TextLabel")
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0.04, 0, 0.5, 0)
	nameLabel.Size = UDim2.new(0.5, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = if tier <= currentTier then Color3.new(1, 1, 1) else Color3.new(0.6, 0.6, 0.65)
	nameLabel.Text = string.format("Tier %d  (%.1fx distance)", tier, scale)
	nameLabel.ZIndex = 10
	nameLabel.Parent = row

	if tier <= currentTier then
		local ownedLabel = Instance.new("TextLabel")
		ownedLabel.AnchorPoint = Vector2.new(1, 0.5)
		ownedLabel.Position = UDim2.new(0.96, 0, 0.5, 0)
		ownedLabel.Size = UDim2.new(0.4, 0, 0.7, 0)
		ownedLabel.BackgroundTransparency = 1
		ownedLabel.Font = Enum.Font.GothamBold
		ownedLabel.TextScaled = true
		ownedLabel.TextColor3 = Color3.new(0.3, 1, 0.4)
		ownedLabel.Text = if tier == currentTier then "CURRENT" else "OWNED"
		ownedLabel.ZIndex = 10
		ownedLabel.Parent = row
	elseif tier == currentTier + 1 then
		local price = ShopConfig.SWING_TIER_PRICES[tier]
		local buyButton = Instance.new("TextButton")
		buyButton.AnchorPoint = Vector2.new(1, 0.5)
		buyButton.Position = UDim2.new(0.96, 0, 0.5, 0)
		buyButton.Size = UDim2.new(0.42, 0, 0.75, 0)
		buyButton.BackgroundColor3 = Color3.new(0.15, 0.55, 0.25)
		buyButton.Font = Enum.Font.GothamBold
		buyButton.TextScaled = true
		buyButton.TextColor3 = Color3.new(1, 1, 1)
		buyButton.Text = "Buy " .. MoneyFormat.format(price)
		buyButton.ZIndex = 10
		buyButton.Parent = row

		local buyButtonCorner = Instance.new("UICorner")
		buyButtonCorner.CornerRadius = UDim.new(0, 6)
		buyButtonCorner.Parent = buyButton

		buyButton.MouseButton1Click:Connect(function()
			buyTierRemote:FireServer()
		end)
	else
		local price = ShopConfig.SWING_TIER_PRICES[tier]
		local lockedLabel = Instance.new("TextLabel")
		lockedLabel.AnchorPoint = Vector2.new(1, 0.5)
		lockedLabel.Position = UDim2.new(0.96, 0, 0.5, 0)
		lockedLabel.Size = UDim2.new(0.4, 0, 0.7, 0)
		lockedLabel.BackgroundTransparency = 1
		lockedLabel.Font = Enum.Font.Gotham
		lockedLabel.TextScaled = true
		lockedLabel.TextColor3 = Color3.new(0.5, 0.5, 0.55)
		lockedLabel.Text = MoneyFormat.format(price)
		lockedLabel.ZIndex = 10
		lockedLabel.Parent = row
	end

	return row
end

local function refreshList()
	local currentTier = baseFolder:GetAttribute("SwingTier")
	if typeof(currentTier) ~= "number" then
		currentTier = 1
	end
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for tier = 1, TIER_COUNT do
		buildRow(tier, currentTier)
	end
end

baseFolder:GetAttributeChangedSignal("SwingTier"):Connect(refreshList)
refreshList()

openButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		statusLabel.Text = ""
		refreshList()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

-- INVESTIGATED (see the written report): the swing structure itself is
-- deliberately NOT rebuilt the instant a purchase like this succeeds while
-- the buyer is already riding -- see LaunchServer.server.luau's onRelease,
-- which only refreshes the visual at setupCharacter (claiming the seat) and
-- at release, never mid-ride. That's correct, not a bug: rope length and
-- pivot height both scale with tier, so rebuilding out from under a rider
-- mid-swing would teleport the seat and could corrupt an in-progress
-- release's timing. The purchase itself (money spent, tier recorded) is
-- still immediate and authoritative regardless -- only the swing's LOOK
-- catches up later -- so the confirmation says so, instead of implying the
-- new swing is already under the player when it visibly isn't yet.
buyTierResultRemote.OnClientEvent:Connect(function(success: boolean, reason: string?)
	if success then
		statusLabel.Text = "Purchased! New swing shows next time you sit down or release."
		statusLabel.TextColor3 = Color3.new(0.3, 1, 0.4)
		-- Driven off the RESULT remote, not off the button press, so the chime
		-- can only ever follow a purchase the server actually granted -- the
		-- same reason the status text itself lives here.
		SoundPlayer.play2D("UI_PURCHASE_SUCCESS")
	else
		statusLabel.Text = reason or "Purchase failed"
		statusLabel.TextColor3 = Color3.new(1, 0.4, 0.3)
		SoundPlayer.play2D("UI_ACTION_DENIED")
	end
end)
