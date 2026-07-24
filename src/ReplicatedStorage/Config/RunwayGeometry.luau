--!strict
-- Single source of truth for where the rainbow runway sits in world space.
-- RunwayBuilder (which places the coloured band parts) and LaunchServer
-- (which scores a landing against them) both read RUNWAY_START_Z from HERE,
-- computed once, the same way, from the same Baseplate part -- neither script
-- computes its own copy. That's what guarantees the band a player visibly
-- lands on and the band their luck is drawn from can never drift apart: there
-- is only one formula for "where band 0 begins," used by both consumers.
local Workspace = game:GetService("Workspace")

local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart

local RunwayGeometry = {}

-- Z coordinate where band 0 begins: the far edge of the support platform, in
-- the flight direction (-Z). Read from the Baseplate part itself, not a
-- hardcoded number, so it can never fall out of sync with wherever the
-- platform actually sits in the place file.
RunwayGeometry.RUNWAY_START_Z = baseplate.Position.Z - baseplate.Size.Z / 2

return RunwayGeometry
