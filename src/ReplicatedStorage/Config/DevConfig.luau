--!strict
-- ============================================================
-- TODO: REMOVE BEFORE LAUNCH -- this is the dev-testing panel's config.
-- See DevPanelServer.server.luau, DevPanelClient.client.luau, and the
-- "DEV PANEL SUPPORT" block in PlayerProfile.luau -- all four either exist
-- solely to support this panel or (PlayerProfile.luau) contain a clearly-
-- marked, easily-deleted section that does. Delete all four to strip the
-- panel entirely -- see the written report for the exact list.
--
-- This file itself is inert without those others: it's plain data (a
-- keycode, a UserId list, some numbers), not a remote, so its mere presence
-- in a published game is harmless -- but it should still go, since nothing
-- reads it once the panel is gone.
-- ============================================================
-- SECURITY NOTE: this allowlist is the SECOND of two independent gates (see
-- DevPanelServer.server.luau for the first, a hard RunService:IsStudio()
-- check that keeps the dev remotes from existing at all outside Studio).
-- Checked on EVERY dev action server-side, not just once -- so even if the
-- Studio gate is ever loosened, only these UserIds can do anything.

export type DevConfig = {
	-- Key that toggles the dev panel's visibility (client-side only -- see
	-- DevPanelClient.client.luau). F4 was picked as unlikely to collide with
	-- anything else bound in this project (Space is the swing
	-- release/box-press key) or with Roblox's own reserved debug keys (F9
	-- Developer Console, F8 stats).
	TOGGLE_KEYCODE: Enum.KeyCode,
	-- UserIds allowed to use the panel at all -- checked server-side in
	-- every DevPanelServer action handler. Add your own UserId(s) here.
	ALLOWLISTED_USER_IDS: { number },
	-- The three fixed "give money" quick amounts (requirement: "+1K, +100K,
	-- +10M").
	MONEY_QUICK_AMOUNTS: { number },
}

local DevConfig: DevConfig = {
	TOGGLE_KEYCODE = Enum.KeyCode.F4,
	ALLOWLISTED_USER_IDS = { 80249110 },
	MONEY_QUICK_AMOUNTS = { 1000, 100000, 10000000 },
}

return DevConfig
