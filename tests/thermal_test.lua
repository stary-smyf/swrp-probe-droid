-- Exercise the replacement NVG renderer, its assets, and state restoration.
local hooks, now, enabled, active, missing = {}, 0, false, true, false
local scans, projectors, draws, warnings = 0, {}, {}, 0
local toggleCallback
local function noop() end
local function color(r, g, b, a) return {r = r, g = g, b = b, a = a or 255} end
local function actor(kind)
    return {valid = true, material = "original", mode = 7, color = color(10, 20, 30, 200),
        IsPlayer = function() return kind == "player" end,
        IsNPC = function() return kind == "npc" end,
        IsNextBot = function() return kind == "nextbot" end,
        Alive = function(self) return not self.dead end,
        IsDormant = function(self) return self.dormant end,
        GetNoDraw = function(self) return self.hidden end,
        GetMaterial = function(self) return self.serverMaterial or self.material end,
        SetMaterial = function(self, value) self.material = value end,
        GetRenderMode = function(self) return self.mode end,
        SetRenderMode = function(self, value) self.mode = value end,
        GetColor = function(self) return self.color end,
        SetColor = function(self, value) self.color = value end}
end
local player, npc, bot, prop, dead, hidden = actor("player"), actor("npc"), actor("nextbot"),
    actor("prop"), actor("player"), actor("npc")
dead.dead, hidden.hidden = true, true
local entities = {player, npc, bot, prop, dead, hidden}
local probe = {GetCameraPosition = function() return "drone-camera" end, ClientViewAngles = "drone-angles"}
local heatPath = "probe_droid/thermal/heat"
local env = setmetatable({
    _G = {}, RENDERMODE_GLOW = 3, Color = color, CurTime = function() return now end,
    isfunction = function(value) return type(value) == "function" end,
    cvars = {AddChangeCallback = function(_, callback) toggleCallback = callback end},
    LocalPlayer = function() return player end,
    IsValid = function(ent) return ent and ent.valid end,
    ErrorNoHalt = function() warnings = warnings + 1 end,
    Material = function(path)
        assert(path == heatPath or path == "probe_droid/thermal/lookup" or path == "probe_droid/thermal/noise")
        return {IsError = function() return missing end}
    end,
    hook = {Add = function(event, name, callback) hooks[event .. "/" .. name] = callback end,
        Remove = function(event, name) hooks[event .. "/" .. name] = nil end},
    ents = {GetAll = function() scans = scans + 1 return entities end},
    ProjectedTexture = function()
        local p = {valid = true, SetTexture = noop, SetEnableShadows = noop,
            SetFOV = noop, SetVerticalFOV = noop, SetBrightness = noop, SetFarZ = noop,
            SetPos = function(self, value) self.pos = value end,
            SetAngles = function(self, value) self.angles = value end, Update = noop,
            Remove = function(self) self.valid = false end}
        projectors[#projectors + 1] = p
        return p
    end,
    DrawColorModify = function(palette) draws[#draws + 1] = {"color", palette} end,
    DrawBloom = function() draws[#draws + 1] = {"bloom"} end,
    DrawTexturize = function(scale)
        assert(scale == 0, "thermal palette must not repeat as horizontal bands")
        draws[#draws + 1] = {"lookup"}
    end,
    DrawMotionBlur = function() draws[#draws + 1] = {"motion"} end,
    math = setmetatable({Rand = function() return 0 end}, {__index = math}),
    ScrW = function() return 1920 end, ScrH = function() return 1080 end,
    cam = {Start2D = noop, End2D = noop},
    surface = {SetMaterial = noop, SetDrawColor = noop,
        DrawTexturedRect = function() draws[#draws + 1] = {"noise"} end}
}, {__index = _G})
local chunk = assert(loadfile("lua/probe_droid/thermal.lua"))
setfenv(chunk, env)
chunk()(function() return active and probe or nil end, {GetBool = function() return enabled end})
scans = 0 -- Ignore the one-time repair pass for old client overrides.
local function think() hooks["Think/ProbeDroid.NVGThermal"]() end
local function post() hooks["RenderScreenspaceEffects/ProbeDroid.ThermalVision"]() end
think() post()
assert(scans == 0 and #projectors == 0 and #draws == 0, "inactive thermal changed the scene")
enabled = true
hooks["PreDrawOpaqueRenderables/ProbeDroid.NVGThermal"](true, false)
assert(scans == 0, "depth pass changed entity rendering")
hooks["PreDrawOpaqueRenderables/ProbeDroid.NVGThermal"](false, false)
think() post()
for _, ent in ipairs({player, npc, bot}) do
    assert(ent.material == heatPath and ent.mode == 3 and ent.color.a == 254, "NVG heat preset not applied")
end
for _, ent in ipairs({prop, dead, hidden}) do assert(ent.material == "original", "invalid heat target") end
assert(#projectors == 1 and projectors[1].pos == "drone-camera" and projectors[1].angles == "drone-angles",
    "illuminator did not follow drone view")
assert(scans == 1, "target scan was repeated inside throttle interval")
for i, name in ipairs({"color", "bloom", "lookup", "bloom", "motion", "color", "noise"}) do
    assert(draws[i][1] == name, "NVG postprocess order changed")
end
assert(draws[1][2]["$pp_colour_mulr"] == 15.5 and draws[6][2]["$pp_colour_contrast"] == 2)
-- New targets are picked up without re-saving already overridden entities.
now = 0.3
local newcomer = actor("npc")
entities[#entities + 1] = newcomer
think()
assert(newcomer.material == heatPath and scans == 2)
npc.hidden, now = true, 0.6
think()
assert(npc.material == "original" and npc.mode == 7 and npc.color.r == 10, "hidden target not restored")
-- Cleanup must not overwrite a material newly assigned by another addon.
bot.material = "another-addon"
enabled = false
think()
assert(player.material == "original" and player.mode == 7 and player.color.a == 200)
assert(bot.material == "another-addon" and newcomer.material == "original")
assert(not projectors[1].valid, "illuminator survived sensor disable")
enabled, now = true, 1
think()
active = false
think()
assert(player.material == "original" and not projectors[2].valid, "flight exit leaked thermal state")
active, missing = true, true
local previousDraws = #draws
think() post() think()
assert(#draws == previousDraws and warnings == 1, "missing assets drew an error material or spammed warnings")
missing = false
think()
env._G.ProbeDroidNPCHeatCleanup()
assert(player.material == "original" and not projectors[#projectors].valid, "reload cleanup failed")
-- Multiplayer getters can return the server value while the client still
-- renders our heat override. Restore must explicitly write the normal material.
player.serverMaterial, enabled, now = "server-original", true, 2
think()
assert(player.material == heatPath and player:GetMaterial() == "server-original")
enabled = false
think()
assert(player.material == "server-original", "heat colour remained after disabling thermal")
-- The toggle should restore immediately, before the next frame or Think.
enabled, now = true, 3
think()
enabled = false
assert(toggleCallback, "thermal has no immediate cleanup callback")
toggleCallback("probe_droid_thermal", "1", "0")
assert(player.material == "server-original" and player.mode == 7 and player.color.a == 200)
assert(not projectors[#projectors].valid, "toggle left thermal lighting active")
local drawCount = #draws
post()
assert(#draws == drawCount, "thermal drew colours while switched off")
-- Loading the fix must repair characters already stuck in the old heat material.
player.material = heatPath
chunk()(function() return nil end, {GetBool = function() return false end})
assert(player.material == "server-original", "old stuck heat material survived reload")
-- Confirm native texture assets exist and match the source heat animation.
local function read(path)
    local f = assert(io.open(path, "rb")) local bytes = f:read("*a") f:close() return bytes
end
local lookup = read("materials/probe_droid/thermal/lookup.vtf")
assert(lookup:sub(1, 4) == "VTF\0" and #lookup == 112 and lookup:byte(17) == 1 and lookup:byte(19) == 8)
local heat = read("materials/probe_droid/thermal/heat.vtf")
assert(heat:sub(1, 4) == "VTF\0" and #heat == 824, "heat animation missing")
print("NVG thermal checks passed: preset effects, actor filtering, drone illuminator, throttling, cleanup and native assets")
