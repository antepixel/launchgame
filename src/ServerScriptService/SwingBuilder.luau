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
-- There is no brace code path any more -- the A-frame's own two-legs-
-- per-side geometry IS the bracing.
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
-- (posts, beam, bracing, caps, pads, chain) or a REFERENCE POSE for the
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
	parent: Instance
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
	parent: Instance
): Part
	if shape == Enum.PartType.Cylinder then
		local cf, length = cframeAlongX(pointA, pointB)
		return newPart(shape, Vector3.new(length, thickness, thickness), cf, material, color, name, parent)
	end
	local cf, length = cframeAlongY(pointA, pointB)
	return newPart(shape, Vector3.new(thickness, length, thickness), cf, material, color, name, parent)
end

local function groundPadMaterialColor(visual: SwingTierVisuals.TierVisual): (Enum.Material, Color3)
	if visual.groundPad == "Dirt" then
		return Enum.Material.Ground, Color3.fromRGB(90, 65, 40)
	elseif visual.groundPad == "Concrete" then
		return Enum.Material.Concrete, Color3.fromRGB(120, 120, 122)
	elseif visual.groundPad == "Metal" then
		return Enum.Material.DiamondPlate, Color3.fromRGB(150, 150, 158)
	end
	-- "Glow" pads keep the tier's own glowColor (per-tier colour preserved)
	-- but on a SOLID material -- Neon here made the ground pad itself part
	-- of "everything glowing solid", the same over-application this pass
	-- fixes for the frame; the glow accent trim (GlowTrimBeam/GlowTrimLeg,
	-- still hardcoded Neon just below) is where the glow is supposed to
	-- live.
	return Enum.Material.DiamondPlate, visual.glowColor
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
		if visual.groundPad == "Metal" or visual.groundPad == "Glow" then
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
	-- separate brace code path any more (see the written report). =====
	newRod(foot1Front, apex1, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg1Front", parentFolder)
	newRod(foot1Back, apex1, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg1Back", parentFolder)
	newRod(foot2Front, apex2, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg2Front", parentFolder)
	newRod(foot2Back, apex2, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Leg2Back", parentFolder)

	-- ===== Caps: NO bare box ends anywhere -- every apex and beam end gets
	-- a part sized larger than its cross-section. =====
	local capSize = postThickness * 1.5
	local function buildCap(point: Vector3, outward: Vector3, name: string)
		if visual.capShape == Enum.PartType.Ball then
			newPart(Enum.PartType.Ball, Vector3.new(capSize, capSize, capSize), CFrame.new(point), visual.frameMaterial, visual.frameColor, name, parentFolder)
		elseif visual.capShape == Enum.PartType.Cylinder then
			local cf = cframeFacingAlongX(point, outward)
			newPart(Enum.PartType.Cylinder, Vector3.new(capSize * 0.5, capSize, capSize), cf, visual.frameMaterial, visual.frameColor, name, parentFolder)
		else
			newPart(Enum.PartType.Block, Vector3.new(capSize, capSize * 0.6, capSize), CFrame.new(point), visual.frameMaterial, visual.frameColor, name, parentFolder)
		end
	end
	buildCap(apex1, Vector3.new(0, 1, 0), "Apex1Cap")
	buildCap(apex2, Vector3.new(0, 1, 0), "Apex2Cap")

	-- ===== Beam -- overhangs each apex slightly, per real playground/
	-- industrial frame proportion =====
	local beamStart = Vector3.new(apex1.X - beamOverhang, postTopY, centerZ)
	local beamEnd = Vector3.new(apex2.X + beamOverhang, postTopY, centerZ)
	newRod(beamStart, beamEnd, beamThickness, visual.beamShape, visual.frameMaterial, visual.frameColor, "Beam", parentFolder)
	buildCap(beamStart, Vector3.new(1, 0, 0), "BeamCap1")
	buildCap(beamEnd, Vector3.new(1, 0, 0), "BeamCap2")

	-- ===== Trim: hazard stripes (industrial), glow accent strips
	-- (engineered/spectacular), or simple corner brackets (playground) --
	-- never the same material as the frame, per "surface variety." Applied
	-- to all FOUR legs now (used to be two posts) for even coverage. =====
	if visual.hazardStripes then
		local stripeCount = 6
		for i = 0, stripeCount - 1 do
			local segStart = beamStart:Lerp(beamEnd, i / stripeCount)
			local segEnd = beamStart:Lerp(beamEnd, (i + 1) / stripeCount)
			local stripeColor = if i % 2 == 0 then Color3.new(0.05, 0.05, 0.05) else visual.trimColor
			newRod(segStart, segEnd, beamThickness * 1.2, Enum.PartType.Cylinder, visual.trimMaterial, stripeColor, "HazardStripe" .. i, parentFolder)
		end
	elseif visual.glowAccent then
		local underOffset = Vector3.new(0, -beamThickness * 0.75, 0)
		newRod(beamStart + underOffset, beamEnd + underOffset, beamThickness * 0.22, Enum.PartType.Cylinder, Enum.Material.Neon, visual.glowColor, "GlowTrimBeam", parentFolder)
		local function glowTrimLeg(footPoint: Vector3, apex: Vector3, name: string)
			newRod(pointAlongPost(footPoint, apex, 0.15), apex - Vector3.new(0, postThickness, 0), postThickness * 0.18, Enum.PartType.Cylinder, Enum.Material.Neon, visual.glowColor, name, parentFolder)
		end
		glowTrimLeg(foot1Front, apex1, "GlowTrimLeg1Front")
		glowTrimLeg(foot1Back, apex1, "GlowTrimLeg1Back")
		glowTrimLeg(foot2Front, apex2, "GlowTrimLeg2Front")
		glowTrimLeg(foot2Back, apex2, "GlowTrimLeg2Back")
	else
		local bracketSize = postThickness * 1.3
		local function buildBracket(footPoint: Vector3, apex: Vector3, name: string)
			newPart(Enum.PartType.Block, Vector3.new(bracketSize, bracketSize * 0.5, bracketSize), CFrame.new(pointAlongPost(footPoint, apex, 0.45)), visual.trimMaterial, visual.trimColor, name, parentFolder)
		end
		buildBracket(foot1Front, apex1, "Bracket1Front")
		buildBracket(foot1Back, apex1, "Bracket1Back")
		buildBracket(foot2Front, apex2, "Bracket2Front")
		buildBracket(foot2Back, apex2, "Bracket2Back")
	end

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

	local seatModel = Instance.new("Model")
	seatModel.Name = "SwingSeat"

	local seatCore = newPart(
		Enum.PartType.Block,
		Vector3.new(seatWidth, seatThickness, seatDepth),
		CFrame.new(referenceSeatPosition),
		visual.seatMaterial,
		visual.seatColor,
		"SeatCore",
		seatModel
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

	if visual.seatStyle == "Plank" then
		local knotSize = math.max(0.4, 0.5 * footprintScale)
		newPart(
			Enum.PartType.Ball,
			Vector3.new(knotSize, knotSize, knotSize),
			CFrame.new(referenceSeatPosition + Vector3.new(-seatWidth / 2 + knotSize * 0.5, seatThickness, -seatDepth / 2 + knotSize * 0.5)),
			visual.chainMaterial,
			visual.chainColor,
			"SeatKnot1",
			seatModel
		)
		newPart(
			Enum.PartType.Ball,
			Vector3.new(knotSize, knotSize, knotSize),
			CFrame.new(referenceSeatPosition + Vector3.new(seatWidth / 2 - knotSize * 0.5, seatThickness, -seatDepth / 2 + knotSize * 0.5)),
			visual.chainMaterial,
			visual.chainColor,
			"SeatKnot2",
			seatModel
		)
	elseif visual.seatStyle == "Bucket" or visual.seatStyle == "Contoured" then
		local backHeight = seatThickness * (if visual.seatStyle == "Contoured" then 3.5 else 3)
		newPart(
			Enum.PartType.Block,
			Vector3.new(seatWidth, backHeight, seatThickness),
			CFrame.new(referenceSeatPosition + Vector3.new(0, backHeight / 2, -seatDepth / 2)),
			visual.seatMaterial,
			visual.seatColor,
			"SeatBack",
			seatModel
		)
		newPart(
			Enum.PartType.Block,
			Vector3.new(seatThickness, backHeight * 0.6, seatDepth),
			CFrame.new(referenceSeatPosition + Vector3.new(-seatWidth / 2, backHeight * 0.3, 0)),
			visual.trimMaterial,
			visual.trimColor,
			"SeatRail1",
			seatModel
		)
		newPart(
			Enum.PartType.Block,
			Vector3.new(seatThickness, backHeight * 0.6, seatDepth),
			CFrame.new(referenceSeatPosition + Vector3.new(seatWidth / 2, backHeight * 0.3, 0)),
			visual.trimMaterial,
			visual.trimColor,
			"SeatRail2",
			seatModel
		)
	else -- "Floating"
		newPart(
			Enum.PartType.Block,
			Vector3.new(seatThickness * 0.7, seatThickness * 0.3, seatDepth * 0.85),
			CFrame.new(referenceSeatPosition + Vector3.new(-seatWidth / 2 * 0.6, -seatThickness * 0.6, 0)),
			visual.trimMaterial,
			visual.trimColor,
			"SeatUnderlight1",
			seatModel
		)
		newPart(
			Enum.PartType.Block,
			Vector3.new(seatThickness * 0.7, seatThickness * 0.3, seatDepth * 0.85),
			CFrame.new(referenceSeatPosition + Vector3.new(seatWidth / 2 * 0.6, -seatThickness * 0.6, 0)),
			visual.trimMaterial,
			visual.trimColor,
			"SeatUnderlight2",
			seatModel
		)
	end

	seatModel.Parent = parentFolder

	-- ===== Chain anchors: two tiny invisible fixed points just under the
	-- beam, one per side, offset by the SAME seatHalfWidth the two seat
	-- attachments above use -- so each tether's top and bottom line up
	-- directly above/below each other, parallel, seatHalfWidth off centre,
	-- instead of both tethers sharing one dead-centre anchor AND one
	-- dead-centre seat point (which is what made this a single line, not
	-- two, before this pass -- see the written report). =====
	local function buildChainAnchor(name: string, xOffset: number): BasePart
		local anchor = newPart(
			Enum.PartType.Block,
			Vector3.new(0.2, 0.2, 0.2),
			CFrame.new(centerX + xOffset, postTopY - beamThickness, centerZ),
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
			beam.Color = ColorSequence.new(visual.chainColor)
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
					link = newPart(Enum.PartType.Block, Vector3.new(chainThickness, length, chainThickness * 0.5), cf, visual.chainMaterial, visual.chainColor, sideName .. "ChainLink" .. i, chainLinksFolder)
				else
					link = newRod(segStart, segEnd, chainThickness, Enum.PartType.Cylinder, visual.chainMaterial, visual.chainColor, sideName .. "ChainLink" .. i, chainLinksFolder)
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
