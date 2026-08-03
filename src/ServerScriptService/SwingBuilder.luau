--!strict
-- Builds ONE swing structure -- a standard A-FRAME (four legs, two per
-- side, each pair meeting at a shared apex and splayed outward along
-- DEPTH/Z, beam connecting the two apexes along WIDTH/X), caps, ground
-- pads, seat, and chain -- from SwingTierVisuals data, into a
-- CALLER-SUPPLIED pivot part and folder. Completely REBUILDS (destroy
-- everything in the given folder, construct fresh) every call.
--
-- ONE SILHOUETTE FOR EVERY TIER (see the written report -- the A-frame
-- rebuild): tiers differ by scale, material, and colour ONLY -- never by
-- shape. The previous silhouette (two vertical posts + a crossbar, plus a
-- FOUR-way varying brace style) had almost no depth at all (tier 1
-- measured 3.8 studs deep against 14.4 tall) and four different
-- unreproducible shapes to reason about; neither paid for its complexity.
-- The A-frame's own two-legs-per-side geometry is still the PRIMARY
-- bracing; the four-band visual scheme (see SwingTierVisuals.luau) layers
-- explicit X-bracing (buildBraces) and beam collars (buildBeamCollars) on
-- top of it at higher tiers, purely as surface detail -- neither changes
-- the silhouette itself.
--
-- NO MODULE-LEVEL SINGLETON STATE: this module used to own one hardcoded
-- Workspace.SwingPivot and one hardcoded "SwingStructure" folder, which
-- meant only one swing could ever exist at a time -- see the written
-- report (the swing-lane investigation, and the gallery this refactor was
-- built for). SwingBuilder.build now takes the pivot part and the parent
-- folder as explicit arguments; it never looks either up itself and holds
-- no reference to either between calls. The CALLER owns creating/finding
-- its own pivot and folder and is responsible for any defensive cleanup of
-- stale state -- see LaunchServer.server.luau for the one real game swing,
-- and SwingGallery.server.luau for eleven independent ones built from this
-- exact same function.
--
-- The pivot's X/Z are never touched here (whatever the caller placed it
-- at), but its Y and the effective rope length used to hang the seat off
-- it BOTH move, once per build, scaled together by the current tier (see
-- SwingGeometry.luau for the formulas and why scaling both -- not just the
-- pivot -- keeps the arc's PERIOD and SWEET-SPOT WINDOW untouched while
-- still growing the arc's own RADIUS with the frame; LaunchConfig.
-- SWING_ROPE_LENGTH itself, the base value that gets scaled, never
-- changes). Every part this file creates is either purely decorative
-- (posts, beam, bracing, collars, trim, pads, chain) or a REFERENCE POSE for the
-- seat/chain (built at the swing's theta=0 rest position, corrected to the
-- true live position on the very next client RenderStepped -- see
-- LaunchClient.client.luau). Nothing here can feed back into the seat's
-- actual swept position or the scoring math that depends on it.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SwingTierVisuals = require(ReplicatedStorage.Config.SwingTierVisuals)
local SwingGeometry = require(ReplicatedStorage.Config.SwingGeometry)

local SwingBuilder = {}

local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart
-- Ground level -- the baseplate's own top surface, same reasoning
-- BaseGeometry/RunwayGeometry already use elsewhere in this project. Still
-- legitimately shared/module-level: every caller (the one real game swing,
-- all eleven gallery swings) sits on the SAME single Baseplate and needs
-- the SAME ground reference, unlike the pivot/folder above, which are
-- genuinely per-swing now.
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

-- ===== Orientation helpers =====
-- Every "rod between two points" (posts, braces, chain links, ropes) needs a
-- CFrame whose LENGTH axis (Y for a Block, X for a Cylinder -- Roblox's
-- round faces sit on +-X by default) points from one point to the other.
-- Built from explicit basis vectors (CFrame.fromMatrix) rather than
-- computed Euler angles, specifically so there is no rotation-sign
-- ambiguity to get backwards -- cross products are perpendicular to their
-- inputs by construction, so this is correct regardless of which direction
-- the two points happen to be in.
local function cframeFacingAlongX(position: Vector3, direction: Vector3): CFrame
	local xAxis = direction.Unit
	local reference = if math.abs(xAxis.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local yAxis = xAxis:Cross(reference).Unit
	return CFrame.fromMatrix(position, xAxis, yAxis)
end

local function cframeFacingAlongY(position: Vector3, direction: Vector3): CFrame
	local yAxis = direction.Unit
	local reference = if math.abs(yAxis.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local xAxis = reference:Cross(yAxis).Unit
	return CFrame.fromMatrix(position, xAxis, yAxis)
end

local function cframeAlongY(pointA: Vector3, pointB: Vector3): (CFrame, number)
	local delta = pointB - pointA
	local length = delta.Magnitude
	if length < 1e-4 then
		return CFrame.new(pointA), 0
	end
	return cframeFacingAlongY((pointA + pointB) / 2, delta), length
end

local function cframeAlongX(pointA: Vector3, pointB: Vector3): (CFrame, number)
	local delta = pointB - pointA
	local length = delta.Magnitude
	if length < 1e-4 then
		return CFrame.new(pointA), 0
	end
	return cframeFacingAlongX((pointA + pointB) / 2, delta), length
end

local function pointAlongPost(bottom: Vector3, top: Vector3, fraction: number): Vector3
	return bottom:Lerp(top, fraction)
end

-- ===== Part factory =====
local function newPart(
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	material: Enum.Material,
	color: Color3,
	name: string,
	parent: Instance,
	reflectance: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Shape = shape
	part.Size = size
	part.CFrame = cf
	part.Material = material
	part.Color = color
	part.Reflectance = reflectance or 0
	part.Parent = parent
	return part
end

-- A "rod" spanning two points, thickness studs wide/deep, using whichever
-- axis is the natural length axis for the given shape.
local function newRod(
	pointA: Vector3,
	pointB: Vector3,
	thickness: number,
	shape: Enum.PartType,
	material: Enum.Material,
	color: Color3,
	name: string,
	parent: Instance,
	reflectance: number?
): Part
	if shape == Enum.PartType.Cylinder then
		local cf, length = cframeAlongX(pointA, pointB)
		return newPart(shape, Vector3.new(length, thickness, thickness), cf, material, color, name, parent, reflectance)
	end
	local cf, length = cframeAlongY(pointA, pointB)
	return newPart(shape, Vector3.new(thickness, length, thickness), cf, material, color, name, parent, reflectance)
end

-- Ground pad colour is always frameColor lerped 40% toward black -- exact
-- per the approved four-band scheme, computed here rather than stored per
-- tier so there is one formula, not eleven hand-copied results of it.
local function groundPadMaterialColor(visual: SwingTierVisuals.TierVisual): (Enum.Material, Color3)
	local color = visual.frameColor:Lerp(Color3.new(0, 0, 0), 0.4)
	return visual.groundPadMaterial, color
end

-- Chain/seat colour is always frameColor lerped 22% toward (210,210,215),
-- and their reflectance is always this tier's frame reflectance x 0.5 --
-- same reasoning as groundPadMaterialColor above.
local function chainSeatMaterialColor(visual: SwingTierVisuals.TierVisual): (Enum.Material, Color3, number)
	local color = visual.frameColor:Lerp(Color3.fromRGB(210, 210, 215), 0.22)
	return visual.chainSeatMaterial, color, visual.reflectance * 0.5
end

-- pivotPart: moved (Y only) to this tier's target height, X/Z left exactly
-- where the caller placed it. parentFolder: cleared, then rebuilt into --
-- must already be parented somewhere the caller wants it to render; this
-- function never sets parentFolder's OWN Parent.
function SwingBuilder.build(tier: number, pivotPart: BasePart, parentFolder: Instance)
	parentFolder:ClearAllChildren()

	local visual = SwingTierVisuals.forTier(tier)
	-- TWO scales, split from what used to be one `scale` -- see the
	-- written report on the swing-lane footprint clamp. HEIGHT scale
	-- (visual.scale) is UNCLAMPED, exactly the 1.00-3.60 per-tier values
	-- this always used -- it's the only scale allowed to drive vertical
	-- quantities (postHeight below, and SwingGeometry.pivotYForScale/
	-- ropeLengthForScale, both called with `heightScale`, never
	-- `footprintScale`). FOOTPRINT scale is the SAME per-tier value,
	-- clamped at SwingTierVisuals.FOOTPRINT_SCALE_MAX, and drives every
	-- dimension that determines the frame's X (width) or Z (depth) extent
	-- -- applied EQUALLY to both, so a clamped tier's A-frame silhouette
	-- stays proportioned (never reads deeper than it is wide) instead of
	-- only capping width and leaving depth to keep growing unclamped.
	local heightScale = visual.scale
	local footprintScale = math.min(visual.scale, SwingTierVisuals.FOOTPRINT_SCALE_MAX)

	-- Raise the pivot's height above ground by the HEIGHT scale (see
	-- SwingGeometry.luau) -- always computed from the config baseline,
	-- never from pivotPart.Position.Y as it currently sits, so repeated
	-- tier changes land on the same absolute height for a given tier
	-- rather than compounding. X/Z are re-passed through unchanged -- this
	-- only ever touches Y. Pivot height is a VERTICAL quantity, so this
	-- reads heightScale, not footprintScale, even for a clamped tier.
	pivotPart.Position = Vector3.new(
		pivotPart.Position.X,
		SwingGeometry.pivotYForScale(heightScale),
		pivotPart.Position.Z
	)

	local postHeight = SwingTierVisuals.BASE_POST_HEIGHT * heightScale
	local standHalfWidth = SwingTierVisuals.BASE_STAND_HALF_WIDTH * footprintScale
	local postThickness = SwingTierVisuals.BASE_POST_THICKNESS * footprintScale
	local beamThickness = SwingTierVisuals.BASE_BEAM_THICKNESS * footprintScale
	local beamOverhang = SwingTierVisuals.BASE_BEAM_OVERHANG * footprintScale
	local legSplayHalfDepth = SwingTierVisuals.BASE_LEG_SPLAY_HALF_DEPTH * footprintScale
	-- Seat dimensions, needed early too: the two chain anchors/attachments
	-- below are offset by seatHalfWidth so each tether hangs directly
	-- above/below its own seat corner instead of both sharing one
	-- dead-centre point (see the written report on the crossed-chain bug).
	-- Seat width/depth/thickness are the seat's own X/Z/Y size -- footprint
	-- scale, same as the frame around it, so a clamped tier's seat stays
	-- proportioned to its (also clamped) frame instead of ballooning past
	-- it.
	local seatWidth = 4 * footprintScale
	local seatDepth = 3 * footprintScale
	local seatThickness = 0.5 * footprintScale
	local seatHalfWidth = seatWidth / 2

	local centerX = pivotPart.Position.X
	local centerZ = pivotPart.Position.Z
	local postTopY = groundY + postHeight

	-- ===== A-frame apexes and feet -- the ONLY silhouette, every tier (see
	-- the written report). Two apexes (X = width, under the beam, one per
	-- side); each apex has TWO legs splaying outward along Z (depth) down
	-- to two feet, never splaying in X -- unlike the old single-post-per-
	-- side model, X width no longer depends on any per-tier angle. =====
	local apex1 = Vector3.new(centerX - standHalfWidth, postTopY, centerZ)
	local apex2 = Vector3.new(centerX + standHalfWidth, postTopY, centerZ)
	local foot1Front = Vector3.new(apex1.X, groundY, centerZ + legSplayHalfDepth)
	local foot1Back = Vector3.new(apex1.X, groundY, centerZ - legSplayHalfDepth)
	local foot2Front = Vector3.new(apex2.X, groundY, centerZ + legSplayHalfDepth)
	local foot2Back = Vector3.new(apex2.X, groundY, centerZ - legSplayHalfDepth)

	-- ===== Ground contact: one pad per foot, four total -- no structure
	-- floating bare on the grass. =====
	local padMaterial, padColor = groundPadMaterialColor(visual)
	local padDiameter = postThickness * 2.4
	local padThickness = math.max(0.6, postThickness * 0.3)
	local function buildGroundPad(footPoint: Vector3, name: string)
		local center = footPoint + Vector3.new(0, padThickness / 2, 0)
		if visual.groundPadMaterial == Enum.Material.Slate then
			local cf = cframeFacingAlongX(center, Vector3.new(0, 1, 0))
			newPart(Enum.PartType.Cylinder, Vector3.new(padThickness, padDiameter, padDiameter), cf, padMaterial, padColor, name, parentFolder)
		else
			newPart(Enum.PartType.Block, Vector3.new(padDiameter, padThickness, padDiameter), CFrame.new(center), padMaterial, padColor, name, parentFolder)
		end
	end
	buildGroundPad(foot1Front, "GroundPad1Front")
	buildGroundPad(foot1Back, "GroundPad1Back")
	buildGroundPad(foot2Front, "GroundPad2Front")
	buildGroundPad(foot2Back, "GroundPad2Back")

	-- ===== Legs: four total, each running from its own foot up to the
	-- shared apex on its side. This IS the A-frame's bracing -- there is no
	-- separate brace STYLE code path any more (see the written report);
	-- X-bracing (below) adds visible cross struts on top of this, it never
	-- replaces it. =====
	newRod(foot1Front, apex1, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg1Front", parentFolder, visual.reflectance)
	newRod(foot1Back, apex1, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg1Back", parentFolder, visual.reflectance)
	newRod(foot2Front, apex2, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg2Front", parentFolder, visual.reflectance)
	newRod(foot2Back, apex2, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg2Back", parentFolder, visual.reflectance)

	-- ===== Beam -- overhangs each apex slightly, per real playground/
	-- industrial frame proportion. NO end caps and NO apex caps any more --
	-- deliberately removed (see the written report): they read badly at
	-- every tier, and were a separate code path from the rest of the frame
	-- for no structural reason. =====
	local beamStart = Vector3.new(apex1.X - beamOverhang, postTopY, centerZ)
	local beamEnd = Vector3.new(apex2.X + beamOverhang, postTopY, centerZ)
	newRod(beamStart, beamEnd, beamThickness, visual.beamShape, visual.frameMaterial, visual.frameColor, "Beam", parentFolder, visual.reflectance)

	-- ===== X-bracing: two crossed struts per level, between the two legs
	-- of ONE A-frame side. visual.braceCount levels per side, evenly
	-- dividing that side's leg span from foot (t=0) to apex (t=1); each
	-- level connects the front leg at the level's low end to the back leg
	-- at its high end, and vice versa, so the pair crosses in an X.
	--
	-- CRITICAL: footFront/footBack/apex below are the ACTUAL foot and apex
	-- points already computed above (foot1Front, apex1, etc.), never a
	-- leg PART's own CFrame position -- a leg part is CENTRED on the
	-- midpoint of its run, so ITS OWN Z offset from the swing centre is
	-- only HALF the real foot spread. Lerping between the real foot and
	-- apex points (as this does) sidesteps that trap entirely: the Z
	-- component naturally interpolates from the true foot offset down to
	-- zero at the apex, with no leg-part geometry involved at all. =====
	local BRACE_THICKNESS_FACTOR = 0.02
	local function buildBraces(footFront: Vector3, footBack: Vector3, apex: Vector3, sideName: string)
		local count = visual.braceCount
		if count <= 0 then
			return
		end
		local braceThickness = postHeight * BRACE_THICKNESS_FACTOR
		for i = 1, count do
			local loT = (i - 1) / count
			local hiT = i / count
			local frontLo = footFront:Lerp(apex, loT)
			local frontHi = footFront:Lerp(apex, hiT)
			local backLo = footBack:Lerp(apex, loT)
			local backHi = footBack:Lerp(apex, hiT)
			newRod(frontLo, backHi, braceThickness, Enum.PartType.Cylinder, visual.frameMaterial, visual.accentColor, sideName .. "BraceA" .. i, parentFolder, visual.reflectance)
			newRod(backLo, frontHi, braceThickness, Enum.PartType.Cylinder, visual.frameMaterial, visual.accentColor, sideName .. "BraceB" .. i, parentFolder, visual.reflectance)
		end
	end
	buildBraces(foot1Front, foot1Back, apex1, "Side1")
	buildBraces(foot2Front, foot2Back, apex2, "Side2")

	-- ===== Beam collars: cylinders encircling the beam, centred on it.
	--
	-- CRITICAL: a Cylinder's length axis is X and the beam already runs
	-- along world X (beamStart/beamEnd only differ in X), so a collar
	-- needs NO rotation at all -- CFrame.new(position) is already correct.
	-- Rotating it 90 degrees would lay it flat across the beam as a tab
	-- instead of encircling it. =====
	local COLLAR_LENGTH_FACTOR = 0.022
	local COLLAR_DIAMETER_FACTOR = 0.11
	local COLLAR_SPACING_FACTOR = 0.16
	local COLLAR_REFLECTANCE_BOOST = 0.08
	local function buildBeamCollars()
		local count = visual.collarCount
		if count <= 0 then
			return
		end
		local apexY = postHeight
		local spacing = apexY * COLLAR_SPACING_FACTOR
		local size = Vector3.new(apexY * COLLAR_LENGTH_FACTOR, apexY * COLLAR_DIAMETER_FACTOR, apexY * COLLAR_DIAMETER_FACTOR)
		-- accentColor, not frameColor: in frameColor a collar is the same
		-- colour as the beam it encircles and reads as invisible. Reflectance
		-- is boosted above the tier's own frame reflectance for the same
		-- reason -- a bolted metal collar should read as distinct from the
		-- beam surface it's clamped onto, not blend into it.
		for i = 0, count - 1 do
			local offset = (i - (count - 1) / 2) * spacing
			local center = Vector3.new(centerX + offset, postTopY, centerZ)
			newPart(Enum.PartType.Cylinder, size, CFrame.new(center), visual.frameMaterial, visual.accentColor, "BeamCollar" .. (i + 1), parentFolder, visual.reflectance + COLLAR_REFLECTANCE_BOOST)
		end
	end
	buildBeamCollars()

	-- ===== Glow trim: ONE accentColor rod along the beam underside plus
	-- one along each of the four legs. Thickness SCALES with the frame
	-- (postThickness), not a flat constant -- beam trim postThickness*0.35,
	-- leg trim postThickness*0.28, so trim reads thin at tier 1 and thick
	-- at tier 11 same as everything else, instead of the same 0.36 studs
	-- at every scale. Tiers 1-5 (glowAccent = false): frameMaterial,
	-- opaque, frame reflectance -- "trim uses the frame material in
	-- accentColor," no neon at all. Tiers 6-11 (glowAccent = true): Neon,
	-- this tier's own glowTransparency, no reflectance (Neon ignores it).
	-- No horizontal tie bar between the two A-frames -- deliberately not
	-- built; it would run straight through the seat's swept arc at every
	-- height that would look structural. =====
	local BEAM_TRIM_THICKNESS_FACTOR = 0.35
	local LEG_TRIM_THICKNESS_FACTOR = 0.28
	local beamTrimThickness = postThickness * BEAM_TRIM_THICKNESS_FACTOR
	local legTrimThickness = postThickness * LEG_TRIM_THICKNESS_FACTOR
	local trimMaterial = if visual.glowAccent then Enum.Material.Neon else visual.frameMaterial
	local trimReflectance = if visual.glowAccent then 0 else visual.reflectance
	local function applyTrimTransparency(part: Part)
		if visual.glowAccent then
			part.Transparency = visual.glowTransparency
		end
	end

	-- Industrial band (DiamondPlate frame, tiers 4-6) gets hazard banding
	-- on the BEAM instead of the plain trim rod -- alternating accentColor/
	-- near-black segments, sized slightly larger than the beam so they
	-- read as a painted wrap. The single most recognisable industrial
	-- signal, for the cost of 9 parts. Leg trim below is unaffected by
	-- this -- only the beam's own trim swaps out.
	local isIndustrialBand = visual.frameMaterial == Enum.Material.DiamondPlate
	if isIndustrialBand then
		local HAZARD_SEGMENT_COUNT = 9
		local HAZARD_SEGMENT_THICKNESS = beamThickness * 1.2
		local hazardDarkColor = Color3.fromRGB(28, 29, 33)
		for i = 0, HAZARD_SEGMENT_COUNT - 1 do
			local segStart = beamStart:Lerp(beamEnd, i / HAZARD_SEGMENT_COUNT)
			local segEnd = beamStart:Lerp(beamEnd, (i + 1) / HAZARD_SEGMENT_COUNT)
			local segColor = if i % 2 == 0 then visual.accentColor else hazardDarkColor
			newRod(segStart, segEnd, HAZARD_SEGMENT_THICKNESS, Enum.PartType.Cylinder, visual.frameMaterial, segColor, "HazardBand" .. i, parentFolder, visual.reflectance)
		end
	else
		local underOffset = Vector3.new(0, -beamThickness * 0.75, 0)
		applyTrimTransparency(newRod(beamStart + underOffset, beamEnd + underOffset, beamTrimThickness, Enum.PartType.Cylinder, trimMaterial, visual.accentColor, "TrimBeam", parentFolder, trimReflectance))
	end

	local function buildLegTrim(footPoint: Vector3, apex: Vector3, name: string)
		local part = newRod(pointAlongPost(footPoint, apex, 0.15), apex - Vector3.new(0, postThickness, 0), legTrimThickness, Enum.PartType.Cylinder, trimMaterial, visual.accentColor, name, parentFolder, trimReflectance)
		applyTrimTransparency(part)
	end
	buildLegTrim(foot1Front, apex1, "TrimLeg1Front")
	buildLegTrim(foot1Back, apex1, "TrimLeg1Back")
	buildLegTrim(foot2Front, apex2, "TrimLeg2Front")
	buildLegTrim(foot2Back, apex2, "TrimLeg2Back")

	-- ===== Seat: a REFERENCE pose at the swing's theta=0 rest position --
	-- corrected to the true live position on the very next client
	-- RenderStepped (see LaunchClient.client.luau), same as it always was.
	-- Built as a Model (PrimaryPart = SeatCore) so a multi-part seat moves
	-- rigidly as one unit via Model:PivotTo, same mechanism the character
	-- itself already uses. =====
	-- Effective rope length for THIS tier -- derived from the same
	-- `heightScale` the pivot was just placed with (see SwingGeometry.
	-- luau), not a second independently-read copy of LaunchConfig.
	-- SWING_ROPE_LENGTH. Rope length is a VERTICAL quantity (the seat's
	-- radius below the pivot), so this stays on heightScale -- unclamped --
	-- even for a tier whose FOOTPRINT is capped; only the frame's X/Z
	-- extent stops growing, never the arc radius.
	local effectiveRopeLength = SwingGeometry.ropeLengthForScale(heightScale)
	local referenceSeatPosition = pivotPart.Position + Vector3.new(0, -effectiveRopeLength, 0)

	-- Chain/seat material+colour+reflectance: one formula, shared by the
	-- seat here and every chain link below (see chainSeatMaterialColor).
	local chainSeatMaterial, chainSeatColor, chainSeatReflectance = chainSeatMaterialColor(visual)

	local seatModel = Instance.new("Model")
	seatModel.Name = "SwingSeat"

	local seatCore = newPart(
		Enum.PartType.Block,
		Vector3.new(seatWidth, seatThickness, seatDepth),
		CFrame.new(referenceSeatPosition),
		chainSeatMaterial,
		chainSeatColor,
		"SeatCore",
		seatModel,
		chainSeatReflectance
	)
	seatModel.PrimaryPart = seatCore

	-- Two chain-attachment markers, one at each side of the seat, offset by
	-- +-seatHalfWidth along the seat's OWN local X axis. Parented to
	-- SeatCore (not placed as loose world points) so PivotTo -- which moves
	-- AND TILTS the whole seat every frame, see LaunchClient.client.luau --
	-- carries these along for free: an Attachment inherits its parent
	-- part's full transform, so its WorldPosition always reflects this
	-- frame's actual (rotated) seat corner, never a flat world-space offset
	-- that would drift apart from the seat once it tilts off theta=0.
	local chainSeatAttachmentLeft = Instance.new("Attachment")
	chainSeatAttachmentLeft.Name = "ChainBottomAttachmentLeft"
	chainSeatAttachmentLeft.Position = Vector3.new(-seatHalfWidth, seatThickness / 2, 0)
	chainSeatAttachmentLeft.Parent = seatCore

	local chainSeatAttachmentRight = Instance.new("Attachment")
	chainSeatAttachmentRight.Name = "ChainBottomAttachmentRight"
	chainSeatAttachmentRight.Position = Vector3.new(seatHalfWidth, seatThickness / 2, 0)
	chainSeatAttachmentRight.Parent = seatCore

	-- BUG FIX (see the written report): the seat used to branch four ways on
	-- a per-tier `seatStyle` (Plank/Bucket/Contoured/Floating), building
	-- backs/rails/underlights on top of SeatCore for the higher bands -- the
	-- same per-band SHAPE variation already removed from the frame
	-- silhouette (see the A-frame rebuild), and for the same reason: a
	-- swing seat that grows a chair back and side rails at high tiers reads
	-- as a chair, not a swing. ONE shape now, every tier: SeatCore itself,
	-- a flat plank, sized by footprintScale like the rest of the frame.
	-- Material and colour (chainSeatMaterial/chainSeatColor, set on SeatCore
	-- above) still vary per tier -- only the SHAPE stopped varying.
	--
	-- The two SeatKnot balls that used to sit here (one per side, at
	-- +-seatHalfWidth) are deleted outright, not repositioned -- that offset
	-- is the seat's own edge, exactly where chainSeatAttachmentLeft/Right
	-- and the chain's own last link already terminate (see buildChainSide
	-- below), so a knot ball there was always just a second part rendering
	-- on top of a junction the chain and the seat corner already mark on
	-- their own.

	seatModel.Parent = parentFolder

	-- ===== Chain anchors: two tiny invisible fixed points just under the
	-- beam, one per side, offset by the SAME seatHalfWidth the two seat
	-- attachments above use -- so each tether's top and bottom line up
	-- directly above/below each other, parallel, seatHalfWidth off centre,
	-- instead of both tethers sharing one dead-centre anchor AND one
	-- dead-centre seat point (which is what made this a single line, not
	-- two, before this pass -- see the written report).
	--
	-- BUG FIX (see the written report): this used to sit at
	-- postTopY - beamThickness, a full beamThickness below the beam's own
	-- CENTRE -- but the beam (a Block/Cylinder of thickness `beamThickness`
	-- centred AT postTopY) only extends postTopY -+ beamThickness/2, so its
	-- UNDERSIDE is at postTopY - beamThickness/2, not postTopY -
	-- beamThickness. The anchor was landing a further beamThickness/2 below
	-- the underside it was supposed to sit flush against -- a visible gap
	-- between the beam and the top of the chains, worse at high tiers where
	-- beamThickness (footprint-scaled) is larger. Flush now, at every tier,
	-- by construction. =====
	local function buildChainAnchor(name: string, xOffset: number): BasePart
		local anchor = newPart(
			Enum.PartType.Block,
			Vector3.new(0.2, 0.2, 0.2),
			CFrame.new(centerX + xOffset, postTopY - beamThickness / 2, centerZ),
			Enum.Material.Plastic,
			Color3.new(0, 0, 0),
			name,
			parentFolder
		)
		anchor.Transparency = 1
		return anchor
	end
	local chainAnchorLeft = buildChainAnchor("SwingChainAnchorLeft", -seatHalfWidth)
	local chainAnchorRight = buildChainAnchor("SwingChainAnchorRight", seatHalfWidth)

	-- ===== Chain / rope / rod / energy tether -- built once per side, each
	-- entirely from that side's own anchor down to that side's own seat
	-- attachment, so the two can never share an endpoint. =====
	local chainLinksFolder = Instance.new("Folder")
	chainLinksFolder.Name = "SwingChainLinks"
	chainLinksFolder.Parent = parentFolder

	local function buildChainSide(anchor: BasePart, seatAttachment: Attachment, sideName: string)
		-- Reconstructs this side's REFERENCE-pose seat point (theta=0) from
		-- the attachment's own local offset, the same seatHalfWidth used to
		-- place that attachment above -- one source of truth, not a second
		-- copy of the offset.
		local seatTopPoint = referenceSeatPosition + Vector3.new(seatAttachment.Position.X, seatThickness / 2, 0)

		if visual.chainStyle == "Energy" then
			local anchorAttachment = Instance.new("Attachment")
			anchorAttachment.Name = "ChainTopAttachment"
			anchorAttachment.Parent = anchor

			local beam = Instance.new("Beam")
			beam.Name = "EnergyTether" .. sideName
			beam.Attachment0 = anchorAttachment
			beam.Attachment1 = seatAttachment
			beam.Color = ColorSequence.new(chainSeatColor)
			beam.LightEmission = 1
			beam.Width0 = postThickness * 0.4
			beam.Width1 = postThickness * 0.22
			beam.FaceCamera = true
			beam.Parent = anchor
		else
			local topPoint = anchor.Position
			local count = math.max(1, visual.chainLinkCount)
			local chainThickness = if visual.chainStyle == "Rod" then postThickness * 0.35 else postThickness * 0.22
			for i = 1, count do
				local segStart = topPoint:Lerp(seatTopPoint, (i - 1) / count)
				local segEnd = topPoint:Lerp(seatTopPoint, i / count)
				local link: Part
				local twisted = visual.chainStyle == "Chain" and i % 2 == 0
				if visual.chainStyle == "Chain" then
					local cf, length = cframeAlongY(segStart, segEnd)
					if twisted then
						cf = cf * CFrame.Angles(0, math.rad(90), 0)
					end
					link = newPart(Enum.PartType.Block, Vector3.new(chainThickness, length, chainThickness * 0.5), cf, chainSeatMaterial, chainSeatColor, sideName .. "ChainLink" .. i, chainLinksFolder, chainSeatReflectance)
				else
					link = newRod(segStart, segEnd, chainThickness, Enum.PartType.Cylinder, chainSeatMaterial, chainSeatColor, sideName .. "ChainLink" .. i, chainLinksFolder, chainSeatReflectance)
				end
				link:SetAttribute("ChainIndex", i)
				link:SetAttribute("Side", sideName)
				-- Read back every frame by LaunchClient's repositionChainLinks --
				-- that function recomputes each link's CFrame from scratch, so the
				-- alternating "Chain" twist has to be stored here rather than
				-- assumed, or it would be lost the instant the client starts
				-- repositioning links.
				link:SetAttribute("Twist90", twisted)
			end
		end
	end

	buildChainSide(chainAnchorLeft, chainSeatAttachmentLeft, "Left")
	buildChainSide(chainAnchorRight, chainSeatAttachmentRight, "Right")
end

return SwingBuilder
