-- Runs gallery/SwingGallery.server.luau under Lune via rbxshim.luau, so its
-- measurement/diagnostic/camera-framing output can be read straight from a
-- terminal instead of requiring a Studio round-trip for every change.
--
-- USAGE (from the repo root):
--   lune run dev/run_gallery.luau
--
-- Reads the real gallery/SwingGallery.server.luau and every module it
-- requires straight off disk each run -- there is no separate copy to keep
-- in sync; edit the real source files and rerun.
local shim = require("./rbxshim")
shim.loadLuauModule("gallery/SwingGallery.server.luau")
