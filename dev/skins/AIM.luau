--!strict
-- AIM.luau -- POINTS THE EDIT CAMERA AT ONE SLIME IN A LINEUP, HEAD-ON, AT THE
-- DISTANCE THE PATTERN WAS CALIBRATED FOR.
--
-- Set P.INDEX, paste the whole file into the Studio command bar, then capture.
-- One subject per paste, because the screenshot is taken from outside Studio and
-- the camera has to be standing still when it happens. P.INDEX = 0 puts
-- everything back. No other file needs to be present.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). Same
-- standing as the BUILD_ and VERIFY_ scripts beside it.
--
-- IF THE STUDIO BRIDGE WILL NOT ANSWER, read dev/README.md BEFORE touching the
-- plugin. "Studio plugin connection timeout" usually does NOT mean the plugin is
-- dead -- with several sessions open there are several MCP servers, and yours may
-- simply not be the one Studio attached to.
--
-- ============================ WHAT THIS IS FOR =============================
--
-- A LINEUP IS ONLY A COMPARISON IF EVERY SUBJECT IS SHOT THE SAME WAY. Framing
-- by hand does not survive the tenth slime, let alone next week's rebuild: the
-- distance drifts, the yaw drifts, and then a pattern looks better for being
-- nearer or three-quarter on rather than for being a better pattern. That is the
-- same failure the rigs already refuse on white fraction, one step further down
-- the pipe.
--
-- THE DISTANCE IS NOT A TASTE DECISION. EXPLORE_PATTERNS and BUILD_SKINS both
-- calibrate against VIEW_DISTANCE = 40 studs at VIEW_FOV_DEG = 70: that is where
-- the 8 px minimum-feature floor is asserted, so it is the only distance at
-- which what you see is what was checked. P.DISTANCE and P.FOV BELONG TO THOSE
-- SCRIPTS -- if they move there, move them here, or the screenshots stop being
-- evidence about the thing that was measured.
--
-- HEAD-ON IS TAKEN FROM THE FACE, NOT DECLARED. The whole point of the
-- face-aligned patterns is that the body has a front, so a fixed world yaw would
-- be looking at an arbitrary side of it. The direction comes from where the eye
-- part actually sits, exactly as EXPLORE_PATTERNS derives its own frame, so this
-- stays correct if the lineup is rebuilt at a different yaw or a different
-- origin. It is flattened to the horizontal for the same reason the rig
-- flattens: an animal's front is horizontal even when its face tips.
--
-- ===================== THE TWO THINGS THAT COST A SESSION ==================
--
-- SCRIPTABLE, OR THE ORIENTATION IS SILENTLY DISCARDED. Studio's edit-mode
-- navigation owns the viewport camera and re-asserts its own rotation every
-- frame. Writing CFrame from a plugin LOOKS like it worked -- read the property
-- straight back and you get your own value -- while the viewport keeps
-- rendering from the direction the user last dragged to. Position survives;
-- rotation does not. Setting CameraType to Scriptable first is what makes the
-- controller let go, and P.INDEX = 0 hands it back afterwards. WITHOUT THE
-- HANDBACK THE VIEWPORT IS LEFT UNNAVIGABLE, which is a nasty thing to leave
-- behind, so release when you are done.
--
-- The tell, if this ever regresses: cam:WorldToViewportPoint(centre) comes back
-- with a NEGATIVE depth -- the subject is behind a camera that is standing in
-- exactly the right place. Trust that number over the screenshot, and over the
-- CFrame you just wrote.
--
-- ISOLATION, BECAUSE THE NEIGHBOUR IS NEARER THAN THE SUBJECT. The lineup runs
-- along one axis and the faces point about 38 degrees off it, so a head-on
-- camera stands off to the side and the next slime along sits ~32 studs away
-- against the subject's 40. It renders BIGGER than the thing being judged and
-- lands beside it in frame. Hiding the siblings is therefore not tidying, it is
-- the difference between a comparison and a distraction. Original transparency
-- is remembered per part in an AimT0 attribute and restored on release, so this
-- is reversible even if you never rebuild the lineup.
--
-- IT IS NOT PatternLab-SPECIFIC. Any Model whose children carry an Index
-- attribute works; BodyCentre is used when present and the bounding box stands
-- in when it is not, so this also aims at a lineup some other script built.
--
-- FRAME FILL IS REPORTED so a silent change is visible. If a later rebuild
-- scales the body, the number moves and the shots stop being comparable to the
-- ones already taken -- which is worth knowing at capture time, not afterwards.
--
-- REVERSAL: P.INDEX = 0 and paste again. Restores CameraType and every part's
-- transparency; moves nothing else, and never touched the slimes' geometry.
-- ===========================================================================

local P = {
	-- Which subject. A driver substitutes this per shot; by hand, edit and
	-- re-paste. 1-based, matching the Index attribute the rigs write.
	-- 0 = RELEASE: give the camera back and unhide everything.
	INDEX = 1,

	ROOT_NAME = "PatternLab",

	-- Both of these belong to the build rig -- see above before changing either.
	DISTANCE = 40,
	FOV = 70,

	-- Hide the other variants while shooting. See "ISOLATION" above.
	ISOLATE = true,

	-- Any of these, first match wins: the part that says where the face is.
	FACE_PARTS = { "eye_dark", "eye_white", "blush" },
}

-- Transparency is remembered on the part itself rather than in a table, so a
-- release works even from a fresh paste that never saw the hide.
local function setShown(m: Instance, shown: boolean)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local t0 = d:GetAttribute("AimT0")
			if shown then
				if t0 ~= nil then
					d.Transparency = t0 :: number
					d:SetAttribute("AimT0", nil)
				end
			else
				if t0 == nil then d:SetAttribute("AimT0", d.Transparency) end
				d.Transparency = 1
			end
		end
	end
end

local function run(): string
	local root = workspace:FindFirstChild(P.ROOT_NAME)
	assert(root, string.format(
		"[Aim] workspace.%s is not there -- build the lineup first", P.ROOT_NAME))
	local cam = workspace.CurrentCamera

	if P.INDEX == 0 then
		for _, c in ipairs(root:GetChildren()) do setShown(c, true) end
		cam.CameraType = Enum.CameraType.Fixed
		local out = "[Aim] released: camera handed back to Studio, all variants shown"
		print(out)
		return out
	end

	local subject: Model? = nil
	local indexed: { Model } = {}
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Index") ~= nil then
			table.insert(indexed, c)
			if c:GetAttribute("Index") == P.INDEX then subject = c end
		end
	end
	assert(subject, string.format(
		"[Aim] no child of %s carries Index %d (%d indexed children present)",
		P.ROOT_NAME, P.INDEX, #indexed))
	local m = subject :: Model

	-- BodyCentre is what the rig measured; the bounding box is the fallback so
	-- this works on a lineup that did not write one.
	local boxCF, extents = m:GetBoundingBox()
	local stored = m:GetAttribute("BodyCentre")
	local at = typeof(stored) == "Vector3" and (stored :: Vector3) or boxCF.Position

	-- forward = centre -> face, flattened
	local face: BasePart? = nil
	for _, name in ipairs(P.FACE_PARTS) do
		local p = m:FindFirstChild(name)
		if p and p:IsA("BasePart") then face = p break end
	end
	assert(face, string.format(
		"[Aim] %s has none of {%s}, so there is no way to tell which side is the front",
		m.Name, table.concat(P.FACE_PARTS, ", ")))
	local d = (face :: BasePart).Position - at
	d = Vector3.new(d.X, 0, d.Z)
	assert(d.Magnitude > 1e-4, string.format(
		"[Aim] %s's face part sits directly above the centre -- no facing direction",
		m.Name))
	local fwd = d.Unit

	for _, c in ipairs(indexed) do
		setShown(c, (not P.ISOLATE) or c == m)
	end

	-- Scriptable BEFORE the write, or the rotation is discarded. See above.
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = P.FOV
	cam.CFrame = CFrame.lookAt(at + fwd * P.DISTANCE, at)

	-- The check that actually catches the failure: where does the subject land?
	local v = cam:WorldToViewportPoint(at)
	local vp = cam.ViewportSize
	assert(v.Z > 0, string.format(
		"[Aim] subject is BEHIND the camera (depth %.1f) -- the viewport kept its own "
			.. "rotation; CameraType is %s", v.Z, tostring(cam.CameraType)))
	local offCentre = math.max(math.abs(v.X - vp.X / 2), math.abs(v.Y - vp.Y / 2))
	assert(offCentre < 2, string.format(
		"[Aim] subject projects to %.0f,%.0f but the frame centre is %.0f,%.0f",
		v.X, v.Y, vp.X / 2, vp.Y / 2))

	-- FieldOfView is the VERTICAL angle, so this is fill against frame height
	local frameStuds = 2 * P.DISTANCE * math.tan(math.rad(P.FOV) / 2)
	local out = string.format(
		"[Aim] %02d %s | %.1f studs, fov %d | centred %.0f,%.0f | %.0f%% of frame height%s",
		P.INDEX, tostring(m:GetAttribute("Variant") or m.Name), v.Z, P.FOV, v.X, v.Y,
		(extents.Y / frameStuds) * 100, P.ISOLATE and " | isolated" or "")
	print(out)
	return out
end

return run()
