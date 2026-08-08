--!strict
-- THE FLIGHT HUD: every screen-space element LaunchClient owns, the widgets
-- themselves and the handful of functions that write to them.
--
-- SPLIT OUT OF LaunchClient.client.luau (see REPORT.md -- that file hit Luau's
-- hard 200-locals-per-function-scope limit). Lives in
-- ReplicatedStorage.LaunchClient -- see LaunchClient's own require comment for
-- why, and note that being REACHABLE from the server is not the same as being
-- run there: this module builds nothing until create() is called, and only a
-- LocalScript ever calls it. Every widget's construction and
-- every write to it moved VERBATIM; the only structural change is that the
-- construction now sits inside create() instead of at file scope, so that it
-- still happens at exactly the same point in LaunchClient's own startup
-- sequence -- AFTER the remotes have resolved. That ordering is load-bearing:
-- if the remotes never appear, LaunchClient shows the failure label and
-- returns before ever calling create(), and no flight HUD is built at all.
-- Building this at require time instead would put a live HUD on screen during
-- the ten-second remote timeout on a broken server.
--
-- WHAT THIS MODULE DOES NOT DECIDE. It owns no state of its own -- not
-- `grounded`, not `mounted`, not `rewardSequenceActive`, not the flight
-- readouts. Every function here takes what it needs as an argument and writes
-- pixels; the gates stay in LaunchClient, where the state they read lives.
-- refreshFlightHud is the clearest case: the condition is unchanged and still
-- written out in full here, but both of its inputs arrive as parameters.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local LuckCurve = require(ReplicatedStorage.Config.LuckCurve)
local LaunchFormulas = require(ReplicatedStorage.LaunchClient.LaunchFormulas)

local LaunchHud = {}

-- Styling for each OUTCOME_BANDS entry, same order/length (5) -- a perfect
-- reads as a celebration (biggest, boldest, gold), a miss reads as flat (small,
-- muted, regular weight, no bold) per the written report: this game is
-- launched hundreds of times, so the low end has to stay gentle, not harsh.
export type OutcomeStyle = { color: Color3, size: UDim2, font: Enum.Font, strokeTransparency: number }

local OUTCOME_STYLES: { OutcomeStyle } = {
	{ color = Color3.new(1, 0.85, 0.25), size = UDim2.new(0, 320, 0, 46), font = Enum.Font.GothamBlack, strokeTransparency = 0.2 }, -- Perfect!
	{ color = Color3.new(0.4, 1, 0.5), size = UDim2.new(0, 300, 0, 38), font = Enum.Font.GothamBold, strokeTransparency = 0.35 }, -- Great!
	{ color = Color3.new(0.85, 0.85, 1), size = UDim2.new(0, 280, 0, 32), font = Enum.Font.GothamBold, strokeTransparency = 0.5 }, -- Good
	{ color = Color3.new(0.75, 0.75, 0.8), size = UDim2.new(0, 260, 0, 28), font = Enum.Font.GothamBold, strokeTransparency = 0.5 }, -- Okay
	{ color = Color3.new(0.55, 0.55, 0.6), size = UDim2.new(0, 240, 0, 24), font = Enum.Font.Gotham, strokeTransparency = 0.6 }, -- Lock in..
}

-- The last-band ring's own style (LaunchConfig.LAST_BAND_OUTCOME_TEXT), kept
-- out of the list above because the ring is not an OUTCOME_BANDS entry and has
-- no index to look up by -- see landsOnLastBand below. GothamBlack at nearly
-- Perfect's size, because this IS the biggest thing that can happen to a
-- player who did not snap; SILVER, not gold, and that is the load-bearing
-- part -- read at a glance, in motion, the only thing separating this from a
-- perfect launch is the colour, so it must not be the celebration colour.
local LAST_BAND_OUTCOME_STYLE: OutcomeStyle = {
	color = Color3.new(0.82, 0.87, 0.96),
	size = UDim2.new(0, 310, 0, 42),
	font = Enum.Font.GothamBlack,
	strokeTransparency = 0.25,
}

-- Builds every widget and returns the handful of operations LaunchClient
-- performs on them. Called ONCE, from LaunchClient, at the exact point in its
-- startup where this construction used to sit inline.
function LaunchHud.create(playerGui: Instance)
	-- ===== UI =====
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LaunchHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	-- Groups every element that only means something while THIS client is
	-- riding or flying -- the distance readout, the multiplier/bar, the outcome
	-- text, and the release button -- behind ONE Visible flip instead of six
	-- independent ones (see refreshFlightHud below, the single place this
	-- toggles).
	--
	-- BUG FIX (see the written report -- flight HUD showing during the box):
	-- "riding, flying, OR IN THE BOX SEQUENCE" is what this used to say, and what
	-- setGrounded's `flightHudFrame.Visible = not grounded` actually implemented.
	-- That third case is wrong now. Once the box became a real object in the
	-- world carrying its own luck readout, everything in this frame during the
	-- box window is either stale or duplicated: the distance countup has stopped,
	-- the outcome text is about a release that already happened, the RELEASE
	-- button controls nothing (doRelease refuses -- not mounted), and the luck
	-- line reads the SAME number the box's own billboard is showing a few
	-- hundred pixels away. See refreshFlightHud for where the condition lives now
	-- and why it is not simply `not grounded`.
	--
	-- A plain full-screen, invisible-background Frame, not the ScreenGui itself:
	-- returnHintLabel (and the money/tier
	-- labels BaseClient.client.luau owns) must stay independently controllable,
	-- so the whole LaunchHud ScreenGui can never be the thing toggled here.
	-- Sized/positioned to exactly cover the ScreenGui so every child's existing
	-- UDim2 (all written relative to the full screen) renders identically
	-- whether parented here or directly to screenGui -- reparenting below is
	-- purely an organisational change, not a layout one.
	--
	-- BUG FIX (see the written report -- dismount button not responding): this
	-- is a pure grouping container, never meant to be interacted with directly
	-- -- only its children (the release button) are. Active is left at its
	-- default here for every OTHER label, but a Frame this large (the whole
	-- screen) sitting as a SIBLING of dismountButton, both visible at the same
	-- time ("riding"), made their relative click-hit priority depend on
	-- sibling order Roblox does not actually guarantee -- which is exactly the
	-- kind of thing that can silently swallow a click with no error and no
	-- visible effect, matching "pressing Dismount does nothing" exactly.
	-- Active = false removes the ambiguity outright: this frame can now never
	-- capture a click meant for anything else, regardless of sibling order,
	-- while its own children (releaseButton) keep receiving their own clicks
	-- completely independently of their parent's Active value.
	local flightHudFrame = Instance.new("Frame")
	flightHudFrame.Name = "FlightHud"
	flightHudFrame.Active = false
	flightHudFrame.BackgroundTransparency = 1
	flightHudFrame.Size = UDim2.fromScale(1, 1)
	flightHudFrame.Visible = false
	flightHudFrame.Parent = screenGui

	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Name = "DistanceReadout"
	distanceLabel.AnchorPoint = Vector2.new(0.5, 0)
	distanceLabel.Position = UDim2.new(0.5, 0, 0.05, 0)
	distanceLabel.Size = UDim2.new(0, 400, 0, 60)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Font = Enum.Font.GothamBold
	distanceLabel.TextScaled = true
	distanceLabel.TextColor3 = Color3.new(1, 1, 1)
	distanceLabel.TextStrokeTransparency = 0.4
	distanceLabel.Text = "Time your release!"
	distanceLabel.Parent = flightHudFrame

	-- The bar track: a fixed vertical strip. The moving indicator's Y POSITION inside
	-- it (not its size) is the swing position -- "the bar IS the swing position."
	-- LEFT side of the screen, vertically centred (mirrored from its old right-
	-- side spot -- see the written report): the DISMOUNT button now takes the
	-- middle of the right-hand side instead (see dismountButton below).
	local barTrack = Instance.new("Frame")
	barTrack.Name = "SwingBarTrack"
	barTrack.AnchorPoint = Vector2.new(0, 0.5)
	barTrack.Position = UDim2.new(0.03, 0, 0.5, 0)
	barTrack.Size = UDim2.new(0, 36, 0, 360)
	barTrack.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
	barTrack.BackgroundTransparency = 0.25
	barTrack.BorderSizePixel = 0
	barTrack.Parent = flightHudFrame

	local barTrackCorner = Instance.new("UICorner")
	barTrackCorner.CornerRadius = UDim.new(0, 8)
	barTrackCorner.Parent = barTrack

	-- A thin rim so the track reads as a distinct object at a glance instead of a
	-- flat rectangle, even before the sweet-spot band draws the eye. Subtle by
	-- design -- this is polish, not a second signal competing with the indicator.
	local barTrackStroke = Instance.new("UIStroke")
	barTrackStroke.Name = "TrackRim"
	barTrackStroke.Color = Color3.new(1, 1, 1)
	barTrackStroke.Transparency = 0.85
	barTrackStroke.Thickness = 1.5
	barTrackStroke.Parent = barTrack

	-- Sweet-spot band: a static highlight at the TOP of the track (fill = 1 is the
	-- forward extreme of the arc -- see LaunchConfig.SWEET_SPOT_PHASE). Its height is
	-- computed from SWEET_SPOT_WIDTH using the same sine relationship as the server's
	-- circularPhaseDistance check, so it visually represents the actual accepted
	-- window, not an approximation of it. The vertical gradient across it mirrors
	-- the actual grading curve (see LaunchConfig.SWEET_SPOT_EDGE_MULTIPLIER/
	-- SWEET_SPOT_MULTIPLIER) instead of just being decoration: brightest at the top
	-- of the band (dead centre, the 2.0x peak) fading to dimmer at the bottom (the
	-- window's edges, 1.8x) -- so the band ITSELF shows where the grading is
	-- heading, not just where the window is.
	do
		local halfWidth = LaunchConfig.SWEET_SPOT_WIDTH / 2
		-- fillFraction is symmetric around its peak (phase 0.25), so the fill value at
		-- EITHER edge of the sweet-spot window is the same: cos(2*pi*halfWidth) mapped
		-- into [0,1] the same way fillFraction does.
		local edgeFill = (math.cos(2 * math.pi * halfWidth) + 1) / 2
		local bandHeightFraction = 1 - edgeFill

		-- fill = 1 is the TOP of the track (Y scale 0, per barIndicator's own
		-- convention below), so the band anchors to the top edge and extends downward.
		local sweetBand = Instance.new("Frame")
		sweetBand.Name = "SweetSpotBand"
		sweetBand.AnchorPoint = Vector2.new(0.5, 0)
		sweetBand.Position = UDim2.new(0.5, 0, 0, 0)
		sweetBand.Size = UDim2.new(1, 0, bandHeightFraction, 0)
		sweetBand.BackgroundColor3 = Color3.new(0.2, 1, 0.35)
		sweetBand.BackgroundTransparency = 0.3
		sweetBand.BorderSizePixel = 0
		sweetBand.ZIndex = 2
		sweetBand.Parent = barTrack

		local sweetBandCorner = Instance.new("UICorner")
		sweetBandCorner.CornerRadius = UDim.new(0, 8)
		sweetBandCorner.Parent = sweetBand

		-- Rotation 90 turns the gradient vertical, offset 0 at the top of the frame.
		local sweetBandGradient = Instance.new("UIGradient")
		sweetBandGradient.Rotation = 90
		sweetBandGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(0.6, 1, 0.65)),
			ColorSequenceKeypoint.new(1, Color3.new(0.1, 0.55, 0.25)),
		})
		sweetBandGradient.Parent = sweetBand

		-- A crisp edge on the band is what sells the 1.5->1.8 jump visually: the
		-- moment the indicator crosses this line, it's a hard boundary, not a fade.
		local sweetBandStroke = Instance.new("UIStroke")
		sweetBandStroke.Color = Color3.new(0.6, 1, 0.65)
		sweetBandStroke.Transparency = 0.4
		sweetBandStroke.Thickness = 1.5
		sweetBandStroke.Parent = sweetBand
	end

	local barIndicator = Instance.new("Frame")
	barIndicator.Name = "SwingBarIndicator"
	barIndicator.AnchorPoint = Vector2.new(0.5, 0.5)
	barIndicator.Position = UDim2.new(0.5, 0, 1, 0)
	barIndicator.Size = UDim2.new(1, 8, 0, 10)
	barIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
	barIndicator.BorderSizePixel = 0
	barIndicator.ZIndex = 3
	barIndicator.Parent = barTrack

	local barIndicatorCorner = Instance.new("UICorner")
	barIndicatorCorner.CornerRadius = UDim.new(0, 5)
	barIndicatorCorner.Parent = barIndicator

	-- Invisible outside the sweet spot, a bright gold glow the instant the indicator
	-- is inside it (set every frame below, alongside its size/color) -- this is the
	-- "at a glance, without reading" signal item 6 asks for: a distinct pop that
	-- doesn't depend on noticing a number change.
	local barIndicatorGlow = Instance.new("UIStroke")
	barIndicatorGlow.Name = "HitGlow"
	barIndicatorGlow.Thickness = 3
	barIndicatorGlow.Color = Color3.new(1, 0.85, 0.25)
	barIndicatorGlow.Transparency = 1
	barIndicatorGlow.Parent = barIndicator

	-- Live multiplier readout, right above the bar. Updated every frame alongside
	-- the indicator (same RenderStepped loop below) -- normal styling for the
	-- gradual-ramp range, a distinct brighter look when in the sweet spot. Reads as
	-- a smoothly climbing/falling number now (grading removed the flat "2x!" snap
	-- text) -- the hit/miss signal lives in the bar, not in this label freezing.
	-- Mirrored to sit right above the bar's own NEW left-side spot (see
	-- barTrack above).
	local multiplierLabel = Instance.new("TextLabel")
	multiplierLabel.Name = "MultiplierReadout"
	multiplierLabel.AnchorPoint = Vector2.new(0, 1)
	multiplierLabel.Position = UDim2.new(0.03, 0, 0.5, -190)
	multiplierLabel.Size = UDim2.new(0, 120, 0, 40)
	multiplierLabel.BackgroundTransparency = 1
	multiplierLabel.Font = Enum.Font.GothamBold
	multiplierLabel.TextScaled = true
	multiplierLabel.TextColor3 = Color3.new(1, 1, 1)
	multiplierLabel.TextStrokeTransparency = 0.4
	multiplierLabel.Text = "0.75x"
	multiplierLabel.Parent = flightHudFrame

	-- Outcome readout: the short result word (see LaunchConfig.OUTCOME_BANDS),
	-- set once per release, in doRelease below, from the same phase the release
	-- itself fires on -- this IS the feedback, meant to read instantly without
	-- parsing a number, styled per band (OUTCOME_STYLES above) so a perfect looks
	-- like a celebration and a miss looks flat. Left up through the whole flight
	-- and beyond (nothing clears it until the NEXT release overwrites it), so it
	-- also works as a "how did I just do" readout while lining up the next swing,
	-- not just an instant flash at release. Stacked directly under the distance
	-- readout (same horizontal centre, not a separate corner) so its size
	-- changing per band can't overlap that label on a narrow phone screen, where
	-- the distance readout's fixed 400px width already spans most of the width.
	local outcomeLabel = Instance.new("TextLabel")
	outcomeLabel.Name = "OutcomeReadout"
	outcomeLabel.AnchorPoint = Vector2.new(0.5, 0)
	outcomeLabel.Position = UDim2.new(0.5, 0, 0.05, 64)
	outcomeLabel.Size = UDim2.new(0, 260, 0, 28)
	outcomeLabel.BackgroundTransparency = 1
	outcomeLabel.Font = Enum.Font.GothamBold
	outcomeLabel.TextScaled = true
	outcomeLabel.TextColor3 = Color3.new(0.75, 0.75, 0.8)
	outcomeLabel.TextStrokeTransparency = 0.5
	outcomeLabel.Text = ""
	outcomeLabel.Parent = flightHudFrame

	-- ===== THE PERFECT RAINBOW. A UIGradient on the outcome label, off unless
	-- the launch actually snapped -- see setOutcome and updateOutcomeRainbow.
	--
	-- A UIGradient, NOT ONE LABEL PER CHARACTER, and the reasoning is the
	-- nametag scar tissue rather than taste. Per-character labels mean N
	-- Instances rebuilt every time the text changes, a layout (UIListLayout or
	-- hand-positioned offsets) to hold them in a row, and TextScaled going out
	-- the window since each letter would scale to its own box. Every one of
	-- those is a chance to reintroduce exactly the two bugs that took three
	-- passes to find on the base nametags. A UIGradient is ONE child instance,
	-- parented once, that never touches Text, Size, Position, Font or layout at
	-- all -- the label is bit-identical to what it was, with a tint applied at
	-- render time.
	--
	-- IT CANNOT BRING BACK THE GREY BOX. That was BorderSizePixel, and a
	-- UIGradient tints the background and border rather than drawing one --
	-- outcomeLabel is BackgroundTransparency = 1, which the engine applies to
	-- the border as well as the fill, so there is nothing there for a tint to
	-- make visible.
	--
	-- IT CANNOT BRING BACK THE HAZE. That was TextStrokeTransparency, which this
	-- block does not touch: the stroke stays on whatever each OUTCOME_STYLES
	-- entry already sets. And TextStrokeColor3 is never assigned anywhere in
	-- this project, so it is the default black -- a gradient MULTIPLIES, and
	-- black multiplied by any colour is still black, so the stroke cannot pick
	-- up a tint even if the engine applies the gradient to it.
	--
	-- Enabled = false at construction, so a HUD that is never used for a perfect
	-- carries a dormant instance and nothing else.
	local outcomeRainbow = Instance.new("UIGradient")
	outcomeRainbow.Name = "PerfectRainbow"
	outcomeRainbow.Enabled = false
	outcomeRainbow.Parent = outcomeLabel

	-- Whether the per-frame tick should do anything. The single flag every
	-- teardown path clears -- see clearOutcomeRainbow.
	local outcomeRainbowActive = false
	-- Keypoints across the width of the text. 13 gives twelve segments of 30
	-- degrees of hue each, which is fine enough that the straight RGB lerp the
	-- engine runs between keypoints never visibly cuts a corner -- including
	-- across the wrap, where one segment spans the seam from magenta back to
	-- red. Well under the engine's 20-keypoint ceiling.
	local OUTCOME_RAINBOW_KEYPOINTS = 13

	-- THE ONE TEARDOWN, and every path that can end a perfect calls it: a
	-- different outcome replacing it (setOutcome), the per-cycle text reset
	-- (resetFlightHudText), and the HUD being hidden (refreshFlightHud).
	-- Declared up here, beside the gradient it owns, because two of those three
	-- callers are declared above the rest of this module's surface.
	--
	-- It does NOT restore TextColor3. Two of the three callers are blanking or
	-- hiding the label, where the colour is invisible and arbitrary; the third
	-- (setOutcome) is about to write the band's own colour on the very next
	-- line. Leaving the white behind in the first two cases is unobservable, and
	-- not writing it keeps this function honest about what it is: the switch
	-- that stops the animation.
	local function clearOutcomeRainbow()
		outcomeRainbowActive = false
		outcomeRainbow.Enabled = false
	end

	-- Distance sub-readout: small and muted on purpose -- the player launches for
	-- luck, not studs, so luck gets the big primary line (see distanceLabel's
	-- landed-text below) and distance is demoted to this quiet footnote instead of
	-- being the headline. Positioned below the outcome label's tallest ("Perfect!")
	-- size so it never gets covered as that label grows/shrinks per band.
	local distanceSubLabel = Instance.new("TextLabel")
	distanceSubLabel.Name = "DistanceSubReadout"
	distanceSubLabel.AnchorPoint = Vector2.new(0.5, 0)
	distanceSubLabel.Position = UDim2.new(0.5, 0, 0.05, 116)
	distanceSubLabel.Size = UDim2.new(0, 200, 0, 20)
	distanceSubLabel.BackgroundTransparency = 1
	distanceSubLabel.Font = Enum.Font.Gotham
	distanceSubLabel.TextScaled = true
	distanceSubLabel.TextColor3 = Color3.new(0.6, 0.6, 0.65)
	distanceSubLabel.TextStrokeTransparency = 0.6
	distanceSubLabel.Text = ""
	-- ON THE NORMAL HUD, FOR EVERYONE, on every landing. This spent one pass
	-- behind a RunService:IsStudio() gate at exactly this line; the gate is gone
	-- and the label is back to its default Visible. What survives from that pass
	-- is the reason it was worth keeping at all: this is the only place the
	-- SERVER's own authoritative flight distance surfaces, straight off
	-- FlightStarted -- see showLandingResult, which still keeps the exact number
	-- reachable in Studio even on the one landing that hides it from players.
	distanceSubLabel.Parent = flightHudFrame

	local releaseButton = Instance.new("TextButton")
	releaseButton.Name = "ReleaseButton"
	releaseButton.AnchorPoint = Vector2.new(0.5, 1)
	releaseButton.Position = UDim2.new(0.5, 0, 0.97, 0)
	releaseButton.Size = UDim2.new(0, 200, 0, 60)
	releaseButton.BackgroundColor3 = Color3.new(0.85, 0.25, 0.1)
	releaseButton.Font = Enum.Font.GothamBold
	releaseButton.TextScaled = true
	releaseButton.TextColor3 = Color3.new(1, 1, 1)
	releaseButton.Text = "RELEASE!"
	releaseButton.Parent = flightHudFrame

	local releaseButtonCorner = Instance.new("UICorner")
	releaseButtonCorner.CornerRadius = UDim.new(0, 10)
	releaseButtonCorner.Parent = releaseButton

	-- returnHintLabel USED TO BE HERE and is deliberately gone (see the written
	-- report). It was a floating bottom-of-screen prompt that only appeared once
	-- the reward sequence had fully resolved -- i.e. after the reveal panel had
	-- already auto-hidden -- which put the player on an empty road being told to
	-- click, as a second step separate from the reward they had just been shown.
	--
	-- There is no return prompt anywhere now. The reveal is a slime standing in
	-- the world where the box was (see showSlimeReveal) and a primary click or tap
	-- anywhere dismisses it and returns the player in one action -- the same
	-- gesture they have just been using to press the box, so it needs no label.
	-- The luckless landing has no reveal and needs no prompt either: it returns on
	-- its own timer server-side (see LaunchServer's scheduleLucklessReturn).

	-- Dismount button: visible ONLY while actually RIDING -- narrower than
	-- flightHudFrame's own "riding, flying, or box" window (see setMounted
	-- below, the single place this and `mounted` change together) -- lets a
	-- player back off a swing they mounted but don't want to launch from,
	-- without waiting through an unwanted flight/box sequence. Middle of the
	-- right-hand side -- the bar moved to the LEFT (see barTrack above) to
	-- clear this exact spot. ZIndex explicitly above flightHudFrame's default
	-- (see the written report -- dismount button not responding): belt-and-
	-- braces on top of flightHudFrame.Active = false, so this is never
	-- ambiguous about which of the two wins a click even if that changes later.
	local dismountButton = Instance.new("TextButton")
	dismountButton.Name = "DismountButton"
	dismountButton.AnchorPoint = Vector2.new(1, 0.5)
	dismountButton.Position = UDim2.new(0.97, 0, 0.5, 0)
	dismountButton.Size = UDim2.new(0, 160, 0, 44)
	dismountButton.BackgroundColor3 = Color3.new(0.18, 0.18, 0.22)
	dismountButton.Font = Enum.Font.GothamBold
	dismountButton.TextScaled = true
	dismountButton.TextColor3 = Color3.new(1, 1, 1)
	dismountButton.Text = "DISMOUNT"
	dismountButton.ZIndex = 2
	dismountButton.Visible = false
	dismountButton.Parent = screenGui

	local dismountButtonCorner = Instance.new("UICorner")
	dismountButtonCorner.CornerRadius = UDim.new(0, 10)
	dismountButtonCorner.Parent = dismountButton

	-- Draws the bar/multiplier readout for a GIVEN phase -- shared by the live
	-- per-frame sweep (RenderStepped below) and doRelease's freeze-on-release
	-- (below), so the two can never disagree. BUG FIX (see written report): the
	-- live sweep used to keep animating for one extra frame after release --
	-- doRelease flips canRelease synchronously, but the bar's last on-screen
	-- value was whatever the PREVIOUS RenderStepped frame rendered, a fraction of
	-- a frame stale relative to the exact phase doRelease captures for the
	-- outcome text. Near the sweet spot's narrow window that stale frame can read
	-- a noticeably different multiplier (even flip in or out of a snap), so the
	-- bar and the outcome text could disagree. Calling this with the SAME phase
	-- doRelease grades the outcome from guarantees they always match.
	--
	-- TIER IS A PARAMETER now rather than an upvalue: the snap threshold is
	-- per-tier (see LaunchFormulas.snapThresholdForTier), and this module
	-- deliberately holds no state of its own -- LaunchClient owns
	-- ownSwingTier and hands it in at both call sites, which are the same
	-- two call sites as before.
	local function renderBarForPhase(phase: number, tier: number)
		local fill = LaunchFormulas.fillFraction(phase)
		barIndicator.Position = UDim2.new(0.5, 0, 1 - fill, 0)

		local hit = LaunchFormulas.inSweetSpot(phase)
		multiplierLabel.Text = string.format("%.2fx", LaunchFormulas.launchMultiplier(phase, tier))
		multiplierLabel.TextColor3 = hit and Color3.new(0.4, 1, 0.5) or Color3.new(1, 1, 1)

		if hit then
			barIndicator.Size = UDim2.new(1, 14, 0, 14)
			barIndicator.BackgroundColor3 = Color3.new(1, 0.85, 0.25)
			barIndicatorGlow.Transparency = 0.15
		else
			barIndicator.Size = UDim2.new(1, 8, 0, 10)
			barIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
			barIndicatorGlow.Transparency = 1
		end
	end

	-- ===== The two screen-space things `grounded` alone cannot decide =====
	--
	-- `grounded` is a TWO-valued client mirror of a FIVE-valued server state (see
	-- LaunchServer's LoopState: grounded | riding | inflight | box | cooldown).
	-- It is a faithful mirror of exactly one bit -- "is the server willing to
	-- accept a return from me" -- and both refreshes below need one bit more than
	-- that, the same missing bit: whether the box sequence is running. `boxActive`
	-- already carries it, exactly, and is maintained through one setter.
	--
	-- So neither of these gets a new state variable. A third client-side state
	-- enum would have to be kept in sync with the server's own for no new
	-- information -- `not grounded and not boxActive` IS "riding, flying, or
	-- cooling down after a luckless landing", which is precisely the window each
	-- of these means something in. See the written report.
	--
	-- BOTH INPUTS ARE PARAMETERS. They are LaunchClient's own state and stay
	-- there; the CONDITION -- which is the part with the bug history below --
	-- is unchanged and still lives here, next to the frame it governs.
	local function refreshFlightHud(grounded: boolean, rewardSequenceActive: boolean)
		-- NOT `not grounded` (see flightHudFrame's own construction comment): the
		-- reward sequence lives inside `not grounded`, and everything in this
		-- frame is stale or duplicated there. A luckless landing never starts a
		-- reward sequence, so `cooldown` still shows it -- which is what keeps "No
		-- luck (short of the road)" on screen for RESET_DELAY, unchanged.
		--
		-- BUG FIX -- and it is a correction to the previous fix, not an addition:
		-- this read `not boxActive`, which is the WRONG FLAG for this gate.
		-- boxActive means "the box is still pressable" and goes false the instant
		-- BoxResult reports an open -- so the whole flight HUD popped back on for
		-- the thrash, the burst AND the entire slime reveal window, right up until
		-- ResetReady. That is most of the reward sequence, and it is where the
		-- "Luck x700!" line, the outcome text, the bar track and the RELEASE
		-- button were coming back from. rewardSequenceActive spans the thing this
		-- gate actually cares about: BoxStarted through to the sequence being
		-- fully resolved.
		local visible = not grounded and not rewardSequenceActive
		flightHudFrame.Visible = visible
		if not visible then
			-- The HUD going away is one of the three things that ends a perfect
			-- (see clearOutcomeRainbow). Nothing would be VISIBLE if the tick
			-- kept running against a hidden frame, but it would keep running,
			-- and "no lingering animation" is the requirement rather than "no
			-- visible lingering animation".
			clearOutcomeRainbow()
		end
	end

	-- BUG FIX (see the written report -- mid-flight death): clears every readout
	-- a flight leaves behind -- distance/luck (distanceLabel doubles as both),
	-- the distance sub-readout, the live multiplier, and the frozen outcome
	-- text -- back to the same values they hold before a player has ever
	-- released. Without this, a value left behind by an ABANDONED flight (see
	-- resetFlightState's own comment) would sit on an INVISIBLE flightHudFrame
	-- indefinitely and get revealed again, unchanged, the next time
	-- setGrounded(false) shows it -- which is exactly the "Luck x100,000!" /
	-- "Perfect! 2.00x" / "2960.0 studs" still on screen after a respawn. Reset
	-- text matches each label's own pre-flight default (see their construction
	-- above). One place, called from resetReadyRemote's handler below, the only
	-- caller either kind of reset (landing or death/disconnect cancellation)
	-- goes through.
	local function resetFlightHudText()
		distanceLabel.Text = "Time your release!"
		distanceLabel.TextColor3 = Color3.new(1, 1, 1)
		distanceSubLabel.Text = ""
		multiplierLabel.Text = "0.75x"
		multiplierLabel.TextColor3 = Color3.new(1, 1, 1)
		outcomeLabel.Text = ""
		-- The per-cycle reset is the second of the three teardown paths: whatever
		-- the last flight ended on, the next swing starts with no animation
		-- running and a blank label.
		clearOutcomeRainbow()
	end

	-- ===== The rest of the surface: one function per write LaunchClient makes
	-- to a widget in this frame. Each body is the exact statement (or exact
	-- group of statements) that used to sit at the call site, moved here so the
	-- labels themselves stay private to this module. =====

	-- The frozen outcome word, set once per release. The DECISION -- which word
	-- and which style -- stays in LaunchClient's doRelease, because it reads the
	-- landing (landsOnLastBand) and that reads this client's own swing pivot.
	-- This is only the write.
	-- `rainbow` is decided by the caller, which is the only place that knows
	-- both halves of the question -- see LaunchClient's FlightStarted handler.
	local function setOutcome(text: string, style: OutcomeStyle, multiplier: number, rainbow: boolean)
		outcomeLabel.Text = string.format("%s  %.2fx", text, multiplier)
		outcomeLabel.Size = style.size
		outcomeLabel.Font = style.font
		outcomeLabel.TextStrokeTransparency = style.strokeTransparency
		if rainbow then
			-- WHITE, and this is not cosmetic: a UIGradient MULTIPLIES the
			-- label's own TextColor3, so leaving the band's gold in place would
			-- filter every hue through it and produce a muddy gold-to-brown
			-- sweep instead of a rainbow. White is the identity for that
			-- multiply, and the band's own colour goes back on in the else
			-- branch below the moment a non-perfect outcome replaces this one.
			outcomeLabel.TextColor3 = Color3.new(1, 1, 1)
			outcomeRainbow.Enabled = true
			outcomeRainbowActive = true
		else
			clearOutcomeRainbow()
			outcomeLabel.TextColor3 = style.color
		end
	end

	-- ONE FRAME OF THE SWEEP. Driven from LaunchClient's existing
	-- BindToRenderStep loop -- NO new connection exists for this, which is also
	-- the whole of its lifetime guarantee: an animation with no connection of
	-- its own cannot outlive anything or be left running. When the flag is
	-- false this is a single boolean test.
	--
	-- THE SEQUENCE IS REBUILT, NOT OFFSET. UIGradient.Offset slides the gradient
	-- across the object and clamps to the end colours outside it, which would
	-- park a flat red band at one edge of the text and grow it as the sweep
	-- travelled. Re-deriving the keypoints each frame keeps the sequence
	-- spanning the full width at every phase. It costs OUTCOME_RAINBOW_KEYPOINTS
	-- keypoint allocations per frame, and only while a perfect is on screen.
	--
	-- SEAMLESS BY CONSTRUCTION: the hue at t = 0 is `phase` and at t = 1 is
	-- `phase + 1`, the same colour, so the sweep has no visible join to cross as
	-- it loops.
	local function updateOutcomeRainbow()
		if not outcomeRainbowActive then
			return
		end
		local phase = os.clock() * LaunchConfig.OUTCOME_RAINBOW_CYCLES_PER_SECOND
		local keypoints = table.create(OUTCOME_RAINBOW_KEYPOINTS)
		for i = 1, OUTCOME_RAINBOW_KEYPOINTS do
			local t = (i - 1) / (OUTCOME_RAINBOW_KEYPOINTS - 1)
			keypoints[i] = ColorSequenceKeypoint.new(t, Color3.fromHSV(
				(phase + t) % 1,
				LaunchConfig.OUTCOME_RAINBOW_SATURATION,
				LaunchConfig.OUTCOME_RAINBOW_VALUE
			))
		end
		outcomeRainbow.Color = ColorSequence.new(keypoints)
	end

	-- The bar's own multiplier number, overwritten once per flight with the value
	-- the SERVER graded the release at -- see LaunchClient's FlightStarted
	-- handler. Until then the number is whatever renderBarForPhase last predicted
	-- and froze, which is right: it is a live aid while the player is aiming, and
	-- only becomes a claim once the flight exists.
	--
	-- THE COLOUR RULE IS THE SAME ONE, DERIVED FROM THE MULTIPLIER INSTEAD OF THE
	-- PHASE. renderBarForPhase colours on inSweetSpot(phase); here there is no
	-- phase to test, only the number -- and the two ramps are disjoint by
	-- construction, which is what the deliberate 1.5 -> 1.8 jump buys: the outer
	-- ramp tops out at EDGE_MULTIPLIER and the inner one starts at
	-- SWEET_SPOT_EDGE_MULTIPLIER, so "at least 1.8" IS "inside the window", with
	-- nothing in between for it to be wrong about.
	local function setMultiplierReadout(multiplier: number)
		multiplierLabel.Text = string.format("%.2fx", multiplier)
		multiplierLabel.TextColor3 = if multiplier >= LaunchConfig.SWEET_SPOT_EDGE_MULTIPLIER
			then Color3.new(0.4, 1, 0.5)
			else Color3.new(1, 1, 1)
	end

	-- The DISMOUNT button's visibility, which setMounted flips in lockstep with
	-- `mounted` itself -- see that setter in LaunchClient, still the single
	-- owner of the flag.
	local function setDismountVisible(value: boolean)
		dismountButton.Visible = value
	end

	-- ONE FORMATTER FOR EVERY DISTANCE ON SCREEN -- the live countup, the landing
	-- sub-line, and the zero doRelease writes at the instant of release. They
	-- used to be two `string.format("%.1f studs", ...)` calls and a hand-written
	-- "0.0 studs" literal, which is three places to keep in step and is how the
	-- countup could have ended on a different rounding than the final readout.
	--
	-- ROUNDED, NOT TRUNCATED. Two reasons, and the first is the real one:
	--   * the sub-line is a MEASUREMENT of a finished flight, and rounding is
	--     the smaller error -- at most half a stud out, against a whole stud for
	--     truncation.
	--   * the countup and the final readout are different labels a player can
	--     see one after the other, so they have to agree at the boundary. One
	--     rule in one function is what guarantees that; the old split of a
	--     formatted countup and a literal reset did not.
	-- The usual argument for truncating a counter -- never claim distance not yet
	-- travelled -- costs at most half a stud in 3,071 for a fraction of the last
	-- frame, which is not visible and is not worth a second rounding rule for.
	local function distanceText(distance: number): string
		return string.format("%d studs", math.round(distance))
	end

	-- The live countup, every frame of a flight -- and the zero at release, which
	-- is the same call with the same formatter rather than its own literal.
	local function setLiveDistance(distance: number)
		distanceLabel.Text = distanceText(distance)
	end

	-- The landing readout: luck as the headline, distance demoted to the sub-
	-- line. Both branches and the sub-line write are exactly the statements
	-- that used to sit inline in the render loop's u >= 1 branch.
	-- THE ZONE IS CHECKED FIRST, and it still has to be even though its branch
	-- now writes nothing: a "past" landing carries luck 0 BY DESIGN (a chest
	-- landing earns no luck -- see LaunchServer's bandLuckForLandingZ), so
	-- without this branch it falls straight through to the whiff wording and the
	-- best outcome in the game announces itself as the worst. Deleting the
	-- branch and deleting the line are not the same edit.
	--
	-- NOTHING IS WRITTEN, deliberately. A player who cleared the road is
	-- standing on the platform with a chest in front of them; a headline saying
	-- so is describing what is already on screen. The three branches are still
	-- the same three cases LaunchServer's own bandLuckForLandingZ returns, in
	-- the same vocabulary -- this one just has nothing worth saying.
	local function showLandingResult(luck: number, distance: number, zone: string)
		if zone == "past" then
			distanceLabel.Text = ""
		elseif luck > 0 then
			distanceLabel.Text = string.format("Luck x%s!", LuckCurve.formatLuck(luck))
			distanceLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
		else
			distanceLabel.Text = "No luck (short of the road)"
			distanceLabel.TextColor3 = Color3.new(1, 1, 1)
		end
		-- "???" WHEN THE ROAD WAS CLEARED. Gated on the ZONE, not on a distance
		-- threshold: "past" is exactly the case bandLuckForLandingZ already
		-- decides -- the flight came down beyond the last band -- and a threshold
		-- would be a second, hand-maintained copy of the road's own length that
		-- could disagree with it. It is the same branch the headline above uses,
		-- so the two readouts can never describe different landings.
		--
		-- It reads as somewhere OFF THE MAP rather than as a bigger number, which
		-- is what the landing actually is: past the end of the measured road,
		-- where the bands stop and there is nothing left to count against.
		--
		-- THE REAL NUMBER SURVIVES IN STUDIO, appended in brackets. That value is
		-- what made the ping bug findable -- it is the SERVER's own distance, and
		-- reading it off the screen mid-session is how the client/server phase gap
		-- was caught -- and the chest landing is precisely the case worth watching,
		-- so hiding it there and nowhere else would have removed it from where it
		-- matters most. On screen rather than printed, deliberately: a log line is
		-- only found by someone already looking for it.
		if zone == "past" then
			distanceSubLabel.Text = if RunService:IsStudio()
				then string.format("??? (%s)", distanceText(distance))
				else "???"
		else
			distanceSubLabel.Text = distanceText(distance)
		end
	end

	-- THE TWO BUTTONS ARE EXPOSED AS INSTANCES, and only these two. Their
	-- handlers (doRelease/doDismount) are declared far below this point in
	-- LaunchClient and cannot be handed in at construction time without a
	-- forward declaration; exposing the buttons instead keeps both
	-- MouseButton1Click:Connect lines exactly where and as they were.
	return {
		releaseButton = releaseButton,
		dismountButton = dismountButton,
		renderBarForPhase = renderBarForPhase,
		refreshFlightHud = refreshFlightHud,
		resetFlightHudText = resetFlightHudText,
		setOutcome = setOutcome,
		updateOutcomeRainbow = updateOutcomeRainbow,
		setMultiplierReadout = setMultiplierReadout,
		setDismountVisible = setDismountVisible,
		setLiveDistance = setLiveDistance,
		showLandingResult = showLandingResult,
	}
end

LaunchHud.OUTCOME_STYLES = OUTCOME_STYLES
LaunchHud.LAST_BAND_OUTCOME_STYLE = LAST_BAND_OUTCOME_STYLE

return LaunchHud
