-- Run the real control lookup and battery sync against archived sensor values.
local file = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local current, thermal, night, resets, sync = nil, true, true, 0, nil
local player = {valid = true, GetNW2Entity = function() return current end}
local thermalConvar = {GetBool = function() return thermal end,
    SetBool = function(_, value) thermal = value resets = resets + 1 end}
local nightConvar = {GetBool = function() return night end,
    SetBool = function(_, value) night = value resets = resets + 1 end}
local modes, pending = {}, nil
local env = setmetatable({CLIENT = true,
    IsValid = function(ent) return ent and ent.valid end,
    isfunction = function(value) return type(value) == "function" end,
    GetConVar = function(name)
        if name == "probe_droid_thermal" then return thermalConvar end
        assert(name == "probe_droid_nightvision") return nightConvar
    end,
    LocalPlayer = function() return player end,
    thermalVision = thermalConvar, nightVision = nightConvar,
    hook = {Add = function(_, _, callback) sync = callback end},
    net = {Start = function() end,
        WriteUInt = function(mode) pending = mode end,
        SendToServer = function() modes[#modes + 1] = pending end}
}, {__index = _G})
local function run(text)
    local chunk = assert(loadstring(text)) setfenv(chunk, env) return chunk()
end
env.controlledProbe = run(assert(source:match("(local function controlledProbe%([^\n]*.-\nend)"))
    .. "\nreturn controlledProbe")
run(assert(source:match('(do\n    local lastProbe, lastMode\n    hook.Add%("Think", "ProbeDroid.SensorBatteryMode".-)\n%-%- Keep console commands')))
local function drone()
    return {valid = true, GetClass = function() return "sent_probe_droid" end,
        GetCameraPosition = function() end, GetCameraOffset = function() end,
        GetPilot = function() return player end}
end
sync()
assert(resets == 0 and #modes == 0, "inactive control changed sensor settings")
current = drone()
sync()
assert(not thermal and not night and modes[1] == 0 and resets == 2,
    "deployment inherited sensor modes or charged sensor battery cost")
thermal = true
sync() sync()
assert(thermal and modes[2] == 1 and #modes == 2 and resets == 2,
    "normal flight updates reset an intentionally selected sensor")
current = nil
sync()
current, thermal, night = drone(), false, true
sync()
assert(not night and modes[3] == 0 and resets == 4, "new flight inherited night vision")
-- The first caller may be a render hook rather than battery synchronization.
current, thermal = drone(), true
assert(env.controlledProbe(player) == current and not thermal and not night and resets == 6,
    "first render/control lookup did not reset to optical immediately")
print("Sensor reset checks passed: optical deployment, redeployment, first render lookup, battery sync and in-flight toggles")
