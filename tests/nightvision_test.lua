-- Exercise the imported NVG Night preset, illumination and sensor cleanup.
local hooks, changes, projectors, events = {}, {}, {}, {}
local night, thermal, lightEnabled, active, missing = false, false, true, true, false
local warnings, blend, twoD = 0, false, false
local probe = {GetCameraPosition = function() return "camera" end, ClientViewAngles = "steering"}
local player = {EyeAngles = function() return "body-angles" end}
local function noop() end
local env = setmetatable({
    _G = {}, isfunction = function(v) return type(v) == "function" end,
    LocalPlayer = function() return player end,
    IsValid = function(ent) return ent and ent.valid end,
    FrameTime = function() return 0.1 end,
    Lerp = function(t, a, b) return a + (b - a) * t end,
    math = setmetatable({Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end,
        Rand = function() return 0 end}, {__index = math}),
    Material = function(path)
        assert(path == "probe_droid/nightvision/grain")
        return {IsError = function() return missing end}
    end,
    hook = {Add = function(event, name, callback) hooks[event .. "/" .. name] = callback end,
        Remove = function(event, name) hooks[event .. "/" .. name] = nil end},
    cvars = {AddChangeCallback = function(name, callback) changes[name] = callback end},
    ProjectedTexture = function()
        local p = {valid = true, SetTexture = function(_, path) assert(path == "effects/flashlight/soft") end,
            SetEnableShadows = function(_, value) assert(value == false) end,
            SetFOV = function(_, value) assert(value == 140) end,
            SetVerticalFOV = function(_, value) assert(value == 100) end,
            SetBrightness = function(_, value) assert(value == 2) end,
            SetFarZ = function(_, value) assert(value == 2500) end,
            SetPos = function(self, value) self.pos = value end,
            SetAngles = function(self, value) self.angles = value end,
            Update = noop, Remove = function(self) self.valid = false end}
        projectors[#projectors + 1] = p return p
    end,
    DrawBloom = function(threshold, strength)
        events[#events + 1] = {"bloom", threshold, strength}
    end,
    DrawColorModify = function(palette)
        assert(palette["$pp_colour_colour"] == 0 and palette["$pp_colour_contrast"] == 1.5)
        events[#events + 1] = {"color", palette["$pp_colour_brightness"]}
    end,
    render = {GetLightColor = function(pos) assert(pos == "camera") return {x = 0.5, y = 0.5, z = 0.5} end,
        OverrideBlend = function(value) blend = value end},
    cam = {Start2D = function() twoD = true end, End2D = function() twoD = false end},
    draw = {NoTexture = noop},
    surface = {SetMaterial = noop, SetDrawColor = function(r, g, b, a)
        assert(r == 255 and g == 45 and b == 25 and (a == 80 or a == 255))
    end,
        DrawTexturedRect = function() assert(twoD) events[#events + 1] = {"grain"} end,
        DrawRect = function() assert(twoD and blend) events[#events + 1] = {"fallback"} end},
    ScrW = function() return 1920 end, ScrH = function() return 1080 end,
    ErrorNoHalt = function() warnings = warnings + 1 end
}, {__index = _G})
local chunk = assert(loadfile("lua/probe_droid/nightvision.lua"))
setfenv(chunk, env)
chunk()(function() return active and probe or nil end,
    {GetBool = function() return night end}, {GetBool = function() return thermal end},
    {GetBool = function() return lightEnabled end})
local function think() hooks["Think/ProbeDroid.NVGNightVision"]() end
local function paint() hooks["RenderScreenspaceEffects/ProbeDroid.NightVision"]() end
think() paint()
assert(#projectors == 0 and #events == 0)
night = true
think() paint()
assert(projectors[1].pos == "camera" and projectors[1].angles == "steering")
assert(events[1][1] == "bloom" and events[1][2] == 0.65 and events[1][3] == 3.1)
assert(events[2][1] == "bloom" and events[2][2] == 0.1 and events[2][3] == 2)
assert(events[3][1] == "color" and math.abs(events[3][2] - 0.06) < 0.000001)
assert(events[4][1] == "grain" and not twoD)
lightEnabled = false
think()
assert(not projectors[1].valid)
local before = #events
paint()
assert(#events == before + 4, "disabling the light disabled night vision")
lightEnabled, thermal = true, true
before = #events
think() paint()
assert(#projectors == 1 and #events == before, "night vision stacked over thermal")
thermal = false
think()
night = false
changes.probe_droid_nightvision("probe_droid_nightvision", "1", "0")
assert(not projectors[2].valid, "toggle-off leaked projected light")
night = true
think()
active = false
think() paint()
assert(not projectors[3].valid, "flight exit leaked night vision light")
active, missing = true, true
think() paint() paint()
assert(warnings == 1 and not blend and not twoD, "missing grain leaked blend state or warning spam")
assert(events[#events][1] == "fallback", "missing grain did not retain red night vision")
env._G.ProbeDroidNightVisionCleanup()
assert(not projectors[#projectors].valid, "reload cleanup leaked projected light")
local file = assert(io.open("materials/probe_droid/nightvision/grain.vtf", "rb"))
local bytes = file:read("*a") file:close()
assert(bytes:sub(1, 4) == "VTF\0" and #bytes == 590752)
print("NVG night vision checks passed: red tint, bloom, photo adaptation, camera illuminator, sensor exclusion, cleanup and missing-grain fallback")
