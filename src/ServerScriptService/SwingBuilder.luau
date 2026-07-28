--!strict
-- Builds the swing structure -- posts, beam, caps, bracing, ground pads,
-- seat, and chain -- from SwingTierVisuals data, and completely REBUILDS it
-- (destroy everything, construct fresh) whenever the current rider's tier
-- changes. Each of the four tier BANDS (see SwingTierVisuals) produces a
-- genuinely different arrangement of parts -- different post angle, shape,
-- bracing, seat style, chain style -- not the same four boxes recoloured.
--
-- WHAT NEVER MOVES: SwingPivot (a separate, pre-placed, invisible part in
-- default.project.json) is never touched here, and LaunchConfig.SWING_ROPE_
-- LENGTH is only ever READ, never derived from anything this file builds.
-- Every part this file creates is either purely decorative (posts, beam,
-- bracing, caps, pads, chain) or a REFERENCE POSE for the seat/chain (built
-- at the swing's theta=0 rest position, corrected to the true live position
-- on the very next client RenderStepped -- see LaunchClient.client.luau).
-- Nothing here can feed back into the seat's actual swept position or the
-- scoring math that depends on it.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local SwingTierVisuals = require(ReplicatedStorage.Config.SwingTierVisuals)

local SwingBuilder = {}

local swingPivot = Workspace:WaitForChild("SwingPivot") :: BasePart
local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart
-- Ground level -- the baseplate's own top surface, same reasoning
-- BaseGeometry/RunwayGeometry already use elsewhere in this project.
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

local structureFolder = Instance.new("Folder")
structureFolder.Name = "SwingStructure"
structureFolder.Parent = Workspace

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
	return Enum.Material.Neon, visual.glowColor
end

function SwingBuilder.build(tier: number)
	structureFolder:ClearAllChildren()

	local visual = SwingTierVisuals.forTier(tier)
	local scale = visual.scale
	local postHeight = SwingTierVisuals.BASE_POST_HEIGHT * scale
	local standHalfWidth = SwingTierVisuals.BASE_STAND_HALF_WIDTH * scale
	local postThickness = SwingTierVisuals.BASE_POST_THICKNESS * scale
	local beamThickness = SwingTierVisuals.BASE_BEAM_THICKNESS * scale
	local beamOverhang = SwingTierVisuals.BASE_BEAM_OVERHANG * scale

	local centerX = swingPivot.Position.X
	local centerZ = swingPivot.Position.Z
	local postTopY = groundY + postHeight

	-- A-frame splay: the post's TOP stays fixed under the beam; only the
	-- GROUND contact point moves outward, exactly like a real A-frame leg.
	local postAngle = math.rad(visual.postAngleDegrees)
	local splay = postHeight * math.tan(postAngle)

	local post1Top = Vector3.new(centerX - standHalfWidth, postTopY, centerZ)
	local post1Bottom = Vector3.new(centerX - standHalfWidth - splay, groundY, centerZ)
	local post2Top = Vector3.new(centerX + standHalfWidth, postTopY, centerZ)
	local post2Bottom = Vector3.new(centerX + standHalfWidth + splay, groundY, centerZ)

	-- ===== Ground contact: no structure floating bare on the grass =====
	local padMaterial, padColor = groundPadMaterialColor(visual)
	local padDiameter = postThickness * 2.4
	local padThickness = math.max(0.6, postThickness * 0.3)
	local function buildGroundPad(footPoint: Vector3, name: string)
		local center = footPoint + Vector3.new(0, padThickness / 2, 0)
		if visual.groundPad == "Metal" or visual.groundPad == "Glow" then
			local cf = cframeFacingAlongX(center, Vector3.new(0, 1, 0))
			newPart(Enum.PartType.Cylinder, Vector3.new(padThickness, padDiameter, padDiameter), cf, padMaterial, padColor, name, structureFolder)
		else
			newPart(Enum.PartType.Block, Vector3.new(padDiameter, padThickness, padDiameter), CFrame.new(center), padMaterial, padColor, name, structureFolder)
		end
	end
	buildGroundPad(post1Bottom, "GroundPad1")
	buildGroundPad(post2Bottom, "GroundPad2")

	-- ===== Posts =====
	newRod(post1Bottom, post1Top, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Post1", structureFolder)
	newRod(post2Bottom, post2Top, postThickness, visual.postShape, visual.frameMaterial, visual.frameColor, "Post2", structureFolder)

	-- ===== Caps: NO bare box ends anywhere -- every post top and beam end
	-- gets a part sized larger than its cross-section. =====
	local capSize = postThickness * 1.5
	local function buildCap(point: Vector3, outward: Vector3, name: string)
		if visual.capShape == Enum.PartType.Ball then
			newPart(Enum.PartType.Ball, Vector3.new(capSize, capSize, capSize), CFrame.new(point), visual.frameMaterial, visual.frameColor, name, structureFolder)
		elseif visual.capShape == Enum.PartType.Cylinder then
			local cf = cframeFacingAlongX(point, outward)
			newPart(Enum.PartType.Cylinder, Vector3.new(capSize * 0.5, capSize, capSize), cf, visual.frameMaterial, visual.frameColor, name, structureFolder)
		else
			newPart(Enum.PartType.Block, Vector3.new(capSize, capSize * 0.6, capSize), CFrame.new(point), visual.frameMaterial, visual.frameColor, name, structureFolder)
		end
	end
	buildCap(post1Top, Vector3.new(0, 1, 0), "Post1Cap")
	buildCap(post2Top, Vector3.new(0, 1, 0), "Post2Cap")

	-- ===== Beam -- overhangs the posts slightly, per real playground/
	-- industrial frame proportion =====
	local beamStart = Vector3.new(post1Top.X - beamOverhang, postTopY, centerZ)
	local beamEnd = Vector3.new(post2Top.X + beamOverhang, postTopY, centerZ)
	newRod(beamStart, beamEnd, beamThickness, visual.beamShape, visual.frameMaterial, visual.frameColor, "Beam", structureFolder)
	buildCap(beamStart, Vector3.new(1, 0, 0), "BeamCap1")
	buildCap(beamEnd, Vector3.new(1, 0, 0), "BeamCap2")

	-- ===== Bracing -- this alone transforms the silhouette. ARung is a
	-- classic playground A-frame crossbar; the others are diagonal
	-- post-to-beam gussets/struts, varied shape (Wedge) and material by band. =====
	if visual.braceStyle == "ARung" then
		local p1 = pointAlongPost(post1Bottom, post1Top, 0.45)
		local p2 = pointAlongPost(post2Bottom, post2Top, 0.45)
		newRod(p1, p2, postThickness * 0.5, Enum.PartType.Cylinder, visual.frameMaterial, visual.frameColor, "Rung", structureFolder)
	else
		local isStrut = visual.braceStyle == "Strut"
		local braceThickness = postThickness * (if isStrut then 0.35 else 0.55)
		local braceMaterial = if isStrut then Enum.Material.Neon else visual.trimMaterial
		local braceColor = if isStrut then visual.glowColor else visual.trimColor
		local count = math.max(1, visual.braceCount)
		for i = 1, count do
			local fromPost1 = (i % 2 == 1)
			local lowPoint = pointAlongPost(if fromPost1 then post1Bottom else post2Bottom, if fromPost1 then post1Top else post2Top, 0.12)
			local highPoint = Vector3.new(centerX, postTopY - beamThickness, centerZ)
			local braceCFrame, braceLength = cframeAlongY(lowPoint, highPoint)
			newPart(
				Enum.PartType.Wedge,
				Vector3.new(braceThickness, braceLength, braceThickness),
				braceCFrame,
				braceMaterial,
				braceColor,
				"Brace" .. i,
				structureFolder
			)
		end
	end

	-- ===== Trim: hazard stripes (industrial), glow accent strips
	-- (engineered/spectacular), or simple corner brackets (playground) --
	-- never the same material as the frame, per "surface variety." =====
	if visual.hazardStripes then
		local stripeCount = 6
		for i = 0, stripeCount - 1 do
			local segStart = beamStart:Lerp(beamEnd, i / stripeCount)
			local segEnd = beamStart:Lerp(beamEnd, (i + 1) / stripeCount)
			local stripeColor = if i % 2 == 0 then Color3.new(0.05, 0.05, 0.05) else visual.trimColor
			newRod(segStart, segEnd, beamThickness * 1.2, Enum.PartType.Cylinder, visual.trimMaterial, stripeColor, "HazardStripe" .. i, structureFolder)
		end
	elseif visual.glowAccent then
		local underOffset = Vector3.new(0, -beamThickness * 0.75, 0)
		newRod(beamStart + underOffset, beamEnd + underOffset, beamThickness * 0.22, Enum.PartType.Cylinder, Enum.Material.Neon, visual.glowColor, "GlowTrimBeam", structureFolder)
		newRod(pointAlongPost(post1Bottom, post1Top, 0.15), post1Top - Vector3.new(0, postThickness, 0), postThickness * 0.18, Enum.PartType.Cylinder, Enum.Material.Neon, visual.glowColor, "GlowTrimPost1", structureFolder)
		newRod(pointAlongPost(post2Bottom, post2Top, 0.15), post2Top - Vector3.new(0, postThickness, 0), postThickness * 0.18, Enum.PartType.Cylinder, Enum.Material.Neon, visual.glowColor, "GlowTrimPost2", structureFolder)
	else
		local bracketSize = postThickness * 1.3
		local p1 = pointAlongPost(post1Bottom, post1Top, 0.45)
		local p2 = pointAlongPost(post2Bottom, post2Top, 0.45)
		newPart(Enum.PartType.Block, Vector3.new(bracketSize, bracketSize * 0.5, bracketSize), CFrame.new(p1), visual.trimMaterial, visual.trimColor, "Bracket1", structureFolder)
		newPart(Enum.PartType.Block, Vector3.new(bracketSize, bracketSize * 0.5, bracketSize), CFrame.new(p2), visual.trimMaterial, visual.trimColor, "Bracket2", structureFolder)
	end

	-- ===== Chain anchor: a tiny invisible fixed point just under the beam,
	-- read every frame by the client (discrete chain links) or by the
	-- Energy Beam's own Attachment (auto-tracking, no script needed). =====
	local chainAnchor = newPart(
		Enum.PartType.Block,
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(centerX, postTopY - beamThickness, centerZ),
		Enum.Material.Plastic,
		Color3.new(0, 0, 0),
		"SwingChainAnchor",
		structureFolder
	)
	chainAnchor.Transparency = 1

	-- ===== Seat: a REFERENCE pose at the swing's theta=0 rest position --
	-- corrected to the true live position on the very next client
	-- RenderStepped (see LaunchClient.client.luau), same as it always was.
	-- Built as a Model (PrimaryPart = SeatCore) so a multi-part seat moves
	-- rigidly as one unit via Model:PivotTo, same mechanism the character
	-- itself already uses. =====
	local referenceSeatPosition = swingPivot.Position + Vector3.new(0, -LaunchConfig.SWING_ROPE_LENGTH, 0)

	local seatModel = Instance.new("Model")
	seatModel.Name = "SwingSeat"

	local seatWidth = 4 * scale
	local seatDepth = 3 * scale
	local seatThickness = 0.5 * scale

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

	if visual.seatStyle == "Plank" then
		local knotSize = math.max(0.4, 0.5 * scale)
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

	seatModel.Parent = structureFolder

	-- ===== Chain / rope / rod / energy tether =====
	local chainLinksFolder = Instance.new("Folder")
	chainLinksFolder.Name = "SwingChainLinks"
	chainLinksFolder.Parent = structureFolder

	local seatTopPoint = referenceSeatPosition + Vector3.new(0, seatThickness / 2, 0)

	if visual.chainStyle == "Energy" then
		local anchorAttachment = Instance.new("Attachment")
		anchorAttachment.Name = "ChainTopAttachment"
		anchorAttachment.Parent = chainAnchor

		local seatAttachment = Instance.new("Attachment")
		seatAttachment.Name = "ChainBottomAttachment"
		seatAttachment.Position = Vector3.new(0, seatThickness / 2, 0)
		seatAttachment.Parent = seatCore

		local beam = Instance.new("Beam")
		beam.Name = "EnergyTether"
		beam.Attachment0 = anchorAttachment
		beam.Attachment1 = seatAttachment
		beam.Color = ColorSequence.new(visual.chainColor)
		beam.LightEmission = 1
		beam.Width0 = postThickness * 0.4
		beam.Width1 = postThickness * 0.22
		beam.FaceCamera = true
		beam.Parent = chainAnchor
	else
		local topPoint = chainAnchor.Position
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
				link = newPart(Enum.PartType.Block, Vector3.new(chainThickness, length, chainThickness * 0.5), cf, visual.chainMaterial, visual.chainColor, "ChainLink" .. i, chainLinksFolder)
			else
				link = newRod(segStart, segEnd, chainThickness, Enum.PartType.Cylinder, visual.chainMaterial, visual.chainColor, "ChainLink" .. i, chainLinksFolder)
			end
			link:SetAttribute("ChainIndex", i)
			-- Read back every frame by LaunchClient's repositionChainLinks --
			-- that function recomputes each link's CFrame from scratch, so the
			-- alternating "Chain" twist has to be stored here rather than
			-- assumed, or it would be lost the instant the client starts
			-- repositioning links.
			link:SetAttribute("Twist90", twisted)
		end
	end
end

return SwingBuilder
