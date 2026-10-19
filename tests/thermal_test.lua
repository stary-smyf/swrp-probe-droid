-- Run the actual thermal hook block against a small rendering API simulation.
-- This checks draw submission/control flow; engine depth/stencil pixels still
-- require an in-game visual test.
local file = assert(io.open(os.getenv("PROBE_DROID_THERMAL_TEST_SOURCE") or "lua/autorun/probe_droid.lua", "rb"))
local source = file:read("*a")
file:close()
local first = assert(source:find("do\n    local coldPalette =", 1, true))
local last = assert(source:find("-- The local player's model", first, true))
local tint = source:match("(local function tintSensorImage%([^\n]*.-\nend)") or ""
local block = tint .. "\n" .. source:sub(first, last - 1)

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function noop() end
local vectorMeta = {}
vectorMeta.__index = vectorMeta
local function vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta) end
function vectorMeta.__sub(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vectorMeta:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function vectorMeta:LengthSqr() return self:Dot(self) end
function vectorMeta:DistToSqr(b) return (self - b):LengthSqr() end
local angles = {Forward = function() return vector(1, 0, 0) end,
    Right = function() return vector(0, 1, 0) end, Up = function() return vector(0, 0, 1) end}
local function bitPair(a, b, either)
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local aa, bb = a % 2, b % 2
        if (either and (aa == 1 or bb == 1)) or (not either and aa == 1 and bb == 1) then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end
local bit = {band = function(a, b) return bitPair(a, b, false) end}
function bit.bor(...)
    local result = 0
    for _, value in ipairs({...}) do result = bitPair(result, value, true) end
    return result
end

local function simulation()
    local sim = {now = 0, frame = 1, enabled = true, active = true, entities = {}, hooks = {},
        scans = 0, copies = 0, filters = 0, errors = 0, render = {stencil = false, blend = false}, blendCalls = {}, engine = false}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.STUDIO_RENDER, env.STUDIO_NOSHADOWS, env.STUDIO_SKIP_FLEXES, env.STUDIO_SKIP_DECALS = 1, 2, 4, 8
    env.STUDIO_SHADOWDEPTHTEXTURE, env.STUDIO_SSAODEPTHTEXTURE = 16, 32
    env.RENDERGROUP_OPAQUE, env.RENDERGROUP_OPAQUE_HUGE, env.RENDERGROUP_TRANSLUCENT, env.RENDERGROUP_BOTH = 0, 1, 2, 3
    env.STENCIL_ALWAYS, env.STENCIL_REPLACE, env.STENCIL_KEEP, env.STENCIL_NOTEQUAL = 1, 2, 3, 4
    env.BLEND_ZERO, env.BLEND_ONE, env.BLEND_SRC_COLOR, env.BLENDFUNC_ADD = 0, 1, 2, 3
    env.RT_SIZE_LITERAL, env.MATERIAL_RT_DEPTH_NONE, env.IMAGE_FORMAT_RGBA8888 = 0, 0, 0
    env.math = setmetatable({Clamp = function(n, a, b) return math.min(b, math.max(a, n)) end}, {__index = math})
    env.table = setmetatable({Empty = function(t) for k in pairs(t) do t[k] = nil end end}, {__index = table})
    env.bit = bit
    env.IsValid = function(ent) return type(ent) == "table" and ent.valid ~= false end
    env.isfunction = function(value) return type(value) == "function" end
    env.CurTime, env.FrameNumber = function() return sim.now end, function() return sim.frame end
    env.ScrW, env.ScrH = function() return 1920 end, function() return 1080 end
    env.thermalVision = {GetBool = function() return sim.enabled end}
    sim.probe = {GetMaxRange = function() return 3000 end, GetCameraPosition = function() return vector() end}
    sim.player = {EyeAngles = function() return angles end}
    env.LocalPlayer = function() return sim.player end
    env.controlledProbe = function() return sim.active and sim.probe or nil end
    env.hook = {Add = function(event, name, fn) sim.hooks[event .. "/" .. name] = fn end}
    env.ents = {GetAll = function() sim.scans = sim.scans + 1 return sim.entities end}
    env.ErrorNoHalt = function() sim.errors = sim.errors + 1 end
    env.CreateMaterial = function() return {SetTexture = noop} end
    env.GetRenderTargetEx = function() return {GetName = function() return "test-heat" end} end
    env.surface = setmetatable({}, {__index = function() return noop end})
    env.cam = {Start2D = noop, End2D = noop, Start3D = function() sim.in3D = true end,
        End3D = function() sim.in3D = false end}
    env.draw = {NoTexture = noop}
    env.DrawColorModify = function() sim.filters = sim.filters + 1 sim.copies = sim.copies + 1 end
    env.render = setmetatable({
        GetViewSetup = function() return {origin = vector(), angles = angles, fov = 90} end,
        UpdateScreenEffectTexture = function() sim.copies = sim.copies + 1 end,
        GetScreenEffectTexture = function() return {} end,
        MaterialOverride = function(value) sim.render.material = value end,
        SetStencilEnable = function(value) sim.render.stencil = value end,
        SetStencilReferenceValue = function(value) sim.render.reference = value end,
        OverrideBlend = function(...) sim.blendCalls[#sim.blendCalls + 1] = {...} sim.render.blend = (...) end
    }, {__index = function() return noop end})
    local function nativeDraw(ent, flags)
        ent.draws = ent.draws + 1
        ent.lastFlags, ent.lastMaterial = flags, sim.render.material
        if sim.engine then ent.engineDraws = ent.engineDraws + 1 else ent.extraDraws = ent.extraDraws + 1 end
        if ent.fail then error("simulated model error") end
    end
    env.FindMetaTable = function() return {DrawModel = nativeDraw} end
    function sim.entity(options)
        local ent = {valid = true, npc = true, class = "npc_combine_s", model = "models/combine_soldier.mdl",
            position = vector(300, 0, 0), group = env.RENDERGROUP_OPAQUE,
            draws = 0, engineDraws = 0, extraDraws = 0, classReads = 0}
        for k, value in pairs(options or {}) do ent[k] = value end
        ent.GetTable = function(self) return self end
        ent.IsDormant = function(self) return self.dormant end
        ent.GetNoDraw = function(self) return self.noDraw end
        ent.IsWorld = function(self) return self.world end
        ent.GetClass = function(self) self.classReads = self.classReads + 1 return self.class end
        ent.GetModel = function(self) return self.model end
        ent.IsPlayer = function(self) return self.player end
        ent.Alive = function(self) return not self.dead end
        ent.IsNPC = function(self) return self.npc end
        ent.IsNextBot = function(self) return self.nextbot end
        ent.IsWeapon = function(self) return self.weapon end
        ent.IsVehicle = function(self) return self.vehicle end
        ent.BoundingRadius = function() return 32 end
        ent.WorldSpaceCenter = function(self) return self.position end
        ent.GetOwner = function(self) return self.owner end
        ent.GetRenderGroup = function(self) return self.group end
        ent.GetActiveWeapon = function(self) return self.activeWeapon end
        ent.EntIndex = function() return 10 end
        ent.DrawModel = nativeDraw
        sim.entities[#sim.entities + 1] = ent
        return ent
    end
    function sim.hook(event, name, ...) return assert(sim.hooks[event .. "/" .. name], "missing hook " .. event)(...) end
    function sim.pre() sim.hook("PreDrawOpaqueRenderables", "ProbeDroid.NPCHeatMask", false, false) end
    function sim.engineDraw(ent, flags)
        sim.engine = true
        (ent.RenderOverride or ent.Draw or nativeDraw)(ent, flags or env.STUDIO_RENDER)
        sim.engine = false
    end
    function sim.post()
        sim.hook("PostDrawOpaqueRenderables", "ProbeDroid.NPCHeatMask", false, false)
        sim.hook("RenderScreenspaceEffects", "ProbeDroid.ThermalVision")
        equal(sim.render.material, nil, "material override restored")
        equal(sim.render.blend, false, "blend restored")
        equal(sim.render.stencil, false, "stencil restored")
        equal(sim.in3D, false, "3D camera restored")
    end
    function sim.advance(dt) sim.now = sim.now + dt sim.frame = sim.frame + 1 end
    local chunk = assert(loadstring(block, "@thermal-source"))
    setfenv(chunk, env)
    chunk()
    sim.env = env
    return sim
end

do
    local sim = simulation()
    local visible, hidden = {}, {}
    for i = 1, 80 do visible[i] = sim.entity() hidden[i] = sim.entity() end
    sim.pre()
    for _, ent in ipairs(visible) do sim.engineDraw(ent) end
    sim.post()
    for _, ent in ipairs(visible) do equal(ent.draws, 1, "visible native NPC drawn once") end
    for _, ent in ipairs(hidden) do equal(ent.draws, 0, "engine-culled native NPC not resubmitted") end
    equal(sim.scans, 1, "shared scan between opaque and effects hooks")
    equal(sim.filters, 1, "one cold image filter")
    equal(sim.copies, 1, "only DrawColorModify copies the framebuffer")
    local blend = sim.blendCalls[1]
    equal(blend[2], sim.env.BLEND_ZERO, "RGB source factor")
    equal(blend[3], sim.env.BLEND_SRC_COLOR, "RGB destination multiply")
    equal(blend[5], sim.env.BLEND_ZERO, "alpha source factor")
    equal(blend[6], sim.env.BLEND_ONE, "destination alpha preserved")
    for i = 1, 29 do sim.advance(1 / 60) sim.pre() sim.post() end
    equal(sim.scans, 1, "no whole-world rescan per frame")
    equal(hidden[1].classReads, 1, "class eligibility cached between scans")
    sim.advance(0.1) sim.pre() sim.post()
    equal(sim.scans, 2, "candidate scan refreshes after interval")
end

do
    local sim = simulation()
    local custom = sim.entity({RenderOverride = function(self) self.customCalls = (self.customCalls or 0) + 1 self:DrawModel() end})
    local customDraw = sim.entity({Draw = function(self) self:DrawModel() end})
    local translucent = sim.entity({group = sim.env.RENDERGROUP_TRANSLUCENT})
    local both = sim.entity({group = sim.env.RENDERGROUP_BOTH})
    local huge = sim.entity({group = sim.env.RENDERGROUP_OPAQUE_HUGE})
    local changed = sim.entity()
    local nextbot = sim.entity({npc = false, nextbot = true})
    sim.pre()
    changed.RenderOverride = function() end
    sim.post()
    equal(custom.extraDraws, 1, "custom NPC fallback retained")
    equal(customDraw.extraDraws, 1, "scripted Draw fallback retained")
    equal(translucent.extraDraws, 1, "translucent NPC fallback retained")
    equal(both.extraDraws, 1, "BOTH group fallback retained")
    equal(huge.extraDraws, 0, "opaque huge group honors engine culling")
    equal(changed.extraDraws, 1, "replaced RenderOverride retains fallback")
    equal(nextbot.extraDraws, 0, "opaque native NextBot honors engine culling")
    sim.advance(0.1) sim.pre() sim.engineDraw(custom) sim.engineDraw(customDraw) sim.post()
    equal(custom.customCalls, 1, "existing override invoked by engine wrapper")
    equal(custom.extraDraws, 1, "successfully masked custom NPC not redrawn")
    equal(customDraw.extraDraws, 1, "successfully masked scripted Draw not redrawn")
end

do
    local sim = simulation()
    local actor = sim.entity({npc = false, player = true})
    local distant = sim.entity({npc = false, position = vector(4000, 0, 0)})
    local behind = sim.entity({npc = false, position = vector(-100, 0, 0)})
    local sideways = sim.entity({npc = false, position = vector(300, 2500, 0)})
    local prop = sim.entity({npc = false, class = "prop_physics"})
    local jeep = sim.entity({npc = false, vehicle = true, class = "prop_vehicle_jeep"})
    local airboat = sim.entity({npc = false, vehicle = true, class = "prop_vehicle_airboat"})
    local seat = sim.entity({npc = false, vehicle = true, class = "prop_vehicle_prisoner_pod"})
    local distantVehicle = sim.entity({npc = false, vehicle = true, class = "prop_vehicle_jeep",
        position = vector(4000, 0, 0)})
    local hiddenVehicle = sim.entity({npc = false, vehicle = true, class = "prop_vehicle_airboat", noDraw = true})
    local dormant = sim.entity({dormant = true})
    local noDraw = sim.entity({noDraw = true})
    local dead = sim.entity({npc = false, player = true, dead = true})
    local inventory = sim.entity({npc = false, weapon = true, owner = actor})
    local held = sim.entity({npc = false, weapon = true, owner = actor})
    actor.activeWeapon = held
    sim.pre() sim.post()
    equal(actor.extraDraws, 1, "player fallback visible")
    equal(held.extraDraws, 1, "active weapon fallback visible")
    for _, ent in ipairs({jeep, airboat, seat}) do
        equal(ent.extraDraws, 1, "Source vehicle must receive thermal highlight")
    end
    for _, ent in ipairs({distant, behind, sideways, prop, dormant, noDraw, dead, inventory, distantVehicle, hiddenVehicle}) do
        equal(ent.draws, 0, "ineligible/outside-view target not drawn")
    end
    actor.valid = false
    sim.advance(0.1) sim.pre() sim.post()
    equal(actor.draws, 1, "removed candidate skipped before rescan")
end

do
    local sim = simulation()
    local npc = sim.entity()
    -- Some additional world views can reach screenspace effects without the
    -- normal opaque pass. They must retain a heat fallback for native NPCs.
    sim.hook("RenderScreenspaceEffects", "ProbeDroid.ThermalVision")
    equal(npc.extraDraws, 1, "no opaque mask keeps native NPC fallback")
    equal(sim.render.material, nil, "fallback-only frame restores material")
    equal(sim.render.blend, false, "fallback-only frame restores blend")
    equal(sim.in3D, false, "fallback-only frame restores camera")
    sim.advance(0.1) sim.pre() sim.post()
    equal(npc.extraDraws, 1, "next masked frame resumes culling")
end

do
    local sim = simulation()
    local custom = sim.entity({group = sim.env.RENDERGROUP_BOTH})
    local distant = sim.entity({position = vector(4000, 0, 0)})
    sim.pre()
    sim.engineDraw(distant)
    equal(distant.lastMaterial, nil, "native NPC outside range keeps normal material")
    equal(distant.lastFlags, sim.env.STUDIO_RENDER, "native NPC outside range keeps original flags")
    sim.engineDraw(custom, sim.env.STUDIO_SHADOWDEPTHTEXTURE)
    equal(custom.lastMaterial, nil, "shadow draw leaves material untouched")
    equal(custom.lastFlags, sim.env.STUDIO_SHADOWDEPTHTEXTURE, "shadow flags unchanged")
    sim.engineDraw(custom, sim.env.STUDIO_SSAODEPTHTEXTURE)
    equal(custom.lastMaterial, nil, "SSAO draw leaves material untouched")
    sim.post()
    equal(custom.extraDraws, 1, "depth-only rendering does not mark target heated")
    equal(distant.extraDraws, 0, "native NPC outside range is not redrawn")
end

do
    local sim = simulation()
    local broken = sim.entity({npc = false, fail = true})
    local later = sim.entity({npc = false})
    local failingCustom = sim.entity({RenderOverride = function() error("custom renderer failed") end})
    sim.pre() sim.engineDraw(failingCustom) sim.post()
    equal(broken.extraDraws, 1, "broken target attempted")
    equal(later.extraDraws, 1, "one error does not cancel later targets")
    equal(failingCustom.extraDraws, 1, "failed custom mask uses fallback")
    equal(sim.errors, 2, "draw errors reported once")
    sim.advance(0.1) sim.pre() sim.post()
    equal(sim.errors, 2, "repeated errors rate limited")
end

do
    local sim = simulation()
    local old = function() end
    local custom = sim.entity({RenderOverride = old})
    local native = sim.entity()
    local changed = sim.entity()
    sim.pre() sim.post()
    assert(custom.RenderOverride ~= old and native.RenderOverride, "temporary wrappers installed")
    local otherAddon = function() end
    changed.RenderOverride = otherAddon
    sim.enabled = false
    sim.hook("Think", "ProbeDroid.NPCHeatMaskCleanup")
    equal(custom.RenderOverride, old, "sensor exit restores previous override")
    equal(native.RenderOverride, nil, "sensor exit removes native override")
    equal(changed.RenderOverride, otherAddon, "cleanup preserves later addon override")
    sim.enabled = true sim.advance(1) sim.pre() sim.post()
    sim.active = false
    sim.hook("Think", "ProbeDroid.NPCHeatMaskCleanup")
    equal(custom.RenderOverride, old, "flight exit restores override")
    sim.active = true sim.advance(1) sim.pre() sim.post()
    sim.env.ProbeDroidNPCHeatCleanup()
    equal(custom.RenderOverride, old, "hot-reload cleanup restores override")
    sim.advance(1) sim.pre() sim.post()
    sim.hook("ShutDown", "ProbeDroid.NPCHeatMask")
    equal(native.RenderOverride, nil, "shutdown restores native draw path")
end
