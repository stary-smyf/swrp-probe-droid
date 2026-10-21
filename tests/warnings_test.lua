local tick, now, battery, distance, controlled = nil, 0, 100, 0, nil
local pending, voices = {}, {}
local probe = {
    GetBatteryEnd = function() return battery end,
    GetBatteryDuration = function() return 100 end,
    GetMaxRange = function() return 1000 end,
    GetLaunchPosition = function() return "launch" end,
    GetCameraPosition = function() return {Distance = function(_, pos)
        assert(pos == "launch") return distance end} end
}
local player = {Alive = function() return true end,
    GetNW2Entity = function(_, key) assert(key == "ProbeDroidControlled") return controlled end}
local env = setmetatable({
    _G = {}, isfunction = function(v) return type(v) == "function" end,
    LocalPlayer = function() return player end, IsValid = function(v) return type(v) == "table" end,
    CurTime = function() return 0 end, RealTime = function() return now end,
    hook = {Add = function(event, _, callback) if event == "Think" then tick = callback end end},
    sound = {PlayFile = function(path, flags, callback)
        assert(path == "sound/probe_droid/warning.wav" and flags == "noplay")
        pending[#pending + 1] = callback
    end}
}, {__index = _G})
local function finish()
    local voice = {EnableLooping = function(self, looped) self.looped = looped assert(looped) end,
        SetVolume = function(_, value) assert(value == 1) end,
        GetLength = function() return 4 end,
        Play = function(self) self.played = true end,
        Stop = function(self) self.stopped = true end}
    voices[#voices + 1] = voice
    table.remove(pending, 1)(voice)
    return voice
end
local chunk = assert(loadfile("lua/autorun/client/probe_droid_warnings.lua"))
setfenv(chunk, env) chunk()
tick() assert(#pending == 0)
controlled = probe tick() assert(#pending == 0)
distance = 810 tick() assert(#pending == 0, "transmission warned above ten percent")
distance = 900 tick() assert(#pending == 0, "transmission warned at threshold")
distance, battery = 0, 19 tick() assert(#pending == 0, "battery warned above ten percent")
battery = 10 tick() assert(#pending == 0, "battery warned at threshold")
battery = 9
tick() tick() assert(#pending == 1, "duplicate loading alerts")
local first = finish() assert(first.played and first.looped)
now = 3 tick() assert(#pending == 0, "warning clip interrupted")
now = 20 tick() assert(#pending == 0 and not first.stopped, "active loop was restarted")
distance = 910
battery = 100 tick() assert(not first.stopped, "range warning did not retain loop")
distance = 0 tick() assert(first.stopped, "recovery leaked sound")
distance = 910 tick() assert(#pending == 1, "range alone did not warn below ten percent")
controlled = nil tick()
local stale = finish() assert(stale.stopped and not stale.played, "late callback played after exit")
controlled = probe tick() assert(#pending == 1, "new flight inherited cooldown")
finish()
env._G.ProbeDroidStopWarnings() assert(voices[#voices].stopped)
print("Warning checks passed: custom WAV, continuous loop, shared warnings, async guards, recovery and flight cleanup")
