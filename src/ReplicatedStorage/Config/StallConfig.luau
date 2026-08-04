--!strict
-- Every constant for the two shop stalls lives here, and ONLY here. Built
-- at runtime by MapBuilder.server.luau, same "generated, not hand-
-- authored" reasoning as RunwayBuilder -- only the Baseplate itself
-- belongs in default.project.json.
--
-- Both stalls are the SAME shape, mirrored: each stall's own `face` --
-- -sign(x0), computed at build time, never stored here -- points every
-- X-offset below back toward the road's centerline, so the counter/panel
-- faces inward toward the swings regardless of which stall (left or
-- right) is being built. STALL_SHOPKEEPER placeholder is a plain coloured
-- torso+head, to be replaced with a real NPC later -- see MapBuilder.

export type StallConfig = {
	STALL_X_POSITIONS: { number },
	STALL_CENTER_Z: number,
	STALL_DEPTH: number,

	STALL_POST_SIZE: Vector3,
	STALL_POST_X_OFFSET: number,
	STALL_POST_Z_OFFSET: number,
	STALL_POST_Y_OFFSET: number,
	STALL_POST_COLOR: Color3,
	STALL_POST_MATERIAL: Enum.Material,

	STALL_PANEL_SIZE: Vector3,
	STALL_PANEL_X_OFFSET: number,
	STALL_PANEL_Y_OFFSET: number,
	STALL_PANEL_COLOR: Color3,
	STALL_PANEL_MATERIAL: Enum.Material,

	STALL_RAIL_SIZE: Vector3,
	STALL_RAIL_X_OFFSET: number,
	STALL_RAIL_Y_OFFSET: number,
	STALL_RAIL_COLOR: Color3,
	STALL_RAIL_MATERIAL: Enum.Material,

	STALL_COUNTER_SIZE: Vector3,
	STALL_COUNTER_X_OFFSET: number,
	STALL_COUNTER_Y_OFFSET: number,
	STALL_COUNTER_COLOR: Color3,
	STALL_COUNTER_MATERIAL: Enum.Material,

	STALL_ROOF_DECK_SIZE: Vector3,
	STALL_ROOF_DECK_Y_OFFSET: number,
	STALL_ROOF_DECK_COLOR: Color3,
	STALL_ROOF_DECK_MATERIAL: Enum.Material,

	STALL_ROOF_BAND_SIZE: Vector3,
	STALL_ROOF_BAND_Y_OFFSET: number,
	STALL_ROOF_BAND_COLOR: Color3,
	STALL_ROOF_BAND_MATERIAL: Enum.Material,

	STALL_SHOPKEEPER_X_OFFSET: number,
	STALL_SHOPKEEPER_MATERIAL: Enum.Material,
	STALL_TORSO_SIZE: Vector3,
	STALL_TORSO_Y_OFFSET: number,
	STALL_TORSO_COLOR: Color3,
	STALL_HEAD_SIZE: Vector3,
	STALL_HEAD_Y_OFFSET: number,
	STALL_HEAD_COLOR: Color3,

	STALL_SIGN_X_OFFSET: number,
	STALL_SIGN_Z: number,
	STALL_SIGN_LEG_SIZE: Vector3,
	STALL_SIGN_LEG_Y_OFFSET: number,
	STALL_SIGN_LEG_COLOR: Color3,
	STALL_SIGN_LEG_MATERIAL: Enum.Material,
	STALL_SIGN_BOARD_SIZE: Vector3,
	STALL_SIGN_BOARD_Y_OFFSET: number,
	STALL_SIGN_BOARD_COLOR: Color3,
	STALL_SIGN_BOARD_MATERIAL: Enum.Material,
}

local StallConfig: StallConfig = {
	STALL_X_POSITIONS = { -222, 222 },
	-- Moved from 174 (behind every plot) to level with the walkway -- see
	-- PathConfig.BACK_WALKWAY_Z -- when the shop walkway moved from behind
	-- the bases to between the swings and the bases -- see the written
	-- report. 76, not 62: a later pass moved the walkway again, from 62 to
	-- 76, to give the player's post-flight return position more clearance
	-- (see PathConfig's own header) -- this follows it exactly, same as
	-- STALL_SIGN_Z below. X positions, footprint, and "faces inward" logic
	-- are all unchanged; only this Z and STALL_SIGN_Z move.
	STALL_CENTER_Z = 76,
	STALL_DEPTH = 30,

	-- Four posts: X = x0 +- this, Z = STALL_CENTER_Z +- this -- all four
	-- combinations, one post per corner.
	STALL_POST_SIZE = Vector3.new(1.6, 15, 1.6),
	STALL_POST_X_OFFSET = 1.6,
	STALL_POST_Z_OFFSET = 14,
	STALL_POST_Y_OFFSET = 7.5,
	STALL_POST_COLOR = Color3.fromRGB(126, 88, 56),
	STALL_POST_MATERIAL = Enum.Material.WoodPlanks,

	-- Front panel: X = x0 + face*this.
	STALL_PANEL_SIZE = Vector3.new(1.4, 6, 30),
	STALL_PANEL_X_OFFSET = 1.8,
	STALL_PANEL_Y_OFFSET = 3,
	STALL_PANEL_COLOR = Color3.fromRGB(126, 88, 56),
	STALL_PANEL_MATERIAL = Enum.Material.WoodPlanks,

	-- Panel rail: same X offset as the front panel, sits just above it.
	STALL_RAIL_SIZE = Vector3.new(1.8, 1, 30),
	STALL_RAIL_X_OFFSET = 1.8,
	STALL_RAIL_Y_OFFSET = 4.4,
	STALL_RAIL_COLOR = Color3.fromRGB(96, 66, 42),
	STALL_RAIL_MATERIAL = Enum.Material.WoodPlanks,

	-- Counter top: X = x0 + face*this.
	STALL_COUNTER_SIZE = Vector3.new(7, 0.8, 32),
	STALL_COUNTER_X_OFFSET = 0.6,
	STALL_COUNTER_Y_OFFSET = 6.4,
	STALL_COUNTER_COLOR = Color3.fromRGB(78, 78, 84),
	STALL_COUNTER_MATERIAL = Enum.Material.Slate,

	-- Roof deck: centred on x0, no X offset.
	STALL_ROOF_DECK_SIZE = Vector3.new(7, 0.6, 33),
	STALL_ROOF_DECK_Y_OFFSET = 15,
	STALL_ROOF_DECK_COLOR = Color3.fromRGB(96, 66, 42),
	STALL_ROOF_DECK_MATERIAL = Enum.Material.WoodPlanks,

	-- Roof band: centred on x0, no X offset.
	STALL_ROOF_BAND_SIZE = Vector3.new(6, 2.4, 33),
	STALL_ROOF_BAND_Y_OFFSET = 16.2,
	STALL_ROOF_BAND_COLOR = Color3.fromRGB(56, 118, 196),
	STALL_ROOF_BAND_MATERIAL = Enum.Material.SmoothPlastic,

	-- Shopkeeper placeholder: X = x0 - face*this (the OPPOSITE sign from
	-- the panel/counter/sign offsets above -- the shopkeeper stands BEHIND
	-- the counter, toward the back of the stall, not out front of it).
	STALL_SHOPKEEPER_X_OFFSET = 1.4,
	STALL_SHOPKEEPER_MATERIAL = Enum.Material.SmoothPlastic,
	STALL_TORSO_SIZE = Vector3.new(2, 4, 3),
	STALL_TORSO_Y_OFFSET = 5.5,
	STALL_TORSO_COLOR = Color3.fromRGB(72, 110, 176),
	STALL_HEAD_SIZE = Vector3.new(2, 2, 2),
	STALL_HEAD_Y_OFFSET = 8.5,
	STALL_HEAD_COLOR = Color3.fromRGB(226, 190, 148),

	-- Sign: X = x0 + face*this, Z = its own STALL_SIGN_Z (64, NOT
	-- STALL_CENTER_Z) -- stands forward of the stall itself, same -12
	-- offset from STALL_CENTER_Z the stall has always used (162 when
	-- STALL_CENTER_Z was 174; 50 when it was 62; now 64 = 76 - 12).
	STALL_SIGN_X_OFFSET = 12,
	STALL_SIGN_Z = 64,
	STALL_SIGN_LEG_SIZE = Vector3.new(1.6, 8, 1.6),
	STALL_SIGN_LEG_Y_OFFSET = 4,
	STALL_SIGN_LEG_COLOR = Color3.fromRGB(96, 66, 42),
	STALL_SIGN_LEG_MATERIAL = Enum.Material.WoodPlanks,
	STALL_SIGN_BOARD_SIZE = Vector3.new(1, 9, 14),
	STALL_SIGN_BOARD_Y_OFFSET = 11,
	STALL_SIGN_BOARD_COLOR = Color3.fromRGB(126, 88, 56),
	STALL_SIGN_BOARD_MATERIAL = Enum.Material.WoodPlanks,
}

return StallConfig
