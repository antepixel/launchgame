--!strict
-- BUILD_LEGENDARY_PAINT.luau -- THE TOP RUNG AS SIX SKINS, NOT SIX ATTACHMENTS.
--
-- Paste the whole file into the Studio command bar and it builds
-- workspace.LegendaryPaint from nothing: one cell per design, each on its own
-- ground, at one of the two framings the game actually uses, WITH THE FACE ON.
-- No other file needs to be present.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). Same
-- standing as BUILD_SKINS, BUILD_TIERMARKS, BUILD_DIVINE and EXPLORE_PATTERNS
-- beside it.
--
-- ================== WHY THE GEOMETRY DIRECTION IS OUT ======================
--
-- BUILD_LEGENDARY.luau next to this file is the whole geometry attempt --
-- plume, crown, regalia, antennae, halo, coronet, and nine cut directions kept
-- as code. It is left buildable because the measurements in it are real. It is
-- not the direction, and the reason is one sentence:
--
--     ADDING A THING TO A SLIME GIVES YOU A BLUE SLIME WITH A SPIKE ON IT.
--     IT DOES NOT GIVE YOU A DISTINCTIVE SLIME.
--
-- Three consequences, and each one was visible in the last round's frames
-- before it was argued:
--
--   THE ADDITION READS AS AN OBJECT, NOT AS A CREATURE. A horn, a bead and a
--   drop are all things that could be set down on a table beside the slime.
--   The body underneath was untouched in every candidate -- literally the
--   Common skin -- so what the set actually varied was the hat.
--
--   ATTACHED OBJECTS ARE MUTATION TERRITORY, which was ruled earlier and which
--   the geometry file walked straight back into. A tier is a skin. A thing
--   stuck on the skin is a different axis and it is spoken for.
--
--   WHAT MAKES A SLIME DESIRABLE IS HOW IT LOOKS -- pattern and colour. That is
--   what a player is choosing between in an inventory grid, and it is the axis
--   the four rungs below already run on. Legendary does not need to leave that
--   axis to be the top of it; it needs to be unmistakably further along it.
--
-- SO: NO GEOMETRY IN THIS TIER. Six designs, each a pattern-and-colour
-- combination, each with its own identity.
--
-- ==================== WHAT THE SHARED KIND IS INSTEAD ======================
--
-- Below Legendary a tier is ONE pattern shown across six hues, and every slime
-- in the game is the same sentence: a <hue> slime with white markings. Common
-- has no markings, Uncommon has a blaze, Rare has four spirals, Epic has
-- twenty-four dots. One colour, plus the ladder's one accent.
--
--     A LEGENDARY IS A TWO-COLOUR CREATURE.
--     EVERYTHING BELOW IT IS A ONE-COLOUR CREATURE WITH MARKINGS.
--
-- That is the kind, and it is a change of category rather than a change of
-- degree -- which is what a tier step above a settled four-rung ladder has to
-- be. It is held by three rules, and all three are measured in this file
-- rather than asserted in a comment:
--
--   1. BOTH COLOURS ARE CHROMATIC. Neither of a Legendary's two colours is the
--      ladder's white (252, 251, 247). This is the rule that makes the tier
--      unreachable from below: the lower rungs' entire identity is hue-plus-
--      accent, so a hue-plus-hue slime is not a louder version of one, it is a
--      different sentence. A Legendary is named by a PAIR -- "the teal and gold
--      one" -- and no slime below it can be.
--
--   2. THE SPLIT IS EVEN. Coverage is calibrated to 45% against dots24's 28%,
--      which is the boldness step, and it is the same instrument the ladder is
--      already ordered by rather than a new one. At 28% a second colour is a
--      marking on a body. At 45% neither colour is the background, and the
--      slime IS both colours. 55/45 rather than 50/50 on purpose: one colour
--      still has to be the one the reveal panel and the inventory row can
--      point at.
--
--   3. THE PAIR SEPARATES ON LUMINANCE, ON RGB, AND ON HUE. Below Legendary
--      this gate was free -- white against a saturated hue always clears it --
--      so no rig has ever had to check it. Two chromatic colours can sit on top
--      of each other and turn to mud, so it is checked here, against the worst
--      pair the ladder ALREADY SHIPS rather than against a number picked for
--      the occasion:
--          white on yellow    lum 0.161   rgb 0.767   (Uncommon..Epic, hue 4)
--
--      THE HUE TERM IS THE THIRD ONE AND IT WAS ADDED AFTER A FAILURE, which
--      is the only reason it is trustworthy. `rosette` shipped a lilac body
--      (185,140,235) with deep violet rings (60,25,110) and it read as ONE
--      COLOUR WITH TEXTURE. It passed both numbers and it passed them well:
--          rosette   lum 0.462 (2.9x the floor)   rgb 0.827 (1.08x the floor)
--      What it measures 4 DEGREES on is hue. The two colours are the same
--      violet at two brightnesses, and a colour at two brightnesses is exactly
--      what a LIGHT does to one colour -- so the eye takes the cheaper
--      explanation and sees a lit lilac slime, not a two-colour one.
--
--      THAT IS THE TERMINATOR RULE, IN COLOUR SPACE. It is the same argument
--      that killed countershade and dipped, arriving on a different axis: a
--      difference the renderer could have produced by itself is not a marking.
--      There it was "does the boundary lie where the light already puts one";
--      here it is "is the pair a difference of shade, which is all a light can
--      make". Both are the rule that a tier's identity has to be something
--      lighting cannot fake.
--
--      WHY THE OLD TWO NUMBERS COULD NOT SEE IT is structural, and it is the
--      same shape as everything else in this header. contrast() was lifted
--      from BUILD_SKINS, where the accent is ALWAYS WHITE. White has no hue, so
--      hue separation was never a variable there, and a pair of numbers that
--      never varies is a pair of numbers nobody misses. Rule 1 is what put a
--      hue on both sides of the comparison, so rule 1 is what made the third
--      number necessary. dev/README.md's rule again: when the representation
--      changes, re-derive the metric from the thing you actually care about.
--
--      THE FLOOR IS 60 DEGREES AND IT IS A GUESS IN A GAP, stated as such. The
--      evidence is one failure at 4 degrees and eight passes at 97 and above;
--      60 is comfortably clear of both and there is nothing in between to
--      calibrate on. The rig prints the number for every pair, so the next
--      failure narrows it rather than being argued about.
--
--   4. NO MIRRORED PAIR OF MARKS AT THE EYES' OWN HEIGHT. This one is a
--      PLACEMENT constraint and it is the first rule here that neither the
--      coverage gate nor the contrast gates can see: both of those ask what a
--      design is made of, and this asks where it was put.
--
--          A MARK AT THE EYES' OWN HEIGHT, MIRRORED ABOUT THE MIDLINE, IS READ
--          AS AN EYE.
--
--      `ocelli` shipped five navy rings on hot pink with two of them at 15
--      degrees elevation and 52 degrees either side of the nose. Coverage
--      44.8%, feature 37.9 px, J 0.18, lit 1.05, and all three contrast
--      numbers clear. It rendered as a FOUR-EYED SLIME: a symmetric pair of
--      round marks beside the eyes at eye height does not decorate a face, it
--      joins it, and rings do it worse than blobs because a ring with the body
--      colour in the middle is the shape of an eye.
--
--      IT IS panda's FAILURE FROM THE OTHER SIDE. panda put caps ON the eyes
--      and they merged into a mask; ocelli put them BESIDE the eyes and they
--      were recruited as more eyes. Both are the same thing: the face is a
--      strong reading and anything placed in its neighbourhood gets pulled
--      into it.
--
--      THE ZONE IS DERIVED FROM THE FACE PARTS, NOT DECLARED. FACE_PARTS
--      carries one mesh holding both eyes, so its bounding box is solved back
--      into two spheres -- half-separation 0.335 body radii, radius 0.117, at
--      0.812 forward -- which gives the eyes' own angular footprint:
--          |azimuth| <= 30.1 deg,  elevation -15.1 .. 19.9 deg
--      A mirrored pair fails when its centres sit in that elevation band AND
--      the pair reaches inside that azimuth. Measured on the three designs
--      with placed features:
--          ocelli (old)  el 15.0  approach  8.1 deg   IN BAND, INSIDE  -- fails
--          koi           el 17.5  approach 30.5 deg   in band, outside -- passes
--          cow           el 25.0  approach  6.1 deg   out of band      -- passes
--
--      KOI CLEARS BY 0.4 DEGREES AND THAT IS NOT A MARGIN. The gate is
--      calibrated on exactly one failure and two passes and one of the passes
--      is on the line, so treat a flag as a reason to look at the render and
--      never as a proof. THE ROBUST FIX IS NOT TO TUNE AGAINST IT: the ocelli
--      that ships has no mirrored pair anywhere, which is why it cannot be
--      near the threshold in the first place. Asymmetry breaks the eye reading
--      outright, and it costs nothing -- a spotted animal is not symmetric.
--
-- WHAT IS *NOT* PART OF THE KIND, deliberately: the pattern. Below Legendary
-- one pattern defines the whole tier; here the pattern is what separates the
-- six from each other, so it differs per slime and so does the colour
-- treatment. Six designs, not one design at six hues. That is the second half
-- of what makes the tier feel like a set of individuals rather than a row.
--
-- ====================== WHAT CARRIES OVER UNCHANGED ========================
--
-- All of it from EXPLORE_PATTERNS, and none of it is re-derived here:
--   3D EVALUATION ON THE MESH'S OWN UV ISLAND. Every field is evaluated at the
--   texel's real position on the body, not in UV space, so nothing stretches at
--   the pole and nothing has to know about the unwrap.
--   ANTIALIASED BOUNDARIES. One smoothstep of half-width EDGE_SOFT on every
--   edge; g is written distance-like for every design so one soft width means
--   the same thing across all six.
--   THE TERMINATOR RULE. J and lit are computed and flagged for all six. A
--   marking has to CROSS the light boundary; one that lies along it is a shape
--   the renderer was already drawing for free. Both are flags, never asserts.
--   PLACED FEATURES OVER THRESHOLDED NOISE. Every bar, patch, ring and petal
--   below sits at an AUTHORED position. Five rounds of fire died proving that
--   a thresholded noise field has no lateral contrast and never produces a
--   countable feature; nothing here is sampled from a hash.
--   THE CALIBRATION. Each design has exactly one scalar knob and the build
--   binary-searches it against the real texel set until measured coverage hits
--   COVERAGE_TARGET. Without it the comparison is worthless -- a design would
--   look better simply for carrying less.
--   FEATURE SIZE MEASURED, NOT DERIVED. 2A/P over the mark, reported in pixels
--   at BOTH framings, against the same 8 px floor.
--
-- AND ONE THING THAT DOES NOT: THE FACE IS ON, IN EVERY SHOT. Every frame of
-- the geometry round had a blank body, which is not what a player ever sees --
-- and a blank body is exactly the condition under which an addition looks like
-- the subject. The three face parts are built into every cell here, at the
-- cell's own scale, and the camera is aimed FROM them.
--
-- ========================= WHAT IT HAS TO CLEAR ============================
--
-- THE TWO REAL FRAMINGS, neither of which is the pattern lab's 14-studs-at-40:
--     base    7 studs wide on an 8 x 0.6 x 8 pad, on grass, player eye at 5.0,
--             16 studs out. 25.1 px per stud against a 563 px frame, so the
--             body is 176 px across.
--     reveal  16 studs wide, box camera at 34 studs, pitch 0, over the rainbow
--             road. 11.8 px per stud, body 189 px, and the horizon cuts it in
--             half.
-- BASE IS THE BINDING ONE -- the body is smaller there in pixels despite being
-- the nearer framing, so the 8 px feature floor is asserted against base and
-- reveal is reported beside it.
--
-- ======================= THE SIX, AND WHY EACH ONE ========================
--
-- Every design below is a different ARRANGEMENT FAMILY, and none of them is a
-- family the four rungs below already spent. bare has no marking, blaze is one
-- band, stripes4 is four spirals, dots24 is a scattered field. So: no bands, no
-- spirals, no scatter.
--
--   tiger      twelve wide placed bars      tangerine  / deep indigo
--   koi        six large lobed patches      deep teal  / gold
--   ocelli     four giant annuli, no pair    hot pink   / navy
--   harlequin  three giant diamonds         sea foam   / deep plum
--   split      one seam, a slow wave        royal blue / acid lime
--   cow        three sprawling patches      butter     / deep forest
--
-- FEWER AND LARGER, WHICH IS THE SECOND STRUCTURAL RULE THIS TIER HAS EARNED.
-- The first three above survived a round that cut the other three, and what
-- the survivors share is not a family -- it is a COUNT. split is one shape.
-- koi is six. tiger is twelve, but every one of them is 20 px wide. What was
-- cut was fourteen small rings, a twenty-cell lattice, and four thin bands.
--
--     AT 45% COVERAGE, ELEMENT COUNT AND ELEMENT SIZE TRADE DIRECTLY, AND THE
--     TRADE ONLY RUNS ONE WAY: a slime a player wants is one they can describe.
--
-- "half blue, half lime" is a description. "lilac with a lot of small rings" is
-- a texture, and a texture is what the four rungs BELOW are made of -- dots24
-- is twenty-four small marks and that is precisely why it sits at Epic. Adding
-- a second colour to a texture does not promote it. So the replacements below
-- go the other way: five rings instead of fourteen, three diamonds instead of
-- twenty, three patches instead of four bands. Nothing here is under 25 px.
--
-- ============ TWO DESIGNS DIED OF THE SAME THING, AND IT IS A RULE ========
--
-- mask (three concentric rings about the face axis) and star (a six-petal cap
-- centred on the face) were both built, both calibrated, both cleared every
-- number in the table -- J 0.06 and 0.09, lit 1.08 and 1.01, features 47 px and
-- 92 px -- and both were WRONG IN THE FRAME. star rendered as a plain amber
-- slime with a green fringe. mask rendered as a pink slime with a purple rim.
-- Neither read as its own design at all.
--
--     A FIELD THAT IS RADIAL ABOUT THE VIEW AXIS HAS NO ROOM AT 45% COVERAGE.
--
-- The camera looks along the face axis at BOTH framings -- that is what "the
-- face is toward the player" means -- so a design parameterised by the angle
-- from the nose has all of its boundaries on circles centred in the frame. Fill
-- 45% of the body with one and the boundary lands at about 80-90 degrees from
-- the nose, which is exactly the SILHOUETTE RIM: the one place on the body
-- where the surface turns away from the camera and every feature is
-- foreshortened into the outline. The inside of the frame is one flat colour
-- and the design is squeezed into a fringe a few pixels deep.
--
-- IT IS NOT A COVERAGE PROBLEM AND TUNING WILL NOT FIX IT. At a low coverage a
-- face-centred marking works fine -- that is what blaze and muzzle are, one
-- rung down and at 28%. It is the combination that fails: the tier's own even
-- split is what pushes the boundary out to the rim. So the rule is specific to
-- Legendary and it is a rule, not a note:
--
--     AT THIS TIER, THE PATTERN'S BOUNDARIES MUST RUN ACROSS THE FRAME, NOT
--     AROUND IT. Reach for azimuth, for a lattice, for a seam, for placed
--     features -- for anything whose edges cut the visible front. Do not reach
--     for the angle from the nose.
--
-- TWO MORE DIED IN THAT SLOT BEFORE ribbon TOOK IT, and both are the same
-- lesson one turn further on -- it is not enough for a design's boundaries to
-- exist inside the frame, they have to ALTERNATE across it:
--
--   dipped   one poured boundary with nine placed drips through it. Measured
--            J 0.76 and lit 2.18, the second of which trips the flag, and the
--            render agreed exactly: a navy slime that looks lit from above
--            rather than painted. This is cap-tilt (J 0.73, lit 3.02) wearing
--            drips, and the drips were not enough. The one design here that
--            spent y on its boundary is the one that died of it.
--
--   panda    seven caps placed on FEATURES -- two over the eyes, two ears, two
--            haunches, a saddle. Numbers fine (J 0.17, lit 1.40). But at 45%
--            the two eye caps grow until they meet, and what renders is one
--            navy mask over the whole face. Grown to this tier's coverage,
--            neighbouring caps join; koi survives the same treatment only
--            because its patches are spread over the whole body rather than
--            clustered on one feature.
--
-- AND THREE MORE WERE CUT IN THE ROUND AFTER THAT, on the count rule rather
-- than the frame rule:
--
--   rosette  fourteen annuli, lilac on deep violet. The pattern was fine and
--            the numbers were fine (J 0.04, lit 1.04, 27 px). The PAIR was 4
--            degrees apart in hue -- see rule 3 -- so it rendered as one
--            colour with texture. Kept in the set as `ocelli`: same annulus
--            idea at five rings instead of fourteen, and a pair 97 degrees
--            apart.
--
--   argyle   a six-by-two lattice, jade on magenta. Busy rather than
--            desirable: twenty cells is a fabric swatch, and two colours at
--            full saturation vibrating against each other is not a creature.
--            Kept as `harlequin`: three columns by one row, so the diamonds
--            are 123 px across and there are three of them in the frame, and
--            a lighter primary against a darker mark instead of two loud ones.
--
--   sash     cow's rival for the sixth slot, built beside it in the same run:
--            two wide great circles crossing low on the chest, so the crossing
--            would be a SHAPE where four bands were a rhythm. It is not. The
--            two bands meet at the chest and merge into what reads as a bib,
--            the crossing never resolves as a crossing, and lit came back 0.76
--            -- the lowest in the set, because a crossing placed low puts most
--            of the mark under the equator. cow won the slot on the render.
--
--   ribbon   four crossing great-circle bands. At thumbnail size it shares
--            tiger's banded structure -- both read as "stripes" before the
--            colour arrives, and a set of six cannot spend two slots on one
--            silhouette. Replaced outright by `cow`, which is the only
--            arrangement in the set with no repeat structure at all.
--
-- ONE MORE THING THE ROUND COST, and it is the merge failure a third time:
-- cow's first placement put its two flank patches at 35 degrees elevation with
-- 0.26 of lobe amplitude, and their lobes reached the crown -- 1.05 rad of
-- effective radius against 0.96 rad to the pole -- so the two joined over the
-- top into a mantle and the slime read as green with a yellow face rather than
-- yellow with green patches. Pulling them down to 25 degrees and calming the
-- lobes to 0.22 clears the pole by 0.16 rad and the three patches separate.
-- SO THE CHECK IS ALWAYS THE SAME ONE: effective radius is the authored radius
-- times (1 + lobe amplitude) PLUS k, and k is not known until the bisection
-- runs. Any two placed features whose centres are closer than the sum of those
-- will merge at this tier's coverage, and merging is what killed panda and the
-- first rosette and the first cow.
--
-- All six above obey it: bars run top-to-bottom across the front, the lattice
-- and the annuli cross it, the seam cuts down through it, the partition's cells
-- meet inside it. And note what the numbers did here -- J, lit, coverage and
-- feature size were all HEALTHY on both dead designs. dev/README.md's rule
-- again, from a new direction: a metric that cannot notice its own irrelevance
-- needs a guard, and the guard for this one is the render.
--
-- FOUR OF THE SIX NEVER MENTION HEIGHT, which is the corollary the pattern lab
-- established and the cheapest defence against the terminator rule there is: a
-- marking that is a function of f and s alone cannot be mistaken for a height
-- gradient. tiger and argyle do use y -- tiger to taper its bars toward the
-- belly, argyle because a lattice needs two axes -- and both use it in a way
-- that ALTERNATES with height rather than tracking it, which is the difference
-- between a low J and a high one. Measured, not assumed; the numbers print.
--
-- CHEVRONS ARE NOT HERE AND THAT IS NOT AN OVERSIGHT. The obvious sixth family
-- -- nested V bands over the front -- is the |y + 0.45|s| - c| family the
-- pattern lab swept across four offsets and DROPPED: raising a y-dependent
-- marking across the light boundary is the same act as making it more
-- predictable from height, and there is no offset where it is both. Reach for
-- f and s instead, which is what star does with the same visual idea.
--
-- ============ LEAVING THE SIX-HUE PALETTE: WHAT IT WOULD TAKE ============
--
-- Read SlimeConfig.SLIME_COLOR_BY_TIER and SlimeData's generator before this
-- section; the answer is in the shape of those two, and it is three different
-- sizes of change wearing one name.
--
--   THE PALETTE ITSELF IS FREE. SLIME_COLOR_BY_TIER[5] is six Color3s, and
--   SlimeData zips entry i to "Legendary Slime i" as `color`, asserting only
--   that the array's LENGTH matches SLIME_TIER_COUNTS[5]. Nothing cross-checks
--   one tier's colours against another's -- SlimeConfig's own comment says so
--   ("only within-tier uniqueness is required, never cross-tier"). Replacing
--   Legendary's six values with six colours outside the shared palette is a
--   six-line edit with no structural consequence and no assert to satisfy.
--   Tier identity does not come from this array either; it comes from
--   SLIME_TIER_COLORS, which is separate and untouched.
--
--   THE SECOND COLOUR IS A SMALL TYPED CHANGE, NOT A FREE ONE. `Slime.color`
--   is ONE Color3, and it is read in three places:
--       PlayerProfile.spawnSlimeVisual    -> SlimeBuilder.build(slime.color, w)
--       LaunchRewardScene.showSlimeReveal -> the same builder
--       DevPanelClient                    -> button.TextColor3
--   A pair needs, at minimum: a parallel SLIME_ACCENT_BY_TIER in SlimeConfig, an
--   `accent` field on the Slime type, the same length assert in SlimeData's
--   loop beside the two already there, and a decision at each of the three read
--   sites about which of the two the single-colour context gets. The two UI
--   sites want the PRIMARY (the 55%), which is why every design below names one.
--
--   THE PATTERN IS THE REAL WORK, AND IT IS NOT LEGENDARY'S. SlimeBuilder.build
--   sets body.Color and nothing else -- there is no texture path in the shipping
--   builder at all. Every rung from Uncommon up already needs one, so this is a
--   gap the ladder shares rather than a cost this tier introduces: either an
--   EditableImage painted at runtime (what this file and EXPLORE_PATTERNS do,
--   ~87k texels per skin) or 65 baked uploads. Whichever, it is one decision
--   for the whole catalog and it should not be made inside a tier.
--
-- THE HONEST SUMMARY: the palette is free, the pair costs a typed field and
-- three call sites, and the pattern costs a texture pipeline that four other
-- tiers are already waiting on.
--
-- REVERSAL: workspace.LegendaryPaint:Destroy().
-- ===========================================================================

local AssetService = game:GetService("AssetService")

local TAU = 2 * math.pi

local P = {
	TEX = 512,
	ROOT_NAME = "LegendaryPaint",
	SOURCE_MODELS = { "Slime", "AuxScene", "slime_uv" },
	BODY_MATERIAL = Enum.Material.Plastic,

	-- "base" (7 studs on a pad, on grass, player eye) or
	-- "reveal" (16 studs at Y 40, box camera at pitch 0, over the road)
	FRAMING = "base",

	-- Which designs, by name, in this order. Empty builds all six.
	ONLY = {},

	-- THE EVEN SPLIT. 45% of the body carries the second colour, against
	-- dots24's 28% white one rung below. See rule 2 in the header: this is the
	-- boldness step, measured on the instrument the ladder is already ordered
	-- by rather than on a new one.
	COVERAGE_TARGET = 0.45,
	COVERAGE_TOLERANCE = 0.004,
	SEARCH_ITERS = 32,
	SEARCH_LO = -6.0,
	SEARCH_HI = 6.0,

	-- one smoothstep of this half-width on every boundary; g is distance-like
	-- for every design so this means the same thing across all six
	EDGE_SOFT = 0.012,

	-- THE LADDER'S OWN WORST PAIR, quoted as the gate rather than a fresh
	-- number: white (252,251,247) on yellow (245,215,55), which Uncommon
	-- through Epic all ship today. A Legendary pair that clears both of these
	-- is no harder to read than something already in the game.
	CONTRAST_LUM_FLOOR = 0.161,
	CONTRAST_RGB_FLOOR = 0.767,
	-- A GUESS IN A GAP, AND LABELLED ONE. One measured failure at 4 degrees
	-- (rosette's lilac on deep violet, which cleared both numbers above and
	-- still read as one colour), eight measured passes at 97 and up, nothing in
	-- between. See rule 3 in the header before moving it.
	CONTRAST_HUE_FLOOR = 60.0,
	-- the ladder's accent, here ONLY so rule 1 can be checked against it
	LADDER_WHITE = Color3.fromRGB(252, 251, 247),
	CHROMA_FLOOR = 0.12, -- min max-minus-min channel spread for "chromatic"

	-- THE TERMINATOR RULE, measured. Warnings, never asserts -- a score is a
	-- reason to look, not proof of a bad marking. Two-sided on lit for the
	-- reason the pattern lab found: hiding in the shade and sitting in the
	-- highlight are the same mistake wearing different clothes.
	SHADOW_BINS = 256,
	SHADOW_WARN = 0.80,
	LIT_LO = 0.50,
	LIT_HI = 2.00,

	-- Both framings, both reported, the floor asserted against the smaller.
	-- FRAME_PX is the reference frame HEIGHT these floors were established
	-- against in EXPLORE_PATTERNS; it is not the live viewport.
	FRAME_PX = 563,
	FOV_DEG = 70,
	BASE_WIDTH_STUDS = 7,
	BASE_EYE_Y = 5.0,
	BASE_DISTANCE = 16,
	BASE_PAD_TOP_Y = 1.3,
	REVEAL_WIDTH_STUDS = 16,
	REVEAL_Y = 40,
	REVEAL_DISTANCE = 34,
	MIN_FEATURE_PX = 8,

	BODY_YAW_DEG = 179.4,
	-- The body width the FACE_PARTS offsets and sizes below were measured at.
	-- They are studs, not mesh units -- see the face block in run().
	FACE_REF_WIDTH_STUDS = 14.0,

	-- one cell per design, far enough apart that nothing else is ever in frame
	CELL_SPACING = 400,
	CELL_Z = -1600,

	-- ground, from the game's own config
	GRASS = Color3.fromRGB(104, 198, 78),
	PAD = Color3.fromRGB(182, 182, 188),
	BAND_COUNT = 24,
	BAND_LENGTH = 40,

	-- Run the build off the main thread and publish the log on a workspace
	-- attribute. TRUE by default because this file is driven over the Studio
	-- bridge, whose execute_luau is capped at ~30 s -- and a script that
	-- overruns that does NOT stop, it keeps running while the caller is told it
	-- timed out (dev/README.md). A command-bar paste works either way; it just
	-- prints when it is done rather than returning.
	SPAWN = true,

	SAMPLE_STRIDE = 3,
	TICK_EVERY = 512,
	PAINT_TICK_ROWS = 6,
	YIELD_MS = 12,
}

-- face parts, measured off a lineup slime; offsets are in body-local space, in
-- the mesh's own units, and scaled to the cell at build time
local FACE_PARTS = {
	{ name = "eye_dark", mesh = "rbxassetid://81454373295475",
	  rel = CFrame.new(-3.537100, 0.256561, -4.447517),
	  size = Vector3.new(5.315629, 3.702577, 4.563491),
	  color = Color3.fromRGB(18, 18, 28) },
	{ name = "eye_white", mesh = "rbxassetid://109111264562266",
	  rel = CFrame.new(-3.943192, 0.935150, -4.960449),
	  size = Vector3.new(4.603409, 1.716936, 3.742096),
	  color = Color3.fromRGB(255, 255, 255) },
	{ name = "blush", mesh = "rbxassetid://83359732401472",
	  rel = CFrame.new(-3.323163, -1.230103, -4.188950),
	  size = Vector3.new(7.190265, 0.950127, 5.825126),
	  color = Color3.fromRGB(222, 66, 114) },
}

-- THE FACE-ALIGNED FRAME, taken from where the eyes actually sit rather than
-- declared, so it stays correct if the face parts move. Flattened to the
-- horizontal: an animal's midline is horizontal even when its face tips.
local FACE_REL = FACE_PARTS[1].rel.Position
local FWD = Vector3.new(FACE_REL.X, 0, FACE_REL.Z).Unit
local SIDE = Vector3.new(-FWD.Z, 0, FWD.X)

-- ===================================================================
-- THE EYE ZONE, SOLVED OUT OF THE FACE PARTS RATHER THAN DECLARED.
--
-- Rule 4 needs to know where the eyes actually are in angular terms, and
-- FACE_PARTS does not say: eye_dark is ONE mesh holding BOTH eyes, so all it
-- carries is the pair's bounding box. That box is the AABB of two spheres set
-- apart along the SIDEWAYS axis, which is enough to solve for both unknowns --
-- half-separation d and eye radius r -- because the box's X and Z half-extents
-- are d*|SIDE.X| + r and d*|SIDE.Z| + r, two equations in two unknowns.
--
-- DERIVED RATHER THAN TYPED so it moves when the face moves. A hard-coded
-- "eyes are at 22 degrees" would be a number describing a face that had been
-- edited out from under it -- dev/README.md's whole first section.
-- ===================================================================
local EYE_AZ_HALF_DEG, EYE_EL_LO_DEG, EYE_EL_HI_DEG = 30.1, -15.1, 19.9
do
	local spec = FACE_PARTS[1]
	local refR = 7.0 -- body radius in the frame the offsets are written in
	local c = spec.rel.Position / refR
	local h = spec.size / (2 * refR)
	local ef = c.X * FWD.X + c.Z * FWD.Z
	local ey = c.Y
	-- two spheres along SIDE: halfX = d|SIDE.X| + r, halfZ = d|SIDE.Z| + r
	local sepDen = math.abs(SIDE.X) - math.abs(SIDE.Z)
	if math.abs(sepDen) > 1e-3 then
		local d = (h.X - h.Z) / sepDen
		local r = h.X - d * math.abs(SIDE.X)
		local dist = math.sqrt(ef * ef + ey * ey + d * d)
		if dist > 1e-6 and d > 0 and r > 0 then
			EYE_AZ_HALF_DEG = math.deg(math.atan2(d, ef)) + math.deg(math.asin(math.clamp(r / dist, -1, 1)))
			local elC = math.deg(math.asin(math.clamp(ey / dist, -1, 1)))
			local elH = math.deg(math.asin(math.clamp(h.Y / dist, -1, 1)))
			EYE_EL_LO_DEG, EYE_EL_HI_DEG = elC - elH, elC + elH
		end
	end
end

-- Every design that PLACES features declares them, so rule 4 can be measured
-- rather than eyeballed. d is the centre in the (f, y, s) frame; R is the
-- authored angular radius; lobe is the edge modulation, because a lobed patch
-- reaches further than its radius says. The bisection's k is added at check
-- time -- it is not known until the shape has been calibrated, which is the
-- same trap that let cow's flank patches merge over the crown.
local function eyeReadPairs(centres, k: number)
	local out = {}
	if not centres then return out end
	for i = 1, #centres do
		for j = i + 1, #centres do
			local a, b = centres[i], centres[j]
			-- a mirrored pair: same forward and same height, opposite sideways
			if math.abs(a.d.X - b.d.X) < 0.02 and math.abs(a.d.Y - b.d.Y) < 0.02
				and math.abs(a.d.Z + b.d.Z) < 0.02 and math.abs(a.R - b.R) < 0.02 then
				local reff = a.R * (1 + (a.lobe or 0)) + k
				local el = math.deg(math.asin(math.clamp(a.d.Y, -1, 1)))
				-- how close the pair gets to the midline plane, in degrees
				local approach = math.deg(math.asin(math.clamp(math.abs(a.d.Z), -1, 1))) - math.deg(reff)
				local inBand = el >= EYE_EL_LO_DEG and el <= EYE_EL_HI_DEG
				table.insert(out, {
					el = el, approach = approach, inBand = inBand,
					fails = inBand and approach <= EYE_AZ_HALF_DEG,
				})
			end
		end
	end
	return out
end

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- TWO NUMBERS, because one is not enough -- identical to BUILD_SKINS' accentFor
-- and EXPLORE_PATTERNS' contrast(). Luminance gap alone rejects cream-on-yellow,
-- which reads perfectly well: the separation there is chroma, not brightness.
local function contrast(a: Color3, b: Color3): (number, number)
	local dr, dg, db = b.R - a.R, b.G - a.G, b.B - a.B
	return math.abs(luminance(b) - luminance(a)), math.sqrt(dr * dr + dg * dg + db * db)
end

-- RULE 3's THIRD NUMBER. Hue, in degrees around the wheel, and the circular
-- distance between two of them. Written out rather than pulled from
-- Color3:ToHSV so the achromatic case is explicit: a colour with no chroma has
-- no hue to compare, which is exactly why this number was never needed while
-- the accent was white. Rule 1 guarantees both sides are chromatic here, so it
-- always means something -- but the guard stays, because a rule that depends
-- on another rule should not silently return 0 if that one ever moves.
local function hueOf(c: Color3): number
	local mx = math.max(c.R, c.G, c.B)
	local mn = math.min(c.R, c.G, c.B)
	local d = mx - mn
	if d < 1e-6 then return -1 end
	local h
	if mx == c.R then h = (c.G - c.B) / d % 6
	elseif mx == c.G then h = (c.B - c.R) / d + 2
	else h = (c.R - c.G) / d + 4 end
	return h * 60 % 360
end

local function hueSep(a: Color3, b: Color3): number
	local ha, hb = hueOf(a), hueOf(b)
	if ha < 0 or hb < 0 then return 180 end -- achromatic: not this gate's business
	local d = math.abs(ha - hb) % 360
	return math.min(d, 360 - d)
end

-- Rule 1's test, and it has to be a test rather than a promise: "not white" is
-- not the same as "chromatic". A colour is chromatic when its channels are not
-- all the same -- greys, creams and near-whites collapse to a small spread and
-- would put the tier straight back into hue-plus-accent.
local function chroma(c: Color3): number
	return math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B)
end

local function smoothstep(e0: number, e1: number, x: number): number
	local u = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return u * u * (3 - 2 * u)
end

-- distance from x to the nearest integer
local function dInt(x: number): number
	return math.abs(x - math.floor(x + 0.5))
end

-- wrap an angle difference into (-pi, pi]
local function wrapPi(a: number): number
	return a - TAU * math.floor((a + math.pi) / TAU)
end

local function newYielder(budgetMs: number)
	local budget, last = budgetMs / 1000, os.clock()
	local worst = 0
	return {
		tick = function()
			local now = os.clock()
			if now - last > budget then
				worst = math.max(worst, now - last)
				task.wait()
				last = os.clock()
			end
		end,
		-- os.clock() cannot see a yield, so a known-yielding call has to be
		-- declared on BOTH sides or its wait is charged to whatever ran next.
		mark = function() last = os.clock() end,
		worstMs = function() return worst * 1000 end,
	}
end

-- body half-height in body-radii; refined from the mesh at build time
local YHALF = 0.6773

-- ===================================================================
-- THE SIX FIELDS.
--
-- Every one is g(q): the SECOND colour goes wherever g < k, so a larger k
-- always means more of it and one monotone bisection calibrates all six.
-- g is distance-like in every case -- radians on a unit body ARE arc length in
-- body-radii -- which is what lets one EDGE_SOFT antialias all of them.
--
-- f = forward (toward the face), s = sideways, y = up, l = |q|.
-- ===================================================================

-- ---- tiger: bars placed by hand, mirrored, tapering toward the belly ------
-- Ten bars: five authored azimuths, each mirrored across the midline with its
-- lean mirrored too, so the animal is bilaterally symmetric the way a real
-- marked animal is. Nothing here is a spiral -- the lean is a few degrees per
-- bar, authored per bar, not a constant twist -- which is what keeps it out of
-- stripes4's family two rungs below.
-- WIDTHS ARE RELATIVE AND k CARRIES THE SCALE, so the bisection widens all ten
-- together and the authored proportions between them survive calibration.
local TIGER_BARS = {}
do
	-- centre |theta|, relative width, lean per unit height.
	-- THE WIDTHS ARE THE PART THAT MATTERS. The first version ran five bars per
	-- side at 0.84..1.04 relative width -- near-uniform -- and at 45% coverage
	-- that makes bar and gap the same size all the way round. It rendered as a
	-- BEACH BALL, which is the exact failure stripes4 was pushed from twist 70
	-- to 140 to escape one rung down. Six per side spanning 0.55..1.25 breaks
	-- the alternation, and 0.42 rad for the innermost pair leaves the face
	-- sitting on a clear panel of the primary between them.
	local spec = {
		{ 0.42, 1.25, 0.22 },
		{ 0.98, 0.62, -0.16 },
		{ 1.42, 1.10, 0.10 },
		{ 1.95, 0.55, 0.20 },
		{ 2.40, 1.15, -0.14 },
		{ 2.95, 0.70, 0.08 },
	}
	for _, e in ipairs(spec) do
		table.insert(TIGER_BARS, { e[1], e[2], e[3] })
		table.insert(TIGER_BARS, { -e[1], e[2], -e[3] })
	end
end

-- ---- koi: six large patches, placed, with lobed edges ---------------------
-- A patch is an angular cap whose radius breathes with a sinusoid around its
-- own axis, so the edge is lobed rather than circular -- a circle reads as a
-- sticker and a lobe reads as a marking. The lobes are AUTHORED (amplitude,
-- count, phase per patch), not sampled: the same rule that killed five rounds
-- of noise-thresholded fire.
-- Mirrored pairs, because bilateral symmetry is what makes a patch field read
-- as an animal rather than as spilled paint.
local KOI = {}
do
	-- f, s, y, angular radius, lobe amplitude, lobe count, lobe phase
	local spec = {
		{ -0.25, 0.00, 0.97, 0.60, 0.16, 3, 0.40 },
		{ 0.18, 0.94, 0.30, 0.50, 0.20, 4, 1.10 },
		{ 0.18, -0.94, 0.30, 0.50, 0.20, 4, -1.10 },
		{ -0.80, 0.30, -0.52, 0.44, 0.18, 3, 2.00 },
		{ -0.80, -0.30, -0.52, 0.44, 0.18, 3, -2.00 },
		{ 0.86, 0.00, -0.50, 0.34, 0.22, 5, 0.70 },
	}
	for _, e in ipairs(spec) do
		-- the axis, written (f, y, s) so it lines up with how g resolves the
		-- query below, then a tangent frame on it so the lobe phase means the
		-- same thing on every patch
		local d = Vector3.new(e[1], e[3], e[2]).Unit
		local up = math.abs(d.Y) > 0.9 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local t = up:Cross(d).Unit
		local b = d:Cross(t)
		table.insert(KOI, { d = d, t = t, b = b, R = e[4], a = e[5], m = e[6], p = e[7], lobe = e[5] })
	end
end

-- ---- rosette: ten annuli, placed, mirrored ------------------------------
-- A LEOPARD IS NOT A DOT FIELD, and the difference is one boundary. dots24 --
-- Epic, one rung down -- is discs of the accent on the hue. These are RINGS:
-- the mark colour is the band and the primary shows through the middle, so
-- every rosette carries both colours by itself and the eye counts two edges
-- where the rung below has one.
-- PLACED BY HAND, NOT BY EQUAL AREA. dotCentres solves a different problem --
-- how to spread N identical dots evenly -- and evenness is exactly what a
-- rosette field must not have. These are ten authored (elevation, azimuth,
-- radius) triples, mirrored across the midline, with NOTHING at azimuth 0 so
-- the face sits on clear primary between the two crown rings.
local OCELLI = {}
do
	-- elevation deg, azimuth deg from the face, ring radius in radians.
	-- FOUR RINGS AND NOT ONE MIRRORED PAIR AMONG THEM. The version before this
	-- had five, two of them at 15 deg elevation and 52 deg either side of the
	-- nose, and it rendered as a four-eyed slime -- see rule 4. Every gate it
	-- had passed; the pair was the whole problem.
	--
	-- ASYMMETRY IS THE FIX, NOT A SMALLER PAIR. A pair at eye height beside the
	-- eyes is read as eyes at any size, and moving it far enough out to clear
	-- the zone puts it on the silhouette where nothing resolves. Four rings at
	-- four different elevations and four unrelated azimuths cannot be read as
	-- a face at all, and a spotted animal is not symmetric anyway -- this is
	-- the one design in the set that says so.
	--
	-- STILL PLACED, STILL CHECKED. Closest pair is 85.7 deg apart against outer
	-- radii summing to 81.6, so nothing merges; no mirror of any centre comes
	-- within 43 deg of any other, so no accidental pair; and A and B both sit
	-- well inside the visible front -- upper left and lower right -- so the
	-- design reads as itself at both framings rather than wrapping out of view.
	local spec = {
		{ 55, -40, 0.56 },
		{ -28, 58, 0.54 },
		{ 25, 135, 0.58 },
		{ -30, -125, 0.52 },
	}
	for _, e in ipairs(spec) do
		local el, az = math.rad(e[1]), math.rad(e[2])
		-- (f, y, s), the same frame the fields resolve their query into
		table.insert(OCELLI, {
			d = Vector3.new(math.cos(el) * math.cos(az), math.sin(el), math.cos(el) * math.sin(az)),
			R = e[3],
		})
	end
end

-- ---- dipped: one poured boundary, with placed drips running down ---------
-- THE SIXTH FAMILY, AND THE ONE THE FRAME RULE COST TWO ATTEMPTS TO FIND.
-- star died radial about the view axis. A Voronoi partition ("cow") was tried
-- next and died of the SAME SHAPE by a different route: five mark cells spread
-- around a body, grown to 45%, simply join up into one region that is
-- everything-except-the-front, which is a hood again. Both failures are the
-- one rule -- the pattern has to alternate ACROSS the frame, not close around
-- it -- and a dip with drips is the cheapest thing that does: the boundary
-- runs left to right through the middle of the visible front and the drips cut
-- down through it three times before it leaves the silhouette.
--
-- THIS IS THE ONE DESIGN THAT SPENDS y ON PURPOSE, so read its J and lit before
-- believing it. A single horizontal boundary is exactly what the terminator
-- rule warns about -- cap-tilt scored J 0.73 and lit 3.02 for being a lit top
-- wearing paint. What is different here is the drips: a monotone height
-- threshold cannot follow a boundary that plunges 0.9 of the half-height at
-- nine authored azimuths and rises between them, and that is measurable rather
-- than hopeful. If the numbers come back where cap-tilt's did, this design is
-- wrong and the flag will say so.
--
-- PLACED, LIKE EVERYTHING ELSE HERE. Nine lobes at authored azimuths, widths
-- and depths, mirrored across the midline. Not a noise field with a threshold.
local DRIPS = {}
do
	-- centre azimuth rad, half-width rad, depth in half-heights
	local spec = {
		{ 0.00, 0.30, 0.85 },
		{ 0.80, 0.42, 0.45 },
		{ 1.55, 0.30, 0.95 },
		{ 2.45, 0.45, 0.55 },
		{ 3.14, 0.28, 0.75 },
	}
	for _, e in ipairs(spec) do
		table.insert(DRIPS, e)
		-- 0 and pi are their own mirrors; doubling them would double their depth
		if e[1] > 1e-6 and math.abs(e[1] - math.pi) > 1e-6 then
			table.insert(DRIPS, { -e[1], e[2], e[3] })
		end
	end
end

-- the poured level at this azimuth, in half-heights: 0 at rest, pulled down
-- wherever a drip hangs. A smooth lobe rather than a notch, so the boundary
-- stays differentiable and one EDGE_SOFT antialiases it like everything else.
local function dripLevel(th: number): number
	local drop = 0
	for i = 1, #DRIPS do
		local e = DRIPS[i]
		local u = math.abs(wrapPi(th - e[1])) / e[2]
		if u < 1 then
			local lobe = e[3] * (1 - u * u)
			if lobe > drop then drop = lobe end
		end
	end
	return -drop
end

-- ---- cow: three sprawling patches, and the only design with no repeat ----
-- THE SAME MACHINERY AS koi AND DELIBERATELY NOT THE SAME PICTURE. koi is six
-- round-ish caps spread evenly over the whole body with the face left clear:
-- read as a field. These are THREE, each nearly twice the size, each lobed
-- hard enough to sprawl rather than sit, and one of them comes up the chest
-- under the chin. There is no repeat structure anywhere in it -- no count to
-- notice, no spacing to read as rhythm -- which is what makes it the opposite
-- end of the set from tiger and the reason it took ribbon's slot rather than
-- another band design.
-- THE CHEST PATCH IS KEPT OFF THE EYES ON PURPOSE. panda died putting caps on
-- features and watching them merge into a mask at this coverage; this one is
-- centred 30 degrees BELOW the nose, so it grows down the chest rather than up
-- over the face, and the primary keeps a clear band across the eyes.
local COW = {}
do
	-- f, s, y, angular radius, lobe amplitude, lobe count, lobe phase
	local spec = {
		{ 0.707, 0.000, -0.707, 0.60, 0.20, 3, 0.50 },
		{ -0.157, 0.892, 0.423, 0.72, 0.22, 4, 1.20 },
		{ -0.157, -0.892, 0.423, 0.72, 0.22, 4, -1.20 },
	}
	for _, e in ipairs(spec) do
		local d = Vector3.new(e[1], e[3], e[2]).Unit
		local up = math.abs(d.Y) > 0.9 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local t = up:Cross(d).Unit
		local b = d:Cross(t)
		table.insert(COW, { d = d, t = t, b = b, R = e[4], a = e[5], m = e[6], p = e[7], lobe = e[5] })
	end
end

local DESIGNS = {
	{
		name = "tiger",
		note = "ten placed bars around the body, tapering toward the belly",
		primary = Color3.fromRGB(250, 150, 45), -- tangerine
		mark = Color3.fromRGB(46, 26, 92), -- deep indigo
		primaryName = "tangerine", markName = "deep indigo",
		-- g is |dtheta| divided by a relative width, so it is in bar-widths
		-- rather than radians; a slightly wider soft edge keeps the boundary
		-- resolving at the same sub-pixel scale as the others'.
		soft = 0.018,
		g = function(qx, qy, qz, f, s, l)
			local th = math.atan2(s, f)
			local h = math.clamp(qy / YHALF, -1, 1)
			-- narrower underneath, wider over the back: a tiger's bars run out
			-- before they reach the belly, and a bar of constant width reads as
			-- a barcode wrapped round a ball
			local taper = 0.58 + 0.42 * (h + 1) * 0.5
			local best = math.huge
			for i = 1, #TIGER_BARS do
				local b = TIGER_BARS[i]
				local v = math.abs(wrapPi(th - (b[1] + b[3] * h))) / (b[2] * taper)
				if v < best then best = v end
			end
			return best
		end,
	},
	{
		name = "koi",
		note = "six large lobed patches, placed, mirrored across the midline",
		primary = Color3.fromRGB(16, 124, 124), -- deep teal
		mark = Color3.fromRGB(255, 196, 60), -- gold
		primaryName = "deep teal", markName = "gold",
		centres = KOI,
		g = function(qx, qy, qz, f, s, l)
			-- the query direction in the face-aligned frame, as (f, y, s)
			local dx, dy, dz = f / l, qy / l, s / l
			local best = math.huge
			for i = 1, #KOI do
				local k = KOI[i]
				local d = k.d
				local c = math.clamp(dx * d.X + dy * d.Y + dz * d.Z, -1, 1)
				local ang = math.acos(c)
				local tv = dx * k.t.X + dy * k.t.Y + dz * k.t.Z
				local bv = dx * k.b.X + dy * k.b.Y + dz * k.b.Z
				local phi = math.atan2(bv, tv)
				local v = ang - k.R * (1 + k.a * math.cos(k.m * phi + k.p))
				if v < best then best = v end
			end
			return best
		end,
	},
	{
		name = "ocelli",
		note = "four giant annuli at four elevations, no mirrored pair",
		primary = Color3.fromRGB(230, 80, 160), -- hot pink
		mark = Color3.fromRGB(25, 35, 90), -- navy
		primaryName = "hot pink", markName = "navy",
		centres = OCELLI,
		-- Distance to the nearest ring's BAND rather than to its centre, so one
		-- k is the band's half-width and the bisection thickens all five
		-- together while their authored radii stay in proportion.
		g = function(qx, qy, qz, f, s, l)
			local dx, dy, dz = f / l, qy / l, s / l
			local best = math.huge
			for i = 1, #OCELLI do
				local r = OCELLI[i]
				local d = r.d
				local ang = math.acos(math.clamp(dx * d.X + dy * d.Y + dz * d.Z, -1, 1))
				local v = math.abs(ang - r.R)
				if v < best then best = v end
			end
			return best
		end,
	},
	{
		name = "harlequin",
		note = "three giant diamonds around, the two colours interlocking",
		primary = Color3.fromRGB(130, 215, 180), -- sea foam
		mark = Color3.fromRGB(90, 30, 85), -- deep plum
		primaryName = "sea foam", markName = "deep plum",
		-- THE SAME ROTATED LATTICE argyle USED, AT THE LARGEST SCALE IT HAS.
		-- In (u, v) = (azimuth, height), the points where A = u+v and B = u-v
		-- are both integers form a staggered lattice, and max(distance to the
		-- nearest integer) over the two is the L1 distance to the nearest of
		-- them -- a DIAMOND. Full coverage at k = 0.5, where the two colours
		-- tile the body with no gaps, so the bisection searches a knob whose
		-- whole range means something.
		-- THREE COLUMNS BY ONE ROW, against argyle's six by two. That is twenty
		-- cells down to about six, and a diamond 1.40 rad across -- 123 px at
		-- the base framing, so between one and two of them fill the visible
		-- front. A lattice you can count is a costume; a lattice you cannot is
		-- a fabric swatch, and the tier below is already made of swatches.
		-- SEAMLESS BY CONSTRUCTION: u wraps by an integer number of columns, so
		-- A and B wrap by integers too and dInt does not notice the seam. Three
		-- is odd and still bilaterally symmetric, because u negates under the
		-- mirror and dInt is even.
		g = function(qx, qy, qz, f, s, l)
			local u = 3 * (math.atan2(s, f) / TAU)
			local v = (math.clamp(qy / YHALF, -1, 1) + 1) * 0.5
			return math.max(dInt(u + v), dInt(u - v)) * (TAU / 3)
		end,
	},
	{
		name = "split",
		note = "bilateral two-tone, the seam a slow wave down the midline",
		primary = Color3.fromRGB(48, 70, 205), -- royal blue
		mark = Color3.fromRGB(190, 230, 60), -- acid lime
		primaryName = "royal blue", markName = "acid lime",
		-- THE PUREST STATEMENT OF THE TIER'S KIND, and the reason it is in the
		-- set: a slime that is half one colour and half another cannot be
		-- described as a hue with markings at all. The face straddles the seam,
		-- one eye on each colour.
		-- THE WAVE IS WHAT KEEPS IT OFF THE PAINTED-EGG FAILURE. A straight
		-- bisection reads as a manufactured object; 0.16 radii of vertical wave
		-- -- about 14 px at the base framing -- reads as a pour. And it costs
		-- nothing on the terminator rule: the mark is half the body divided by a
		-- near-vertical surface, so no height threshold predicts it.
		-- AT 45% THE SEAM SITS ABOUT 0.1 RADII OFF THE MIDLINE, roughly 9 px,
		-- because an even 50% is where a pure s-split lands and the tier's
		-- coverage is 45. That is a deliberate consequence of holding every
		-- design to one target rather than exempting this one.
		g = function(qx, qy, qz, f, s, l)
			return s / l + 0.16 * math.sin(2.2 * math.pi * math.clamp(qy / YHALF, -1, 1))
		end,
	},
	{
		name = "cow",
		note = "three sprawling patches, no repeat structure anywhere in it",
		primary = Color3.fromRGB(250, 218, 120), -- butter
		mark = Color3.fromRGB(25, 85, 60), -- deep forest
		primaryName = "butter", markName = "deep forest",
		centres = COW,
		g = function(qx, qy, qz, f, s, l)
			-- the query direction in the face-aligned frame, as (f, y, s)
			local dx, dy, dz = f / l, qy / l, s / l
			local best = math.huge
			for i = 1, #COW do
				local c = COW[i]
				local d = c.d
				local ang = math.acos(math.clamp(dx * d.X + dy * d.Y + dz * d.Z, -1, 1))
				local tv = dx * c.t.X + dy * c.t.Y + dz * c.t.Z
				local bv = dx * c.b.X + dy * c.b.Y + dz * c.b.Z
				local phi = math.atan2(bv, tv)
				local v = ang - c.R * (1 + c.a * math.cos(c.m * phi + c.p))
				if v < best then best = v end
			end
			return best
		end,
	},
}

-- ===================================================================
-- THE UV MAP. Lifted from EXPLORE_PATTERNS unchanged, including the two traps
-- it documents: stray vertices excluded from the bounding box, and ONLY
-- NON-EMPTY height bands used as silhouette samples (interpolating into an
-- empty bucket collapses the radius to about a quarter of true).
-- ===================================================================
local function buildUVMap(meshId: string, W: number, Y)
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))
	local verts, faces = em:GetVertices(), em:GetFaces()
	Y.mark()

	local sx, sy, sz = 0, 0, 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		sx += p.X; sy += p.Y; sz += p.Z
	end
	local gx, gy, gz = sx / #verts, sy / #verts, sz / #verts
	local dsum = 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		dsum += math.sqrt((p.X - gx) ^ 2 + (p.Y - gy) ^ 2 + (p.Z - gz) ^ 2)
	end
	local dmean = dsum / #verts
	local isStray: { [number]: boolean } = {}
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		if math.sqrt((p.X - gx) ^ 2 + (p.Y - gy) ^ 2 + (p.Z - gz) ^ 2) > 8 * dmean then
			isStray[id] = true
		end
	end

	local mnx, mxx = math.huge, -math.huge
	local mny, mxy = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	local amnx, amxx = math.huge, -math.huge
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		amnx = math.min(amnx, p.X); amxx = math.max(amxx, p.X)
		if not isStray[id] then
			mnx = math.min(mnx, p.X); mxx = math.max(mxx, p.X)
			mny = math.min(mny, p.Y); mxy = math.max(mxy, p.Y)
			mnz = math.min(mnz, p.Z); mxz = math.max(mxz, p.Z)
		end
	end
	local CX, CY, CZ = (mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2
	local RAD = (mxx - mnx) / 2

	local PB = 96
	local bucket = table.create(PB, 0)
	for _, id in ipairs(verts) do
		Y.tick()
		if not isStray[id] then
			local p = em:GetPosition(id)
			local tb = (p.Y - mny) / math.max(mxy - mny, 1e-9)
			local bi = math.clamp(math.floor(tb * PB) + 1, 1, PB)
			local rr = math.sqrt((p.X - CX) ^ 2 + (p.Z - CZ) ^ 2) / RAD
			if rr > bucket[bi] then bucket[bi] = rr end
		end
	end
	local profile, filled = {}, 0
	for bi = 1, PB do
		if bucket[bi] > 0 then
			filled += 1
			table.insert(profile, { (bi - 0.5) / PB, bucket[bi] })
		end
	end
	assert(#profile >= 8, string.format(
		"[Paint] silhouette profile has only %d non-empty bands of %d", #profile, PB))

	local POS = buffer.create(W * W * 12)
	local PRIO = buffer.create(W * W * 8)
	local MASK = buffer.create(W * W)
	local covered = 0

	for _, fc in ipairs(faces) do
		Y.tick()
		local fv = em:GetFaceVertices(fc)
		if isStray[fv[1]] or isStray[fv[2]] or isStray[fv[3]] then continue end
		local p1, p2, p3 = em:GetPosition(fv[1]), em:GetPosition(fv[2]), em:GetPosition(fv[3])
		local fu = em:GetFaceUVs(fc)
		local a, b, c = em:GetUV(fu[1]), em:GetUV(fu[2]), em:GetUV(fu[3])
		local e1x, e1y, e1z = p2.X - p1.X, p2.Y - p1.Y, p2.Z - p1.Z
		local e2x, e2y, e2z = p3.X - p1.X, p3.Y - p1.Y, p3.Z - p1.Z
		local nx, ny, nz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
		local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
		local rx, ry, rz = (p1.X + p2.X + p3.X) / 3 - CX, (p1.Y + p2.Y + p3.Y) / 3 - CY, (p1.Z + p2.Z + p3.Z) / 3 - CZ
		local rl = math.sqrt(rx * rx + ry * ry + rz * rz)
		local outward = (nl > 1e-12 and rl > 1e-12) and (nx * rx + ny * ry + nz * rz) / (nl * rl) or 0

		local u1, u2, u3 = a.X, b.X, c.X
		local v1, v2, v3 = a.Y, b.Y, c.Y
		local umin = math.min(u1, u2, u3)
		if math.max(u1, u2, u3) - umin > 0.5 then
			if u1 - umin <= 0.5 then u1 += 1 end
			if u2 - umin <= 0.5 then u2 += 1 end
			if u3 - umin <= 0.5 then u3 += 1 end
		end
		local x1, y1, x2, y2, x3, y3 = u1 * W, v1 * W, u2 * W, v2 * W, u3 * W, v3 * W
		local d = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
		if math.abs(d) < 1e-12 then continue end
		local inv = 1 / d
		for py = math.max(0, math.floor(math.min(y1, y2, y3))), math.min(W - 1, math.ceil(math.max(y1, y2, y3))) do
			local fy = py + 0.5
			for px = math.floor(math.min(x1, x2, x3)), math.ceil(math.max(x1, x2, x3)) do
				local fx = px + 0.5
				local l1 = ((y2 - y3) * (fx - x3) + (x3 - x2) * (fy - y3)) * inv
				local l2 = ((y3 - y1) * (fx - x3) + (x1 - x3) * (fy - y3)) * inv
				local l3 = 1 - l1 - l2
				if l1 >= -0.002 and l2 >= -0.002 and l3 >= -0.002 then
					local idx = py * W + (px % W)
					local o, po = idx * 12, idx * 8
					local qx = (l1 * p1.X + l2 * p2.X + l3 * p3.X - CX) / RAD
					local qy = (l1 * p1.Y + l2 * p2.Y + l3 * p3.Y - CY) / RAD
					local qz = (l1 * p1.Z + l2 * p2.Z + l3 * p3.Z - CZ) / RAD
					local interior = math.min(l1, l2, l3)
					local wins
					if buffer.readu8(MASK, idx) == 0 then
						buffer.writeu8(MASK, idx, 1); covered += 1; wins = true
					else
						local hi_ = buffer.readf32(PRIO, po)
						local ho = buffer.readf32(PRIO, po + 4)
						local ic, hc = interior >= 0, hi_ >= 0
						if ic ~= hc then wins = ic else wins = outward > ho end
					end
					if wins then
						buffer.writef32(POS, o, qx); buffer.writef32(POS, o + 4, qy); buffer.writef32(POS, o + 8, qz)
						buffer.writef32(PRIO, po, interior); buffer.writef32(PRIO, po + 4, outward)
					end
				end
			end
		end
	end
	return {
		POS = POS, MASK = MASK, covered = covered,
		CX = CX, CY = CY, CZ = CZ, RAD = RAD,
		HEIGHT = mxy - mny, FULL_W = amxx - amnx,
		PROFILE = profile, PROFILE_BANDS = PB, PROFILE_FILLED = filled,
		QY0 = (mny - CY) / RAD, QY1 = (mxy - CY) / RAD,
	}
end

local function dilate(POS, MASK, W: number, passes: number, Y): number
	local grown = 0
	for _ = 1, passes do
		local add = {}
		for y = 0, W - 1 do
			Y.tick()
			for x = 0, W - 1 do
				local idx = y * W + x
				if buffer.readu8(MASK, idx) == 0 then
					local nb = -1
					if x > 0 and buffer.readu8(MASK, idx - 1) == 1 then nb = idx - 1
					elseif x < W - 1 and buffer.readu8(MASK, idx + 1) == 1 then nb = idx + 1
					elseif y > 0 and buffer.readu8(MASK, idx - W) == 1 then nb = idx - W
					elseif y < W - 1 and buffer.readu8(MASK, idx + W) == 1 then nb = idx + W
					end
					if nb >= 0 then table.insert(add, { idx, nb }) end
				end
			end
		end
		for _, pr in ipairs(add) do
			local o, no = pr[1] * 12, pr[2] * 12
			buffer.writef32(POS, o, buffer.readf32(POS, no))
			buffer.writef32(POS, o + 4, buffer.readf32(POS, no + 4))
			buffer.writef32(POS, o + 8, buffer.readf32(POS, no + 8))
			buffer.writeu8(MASK, pr[1], 2); grown += 1
		end
		for _, pr in ipairs(add) do buffer.writeu8(MASK, pr[1], 1) end
	end
	return grown
end

-- ===================================================================
-- BUILD.
-- ===================================================================
local function run(): string
	local lines = {}
	local function log(...) table.insert(lines, string.format(...)) end
	local t0 = os.clock()

	local src: BasePart? = nil
	for _, name in ipairs(P.SOURCE_MODELS) do
		local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
		local m = (assets and assets:FindFirstChild(name)) or workspace:FindFirstChild(name)
		if m then
			local best, bestVol = nil, -1
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("MeshPart") then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if v > bestVol then best, bestVol = d :: BasePart, v end
				end
			end
			if best then src = best break end
		end
	end
	assert(src, "[Paint] no MeshPart found under any of {" .. table.concat(P.SOURCE_MODELS, ", ") .. "}")
	local source = src :: BasePart
	log("[Paint] source: %s", source:GetFullName())

	local isBase = P.FRAMING == "base"
	local widthStuds = isBase and P.BASE_WIDTH_STUDS or P.REVEAL_WIDTH_STUDS
	local distance = isBase and P.BASE_DISTANCE or P.REVEAL_DISTANCE

	local W = P.TEX
	local Y = newYielder(P.YIELD_MS)
	local M = buildUVMap((source :: any).MeshId, W, Y)
	local coverage = M.covered / (W * W)
	assert(coverage > 0.10, string.format(
		"[Paint] source mesh covers only %.2f%% of the sheet -- no usable UV unwrap", coverage * 100))
	log("[Paint] UV map: %d texels (%.1f%% of sheet) | silhouette %d of %d bands non-empty",
		M.covered, coverage * 100, M.PROFILE_FILLED, M.PROFILE_BANDS)

	local POS, MASK = M.POS, M.MASK
	dilate(POS, MASK, W, 3, Y)

	local bodySizeX = widthStuds * M.FULL_W / (2 * M.RAD)
	local partScale = bodySizeX / source.Size.X
	local studsPerMeshUnit = bodySizeX / M.FULL_W
	local bodyRadiusStuds = M.RAD * studsPerMeshUnit
	local bodyHeightStuds = M.HEIGHT * studsPerMeshUnit
	YHALF = (M.HEIGHT / M.RAD) / 2

	-- BOTH FRAMINGS, ALWAYS, whichever one is being built. A feature that
	-- resolves here and not there is the failure this file exists to catch, and
	-- it cannot be caught by a number that only knows about the current build.
	local function pxPerStudAt(d: number): number
		return P.FRAME_PX / (2 * d * math.tan(math.rad(P.FOV_DEG) / 2))
	end
	local pxBase = pxPerStudAt(P.BASE_DISTANCE)
	local pxReveal = pxPerStudAt(P.REVEAL_DISTANCE)
	log("[Paint] framing %s | body %.2f studs across | base %.2f px/stud (%.0f px body),"
		.. " reveal %.2f px/stud (%.0f px body) | coverage target %.0f%%",
		P.FRAMING, 2 * bodyRadiusStuds, pxBase, P.BASE_WIDTH_STUDS * pxBase,
		pxReveal, P.REVEAL_WIDTH_STUDS * pxReveal, P.COVERAGE_TARGET * 100)

	-- sample subset, with the face-frame components precomputed once
	local sample = {}
	do
		local n = 0
		for idx = 0, W * W - 1 do
			if buffer.readu8(MASK, idx) == 1 then
				n += 1
				if n % P.SAMPLE_STRIDE == 0 then
					local o = idx * 12
					local qx = buffer.readf32(POS, o)
					local qy = buffer.readf32(POS, o + 4)
					local qz = buffer.readf32(POS, o + 8)
					table.insert(sample, { qx, qy, qz,
						qx * FWD.X + qz * FWD.Z, qx * SIDE.X + qz * SIDE.Z,
						math.max(math.sqrt(qx * qx + qy * qy + qz * qz), 1e-9) })
				end
			end
		end
	end

	local function markAt(d, qx, qy, qz, f, s, l, k)
		local soft = d.soft or P.EDGE_SOFT
		return smoothstep(-soft, soft, k - d.g(qx, qy, qz, f, s, l))
	end

	-- one monotone bisection calibrates every design, because g is written so a
	-- larger k always admits more of the second colour
	local function calibrate(d): (number, number)
		local lo, hi, got = P.SEARCH_LO, P.SEARCH_HI, 0
		for _ = 1, P.SEARCH_ITERS do
			local mid = (lo + hi) / 2
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.TICK_EVERY == 0 then Y.tick() end
				hit += markAt(d, q[1], q[2], q[3], q[4], q[5], q[6], mid)
			end
			got = hit / #sample
			if math.abs(got - P.COVERAGE_TARGET) <= P.COVERAGE_TOLERANCE then return mid, got end
			if got < P.COVERAGE_TARGET then lo = mid else hi = mid end
		end
		return (lo + hi) / 2, got
	end

	-- ===================================================================
	-- THE TERMINATOR RULE, MEASURED. All a light does is fall off monotonically
	-- from top to bottom, so "could lighting have drawn this?" is exactly "how
	-- well does a single height threshold predict where the mark is?" -- J is
	-- Youden's J of the best such threshold. lit is where the mark SITS: mean
	-- lambert over the mark against mean lambert over the whole body.
	-- ===================================================================
	local function lightFit(d, k: number): (number, number)
		local B = P.SHADOW_BINS
		local wHist, nHist = table.create(B, 0), table.create(B, 0)
		local lo, hi = math.huge, -math.huge
		for _, q in ipairs(sample) do
			if q[2] < lo then lo = q[2] end
			if q[2] > hi then hi = q[2] end
		end
		local span = math.max(hi - lo, 1e-9)
		local mark, total = 0, 0
		local litMark, litAll = 0, 0
		for si, q in ipairs(sample) do
			if si % P.TICK_EVERY == 0 then Y.tick() end
			local b = math.clamp(math.floor((q[2] - lo) / span * B), 0, B - 1) + 1
			local lit = math.max(0, q[2] / q[6])
			litAll += lit
			if markAt(d, q[1], q[2], q[3], q[4], q[5], q[6], k) > 0.5 then
				wHist[b] += 1; mark += 1; litMark += lit
			else
				nHist[b] += 1
			end
			total += 1
		end
		local litRatio = (mark > 0 and litAll > 0)
			and (litMark / mark) / (litAll / total) or 0
		if mark == 0 or mark == total then return 1, litRatio end
		local cw, cn, best = 0, 0, 0
		for b = 1, B do
			cw += wHist[b]
			cn += nHist[b]
			local j = math.abs(cw / mark - cn / (total - mark))
			if j > best then best = j end
		end
		return best, litRatio
	end

	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == P.ROOT_NAME then c:Destroy() end
	end
	local root = Instance.new("Model")
	root.Name = P.ROOT_NAME
	root.Parent = workspace

	local localOff = Vector3.new(M.CX, M.CY, M.CZ)
	local buf = buffer.create(W * W * 4)

	-- median texel step, for turning the area/perimeter ratio into studs
	local stepSum, stepN = 0, 0
	do
		local mid = W // 2
		for x = 0, W - 2 do
			local i1, i2 = mid * W + x, mid * W + x + 1
			if buffer.readu8(MASK, i1) == 1 and buffer.readu8(MASK, i2) == 1 then
				local o1, o2 = i1 * 12, i2 * 12
				stepSum += math.sqrt(
					(buffer.readf32(POS, o1) - buffer.readf32(POS, o2)) ^ 2 +
					(buffer.readf32(POS, o1 + 4) - buffer.readf32(POS, o2 + 4)) ^ 2 +
					(buffer.readf32(POS, o1 + 8) - buffer.readf32(POS, o2 + 8)) ^ 2)
				stepN += 1
			end
		end
	end
	local texelStep = stepSum / math.max(1, stepN)

	local build = DESIGNS
	if #P.ONLY > 0 then
		local want = {}
		for _, n in ipairs(P.ONLY) do want[n] = true end
		build = {}
		for _, n in ipairs(P.ONLY) do
			for _, d in ipairs(DESIGNS) do
				if d.name == n then table.insert(build, d) want[n] = nil break end
			end
		end
		for n in pairs(want) do
			error(string.format("[Paint] P.ONLY names %q, which is not a design here", n))
		end
	end

	local function ground(cx: number, cz: number)
		if isBase then
			local g = Instance.new("Part")
			g.Size = Vector3.new(300, 1, 900) g.CFrame = CFrame.new(cx, -0.5, cz - 430)
			g.Color = P.GRASS g.Material = Enum.Material.Grass
			g.Anchored = true g.CanCollide = false g.CanQuery = false g.CanTouch = false
			g.Name = "grass" g.Parent = root
			local pad = Instance.new("Part")
			pad.Size = Vector3.new(8, 0.6, 8) pad.CFrame = CFrame.new(cx, P.BASE_PAD_TOP_Y, cz)
			pad.Color = P.PAD pad.Material = Enum.Material.Concrete
			pad.Anchored = true pad.CanCollide = false pad.CanQuery = false pad.CanTouch = false
			pad.Name = "pad" pad.Parent = root
		else
			-- RunwayBuilder's own road: Color3.fromHSV(i % 5 / 5, 1, 1), every
			-- hue, fully saturated, cycling every 200 studs. This is the backdrop
			-- that killed the glow shell, and a painted body is opaque against it.
			for i = 0, P.BAND_COUNT - 1 do
				local b = Instance.new("Part")
				b.Size = Vector3.new(300, 1, P.BAND_LENGTH)
				b.CFrame = CFrame.new(cx, -0.5, cz - i * P.BAND_LENGTH)
				b.Color = Color3.fromHSV((i % 5) / 5, 1, 1)
				b.Material = Enum.Material.Plastic
				b.Anchored = true b.CanCollide = false b.CanQuery = false b.CanTouch = false
				b.Name = "band" .. i b.Parent = root
			end
		end
	end

	local centreY = isBase and (P.BASE_PAD_TOP_Y + 0.3 + bodyHeightStuds / 2) or P.REVEAL_Y
	local worstPx, worstWhat = math.huge, "?"
	local rows = {}

	for di, d in ipairs(build) do
		Y.tick()
		local k, measured = calibrate(d)
		local shadow, lit = lightFit(d, k)

		-- ---- rule 1 and rule 3, checked rather than promised ----
		local lumGap, rgbDist = contrast(d.primary, d.mark)
		local hSep = hueSep(d.primary, d.mark)
		local pairs4 = eyeReadPairs(d.centres, k)
		local chP, chM = chroma(d.primary), chroma(d.mark)
		local _, wp = contrast(d.primary, P.LADDER_WHITE)
		local _, wm = contrast(d.mark, P.LADDER_WHITE)

		local br, bg, bb = d.primary.R, d.primary.G, d.primary.B
		local ar, ag, ab = d.mark.R, d.mark.G, d.mark.B

		local markN, edgeN = 0, 0
		local rowMark = table.create(W)
		for py = 0, W - 1 do
			if py % P.PAINT_TICK_ROWS == 0 then Y.tick() end
			for px = 0, W - 1 do
				local idx = py * W + px
				local off = idx * 4
				if buffer.readu8(MASK, idx) ~= 0 then
					local o = idx * 12
					local qx = buffer.readf32(POS, o)
					local qy = buffer.readf32(POS, o + 4)
					local qz = buffer.readf32(POS, o + 8)
					local fq = qx * FWD.X + qz * FWD.Z
					local sq = qx * SIDE.X + qz * SIDE.Z
					local lq = math.max(math.sqrt(qx * qx + qy * qy + qz * qz), 1e-9)
					local a = markAt(d, qx, qy, qz, fq, sq, lq, k)
					if a > 0.5 then markN += 1 end
					rowMark[px + 1] = a > 0.5
					if px > 0 and rowMark[px] ~= rowMark[px + 1] then edgeN += 1 end
					local pr = br + (ar - br) * a
					local pg = bg + (ag - bg) * a
					local pb = bb + (ab - bb) * a
					buffer.writeu8(buf, off, math.floor(math.clamp(pr, 0, 1) * 255 + 0.5))
					buffer.writeu8(buf, off + 1, math.floor(math.clamp(pg, 0, 1) * 255 + 0.5))
					buffer.writeu8(buf, off + 2, math.floor(math.clamp(pb, 0, 1) * 255 + 0.5))
					buffer.writeu8(buf, off + 3, 255)
				else
					rowMark[px + 1] = false
					buffer.writeu8(buf, off, 0); buffer.writeu8(buf, off + 1, 0)
					buffer.writeu8(buf, off + 2, 0); buffer.writeu8(buf, off + 3, 255)
				end
			end
		end

		-- characteristic width 2A/P, which is exactly the bar width for a bar.
		-- Reported at BOTH framings from the ONE measurement: the width in body
		-- radii is a property of the design, so it converts to pixels through
		-- each framing's own body size rather than being re-measured there.
		local widthRadii = (edgeN > 0) and (2 * markN / edgeN) * texelStep or 0
		local featBase = widthRadii * (P.BASE_WIDTH_STUDS / 2) * pxBase
		local featReveal = widthRadii * (P.REVEAL_WIDTH_STUDS / 2) * pxReveal
		local bind = math.min(featBase, featReveal)
		if bind < worstPx then worstPx, worstWhat = bind, d.name end

		local img = AssetService:CreateEditableImage({ Size = Vector2.new(W, W) })
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, W), buf)
		Y.mark()

		local cx = (di - 1) * P.CELL_SPACING
		local cz = P.CELL_Z
		ground(cx, cz)

		local m = Instance.new("Model")
		m.Name = string.format("L%d_%s", di, d.name)
		m.Parent = root
		local bodyCF = CFrame.new(cx, centreY, cz) * CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)

		local body = source:Clone()
		body.Size = source.Size * partScale
		body.Name = "body"
		body.Color = Color3.new(1, 1, 1)
		body.Material = P.BODY_MATERIAL
		body.Anchored = true
		body.CanCollide = false body.CanQuery = false body.CanTouch = false
		pcall(function() body.TextureID = "" end)
		body.TextureContent = Content.fromObject(img)
		body.CFrame = bodyCF * CFrame.new(-localOff)
		body.Parent = m
		m.PrimaryPart = body

		-- ---- THE FACE, ON, IN EVERY CELL ----
		-- A blank body is not what a player ever sees, and it is exactly the
		-- condition under which the wrong thing looks like the subject.
		--
		-- THE FACE OFFSETS ARE IN STUDS AT A 14-STUD BODY, NOT IN MESH UNITS,
		-- and getting that wrong is not a subtle failure. EXPLORE_PATTERNS
		-- applies no scaling at all to these numbers because its own lab body is
		-- 14 studs -- the size they were measured off -- so the scale factor
		-- hiding in that file is 1 and invisible. Scaling them by
		-- studsPerMeshUnit instead (3.5 on this mesh, which is 2 units wide)
		-- made every face part 7x too big and pushed it 7x too far out: the eyes
		-- ended up 12 studs off-centre and four studs from the lens, filling the
		-- frame and hiding the body they belong to. The first base shot was of
		-- nothing but two enormous eyes.
		local faceScale = widthStuds / P.FACE_REF_WIDTH_STUDS
		for _, spec in ipairs(FACE_PARTS) do
			local part = AssetService:CreateMeshPartAsync(Content.fromUri(spec.mesh))
			part.Name = spec.name
			part.Size = spec.size * faceScale
			part.Color = spec.color
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false part.CanQuery = false part.CanTouch = false
			part.CFrame = bodyCF * CFrame.new(spec.rel.Position * faceScale)
			part.Parent = m
		end
		Y.mark()

		m:SetAttribute("BodyCentre", Vector3.new(cx, centreY, cz))
		m:SetAttribute("Index", di)
		m:SetAttribute("Design", d.name)
		m:SetAttribute("Framing", P.FRAMING)
		m:SetAttribute("Distance", distance)
		m:SetAttribute("EyeY", isBase and P.BASE_EYE_Y or P.REVEAL_Y)
		m:SetAttribute("Coverage", measured)
		m:SetAttribute("FeatureBasePx", featBase)
		m:SetAttribute("ShadowAlignment", shadow)
		m:SetAttribute("LitRatio", lit)

		table.insert(rows, {
			name = d.name, k = k, cov = measured, fb = featBase, fr = featReveal,
			shadow = shadow, lit = lit, lum = lumGap, rgb = rgbDist, hue = hSep,
			pairs4 = pairs4, placed = d.centres and #d.centres or 0,
			chP = chP, chM = chM, wp = wp, wm = wm,
			pn = d.primaryName, mn = d.markName, note = d.note,
		})
	end

	-- ---- the table, and the two gates that are this tier's own ----
	log("[Paint] %-10s %-12s %-14s cov      k    featBase featReveal   J    lit",
		"design", "primary", "mark")
	for _, r in ipairs(rows) do
		local flag = (r.shadow >= P.SHADOW_WARN or r.lit <= P.LIT_LO or r.lit >= P.LIT_HI)
			and " <-- terminator" or ""
		log("[Paint] %-10s %-12s %-14s %4.1f%% %6.3f %6.1f px %6.1f px  %.2f  %.2f%s",
			r.name, r.pn, r.mn, r.cov * 100, r.k, r.fb, r.fr, r.shadow, r.lit, flag)
	end
	log("[Paint] ---- rule 1: both colours chromatic (chroma floor %.2f) ----", P.CHROMA_FLOOR)
	for _, r in ipairs(rows) do
		local bad = (r.chP < P.CHROMA_FLOOR or r.chM < P.CHROMA_FLOOR) and " <-- NOT CHROMATIC" or ""
		log("[Paint] %-10s chroma %.2f / %.2f | rgb distance from the ladder's white %.2f / %.2f%s",
			r.name, r.chP, r.chM, r.wp, r.wm, bad)
	end
	log("[Paint] ---- rule 3: lum and rgb against the ladder's own worst (white on"
		.. " yellow, %.3f / %.3f), hue against the %.0f deg floor ----",
		P.CONTRAST_LUM_FLOOR, P.CONTRAST_RGB_FLOOR, P.CONTRAST_HUE_FLOOR)
	for _, r in ipairs(rows) do
		-- THE THREE ARE REPORTED SEPARATELY AND FLAGGED SEPARATELY, because the
		-- one failure this gate has caught passed two of them comfortably. A
		-- single combined score would have hidden exactly the case the third
		-- number was added for.
		local bad = ""
		if r.lum < P.CONTRAST_LUM_FLOOR then bad ..= " <-- LUM BELOW THE LADDER'S WORST" end
		if r.rgb < P.CONTRAST_RGB_FLOOR then bad ..= " <-- RGB BELOW THE LADDER'S WORST" end
		if r.hue < P.CONTRAST_HUE_FLOOR then bad ..= " <-- ONE COLOUR IN TWO SHADES" end
		log("[Paint] %-10s lum gap %.3f | rgb distance %.3f | hue apart %3.0f deg%s",
			r.name, r.lum, r.rgb, r.hue, bad)
	end
	log("[Paint] ---- rule 4: mirrored pairs against the eyes' own footprint"
		.. " (|az| <= %.1f deg, elevation %.1f .. %.1f deg, solved from FACE_PARTS) ----",
		EYE_AZ_HALF_DEG, EYE_EL_LO_DEG, EYE_EL_HI_DEG)
	for _, r in ipairs(rows) do
		if r.placed == 0 then
			-- SWITCHED OFF FOR A CLASS OF INPUTS RATHER THAN PRINTED AS ZERO.
			-- A field has no placed centres, so "how many mirrored pairs" is not
			-- a question about it -- and a 0 in this column would read as a pass
			-- it never earned. dev/README.md's habit, one metric later.
			log("[Paint] %-10s no placed features -- rule 4 does not apply", r.name)
		elseif #r.pairs4 == 0 then
			log("[Paint] %-10s %d placed features, NO mirrored pair", r.name, r.placed)
		else
			for _, q in ipairs(r.pairs4) do
				log("[Paint] %-10s mirrored pair at el %5.1f deg | reaches %5.1f deg from the"
					.. " midline | in the eye elevation band: %-5s%s",
					r.name, q.el, q.approach, tostring(q.inBand),
					q.fails and " <-- WILL BE READ AS AN EYE" or "")
			end
		end
	end
	log("[Paint] narrowest feature %.1f px (%s) at the tighter of the two framings,"
		.. " floor is %d px", worstPx, worstWhat, P.MIN_FEATURE_PX)
	log("[Paint] watchdog worst hold %.1f ms | built %d cells at %d studs apart in %.2f s",
		Y.worstMs(), #rows, P.CELL_SPACING, os.clock() - t0)
	log("[Paint] undo with workspace.%s:Destroy()", P.ROOT_NAME)

	local out = table.concat(lines, "\n")
	print(out)
	return out
end

-- SPAWNED BY DEFAULT. execute_luau over the Studio bridge is capped at ~30 s and
-- a script that overruns it does not stop -- it keeps running while the caller
-- is told it timed out, and two of those interleave on the main thread. So the
-- work goes on its own thread and the result lands on an attribute the caller
-- can poll. See dev/README.md.
if P.SPAWN then
	workspace:SetAttribute("PaintDone", false)
	workspace:SetAttribute("PaintLog", "")
	task.spawn(function()
		local ok, res = pcall(run)
		workspace:SetAttribute("PaintLog", tostring(res))
		workspace:SetAttribute("PaintDone", true)
		if not ok then warn(res) end
	end)
	return "[Paint] running; poll workspace:GetAttribute(\"PaintDone\")"
end
return run()
