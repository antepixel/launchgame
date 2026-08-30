--!strict
-- THE REWARD SCENE: the mystery box, the box camera, the character's
-- invisibility, the other scripts' suppressed HUDs, the box's motion, and the
-- reveal slime -- one module, because they are one lifetime.
--
-- SPLIT OUT OF LaunchClient.client.luau (see REPORT.md -- that file hit Luau's
-- hard 200-locals-per-function-scope limit). Lives in
-- ReplicatedStorage.LaunchClient -- see LaunchClient's own require comment for
-- why. This is the most client-SPECIFIC of the four (LocalPlayer, PlayerGui,
-- CurrentCamera, LocalTransparencyModifier), but nothing here runs at require
-- time -- the module body only declares create() -- so sitting somewhere the
-- server can also see costs nothing and executes nothing. Every function moved
-- VERBATIM,
-- bodies and comments both. The only structural change is that they now sit
-- inside create() rather than at file scope, which is a smaller change than it
-- looks: a Luau script's own body IS a function, so these were already
-- closures over a shared scope and still are -- the scope just has a name and
-- a boundary now.
--
-- WHY THIS IS ONE MODULE AND NOT FIVE. Three acquire/release pairs live in
-- here -- the camera lock, the character's LocalTransparencyModifier, and the
-- other scripts' ScreenGui.Enabled -- and each has exactly ONE acquire call
-- site (showWorldBox) and exactly ONE release call site (endRewardScene). That
-- structure has been the fix for two separate soft-locks (a camera left
-- Scriptable, a slime left standing on the road), and it only holds because no
-- caller can reach a half of a pair. So:
--
--   NONE of acquireBoxCamera, releaseBoxCamera, acquireHiddenCharacter,
--   releaseHiddenCharacter, acquireSuppressedHuds, releaseSuppressedHuds,
--   destroyWorldBox's camera-adjacent siblings, or the reveal anchor's
--   clearing is exported. They are not on the returned table at all.
--
-- The module boundary therefore makes the invariant STRONGER than it was: in
-- the old single file, any of the six was in scope for the whole script and
-- could have been called from anywhere in three thousand lines. Here the only
-- ways in are showBox (which acquires all three) and endScene (which releases
-- all three), and there is no third door. Splitting these across two modules
-- would have inverted that -- see REPORT.md, where the split that was
-- considered and rejected is written down.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local LuckCurve = require(ReplicatedStorage.Config.LuckCurve)
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local TreasureConfig = require(ReplicatedStorage.Config.TreasureConfig)
-- For RUNWAY_TOP_Y only -- the surface the platform, the chest and the player
-- all stand on, which is what "a standing player's eye height" is measured from
-- when the chest reveal picks its rest height. See showSlimeReveal.
local RunwayGeometry = require(ReplicatedStorage.Config.RunwayGeometry)
-- The SAME builder every other slime in the game is made with (base slots, the
-- landmark) -- the reveal must not invent a second way to draw a slime.
local SlimeBuilder = require(ReplicatedStorage.SlimeBuilder)

local player = Players.LocalPlayer

-- The top tier, derived from the tier list rather than written as an 8 -- the
-- chest reveal marks a Divine specially (see showSlimeReveal) and must keep
-- meaning "the top tier" if that list ever grows.
local DIVINE_TIER_INDEX = #SlimeConfig.SLIME_TIER_NAMES

local LaunchRewardScene = {}

-- Called ONCE, from LaunchClient, at the point in its startup where this whole
-- block used to begin. The two remotes are handed in rather than re-resolved
-- here so there is still exactly one Remotes bootstrap in this client, and so
-- this module cannot come up half-wired against a folder LaunchClient already
-- decided was missing.
--
-- returnToSwingRemote belongs to this module's three fire sites and no others:
-- the two inside updateBoxCamera (the deferred return, fired after the camera
-- has handed back) and completeDismiss. LaunchClient keeps its own reference
-- for the frozen-on-the-road backstop, which is not part of this scene.
--
-- isBoxActive is a READ of LaunchClient's own boxActive flag, handed in as an
-- accessor rather than copied: doBoxPress needs it (see its own comment), and
-- that flag has one owner -- setBoxActive, over there, next to setMounted and
-- setGrounded -- which this module must not become a second one of.
function LaunchRewardScene.create(
	playerGui: Instance,
	boxPressRemote: RemoteEvent,
	returnToSwingRemote: RemoteEvent,
	isBoxActive: () -> boolean
)
	-- Whether THIS client's own character is currently frozen -- Anchored, with
	-- AutoRotate off -- which only happens (see LaunchServer.server.luau's
	-- Heartbeat landing handler) between landing and a successful return: the
	-- server keeps a landed player anchored all the way through the box and the
	-- slime reveal, specifically so the Humanoid controller (and, on mobile,
	-- tap-to-move) categorically cannot move them until they choose to leave.
	-- Read directly off the character's own RootPart.Anchored (an ordinary
	-- replicated BasePart property) rather than a second, locally tracked flag,
	-- so this can never drift out of sync with the actual server-side freeze --
	-- see refreshReturnAffordance and the click-anywhere listener further down,
	-- both of which call this fresh rather than caching it.
	--
	-- DECLARED HERE, above the box block, rather than down with the rest of this
	-- client's state where it used to live: releaseBoxCamera below is the one
	-- place that decides whether the camera eases back to the pre-box view or
	-- snaps out of Scriptable immediately, and "is there still a frozen character
	-- standing where that view was framed" is exactly the question it asks.
	local function characterIsFrozen(): boolean
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = humanoid and humanoid.RootPart
		return rootPart ~= nil and rootPart.Anchored
	end

	-- ===== Mystery box: A REAL PART IN THE WORLD, not a screen panel =====
	--
	-- This used to be a centre-screen Frame (boxFrame) with a title, a luck line,
	-- a status line and a PRESS button. It read as a dialog asking a question, not
	-- as a reward sitting in front of you -- so the whole panel is gone, and what
	-- the player looks at now is an actual cube standing in front of their frozen
	-- character with a large "?" on every face.
	--
	-- WHAT DID NOT CHANGE: the BoxStarted / BoxPress / BoxResult flow, in either
	-- direction. No new remote exists, the server sends and receives exactly what
	-- it did before, and every probability/delay still lives entirely server-side
	-- (see LaunchServer's onBoxPress). This block is presentation only.
	--
	-- ENTIRELY CLIENT-SIDE AND NON-REPLICATING, the same way SlimeIdleClient/
	-- SlimeUpgradeTagClient's own instances are: the part is created here, on this
	-- client, parented into Workspace, and exists on no other client and on no
	-- server. Nothing about it is trusted by anything, and no other player can see
	-- it -- which is exactly right, since it is one player's own reward beat
	-- happening at their own landing spot.
	--
	-- THE "?" ON ALL SIX FACES: confirmed working, with one structural caveat
	-- worth stating because it drives the loop below -- a SurfaceGui renders on
	-- exactly ONE face (its own Face property), so six faces means six
	-- SurfaceGuis, not one with six faces selected. All six NormalIds (Front,
	-- Back, Left, Right, Top, Bottom) are valid Face values on an ordinary Part
	-- and each renders independently, so the marking is complete from every angle.
	-- None of them is AlwaysOnTop, deliberately: that would draw the far faces'
	-- "?" straight through the near ones and the cube would stop reading as solid.
	local BOX_PART_NAME = "MysteryBoxLocal"
	local BOX_FACES: { Enum.NormalId } = {
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
		Enum.NormalId.Top,
		Enum.NormalId.Bottom,
	}

	-- Luck colours, in the same vocabulary the deleted panel used: gold while the
	-- box is live, hot orange the instant a press DOUBLES it (the escalation --
	-- the number climbed and the box survived), bright green on the open.
	local BOX_LUCK_COLOR_LIVE = Color3.new(1, 0.85, 0.2)
	local BOX_LUCK_COLOR_DOUBLED = Color3.new(1, 0.55, 0.15)
	local BOX_LUCK_COLOR_OPENED = Color3.new(0.4, 1, 0.5)

	-- Everything below is nil/empty whenever no box exists, which is nearly
	-- always -- see destroyWorldBox, the single teardown every cleanup path calls.
	local boxPart: BasePart? = nil
	local boxQuestionLabels: { TextLabel } = {}
	local boxWorldLuckLabel: TextLabel? = nil
	-- The box's UNDEFORMED placement and size, recomputed from the character every
	-- frame (see updateBoxMotion) and held here so the shake has something exact
	-- to return to -- every shake frame overwrites CFrame and Size outright, so
	-- "rest" has to be a value this file owns, not the property's own last state.
	local boxRestCFrame = CFrame.identity
	local boxRestSize = Vector3.zero
	-- The FLAT (horizontal, unit) direction from the box back toward the player,
	-- written by boxRestCFrameForCharacter alongside boxRestCFrame. Kept as its
	-- own value rather than read back off boxRestCFrame.LookVector, because that
	-- CFrame carries the cube's three-quarter display tilt (see
	-- BOX_WORLD_PITCH_DEGREES) and its LookVector is therefore NOT horizontal --
	-- deriving the camera from it would rock the shot by the same 12 degrees the
	-- box is cosmetically tipped by. This is the clean axis the box camera below
	-- is built on.
	local boxRestTowardPlayer = Vector3.new(0, 0, 1)

	-- WHERE THE BOX GOES, derived entirely from the CHARACTER'S OWN CFrame -- no
	-- world constant, no landing-spot lookup, no camera reference. Works at any
	-- landing spot on the road and at any camera angle, because the only inputs
	-- are the character's own position and the direction it is facing.
	--
	-- The look direction is FLATTENED to horizontal before use: the box must sit
	-- level in front of the player regardless of any pitch/roll the character
	-- happens to be carrying out of the flight pose, and a box tipped by the
	-- character's own landing attitude would read as broken rather than placed.
	-- (The server's own landing PivotTo is already level -- see LaunchServer's
	-- Heartbeat landing handler -- so this is belt-and-braces, not a correction.)
	local function boxRestCFrameForCharacter(): CFrame?
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not (rootPart and rootPart:IsA("BasePart")) then
			return nil
		end
		local rootCFrame = (rootPart :: BasePart).CFrame
		local look = rootCFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-4 then
			-- Degenerate only if the character is somehow facing straight up or
			-- down; -Z is the flight direction every landing faces anyway.
			flat = Vector3.new(0, 0, -1)
		end
		flat = flat.Unit
		boxRestTowardPlayer = -flat

		local centre = rootCFrame.Position
			+ flat * LaunchConfig.BOX_WORLD_DISTANCE_STUDS
			+ Vector3.new(0, LaunchConfig.BOX_WORLD_HEIGHT_OFFSET_STUDS, 0)
		-- Facing back TOWARD the player (centre - flat), then turned by the
		-- configured three-quarter tilt so the cube reads as a cube rather than a
		-- flat square -- see BOX_WORLD_YAW_DEGREES.
		return CFrame.lookAt(centre, centre - flat)
			* CFrame.Angles(
				math.rad(LaunchConfig.BOX_WORLD_PITCH_DEGREES),
				math.rad(LaunchConfig.BOX_WORLD_YAW_DEGREES),
				0
			)
	end

	-- ===== Box camera: the box alone, against sky =====
	--
	-- While a box exists the camera leaves the player's control and eases into a
	-- low three-quarter hero shot -- underneath the cube, looking UP at it, with
	-- the character behind the lens and the road below the bottom edge of the
	-- frustum. See BOX_CAMERA_PITCH_DEGREES for why "below the bottom edge" is a
	-- guarantee here and not an approximation.
	--
	-- THE CAMERA DOES NOT FOLLOW THE SHAKE -- deliberately, and this is the one
	-- decision in this block worth arguing. Every frame it targets boxRestCFrame,
	-- the box's UNDEFORMED placement, never the shaken CFrame actually written to
	-- the part. Two reasons:
	--   1. A camera rigidly locked to a box thrashing at BOX_SHAKE_FREQUENCY_HZ
	--      (18) does not make the box look shaky -- it makes the box look STILL
	--      and the entire world look shaky, because the box is the thing held
	--      fixed in frame. The build would read as an earthquake, not as a box
	--      about to burst, which inverts the whole point of it.
	--   2. Full-screen judder at 18 Hz, on a loop the player runs hundreds of
	--      times, is a genuine motion-sickness risk and not one worth taking for
	--      an effect that reads better without it. Less exposure than it used to
	--      be now the violent shake is a quarter-second thrash rather than the
	--      whole wait, but the reasoning is unchanged.
	-- A stable frame with a violently rattling object inside it is what actually
	-- sells the build. If a camera shake is ever wanted it should be its own
	-- small, independently-tuned offset, not a rigid lock to this one.
	--
	-- RESTORATION IS STRUCTURAL, NOT REMEMBERED. The camera lock's lifetime IS
	-- the box's lifetime, enforced by there being exactly one acquire call site
	-- (showWorldBox) and exactly one release call site (destroyWorldBox), and by
	-- nothing else in this file touching CameraType while a box exists. Every
	-- path that ends a box already funnels through destroyWorldBox -- that was
	-- made true in the pass that built the box -- so every path that ends a box
	-- restores the camera by construction, including ones nobody enumerated. A
	-- path cannot forget to restore the camera without also forgetting to remove
	-- the box, which is visible immediately.
	--
	-- READS Workspace.CurrentCamera LIVE rather than the `camera` upvalue this
	-- file caches at startup. The flight's one-frame CFrame nudge can afford a
	-- stale reference (worst case one frame is framed oddly); a MODE change
	-- cannot -- leaving a camera Scriptable is a soft-lock, so this path must
	-- always be talking to the camera that is actually current.
	type BoxCameraPhase = "off" | "entering" | "held" | "returning"
	local boxCameraPhase: BoxCameraPhase = "off"
	local boxCameraPhaseStart = 0
	-- The CFrame the CURRENT transition started from (captured at each phase
	-- change) and the pre-box view to ease back to. The latter is captured only
	-- on a FRESH acquire -- see acquireBoxCamera.
	local boxCameraFrom = CFrame.identity
	local boxCameraReturnCFrame = CFrame.identity

	-- BUG FIX (see the written report -- camera bolting to the character on
	-- dismiss). Set when a dismiss is waiting for the eased camera return to
	-- finish before it fires ReturnToSwing.
	--
	-- THE BOLT WAS A SEQUENCING BUG, not a transition bug. Dismiss used to fire
	-- the remote immediately, so the server teleported the player to their swing
	-- ~one round trip in -- while the camera was still 0.4s from the end of an
	-- ease toward boxCameraReturnCFrame, a view of the LANDING SPOT captured when
	-- the box first appeared. The ease itself was fine; what was not is what
	-- happened when it finished. Handing back to Custom hands the built-in
	-- controller a camera pointing at an empty stretch of road with its subject
	-- now thousands of studs away, and it slams across the map to catch up. That
	-- is the snap -- it lands at the END of the return, not the start, and the
	-- "easing back" seen afterwards is Roblox's own controller settling.
	--
	-- Deferring the remote until the return completes fixes it at the source: the
	-- camera eases back to a view that still has the character in it, Custom takes
	-- over with nothing to correct, and only then does the teleport happen -- an
	-- ordinary cut, the same one every other teleport in this game already makes.
	local returnPendingCameraSettle = false

	-- Smoothstep: zero slope at both ends, so the push-in accelerates out of rest
	-- and decelerates into the framing instead of starting and stopping abruptly.
	local function easeInOut(t: number): number
		return t * t * (3 - 2 * t)
	end

	-- The framing itself, derived entirely from the box's own rest CFrame and the
	-- flat toward-player axis -- so it frames the box identically regardless of
	-- which way the player happened to land or where their camera was pointing.
	--
	-- THE CAMERA IS ON THE PLAYER'S SIDE, BEHIND THEM -- note the PLUS on
	-- boxRestTowardPlayer. It looks DOWN-ROAD: over the character's shoulder,
	-- through the box, out to the giant slime landmark on the horizon.
	--
	-- THAT DIRECTION IS THE WHOLE REASON THE CHARACTER IS HIDDEN. The landmark
	-- sits at the far, most-negative-Z end of the road (see MapBuilder's own
	-- placement) -- BEYOND the landing, in the direction the player was flying --
	-- so the only view that has it behind the box is one shot from this side. And
	-- from this side the character is unavoidably in frame: they stand only
	-- BOX_WORLD_DISTANCE_STUDS (8) from the box, so any camera far enough back to
	-- frame the box loosely has them squarely between the lens and it, and no
	-- amount of height fixes that (raising the camera also drops the aim, and the
	-- two converge -- they stay inside the frustum at every elevation). Hence
	-- LocalTransparencyModifier, above: the shot is chosen for the backdrop and
	-- the character is removed from it outright, rather than the framing being
	-- bent around them.
	local function boxCameraCFrame(): CFrame
		local boxPosition = boxRestCFrame.Position
		local pitch = math.rad(LaunchConfig.BOX_CAMERA_PITCH_DEGREES)
		local distance = LaunchConfig.BOX_CAMERA_DISTANCE_STUDS
		local eye = boxPosition
			+ boxRestTowardPlayer * (distance * math.cos(pitch))
			+ Vector3.new(0, -distance * math.sin(pitch), 0)
		return CFrame.lookAt(eye, boxPosition)
	end

	-- ONE OF EXACTLY TWO CALL SITES that ever touch CameraType in the box path.
	-- Called from showWorldBox only.
	local function acquireBoxCamera()
		local activeCamera = Workspace.CurrentCamera
		if not activeCamera then
			return
		end
		if boxCameraPhase == "off" then
			-- Captured ONLY on a fresh acquire. showWorldBox destroys any previous
			-- box first, which starts a return -- re-capturing here would then
			-- record the BOX framing itself as the view to restore to, and the
			-- camera would never find its way back to the player.
			boxCameraReturnCFrame = activeCamera.CFrame
		end
		boxCameraFrom = activeCamera.CFrame
		boxCameraPhase = "entering"
		boxCameraPhaseStart = os.clock()
		activeCamera.CameraType = Enum.CameraType.Scriptable
	end

	-- THE OTHER call site. Called from destroyWorldBox only -- see this block's
	-- header for why that is the whole of the restoration guarantee.
	--
	-- ANIMATED OR INSTANT is decided from live state, not from which caller it
	-- was: the eased return only makes sense if there is still a frozen character
	-- standing where boxCameraReturnCFrame was framed. On a death/respawn,
	-- dismount, or return-to-swing the character is gone or has moved, so easing
	-- toward a stale view would be a slow pan to nowhere -- those snap straight
	-- back to Custom instead. Deriving it this way means a new teardown path
	-- added later gets the right behaviour without knowing this rule exists.
	local function releaseBoxCamera()
		if boxCameraPhase == "off" or boxCameraPhase == "returning" then
			return
		end
		local activeCamera = Workspace.CurrentCamera
		if not activeCamera then
			boxCameraPhase = "off"
			return
		end
		if characterIsFrozen() then
			boxCameraFrom = activeCamera.CFrame
			boxCameraPhase = "returning"
			boxCameraPhaseStart = os.clock()
			return
		end
		boxCameraPhase = "off"
		activeCamera.CameraType = Enum.CameraType.Custom
	end

	-- Runs every frame from the same RenderStepped connection the box motion uses
	-- (motion first -- it is what refreshes boxRestCFrame from the character, and
	-- this reads it). Outlives the box itself: the return transition still has to
	-- play after destroyWorldBox has already removed the part, which is why this
	-- is gated on boxCameraPhase rather than on boxPart.
	local function updateBoxCamera()
		if boxCameraPhase == "off" then
			return
		end
		local activeCamera = Workspace.CurrentCamera
		if not activeCamera then
			-- The camera this lock was taken on is no longer current. A brand-new
			-- CurrentCamera comes up Custom on its own, so there is nothing left to
			-- restore -- just drop the lock rather than writing to a dead instance.
			boxCameraPhase = "off"
			-- The deferred return still has to fire, though. Abandoning it here
			-- would leave a player who has already dismissed the reveal anchored on
			-- the road with nothing left on screen to click -- the InputBegan
			-- backstop would eventually rescue them, but only if they thought to
			-- try.
			if returnPendingCameraSettle then
				returnPendingCameraSettle = false
				returnToSwingRemote:FireServer()
			end
			return
		end

		local duration = LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS
		local elapsed = os.clock() - boxCameraPhaseStart
		local t = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1

		if boxCameraPhase == "returning" then
			activeCamera.CFrame = boxCameraFrom:Lerp(boxCameraReturnCFrame, easeInOut(t))
			if t >= 1 then
				-- THE handoff back to the player. Same mechanism FlightStarted uses
				-- (see its own comment): Roblox's Custom camera controller reads its
				-- starting distance/angle from wherever the camera CFrame currently
				-- is, so it continues smoothly from the view we just eased into
				-- rather than snapping to some canned default.
				boxCameraPhase = "off"
				activeCamera.CameraType = Enum.CameraType.Custom
				-- THE DEFERRED RETURN (see returnPendingCameraSettle). Fired here,
				-- after the handback, so the teleport can never land mid-ease and
				-- leave the built-in controller chasing a subject that has moved.
				if returnPendingCameraSettle then
					returnPendingCameraSettle = false
					returnToSwingRemote:FireServer()
				end
			end
			return
		end

		local target = boxCameraCFrame()
		if boxCameraPhase == "entering" then
			activeCamera.CFrame = boxCameraFrom:Lerp(target, easeInOut(t))
			if t >= 1 then
				boxCameraPhase = "held"
			end
			return
		end

		-- "held": pinned to the rest framing for as long as the box exists. Written
		-- every frame rather than once, so it tracks boxRestCFrame's own per-frame
		-- re-derivation from the character (see updateBoxMotion) instead of drifting
		-- away from it.
		activeCamera.CFrame = target
	end

	-- ===== Hiding the character for the shot =====
	--
	-- The box camera above shoots from the PLAYER'S side, looking down-road, so
	-- the character is directly between the lens and the box. It is made
	-- invisible rather than framed around, because the framing that would exclude
	-- it is the one that also excludes the landmark (see boxCameraCFrame).
	--
	-- NOTHING IS MOVED. LocalTransparencyModifier only, never a reparent or a
	-- CFrame write: boxRestCFrameForCharacter re-derives the box's own rest
	-- placement from this character's CFrame EVERY FRAME (that per-frame read is
	-- what closes the landing replication race -- see updateBoxMotion), so
	-- relocating the character to get it out of shot would drag the box along
	-- with it.
	--
	-- BASEPARTS AND DECALS BOTH. A Decal has its own LocalTransparencyModifier
	-- and is NOT hidden by its part's -- miss them and the player's face hangs in
	-- the air in front of the box. Roblox's own TransparencyController (the
	-- first-person fade in the default camera scripts) caches exactly these two
	-- classes for the same reason.
	--
	-- RE-APPLIED EVERY FRAME, NOT WRITTEN ONCE. Three independent reasons, any
	-- one sufficient: (1) that same TransparencyController drives these instances
	-- itself from the camera update at RenderPriority.Camera, and pushes them back
	-- toward 0 in third person -- a single write from here could be undone before
	-- the frame is even drawn. (2) The engine resets the property on assorted
	-- replication events. (3) Accessories can finish replicating AFTER the box
	-- already exists, so the set of instances to hide is not fixed at acquire
	-- time. Re-walking the descendants each frame absorbs all three without
	-- needing to know which one happened; the walk is a few dozen instances and
	-- only runs while a box exists.
	--
	-- ORDERING IS WHY THAT WORKS, and this file already established the fact it
	-- rests on: see RENDER_STEP_NAME's own comment further down, which documents
	-- that a plain RunService.RenderStepped:Connect runs at Enum.RenderPriority.
	-- Last -- AFTER the engine's own camera update at RenderPriority.Camera. This
	-- update rides that same plain connection, so on every frame our write is the
	-- last one before the frame renders.
	--
	-- THE CHARACTER IS CAPTURED, NOT RE-READ. hiddenCharacter holds the exact
	-- Model that was hidden. If the player dies and respawns mid-box, the fresh
	-- character is a DIFFERENT Model and this loop never touches it -- so it
	-- cannot inherit invisibility even for one frame, no matter what order the
	-- respawn and the teardown happen in.
	local hiddenCharacter: Model? = nil

	local function applyCharacterTransparency(character: Model, modifier: number)
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") or descendant:IsA("Decal") then
				descendant.LocalTransparencyModifier = modifier
			end
		end
	end

	-- Called from showWorldBox only -- see releaseHiddenCharacter for the other
	-- half of the pair.
	local function acquireHiddenCharacter()
		local character = player.Character
		if not character then
			return
		end
		hiddenCharacter = character
		applyCharacterTransparency(character, 1)
	end

	-- Called from destroyWorldBox only. Restores to 0 rather than to a
	-- remembered original: 0 is the property's own "no local modification"
	-- default, and the value any of these instances would otherwise be carrying
	-- is recomputed from scratch by TransparencyController on the very next frame
	-- anyway (that is what makes first person work at all) -- so there is nothing
	-- meaningful to remember, and no per-instance table to leak.
	--
	-- SAFE ON AN ALREADY-DESTROYED CHARACTER, which is the respawn case. Destroy
	-- unparents every descendant as well as the Model itself, so GetDescendants
	-- returns an EMPTY list and this loop does nothing at all -- which is the
	-- correct outcome, since a destroyed rig has nothing left to make visible. If
	-- the old character has not been destroyed yet (CharacterAdded can fire
	-- first), the loop finds it intact and restores it normally. Either ordering
	-- is fine, and hiddenCharacter is cleared before the loop either way, so
	-- nothing holds a reference to a dead Model past this call.
	local function releaseHiddenCharacter()
		local character = hiddenCharacter
		hiddenCharacter = nil
		if character then
			applyCharacterTransparency(character, 0)
		end
	end

	local function updateHiddenCharacter()
		local character = hiddenCharacter
		if not character then
			return
		end
		applyCharacterTransparency(character, 1)
	end

	-- ===== Suppressing the OTHER scripts' HUDs =====
	--
	-- BUG FIX (see the written report -- "the unnecessary screen"): gating this
	-- file's own flightHudFrame was necessary but not sufficient, because
	-- LaunchClient is not the only script drawing persistent UI. Two other
	-- ScreenGuis sit on screen unconditionally and were still there through the
	-- whole box sequence: ShopClient's "SWING SHOP" button and InventoryClient's
	-- "INVENTORY" button, stacked in the top-right corner. Neither has any
	-- business being pressable while the player is looking at a mystery box, and
	-- between them they were the entire remaining interface.
	--
	-- BaseClient's money and swing-tier readouts are deliberately NOT in this
	-- list -- see BOX_SUPPRESSED_HUD_NAMES.
	--
	-- ScreenGui.Enabled, NOT the children's Visible flags. Enabled is a separate
	-- axis the owning script never touches, so this cannot disturb whatever state
	-- those panels are in: a shop panel left open comes back open, a closed one
	-- comes back closed, and neither ShopClient nor InventoryClient needs to know
	-- this happens or grow a listener for it. Restoring is unconditionally
	-- Enabled = true rather than a remembered value for exactly that reason --
	-- both are created Enabled and neither script ever sets it.
	local suppressedHuds: { ScreenGui } = {}

	-- Called from showWorldBox only.
	local function acquireSuppressedHuds()
		for _, hudName in LaunchConfig.BOX_SUPPRESSED_HUD_NAMES do
			local hud = playerGui:FindFirstChild(hudName)
			if hud and hud:IsA("ScreenGui") then
				(hud :: ScreenGui).Enabled = false
				table.insert(suppressedHuds, hud :: ScreenGui)
			end
		end
	end

	-- Called from destroyWorldBox only. Works off the captured list rather than
	-- re-resolving the names, so it restores exactly what it disabled and cannot
	-- enable something that was already off for an unrelated reason.
	local function releaseSuppressedHuds()
		for _, hud in suppressedHuds do
			hud.Enabled = true
		end
		table.clear(suppressedHuds)
	end

	-- ===== Box motion: the knock, the thrash, and the burst =====
	--
	-- MOTION ONLY. Nothing here gates input or decides anything: boxActive and
	-- doBoxPress's own cooldown are the only things that have ever governed
	-- whether a press is sent, and nothing in this block touches either. The one
	-- place motion costs the sequence any TIME at all is the thrash, which sits
	-- between BoxResult(opened) and the burst -- see the phase table below and the
	-- budget it has to fit in.
	--
	-- THE VIOLENCE BELONGS TO THE OPEN, NOT TO THE WAIT. An earlier pass ran one
	-- rattle that built through the entire round trip and then resolved either
	-- way. That spent the loudest motion in the game on a moment whose outcome was
	-- still unknown, and -- since BOX_DOUBLE_CHANCE means most presses are fails --
	-- made the ordinary, nothing-happened case the most dramatic thing on screen.
	-- Now the size of the motion matches what actually happened:
	--
	--   NUDGE   -- fired on every press, from doBoxPress, before any result
	--              exists. Starts at full energy and decays out over
	--              BOX_NUDGE_SECONDS: a knock, not a struggle. On a FAIL this is
	--              the whole animation -- the box was hit, it moved, it held --
	--              and nothing further is started when BoxResult(false) lands.
	--   THRASH  -- fired ONLY from BoxResult(opened), and legitimately a
	--              prediction: by the time it starts, the server has already told
	--              this client the box is coming apart. Ramps UP over
	--              BOX_THRASH_SECONDS (see BOX_THRASH_BUILD_EXPONENT) straight
	--              into the burst, which it hands off to itself.
	--   BURST   -- unchanged, only later: it now begins BOX_THRASH_SECONDS after
	--              the result instead of on the same frame.
	--
	-- THE OPEN TAIL MUST FIT IN REVEAL_BOX_TO_SLIME_DELAY_SECONDS. Thrash (0.25)
	-- plus burst (0.3) is 0.55 against that constant's 0.6, so the box is gone
	-- before the slime reveal takes the screen -- the same guarantee as before,
	-- with less headroom. Raising either duration means re-checking that sum.
	--
	-- A single frame still tells the two outcomes apart, which was the original
	-- point and survives the retune: on a fail there is a box, sitting there,
	-- barely moving.
	type BoxMotionPhase = "none" | "nudge" | "thrash" | "burst"
	local boxMotionPhase: BoxMotionPhase = "none"
	local boxMotionStart = 0

	local function startBoxMotion(phase: BoxMotionPhase)
		boxMotionPhase = phase
		boxMotionStart = os.clock()
	end

	-- THE SINGLE TEARDOWN. Every path that used to hide boxFrame calls this
	-- instead -- see hideFlightBoxRevealUI, the SlimeRevealed handler, and the
	-- burst's own completion below. Safe to call with no box up (the common case),
	-- and safe to call twice: Destroy takes the SurfaceGuis, the six "?" labels,
	-- the luck billboard and the ClickDetector with it, since all of them are
	-- children of the part.
	-- ===== The reveal slime: the reward, in the world, where the box was =====
	--
	-- The slime used to be a centre-screen panel that appeared once the box had
	-- burst. It is now an actual SlimeBuilder model standing at the box's own
	-- position, on the box's own camera -- the camera does not move between the
	-- two at all, so the burst and the thing that came out of it read as one
	-- continuous event rather than a cut to a menu.
	--
	-- Its lifetime is the REWARD SCENE's, not the box's: it outlives the box by
	-- design (the box bursts, the slime remains) and is torn down by
	-- endRewardScene alongside the camera, the character's invisibility and the
	-- suppressed HUDs. That single release point is what stops a slime being left
	-- standing on the road -- the same class of bug as a camera left Scriptable,
	-- and given the same fix.
	-- ===== THE REVEAL ANCHOR (see REPORT.md). showSlimeReveal used to derive its
	-- rest pose directly from boxRestCFrame, which is written ONLY by
	-- showWorldBox. A chest landing never creates a box, so that value still held
	-- either CFrame.identity or the player's PREVIOUS box landing -- and the
	-- reveal slime was built, labelled and parented into Workspace hundreds to
	-- thousands of studs away, which is why nothing appeared.
	--
	-- nil means "use the box's rest pose", which is every landing except a chest.
	-- The box path therefore reads exactly the expression it always did (see
	-- showSlimeReveal) and is bit-identical. Set by the ChestRevealStarted
	-- handler, cleared in endRewardScene -- the same single acquire / single
	-- release the camera and character hiding already use.
	local revealAnchorCFrame: CFrame? = nil
	local revealAnchorToward: Vector3? = nil
	-- Per-reveal overrides, also nil on the box path. Held rather than passed as
	-- arguments because updateSlimeReveal runs every frame from the render loop
	-- and has no call site to thread them through.
	local revealRiseStuds = 0
	local revealEntranceSeconds = 0

	local slimeRevealModel: Model? = nil
	-- Where it hovers, and the scale SlimeBuilder gave it -- held here because the
	-- entrance animates both and needs somewhere exact to animate TO. Rotation is
	-- baked into the rest CFrame so the mesh's face (-Z, see SlimeBuilder's own
	-- header) points at the camera.
	local slimeRevealRestCFrame = CFrame.identity
	local slimeRevealBuiltScale = 1
	local slimeRevealStartClock = 0

	local function destroySlimeReveal()
		local model = slimeRevealModel
		slimeRevealModel = nil
		if model then
			model:Destroy()
		end
	end

	-- THE BOX ONLY. It no longer releases the camera, the character's visibility
	-- or the suppressed HUDs -- see endRewardScene below for why those moved.
	--
	-- The split is forced by the reveal: the box is destroyed when the burst
	-- finishes, but the SLIME comes out of it and is looked at afterwards, on the
	-- same camera, with the character still hidden. Releasing any of that at burst
	-- time would snap the camera back to the player mid-reveal.
	local function destroyWorldBox()
		local part = boxPart
		boxPart = nil
		boxQuestionLabels = {}
		boxWorldLuckLabel = nil
		boxMotionPhase = "none"
		if part then
			part:Destroy()
		end
	end

	-- THE SINGLE RELEASE POINT for everything the reward sequence takes over: the
	-- box, the reveal slime, the camera, the character's visibility and the other
	-- scripts' HUDs. Every one of those is acquired in exactly one place
	-- (showWorldBox) and released in exactly one place (here), so a teardown path
	-- cannot restore some of them and forget the rest -- it either calls this or
	-- it does not.
	--
	-- MOVED OUT OF destroyWorldBox, which used to be that point. It stopped being
	-- viable when the slime arrived: the box is destroyed the moment the burst
	-- ends, and the reveal is looked at afterwards on the same camera with the
	-- character still hidden, so "the box is gone" is no longer the same event as
	-- "the scene is over". The structure is unchanged -- one acquire, one release
	-- -- only which function holds it.
	--
	-- Safe to call with nothing up (the common case) and safe to call twice:
	-- every release below already no-ops on an absent subject.
	local function endRewardScene()
		-- Cleared FIRST: a scene torn down by anything other than a dismiss (death,
		-- respawn, dismount, a fresh landing) must not leave a deferred
		-- ReturnToSwing armed to fire at whoever owns the camera next.
		-- dismissRevealAndReturn re-arms it immediately after calling this, which is
		-- the only path that should.
		returnPendingCameraSettle = false
		-- Cleared HERE and nowhere else, alongside everything else the reward
		-- scene takes over. A chest anchor left set would make the NEXT box
		-- landing's reveal appear at the chest -- the exact mirror of the bug this
		-- fixes -- so it is released on the same single path the camera is.
		revealAnchorCFrame = nil
		revealAnchorToward = nil
		destroyWorldBox()
		destroySlimeReveal()
		releaseBoxCamera()
		releaseHiddenCharacter()
		releaseSuppressedHuds()
	end

	-- THE PRESS. The server answers on the same frame now (see LaunchServer's
	-- onBoxPress -- the roll no longer sits behind a delay), so there is no wait to
	-- represent here: the box takes its knock and the result is already on its way
	-- back.
	--
	-- THE LOCAL COOLDOWN IS A COURTESY, NOT THE RATE LIMIT. The real one is
	-- server-side and unchanged in force: onBoxPress refuses any press arriving
	-- while box.pending is set, and that flag is now cleared by its own
	-- BOX_PRESS_COOLDOWN_SECONDS timer. Mirroring the same constant here just
	-- means a normal player's presses are never silently dropped by that guard --
	-- a modified client that skips this check gains nothing but rejections.
	--
	-- A CLOCK, NOT A LATCH, and that distinction is load-bearing. This used to be
	-- a boolean (`boxWaitingForResult`) cleared only by BoxResult arriving, which
	-- was safe only while the client could not out-run the server: with the result
	-- now immediate the client is free again long before the server's own cooldown
	-- expires, so a press could be refused server-side, no BoxResult would ever
	-- come, and a boolean latch would stay set forever -- an unpressable box. A
	-- timestamp cannot get stuck: worst case a press near the boundary is dropped
	-- (one dead click, no state), and the next one is fine.
	local lastBoxPressClock = -math.huge

	-- READS boxActive THROUGH AN ACCESSOR, not a copy. That flag is LaunchClient's
	-- -- it gates the Space/pointer branches in the input handler too, and
	-- setBoxActive there is still its single owner -- so this module borrows the
	-- read rather than taking the state. It matters that the check stays HERE and
	-- is not hoisted to the callers: the ClickDetector on the box itself (see
	-- buildWorldBox) calls this directly, and moving the gate out would leave that
	-- one path ungated.
	local function doBoxPress()
		if not isBoxActive() then
			return
		end
		if os.clock() - lastBoxPressClock < LaunchConfig.BOX_PRESS_COOLDOWN_SECONDS then
			return
		end
		lastBoxPressClock = os.clock()
		-- The knock, on the same line as the remote fire. On a fail this is the
		-- entire animation; on an open the thrash takes over when BoxResult lands.
		startBoxMotion("nudge")
		boxPressRemote:FireServer()
	end

	-- The luck readout, ON the box rather than in a panel: a billboard floating
	-- just above the cube, so the number and the object holding it are one thing
	-- the eye takes in together. AlwaysOnTop, unlike the "?" faces -- a number you
	-- can only half-read is useless, and this is the one element that must survive
	-- the box expanding past it during a burst.
	local function setBoxLuck(luck: number, color: Color3)
		local label = boxWorldLuckLabel
		if not label then
			return
		end
		label.Text = string.format("Luck x%s", LuckCurve.formatLuck(luck))
		label.TextColor3 = color
	end

	-- Builds the cube, its six "?" faces, its luck billboard and its ClickDetector
	-- in one shot, fully off-tree, and only parents it into Workspace once every
	-- child already exists -- the same "populate then reveal" ordering LaunchServer
	-- uses for the Remotes folder, for the same reason: nothing should ever be able
	-- to observe a half-built box.
	local function buildWorldBox(): BasePart
		local part = Instance.new("Part")
		part.Name = BOX_PART_NAME
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.one * LaunchConfig.BOX_WORLD_SIZE_STUDS
		part.Color = LaunchConfig.BOX_WORLD_COLOR
		part.Material = LaunchConfig.BOX_WORLD_MATERIAL
		-- Anchored so nothing physical can move it, CanCollide false so it can
		-- never push, block or trap the frozen player standing in front of it (or
		-- collide with the road bands it is standing over). CanQuery STAYS TRUE --
		-- that is what the ClickDetector's own raycast needs to see the part at
		-- all; CanCollide has nothing to do with clickability. CanTouch off since
		-- nothing listens for touches on it.
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = true
		part.CanTouch = false
		-- SHADOW ON, and it is load-bearing rather than decoration: the box hangs
		-- in mid-air with nothing holding it up, and a shadow on the road beneath
		-- it is what tells the eye how far off the ground it actually is. Without
		-- one the hover reads as the box drifting on a flat backdrop.
		--
		-- It lands where it needs to. Nothing in this project configures Lighting,
		-- so Roblox's defaults apply -- ClockTime 14 with GlobalShadows on, a sun
		-- around 40 degrees up -- which throws the shadow of a centre sitting ~6.5
		-- studs up onto the road roughly 7 studs from directly beneath it. The
		-- road is RUNWAY_WIDTH_STUDS (240) across, so there is no landing position
		-- or lane where that offset can walk the shadow off the road's edge, and
		-- with the camera now level (see BOX_CAMERA_PITCH_DEGREES) the ground
		-- immediately below the box sits just under it in frame rather than out of
		-- shot. Fades out on its own during the burst -- a fully transparent part
		-- casts no shadow, so nothing has to unwind this.
		part.CastShadow = true

		for _, face in BOX_FACES do
			local surface = Instance.new("SurfaceGui")
			surface.Name = string.format("Question%s", face.Name)
			surface.Face = face
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = LaunchConfig.BOX_WORLD_QUESTION_PIXELS_PER_STUD
			-- Unlit: the "?" must read identically whichever way this face happens
			-- to be turned relative to the sun, since the box is tilted and shaking.
			surface.LightInfluence = 0
			surface.Adornee = part
			surface.Parent = part

			local questionLabel = Instance.new("TextLabel")
			questionLabel.Name = "Question"
			questionLabel.Size = UDim2.fromScale(1, 1)
			questionLabel.BackgroundTransparency = 1
			questionLabel.BorderSizePixel = 0
			questionLabel.Font = Enum.Font.GothamBlack
			questionLabel.TextScaled = true
			questionLabel.TextColor3 = LaunchConfig.BOX_WORLD_QUESTION_COLOR
			questionLabel.TextStrokeTransparency = 0.35
			questionLabel.Text = "?"
			questionLabel.Parent = surface

			table.insert(boxQuestionLabels, questionLabel)
		end

		local luckGui = Instance.new("BillboardGui")
		luckGui.Name = "BoxLuck"
		luckGui.Size = UDim2.fromOffset(
			LaunchConfig.BOX_WORLD_LUCK_LABEL_WIDTH_PIXELS,
			LaunchConfig.BOX_WORLD_LUCK_LABEL_HEIGHT_PIXELS
		)
		-- StudsOffsetWorldSpace, not StudsOffset: the number must sit above the
		-- box in the WORLD, not above it in camera space, or it would swing around
		-- the cube as the player turns the camera.
		luckGui.StudsOffsetWorldSpace = Vector3.new(0, LaunchConfig.BOX_WORLD_LUCK_LABEL_HEIGHT_STUDS, 0)
		luckGui.AlwaysOnTop = true
		luckGui.Adornee = part
		luckGui.Parent = part

		local luckLabel = Instance.new("TextLabel")
		luckLabel.Name = "BoxLuckText"
		luckLabel.Size = UDim2.fromScale(1, 1)
		luckLabel.BackgroundTransparency = 1
		luckLabel.BorderSizePixel = 0
		luckLabel.Font = Enum.Font.GothamBlack
		luckLabel.TextScaled = true
		luckLabel.TextColor3 = BOX_LUCK_COLOR_LIVE
		luckLabel.TextStrokeTransparency = 0.3
		luckLabel.Text = ""
		luckLabel.Parent = luckGui
		boxWorldLuckLabel = luckLabel

		-- HOW A PRESS IS TRIGGERED NOW that the PRESS button is gone: you click or
		-- tap THE BOX. A ClickDetector is the one input that covers mouse and touch
		-- with the same gesture and no on-screen chrome at all -- Roblox raises
		-- MouseClick for a touch tap on the part exactly as it does for a left
		-- click, and it fires locally for a locally-created part. Space still works
		-- too (see the InputBegan handler below, unchanged), so keyboard players
		-- keep the shortcut they had.
		--
		-- No conflict with the click-anywhere-to-return listener: that one is gated
		-- on `grounded`, which is false for the whole box sequence and only flips
		-- true on ResetReady, long after the box is gone.
		local clickDetector = Instance.new("ClickDetector")
		clickDetector.Name = "BoxPressDetector"
		clickDetector.MaxActivationDistance = LaunchConfig.BOX_WORLD_CLICK_DISTANCE_STUDS
		clickDetector.Parent = part
		clickDetector.MouseClick:Connect(function()
			doBoxPress()
		end)

		return part
	end

	-- Called once per BoxStarted. Tears down any previous reward scene first --
	-- defensive only (every path out of one already does), but it makes "a second
	-- box, or a leftover slime, can never exist" structural rather than a property
	-- of the paths that happen to run first.
	local function showWorldBox(luck: number)
		endRewardScene()

		local part = buildWorldBox()
		boxPart = part
		boxRestSize = part.Size
		-- Placed here so the box is already in the right spot on the frame it
		-- appears rather than for one frame at wherever the previous one stood.
		-- Not authoritative, though: updateBoxMotion re-derives this from the
		-- character every single frame (see its own comment on the landing-CFrame
		-- replication race), so a nil character here costs at most one frame, not
		-- a misplaced box.
		local rest = boxRestCFrameForCharacter()
		if rest then
			boxRestCFrame = rest
		end
		-- The UNHOVERED rest pose, not boxHoverCFrame (which is declared further
		-- down, alongside the motion it feeds). Costs at most one frame at up to
		-- BOX_HOVER_AMPLITUDE_STUDS off the hover's current height -- a third of a
		-- stud, before the box has even been parented -- and updateBoxMotion takes
		-- over on the very next frame.
		part.CFrame = boxRestCFrame
		setBoxLuck(luck, BOX_LUCK_COLOR_LIVE)

		startBoxMotion("none")
		part.Parent = Workspace

		-- THE ONLY PLACE the reward scene is acquired -- camera, character
		-- invisibility and HUD suppression together. Last, after boxRestCFrame and
		-- boxRestTowardPlayer are both settled, since the framing is derived from
		-- them. Paired with endRewardScene's three releases, which is the single
		-- point every teardown path funnels through.
		acquireBoxCamera()
		acquireHiddenCharacter()
		acquireSuppressedHuds()
	end

	local BOX_SHAKE_TAU = 2 * math.pi

	-- ===== The hover: the box's MOVING rest pose =====
	--
	-- Not a motion phase, and deliberately not one. Every phase below builds on
	-- top of whatever this returns for the current frame, instead of any of them
	-- owning the box's placement outright: at rest the box is exactly this, a
	-- press adds the rattle's jitter and tilt on top of it, a fail decays that
	-- back down onto it, and the burst expands out of it. That is what makes the
	-- hover and the shake compose rather than fight -- there is no frame on which
	-- two systems disagree about where the box is, because only one of them ever
	-- answers that question and the others are offsets from its answer.
	--
	-- Driven by the ABSOLUTE clock, exactly like applyBoxShake below and for the
	-- same reason: nothing here restarts on a phase change, so there is no
	-- discontinuity to snap across when one begins or ends. The bob is a plain
	-- sine about the resting height; the spin is unbounded and monotonic, which
	-- is fine -- it feeds CFrame.Angles, and every face carries the same "?".
	--
	-- The BOX CAMERA does not track any of this (it frames boxRestCFrame, not
	-- this) -- see its own block on why following the box's own motion would read
	-- as the world moving rather than the box.
	-- PARAMETERISED so the reveal slime can hover on exactly the same clock as
	-- the box did -- identical bob and spin, applied to whatever rest pose is
	-- passed in. Behaviour for the box is unchanged: boxHoverCFrame below is the
	-- same call it always made, just with the rest CFrame handed in rather than
	-- closed over.
	local function hoverCFrame(rest: CFrame): CFrame
		local now = os.clock()
		local period = LaunchConfig.BOX_HOVER_PERIOD_SECONDS
		local bob = if period > 0
			then LaunchConfig.BOX_HOVER_AMPLITUDE_STUDS * math.sin(BOX_SHAKE_TAU * now / period)
			else 0
		local spin = math.rad(LaunchConfig.BOX_HOVER_SPIN_DEGREES_PER_SECOND * now)
		return CFrame.new(rest.Position + Vector3.new(0, bob, 0))
			* rest.Rotation
			* CFrame.Angles(0, spin, 0)
	end

	local function boxHoverCFrame(): CFrame
		return hoverCFrame(boxRestCFrame)
	end

	-- Builds the reveal slime and starts its entrance. THE ONLY PLACE a reveal
	-- slime is created; destroySlimeReveal (via endRewardScene) is the only place
	-- one is removed.
	--
	-- PLACED AT THE BOX'S OWN REST POSITION. boxRestCFrame still holds it: the
	-- burst destroys the part but nothing overwrites that value afterwards
	-- (updateBoxMotion early-returns once boxPart is nil), and the box camera is
	-- framed off the same value -- so the slime lands exactly where the box was,
	-- centred in a shot that has not moved and will not move until the player
	-- dismisses it.
	--
	-- FACING: the mesh's face axis is -Z (see SlimeBuilder's header, which
	-- measured it rather than assuming), and CFrame.lookAt aims -Z at its target,
	-- so looking at boxRestTowardPlayer -- the flat axis from the box back toward
	-- the player, which is also where the camera sits -- points the slime's face
	-- at the camera with no extra correction.
	-- The slime's pose during the entrance: the LIVE hover pose, dropped straight
	-- down by `rise` studs in WORLD space. Two things matter about it.
	--
	-- It reads the hover, so the spin and bob are already running while the slime
	-- is still rising and growing -- at rise = 0 this is exactly what
	-- updateSlimeReveal settles to, so the entrance ends on the hover rather than
	-- cutting to it.
	--
	-- And the drop is applied to the hover's POSITION, after its rotation, rather
	-- than as a local offset -- so the slime always rises straight up regardless
	-- of which way the spin currently has it turned.
	local function entranceCFrame(rise: number): CFrame
		local hover = hoverCFrame(slimeRevealRestCFrame)
		return CFrame.new(hover.Position - Vector3.new(0, rise, 0)) * hover.Rotation
	end

	local function showSlimeReveal(slime: SlimeData.Slime, isNew: boolean)
		destroySlimeReveal()

		-- Skinned here as well as on the pad, deliberately: the reveal is where
		-- a player first sees the slime they just won, and a painted Legendary
		-- that reveals plain and then turns striped once it lands in a slot
		-- reads as a bug in the reveal.
		local model = SlimeBuilder.build(
			slime.color,
			if revealAnchorCFrame then TreasureConfig.CHEST_REVEAL_WIDTH_STUDS else SlimeConfig.SLIME_REVEAL_WIDTH_STUDS,
			slime.skinTextureId
		)
		-- Captured because the entrance animates scale and Model:ScaleTo takes an
		-- ABSOLUTE scale -- animating it means multiplying THIS, not stacking a
		-- second ScaleTo on top of the one build() already applied.
		slimeRevealBuiltScale = model:GetScale()

		-- THE ONE LINE THE CHEST FIX TURNS ON. With no anchor set -- every landing
		-- except a chest -- these are literally boxRestCFrame.Position and
		-- boxRestTowardPlayer, the same two values this used to read directly, so
		-- the box path computes the identical CFrame.lookAt it always has.
		local centre = if revealAnchorCFrame then revealAnchorCFrame.Position else boxRestCFrame.Position
		local toward = revealAnchorToward or boxRestTowardPlayer
		if revealAnchorCFrame then
			-- CHEST ONLY: pick the rest height, and slow the entrance for a Divine.
			-- Done HERE rather than in the remote handler because neither the tier
			-- nor the slime's own size is known until the reveal itself arrives.
			--
			-- AS LOW AS THE CHEST ALLOWS, AND NO LOWER (see REPORT.md, and
			-- TreasureConfig's own block for the arithmetic at today's numbers).
			-- This was a flat 14 studs above the lid, which was written when the
			-- chest was a 10-stud box and left the slime's billboard 28 studs over
			-- the player's head once the chest became a 12-stud mesh. Both terms
			-- below are measured rather than assumed, so the answer follows the
			-- chest's height and the slime's own size instead of being re-tuned by
			-- hand every time either moves.
			local minCorner, maxCorner = SlimeBuilder.worldAABB(model)
			-- The lid floor: sit ON the closed lid, not in it. `centre.Y` is the
			-- anchor the server measured off the lid's own top face.
			local clearOfLid = centre.Y
				+ TreasureConfig.CHEST_REVEAL_LID_CLEARANCE_STUDS
				+ (maxCorner.Y - minCorner.Y) / 2
			-- Where it would rather be: just above the eyeline of someone standing
			-- on the same surface the chest does.
			local atEyeLevel = RunwayGeometry.RUNWAY_TOP_Y
				+ TreasureConfig.CHEST_REVEAL_EYE_HEIGHT_STUDS
				+ TreasureConfig.CHEST_REVEAL_EYE_RISE_STUDS
			local restY = math.max(atEyeLevel, clearOfLid)
			if slime.tier == DIVINE_TIER_INDEX then
				restY += TreasureConfig.CHEST_REVEAL_DIVINE_EXTRA_HEIGHT_STUDS
				revealEntranceSeconds = TreasureConfig.CHEST_REVEAL_DIVINE_ENTRANCE_SECONDS
			end
			-- X and Z stay exactly the anchor's -- the centre of the lid's top
			-- face. The slime hovers over the OPENING it came out of; only how far
			-- above it changed.
			centre = Vector3.new(centre.X, restY, centre.Z)
		end
		slimeRevealRestCFrame = CFrame.lookAt(centre, centre + toward)

		-- The name/tier/NEW readout, on the slime rather than in a panel -- same
		-- shape and reasoning as the box's own luck billboard it replaces:
		-- AlwaysOnTop so it is never lost behind the body it labels, fixed pixel
		-- size so it stays readable whatever the camera is doing, and world-space
		-- offset so it sits above the slime rather than orbiting it.
		local labelGui = Instance.new("BillboardGui")
		labelGui.Name = "SlimeRevealLabel"
		labelGui.Size = UDim2.fromOffset(
			SlimeConfig.SLIME_REVEAL_LABEL_WIDTH_PIXELS,
			SlimeConfig.SLIME_REVEAL_LABEL_HEIGHT_PIXELS
		)
		-- The chest path gets its own, SMALLER offset: every stud above the slime
		-- is another stud the player has to look up past a 12-stud chest, and the
		-- billboard was the first thing to leave the screen. The box path keeps
		-- SlimeConfig's 7.5 -- it is looked at on a framed camera with nothing
		-- competing for vertical room.
		labelGui.StudsOffsetWorldSpace = Vector3.new(0, if revealAnchorCFrame
			then TreasureConfig.CHEST_REVEAL_LABEL_HEIGHT_STUDS
			else SlimeConfig.SLIME_REVEAL_LABEL_HEIGHT_STUDS, 0)
		labelGui.AlwaysOnTop = true
		labelGui.Adornee = model.PrimaryPart
		labelGui.Parent = model.PrimaryPart

		-- NEW/Duplicate, tier, then name -- top to bottom. The tier line keeps the
		-- deleted panel's two rarity signals: its own tier colour, and a TextSize
		-- that grows per tier so a Divine reads literally bigger than a Common
		-- rather than just differently coloured. The asterisk flourish comes with
		-- it, unchanged.
		local badgeLabel = Instance.new("TextLabel")
		badgeLabel.Name = "NewBadge"
		badgeLabel.Size = UDim2.new(1, 0, 0.24, 0)
		badgeLabel.Position = UDim2.fromScale(0, 0)
		badgeLabel.BackgroundTransparency = 1
		badgeLabel.BorderSizePixel = 0
		badgeLabel.Font = Enum.Font.GothamBold
		badgeLabel.TextScaled = true
		badgeLabel.TextStrokeTransparency = 0.4
		badgeLabel.Text = if isNew then "* NEW! *" else "Duplicate"
		badgeLabel.TextColor3 = if isNew then Color3.new(0.3, 1, 0.4) else Color3.new(0.6, 0.6, 0.65)
		badgeLabel.Parent = labelGui

		local starCount = math.max(0, slime.tier - 4)
		local flourish = string.rep("*", starCount)
		local tierText = string.upper(slime.tierName)
		if flourish ~= "" then
			tierText = flourish .. " " .. tierText .. " " .. flourish
		end

		local tierLabel = Instance.new("TextLabel")
		tierLabel.Name = "SlimeTier"
		tierLabel.Size = UDim2.new(1, 0, 0.44, 0)
		tierLabel.Position = UDim2.fromScale(0, 0.24)
		tierLabel.BackgroundTransparency = 1
		tierLabel.BorderSizePixel = 0
		tierLabel.Font = Enum.Font.GothamBlack
		-- NOT TextScaled, unlike its neighbours: an explicit per-tier TextSize is
		-- the whole point (see SLIME_TIER_TEXT_SIZE_BASE/STEP), and TextScaled
		-- would flatten every tier back to the same fitted height.
		tierLabel.TextSize = SlimeConfig.SLIME_TIER_TEXT_SIZE_BASE + (slime.tier - 1) * SlimeConfig.SLIME_TIER_TEXT_SIZE_STEP
		tierLabel.TextColor3 = slime.tierColor
		tierLabel.TextStrokeTransparency = 0.2
		tierLabel.Text = tierText
		tierLabel.Parent = labelGui

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "SlimeName"
		nameLabel.Size = UDim2.new(1, 0, 0.28, 0)
		nameLabel.Position = UDim2.fromScale(0, 0.7)
		nameLabel.BackgroundTransparency = 1
		nameLabel.BorderSizePixel = 0
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.Text = slime.name
		nameLabel.Parent = labelGui

		-- Populate-then-reveal, same as the box: nothing is ever in Workspace
		-- half-built. The first frame's placement is written here too so it never
		-- appears for one frame at the template's own origin.
		slimeRevealStartClock = os.clock()
		-- Defaulted to the box's own constants whenever no chest reveal armed
		-- them, so the box path's rise and entrance duration are unchanged.
		if not revealAnchorCFrame then
			revealRiseStuds = SlimeConfig.SLIME_REVEAL_RISE_STUDS
			revealEntranceSeconds = SlimeConfig.SLIME_REVEAL_ENTRANCE_SECONDS
		end
		slimeRevealModel = model
		model:ScaleTo(slimeRevealBuiltScale * 0.001)
		-- THE HOVER POSE, not slimeRevealRestCFrame. The hover's spin runs off the
		-- absolute clock and is continuous, so a slime built at an arbitrary moment
		-- inherits whatever phase that clock is at -- placing it at the bare rest
		-- CFrame (facing the camera) meant it faced forward for the whole entrance
		-- and then snapped to the live spin phase the instant the entrance handed
		-- over to the hover. Starting from the hover instead means the two are the
		-- same pose at every u, including u = 0 and u = 1, so there is nothing to
		-- snap between. See updateSlimeReveal, which applies the rise the same way.
		model:PivotTo(entranceCFrame(revealRiseStuds))

		-- DIVINE: a light in the slime's own tier colour, parented to the MODEL so
		-- it is destroyed by destroySlimeReveal along with everything else -- no
		-- second registry, no separate teardown path. Chest reveals only; the box
		-- sequence is untouched.
		if revealAnchorCFrame and slime.tier == DIVINE_TIER_INDEX then
			local light = Instance.new("PointLight")
			light.Name = "DivineGlow"
			light.Color = slime.tierColor
			light.Range = TreasureConfig.CHEST_REVEAL_DIVINE_LIGHT_RANGE_STUDS
			light.Brightness = TreasureConfig.CHEST_REVEAL_DIVINE_LIGHT_BRIGHTNESS
			light.Shadows = false
			light.Parent = model.PrimaryPart
		end

		model.Parent = Workspace
	end

	-- THE ENTRANCE, then the hover. Runs every frame from the same RenderStepped
	-- connection the box motion and camera use.
	--
	-- Rising AND growing together, over SLIME_REVEAL_ENTRANCE_SECONDS: it starts
	-- at nothing, SLIME_REVEAL_RISE_STUDS below its resting height, and arrives at
	-- full size on the spot the box was. That combination is what reads as coming
	-- OUT of something rather than fading in on top of it -- a pure scale-up would
	-- look like it had always been there and was simply revealed, and a pure rise
	-- would look like it had been hiding under the road.
	--
	-- Eased with the same smoothstep the camera transition uses, so it decelerates
	-- into its resting pose instead of stopping dead.
	--
	-- Once the entrance is over it hovers on hoverCFrame -- the SAME bob and spin,
	-- on the same absolute clock, the box was using a moment earlier. That
	-- continuity is deliberate: the object changed, the motion did not.
	--
	-- The idle BREATHING animation does not reach this slime, and is not made to:
	-- SlimeIdleClient discovers its subjects by walking Workspace for
	-- Base_<UserId> folders and the landmark by name, so animating this one would
	-- mean either parenting a reveal prop into a player's base or teaching that
	-- file about this one. The hover is what "sits there hovering" needs.
	local function updateSlimeReveal()
		local model = slimeRevealModel
		if not model then
			return
		end

		local duration = revealEntranceSeconds
		local elapsed = os.clock() - slimeRevealStartClock
		local u = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1

		if u < 1 then
			local eased = easeInOut(u)
			-- Never exactly zero: Model:ScaleTo rejects a scale of 0, and a model
			-- scaled to nothing has no meaningful pivot to grow back out of.
			model:ScaleTo(slimeRevealBuiltScale * math.max(eased, 0.001))
			model:PivotTo(entranceCFrame(revealRiseStuds * (1 - eased)))
			return
		end

		model:ScaleTo(slimeRevealBuiltScale)
		model:PivotTo(hoverCFrame(slimeRevealRestCFrame))
	end

	-- Fades the six "?" faces in step with the body during a burst -- without
	-- this the box would dissolve out from behind its own markings and leave six
	-- floating question marks hanging in the air for the last few frames.
	local function setBoxQuestionTransparency(transparency: number)
		for _, questionLabel in boxQuestionLabels do
			questionLabel.TextTransparency = transparency
			questionLabel.TextStrokeTransparency = math.max(0.35, transparency)
		end
	end

	-- `energy` is the 0-1 envelope; the oscillation itself is driven by the
	-- ABSOLUTE clock, not by time-since-this-phase-started. That's what makes the
	-- rattle -> settle handoff seamless: the settle inherits whatever point of the
	-- cycle the rattle was at, so the box keeps shaking and merely loses
	-- amplitude, instead of snapping back to a zero crossing at the handoff.
	--
	-- WORLD SPACE, and the same three-frequency spread the screen panel used, now
	-- across three axes instead of two: the positional jitter is added to the
	-- HOVERING rest POSITION and the box's current rest rotation is applied after
	-- it, so the shake never inherits the cube's three-quarter tilt and never
	-- collapses into a single diagonal slide along it. Each axis runs at its own
	-- multiple of one frequency with its own phase offset (1x/1.7x/1.3x on
	-- position, 0.8x/1.9x/1.15x on rotation) -- an irrational-ish spread is what
	-- reads as "rattling" rather than "oscillating".
	--
	-- ON TOP OF THE HOVER, not instead of it (see boxHoverCFrame): the box keeps
	-- floating and turning underneath the shake, and at energy 0 this collapses to
	-- exactly the hover pose -- so a nudge decaying to nothing and the "none" phase
	-- resuming are the same placement, with nothing to snap between.
	--
	-- SIZE IS PASSED IN, not read from config here: the nudge and the thrash are
	-- the same motion at two very different scales (see the phase table above), so
	-- the caller supplies which pair of amplitude/tilt constants applies and this
	-- stays the one place the actual oscillation is defined.
	local function applyBoxShake(energy: number, peakAmplitudeStuds: number, peakRotationDegrees: number)
		local part = boxPart
		if not part then
			return
		end
		local hover = boxHoverCFrame()
		local w = BOX_SHAKE_TAU * LaunchConfig.BOX_SHAKE_FREQUENCY_HZ * os.clock()
		local amplitude = peakAmplitudeStuds * energy
		local jitter = Vector3.new(
			amplitude * math.sin(w),
			amplitude * 0.6 * math.sin(w * 1.7 + 1.1),
			amplitude * 0.8 * math.sin(w * 1.3 + 2.3)
		)
		local tilt = math.rad(peakRotationDegrees) * energy
		part.CFrame = CFrame.new(hover.Position + jitter)
			* hover.Rotation
			* CFrame.Angles(
				tilt * math.sin(w * 0.8 + 0.5),
				tilt * math.sin(w * 1.9 + 2.0),
				tilt * math.sin(w * 1.15 + 4.1)
			)
		part.Size = boxRestSize
	end

	local function updateBoxMotion()
		local part = boxPart
		if not part then
			return
		end

		-- Re-derived from the character EVERY frame rather than captured once at
		-- BoxStarted (see the written report): the server's landing PivotTo and its
		-- BoxStarted fire on the same Heartbeat, and there is no guarantee the
		-- character's final landed CFrame has replicated to this client by the time
		-- that remote arrives -- capturing once could place the box off a
		-- still-mid-flight position several studs short of the landing spot. The
		-- character is Anchored for the whole box sequence, so re-reading it every
		-- frame is a no-op the instant it settles, and self-corrects that race
		-- rather than racing it. Falls back to the last known rest CFrame if the
		-- character is momentarily absent (a respawn tears the box down anyway --
		-- see hideFlightBoxRevealUI).
		local rest = boxRestCFrameForCharacter()
		if rest then
			boxRestCFrame = rest
		end

		if boxMotionPhase == "none" then
			-- "none" is NOT "still" -- it is the hover, running on its own (see
			-- boxHoverCFrame). This is the only phase where the hover is the whole
			-- of the box's motion rather than the base the rest is added to.
			part.CFrame = boxHoverCFrame()
			part.Size = boxRestSize
			return
		end

		local elapsed = os.clock() - boxMotionStart

		if boxMotionPhase == "nudge" then
			-- Starts at FULL energy and decays out. No ramp, deliberately: the
			-- knock IS the impact, and an impact that faded in would read as the
			-- box starting to move by itself. At u = 1 the energy reaches 0, which
			-- is exactly the hover pose, so the handoff back to "none" is
			-- continuous rather than a snap.
			local duration = LaunchConfig.BOX_NUDGE_SECONDS
			local u = if duration > 0 then elapsed / duration else 1
			if u >= 1 then
				startBoxMotion("none")
				part.CFrame = boxHoverCFrame()
				part.Size = boxRestSize
				return
			end
			applyBoxShake(
				1 - u,
				LaunchConfig.BOX_NUDGE_AMPLITUDE_STUDS,
				LaunchConfig.BOX_NUDGE_ROTATION_DEGREES
			)
			return
		end

		if boxMotionPhase == "thrash" then
			local duration = LaunchConfig.BOX_THRASH_SECONDS
			local u = if duration > 0 then elapsed / duration else 1
			if u >= 1 then
				-- HANDS OFF TO THE BURST ITSELF rather than waiting to be told.
				-- BoxResult already fired and is not coming again, so this phase
				-- is the only thing that knows when the thrash is over -- and
				-- chaining here keeps the two as one continuous event instead of
				-- two client-side timers that could drift apart.
				startBoxMotion("burst")
				return
			end
			-- Ramps UP into the burst, opposite to the nudge above: the box is
			-- losing its fight with whatever is inside it. See
			-- BOX_THRASH_BUILD_EXPONENT for why the ramp is curved rather than
			-- linear.
			applyBoxShake(
				u ^ LaunchConfig.BOX_THRASH_BUILD_EXPONENT,
				LaunchConfig.BOX_THRASH_AMPLITUDE_STUDS,
				LaunchConfig.BOX_THRASH_ROTATION_DEGREES
			)
			return
		end

		-- "burst": the cube blows outward while spinning and fading to nothing,
		-- then is destroyed -- it reads as coming apart, not as swelling, because
		-- it never comes back. Linear in u on all of scale, spin and fade, so the
		-- expansion is fastest-looking at the start, where the size change is
		-- largest relative to what it was.
		local duration = LaunchConfig.BOX_OPEN_BURST_SECONDS
		local u = if duration > 0 then elapsed / duration else 1
		if u >= 1 then
			destroyWorldBox()
			return
		end
		local scale = 1 + (LaunchConfig.BOX_OPEN_BURST_SCALE - 1) * u
		part.Size = boxRestSize * scale
		-- LIFTED BY HALF THE GROWTH, so the cube's underside stays put and the
		-- whole burst travels UPWARD and outward. Two reasons, and the first is
		-- not cosmetic: BOX_WORLD_HEIGHT_OFFSET_STUDS only buys the resting cube
		-- ~2 studs of clearance over the road, and a burst that more than doubles
		-- the cube's size about its own CENTRE would drive its lower half straight
		-- through the road bands and be occluded by them for the last frames of
		-- the animation. This cancels all but the tilt's own share of the downward
		-- growth (the lift matches the axis-aligned half-height, the tilted corner
		-- reaches ~25% further -- see BOX_WORLD_HEIGHT_OFFSET_STUDS's arithmetic),
		-- which at BOX_OPEN_BURST_SCALE leaves the lowest corner still ~1 stud
		-- clear of the road at the end of the burst. It also reads better -- things
		-- that burst go up, they don't grow symmetrically in place.
		--
		-- Launched from the HOVER pose, like every other phase, so the cube starts
		-- coming apart from exactly where it was floating on the previous frame
		-- rather than jumping back to a static rest position first.
		local hover = boxHoverCFrame()
		part.CFrame = CFrame.new(hover.Position + Vector3.new(0, (scale - 1) * boxRestSize.Y * 0.5, 0))
			* hover.Rotation
			* CFrame.Angles(0, math.rad(LaunchConfig.BOX_OPEN_BURST_SPIN_DEGREES * u), 0)
		part.Transparency = u
		setBoxQuestionTransparency(u)
	end

	-- ===== The per-frame tick, called from LaunchClient's own
	-- RunService.RenderStepped:Connect -- the SAME plain connection, connected at
	-- the SAME point in the file, so it still runs at RenderPriority.Last and
	-- still runs before LaunchRemoteLanes' own connection (which is made after
	-- it, as it always was). The four calls and their order are unchanged. =====
	--
	-- ORDER MATTERS, and only in one direction: updateBoxMotion is what refreshes
	-- boxRestCFrame from the character each frame, and updateBoxCamera frames
	-- itself off that value -- so motion first, always, or the camera spends every
	-- frame chasing the previous one's placement.
	local function update()
		updateBoxMotion()
		updateSlimeReveal()
		updateBoxCamera()
		-- Last, and specifically at this connection's default Last priority --
		-- see the hidden-character block on why it has to land after the default
		-- camera scripts' own per-frame LocalTransparencyModifier pass.
		updateHiddenCharacter()
	end

	-- ===== The surface. Everything above is private; these are the only ways in.
	-- Each one is either an existing function under a shorter name, or the exact
	-- statements that used to sit inline at the single call site that needed
	-- them -- see REPORT.md for the site-by-site mapping. =====

	-- BoxResult(opened = true): the box is coming apart. Both statements were
	-- inline in that handler; they are here so the luck COLOURS stay private,
	-- which is what stops a future call site inventing a fourth box state.
	local function markBoxOpened(luck: number)
		setBoxLuck(luck, BOX_LUCK_COLOR_OPENED)
		-- Overrides the press's own nudge mid-decay -- see the handler's own
		-- comment in LaunchClient for the one-frame discontinuity that buys.
		startBoxMotion("thrash")
	end

	-- BoxResult(opened = false): the box survived and the number climbed.
	-- Deliberately no startBoxMotion call -- the nudge doBoxPress already
	-- started IS the fail's animation.
	local function markBoxDoubled(luck: number)
		setBoxLuck(luck, BOX_LUCK_COLOR_DOUBLED)
	end

	-- ChestRevealStarted: arms the anchor the reveal is about to read, plus its
	-- own rise and duration. The four assignments are exactly the handler's own
	-- body. Everything armed here is released in endRewardScene, the same single
	-- point that already releases the box, the camera and the character.
	local function armChestReveal(anchor: CFrame, toward: Vector3)
		revealAnchorCFrame = anchor
		revealAnchorToward = toward
		-- Its own rise and duration, and a Divine gets longer still. The rest
		-- HEIGHT is not armed here -- it is derived in showSlimeReveal from the
		-- lid's own top face and the slime's own measured size, neither of which
		-- is known yet at this point.
		revealRiseStuds = TreasureConfig.CHEST_REVEAL_RISE_STUDS
		revealEntranceSeconds = TreasureConfig.CHEST_REVEAL_ENTRANCE_SECONDS
	end

	-- READ-ONLY, for the reveal's dismiss lockout: that timer re-checks that the
	-- slime it armed for is still the one standing there, by IDENTITY -- see the
	-- SlimeRevealed handler in LaunchClient. Returning the model rather than a
	-- boolean is what keeps that an identity check and not a presence check.
	local function revealModel(): Model?
		return slimeRevealModel
	end

	-- THE SECOND HALF OF A DISMISS, and it stays in here because both of the
	-- things it reads are private camera state: whether releaseBoxCamera (called
	-- a moment earlier, inside endRewardScene) chose the eased return or the
	-- instant one, and the deferred-return flag that updateBoxCamera consumes.
	-- LaunchClient calls endScene(), clears its own revealDismissable, then calls
	-- this -- the same three steps, in the same order, as before the split.
	--
	-- Either way the remote fires exactly once.
	local function completeDismiss()
		if boxCameraPhase == "returning" then
			returnPendingCameraSettle = true
		else
			returnToSwingRemote:FireServer()
		end
	end

	return {
		update = update,
		characterIsFrozen = characterIsFrozen,
		showBox = showWorldBox,
		press = doBoxPress,
		markBoxOpened = markBoxOpened,
		markBoxDoubled = markBoxDoubled,
		destroyBox = destroyWorldBox,
		armChestReveal = armChestReveal,
		showSlime = showSlimeReveal,
		revealModel = revealModel,
		endScene = endRewardScene,
		completeDismiss = completeDismiss,
	}
end

return LaunchRewardScene
