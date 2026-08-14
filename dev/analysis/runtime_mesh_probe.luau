--!strict
-- runtime_mesh_probe.luau -- MEASUREMENT ONLY. Builds nothing permanent, uploads
-- nothing, changes no mask.
--
-- Answers the two questions that decide whether the tier-mark geometry needs an
-- asset-upload pipeline at all:
--
--   2a. Is CreateMeshPartAsync available in the RUNTIME capability context the
--       shipping builder module would run in (server / client), as opposed to
--       edit mode where the prototype was developed?
--
--   2b. Does a SERVER-generated in-memory MeshPart replicate to clients with
--       usable geometry, or does each client have to build its own?
--
-- These are not edit-mode questions. Run them inside a playtest, against the
-- server and client contexts separately.
--
-- HOW TO RUN (via the Studio MCP bridge):
--   start_playtest
--   execute_luau target="server"   <- SECTION A
--   execute_luau target="client-1" <- SECTION B
--   stop_playtest
--
-- SECTION B must run AFTER section A, in the same playtest.
--
-- ===========================================================================
-- THE REPLICATION DETECTOR
--
-- Distinguishing "replicated with real geometry" from "replicated as a
-- placeholder" needs a signal that survives the network boundary. InitialSize
-- is the right one, and BUILD_TIERMARKS' marker-triangle trick is what makes it
-- diagnostic: the generated mesh's bbox is pinned to the body mesh's bbox, so a
-- correctly-built mesh has a distinctly NON-CUBIC InitialSize (roughly
-- 2.0006 x 1.3550 x 2.0014 -- squashed dome, wider than tall). The
-- missing-mesh placeholder is a UNIT CUBE. Those are trivially separable.
--
-- So: the server stamps its own native mesh size onto the part as an attribute,
-- and the client compares what it actually sees against that stamp. Equal means
-- the geometry crossed. Cubic-or-different means it did not.
--
-- WHICH PROPERTY HOLDS THAT SIZE IS NOT FIXED. This probe was designed around
-- InitialSize, but in this Studio's script context InitialSize is NOT a readable
-- member of MeshPart -- reading it throws
--     InitialSize is not a valid member of MeshPart
-- and the readable name is MeshSize. Measured in edit mode on a rebuilt tier
-- mark: MeshSize = 2.0006, 1.3550, 2.0014, i.e. the value the detector wants.
--
-- So both sections go through nativeSize(), which tries InitialSize first and
-- falls back to MeshSize, and REPORTS WHICH ONE IT USED. That report is part of
-- the 2b result, not incidental logging: MeshSize is not the property this
-- detector was designed around and there is no advance guarantee it replicates
-- the same way, so a run that does not say which property carried the value has
-- not actually answered 2b. Section A also stamps its property name, so the
-- client can say whether the two contexts even agree on the name.
-- ===========================================================================

--[[ ======================= SECTION A -- SERVER ==========================

local AssetService = game:GetService("AssetService")
local out = {}
local function log(...) table.insert(out, string.format(...)) end

-- See the header. InitialSize is unreadable in this Studio's script context;
-- MeshSize is. Returns the size and the property name it came from -- the name
-- is reported, because which property carries the value is part of the answer.
local function nativeSize(mp): (Vector3?, string)
    local okI, vI = pcall(function() return (mp :: any).InitialSize end)
    if okI then return vI, "InitialSize" end
    local okM, vM = pcall(function() return (mp :: any).MeshSize end)
    if okM then return vM, "MeshSize" end
    return nil, "NEITHER"
end

log("context: %s", tostring(game:GetService("RunService"):IsServer() and "SERVER" or "CLIENT"))

-- 2a -- is the API even reachable here?
local okCreate, em = pcall(function() return AssetService:CreateEditableMesh() end)
log("CreateEditableMesh: %s%s", okCreate and "OK" or "BLOCKED",
    okCreate and "" or (" -- " .. tostring(em)))
if not okCreate then
    log("VERDICT 2a: EditableMesh unavailable at runtime. Upload path required.")
    return table.concat(out, "\n")
end

-- ===================================================================
-- TUNER TIMING -- the join-cost delta.
--
-- BAKED CONSTANTS. The bisection is deterministic: same masks, same 96x48
-- grid, same targets, same k every run. So the shipping builder has no reason
-- to rediscover them on every client. These are the identical values
-- precomputed, NOT a mask change -- nothing about the emitted geometry differs.
--
--   Rare      k = -1.157   (target 35%)
--   Epic      k = -0.642   (target 50%)
--   Legendary k =  0.690   (target 65%)
--
-- The block below times BOTH paths so the delta is a measured number rather
-- than an argument, and it RE-DERIVES k as a self-check: if the rediscovered
-- values do not match the baked ones, baking is not safe and the run says so
-- instead of quietly trusting the constants.
--
-- !! THE MASK MATHS BELOW IS A VERBATIM COPY FROM BUILD_TIERMARKS.luau. !!
-- It has to be, because this probe runs standalone in a runtime context where
-- that file is not a module. If the two ever diverge, THIS FILE IS THE WRONG
-- ONE -- the timing would be measuring maths the builder does not use. Re-copy
-- rather than edit in place.
-- ===================================================================
local BAKED_K = { Rare = -1.157, Epic = -0.642, Legendary = 0.690 }
local TAU_M = 2 * math.pi
local NTH, NT = 96, 48
local TMIN, TMAX = 0.02, 0.97
local FACE_AZ, FACE_ANG = math.rad(-141.5), math.rad(46)
local FACE_T_LO, FACE_T_HI = 0.26, 0.68

local PROF = {
    { 0.000, 0.8592 }, { 0.062, 0.9197 }, { 0.125, 0.9722 }, { 0.188, 0.9940 },
    { 0.250, 0.9999 }, { 0.312, 1.0007 }, { 0.375, 0.9949 }, { 0.438, 0.9838 },
    { 0.500, 0.9558 }, { 0.562, 0.9298 }, { 0.625, 0.8799 }, { 0.688, 0.8390 },
    { 0.750, 0.7648 }, { 0.812, 0.6735 }, { 0.875, 0.5417 }, { 0.938, 0.3695 },
}
local MNY, MXY = -0.6775, 0.6775
local function radiusAt(t)
    t = math.clamp(t, 0, 1)
    if t <= PROF[1][1] then return PROF[1][2] end
    if t >= PROF[#PROF][1] then return PROF[#PROF][2] end
    for i = 1, #PROF - 1 do
        local a, b = PROF[i], PROF[i + 1]
        if t >= a[1] and t <= b[1] then
            return a[2] + (b[2] - a[2]) * ((t - a[1]) / (b[1] - a[1]))
        end
    end
    return PROF[#PROF][2]
end
local function angdiff(a, b)
    local d = (a - b) % TAU_M
    if d > math.pi then d = TAU_M - d end
    return d
end
local function faceClear(th, t)
    return not (angdiff(th, FACE_AZ) < FACE_ANG and t > FACE_T_LO and t < FACE_T_HI)
end
local RARE_BLOBS = {
    { FACE_AZ + math.rad(60),  0.68, 1.15, 0.30 },
    { FACE_AZ + math.rad(165), 0.42, 1.35, 0.34 },
    { FACE_AZ + math.rad(255), 0.72, 1.05, 0.28 },
    { FACE_AZ + math.rad(200), 0.14, 1.25, 0.24 },
}
local function makeRare(k)
    local s = 1 + 0.22 * k
    return function(th, t)
        if not faceClear(th, t) then return false end
        for _, b in ipairs(RARE_BLOBS) do
            local da = angdiff(th, b[1]) / (b[3] * s)
            local dt = (t - b[2]) / (b[4] * s)
            local wob = 1 + 0.22 * math.sin(3 * th + 5 * t) + 0.14 * math.sin(7 * t)
            if (da * da + dt * dt) < wob * wob then return true end
        end
        return false
    end
end
local SPLASH_AZ = FACE_AZ + math.rad(175)
local function makeEpic(k)
    local s = 0.50 + 0.14 * k
    return function(th, t)
        if not faceClear(th, t) then return false end
        local edge = s + 0.30 * math.sin(3.0 * t * math.pi + 1.1) + 0.12 * math.sin(6.0 * t * math.pi)
        if angdiff(th, SPLASH_AZ) < edge * math.pi then return true end
        if angdiff(th, SPLASH_AZ + math.rad(120)) < 0.42 and math.abs(t - 0.30) < 0.13 then return true end
        if angdiff(th, SPLASH_AZ - math.rad(118)) < 0.30 and math.abs(t - 0.78) < 0.10 then return true end
        return false
    end
end
local function makeLegendary(k)
    return function(th, t)
        if not faceClear(th, t) then return false end
        local warp = 0.9 * math.sin(3.0 * t * math.pi + 1.7 * th) + 0.5 * math.sin(5.0 * th + 4.0 * t)
        local v = math.sin(5.0 * th + 2.4 * warp) + 0.75 * math.sin(7.5 * t * math.pi + 1.3 * warp)
        return v > -0.62 * k
    end
end
local function measure(mask)
    local inA, allA = 0, 0
    for i = 0, NT - 1 do
        local t0 = TMIN + (TMAX - TMIN) * i / NT
        local t1 = TMIN + (TMAX - TMIN) * (i + 1) / NT
        local tm = (t0 + t1) / 2
        local r0, r1 = radiusAt(t0), radiusAt(t1)
        local dy = (MXY - MNY) * (t1 - t0)
        local cell = radiusAt(tm) * (TAU_M / NTH) * math.sqrt((r1 - r0) ^ 2 + dy * dy)
        for j = 0, NTH - 1 do
            allA += cell
            if mask(TAU_M * (j + 0.5) / NTH, tm) then inA += cell end
        end
    end
    return inA / allA
end
local function tune(make, target)
    local lo, hi = -4, 4
    for _ = 1, 30 do
        local mid = (lo + hi) / 2
        if measure(make(mid)) < target then lo = mid else hi = mid end
    end
    return (lo + hi) / 2
end

-- PATH A -- rediscover k, as the prototype does today.
local ta = os.clock()
local kR = tune(makeRare, 0.35)
local kE = tune(makeEpic, 0.50)
local kL = tune(makeLegendary, 0.65)
local tunerMs = (os.clock() - ta) * 1000
log("PATH A (tuner runs): %.1f ms for 3 tiers (~415k mask evals)", tunerMs)
log("  rediscovered k: Rare=%.3f Epic=%.3f Legendary=%.3f", kR, kE, kL)
log("  baked k:        Rare=%.3f Epic=%.3f Legendary=%.3f",
    BAKED_K.Rare, BAKED_K.Epic, BAKED_K.Legendary)

-- The self-check. Tolerance is loose because the printed constants carry only
-- 3 decimals; the bisection resolves far finer than that.
local drift = math.max(math.abs(kR - BAKED_K.Rare), math.abs(kE - BAKED_K.Epic),
    math.abs(kL - BAKED_K.Legendary))
if drift < 1e-3 then
    log("  BAKING IS SAFE -- max drift %.2e, within print precision.", drift)
else
    log("  !! BAKING UNSAFE -- max drift %.2e. Constants do not reproduce.", drift)
end

-- PATH B -- constants baked, tuner skipped entirely.
local tb = os.clock()
local _ = { makeRare(BAKED_K.Rare), makeEpic(BAKED_K.Epic), makeLegendary(BAKED_K.Legendary) }
local bakedMs = (os.clock() - tb) * 1000
log("PATH B (k baked): %.3f ms -- this is the whole saving", bakedMs)
log("DELTA: baking removes %.1f ms per client at join", tunerMs - bakedMs)

-- Minimal stand-in for a tier shell: a marker-pinned bbox plus a little
-- geometry, matching how BUILD_TIERMARKS shapes its meshes. Deliberately NOT
-- the real masks -- this measures the pipeline, not the art.
local BB = { mnx = -1.0003, mxx = 1.0003, mny = -0.6775, mxy = 0.6775, mnz = -1.0007, mxz = 1.0007 }
local e = 1e-4
local function marker(x, y, z, sx, sy)
    local a = em:AddVertex(Vector3.new(x, y, z))
    local b = em:AddVertex(Vector3.new(x + sx * e, y, z))
    local c = em:AddVertex(Vector3.new(x, y + sy * e, z))
    em:AddTriangle(a, b, c)
end
marker(BB.mnx, BB.mny, BB.mnz, 1, 1)
marker(BB.mxx, BB.mxy, BB.mxz, -1, -1)

-- a band of quads so the part has visible surface to eyeball
local TAU = 2 * math.pi
for j = 0, 47 do
    local th0, th1 = TAU * j / 48, TAU * (j + 1) / 48
    local function v(th, y) return em:AddVertex(Vector3.new(0.98 * math.sin(th), y, 0.98 * math.cos(th))) end
    local a, b, c, d = v(th0, 0.10), v(th1, 0.10), v(th1, 0.42), v(th0, 0.42)
    em:AddTriangle(a, b, c); em:AddTriangle(a, c, d)
end

local t0 = os.clock()
local okMP, mp = pcall(function() return AssetService:CreateMeshPartAsync(Content.fromObject(em)) end)
local dt = os.clock() - t0
log("CreateMeshPartAsync: %s%s", okMP and "OK" or "BLOCKED",
    okMP and string.format(" (%.1f ms)", dt * 1000) or (" -- " .. tostring(mp)))
if not okMP then
    log("VERDICT 2a: CreateMeshPartAsync blocked at runtime. Upload path required.")
    return table.concat(out, "\n")
end

log("VERDICT 2a: available on the server.")
local isz, propUsed = nativeSize(mp)
log("server native size = %s  (read from %s)", tostring(isz), propUsed)
if not isz then
    log("VERDICT 2b: UNTESTABLE -- neither InitialSize nor MeshSize is readable")
    log("            on the server, so there is no detector to compare against.")
    return table.concat(out, "\n")
end

mp.Name = "ProbeMesh"
mp.Anchored = true
mp.CanCollide = false; mp.CanQuery = false; mp.CanTouch = false; mp.CastShadow = false
mp.Size = isz
mp.CFrame = CFrame.new(0, 50, 0)
-- the stamp the client will compare against, plus the property it came from so
-- the client can report whether both contexts agree on the name
mp:SetAttribute("ServerNativeSize", tostring(isz))
mp:SetAttribute("ServerSizeProp", propUsed)
mp.Parent = workspace

log("parented to workspace.ProbeMesh -- now run SECTION B on client-1")
return table.concat(out, "\n")

========================= END SECTION A ============================ ]]

--[[ ======================= SECTION B -- CLIENT ==========================

local out = {}
local function log(...) table.insert(out, string.format(...)) end

-- Same helper as section A -- see the header.
local function nativeSize(mp): (Vector3?, string)
    local okI, vI = pcall(function() return (mp :: any).InitialSize end)
    if okI then return vI, "InitialSize" end
    local okM, vM = pcall(function() return (mp :: any).MeshSize end)
    if okM then return vM, "MeshSize" end
    return nil, "NEITHER"
end

-- The non-cubic signature a correctly-built mesh must show. A unit cube here is
-- the missing-mesh placeholder -- a RESULT for 2b, not a failure of the probe.
local EXPECT = Vector3.new(2.0006, 1.3550, 2.0014)

log("context: %s", tostring(game:GetService("RunService"):IsClient() and "CLIENT" or "SERVER"))

-- 2b -- did the server's part cross, and with what?
local mp = workspace:WaitForChild("ProbeMesh", 10)
if not mp then
    log("VERDICT 2b: part did not replicate AT ALL within 10s.")
    return table.concat(out, "\n")
end

local stamped = mp:GetAttribute("ServerNativeSize")
local serverProp = mp:GetAttribute("ServerSizeProp")
local seenV, clientProp = nativeSize(mp)
local seen = tostring(seenV)
log("server-stamped size: %s  (server read it from %s)", tostring(stamped), tostring(serverProp))
log("client-visible size: %s  (client read it from %s)", seen, clientProp)
log("property agreement: %s", (serverProp == clientProp)
    and ("both contexts used " .. clientProp)
    or string.format("MISMATCH -- server used %s, client used %s",
        tostring(serverProp), clientProp))

if seenV == nil then
    log("VERDICT 2b: UNTESTABLE on the client -- neither InitialSize nor MeshSize")
    log("            is readable here, so the detector has nothing to compare.")
elseif stamped == seen then
    log("VERDICT 2b: GEOMETRY REPLICATED (carried by %s). Server-side generation", clientProp)
    log("            is sufficient; clients do not rebuild. Upload path is moot.")
else
    local cubic = math.abs(seenV.X - seenV.Y) < 1e-3 and math.abs(seenV.Y - seenV.Z) < 1e-3
    log("VERDICT 2b: part replicated but geometry did NOT -- client sees a")
    log("            different mesh. EACH CLIENT MUST BUILD ITS OWN.")
    log("            client shape: %s", cubic
        and "UNIT CUBE -- the textbook missing-mesh placeholder."
        or string.format("non-cubic but wrong; expected ~%s", tostring(EXPECT)))
end

-- 2a on the client side too -- needed if clients must self-build
local AssetService = game:GetService("AssetService")
local okC, errC = pcall(function() return AssetService:CreateEditableMesh() end)
log("client CreateEditableMesh: %s%s", okC and "OK" or "BLOCKED", okC and "" or (" -- " .. tostring(errC)))

return table.concat(out, "\n")

========================= END SECTION B ============================ ]]

return "This file is a reference, not a runnable script. Run sections A and B "
    .. "separately via execute_luau with target=server / target=client-1 "
    .. "inside a playtest. See the header."
