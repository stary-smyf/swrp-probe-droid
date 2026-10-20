-- Exercise zoom, asynchronous stereo playback, and full-clip input cooldown.
local file = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local source = file:read("*a")
file:close()
local first = assert(source:find("local flightCamera\n", 1, true))
local last = assert(source:find("local thermalVision =", first, true))
local hooks, pending, channels = {}, {}, {}
local probe, now, plays, failures = nil, 0, 0, 0
local player = {}
local env = setmetatable({
    controlledProbe = function(ply) assert(ply == player) return probe end,
    LocalPlayer = function() return player end,
    IsValid = function(ent) return ent and ent.valid end,
    RealTime = function() return now end,
    ErrorNoHalt = function() failures = failures + 1 end,
    hook = {Add = function(event, _, callback) hooks[event] = callback end},
    sound = {PlayFile = function(path, flags, callback)
        local expected = probe.ClientZoomLevel == 1 and "sound/probe_droid/unzoom_loud.wav"
            or "sound/probe_droid/camerazoom.wav"
        assert(path == expected and flags == "noplay", "wrong sound for zoom direction")
        pending[#pending + 1] = {callback = callback, path = path}
    end},
    cameraSway = {GetFloat = function() return 0 end},
    FrameNumber = function() return nil end,
    Vector = function() return {} end,
    Angle = function(p, y, r) return {p = p, y = y, r = r} end
}, {__index = _G})
local chunk = assert(loadstring(source:sub(first, last - 1)))
setfenv(chunk, env)
chunk()
local function newProbe()
    return {ClientViewAngles = {p = 0, y = 0}, GetCameraPosition = function() return "camera" end}
end
local function completeLoad()
    local request = table.remove(pending, 1)
    assert(request, "zoom did not request its sound")
    local duration = request.path == "sound/probe_droid/unzoom_loud.wav" and 1.1 or 0.75
    local channel = {valid = true,
        Stop = function(self) self.stopped = true self.valid = false end,
        EnableLooping = function(_, looped) assert(looped == false) end,
        SetVolume = function(_, volume) assert(volume == 1) end,
        GetLength = function() return duration end,
        Play = function(self) self.started = now plays = plays + 1 end}
    channels[#channels + 1] = channel
    request.callback(channel)
    return channel
end
local function checkZoom(factor)
    assert(hooks.AdjustMouseSensitivity() == 1 / factor)
    for _, baseFOV in ipairs({75, 90, 110}) do
        local view = hooks.CalcView(player, nil, nil, baseFOV)
        local actual = math.tan(math.rad(baseFOV) / 2) / math.tan(math.rad(view.fov) / 2)
        assert(math.abs(actual - factor) < 0.000001)
        assert(view.origin == "camera" and view.drawviewer and view.znear == 2)
    end
end
local function click() assert(hooks.PlayerBindPress(player, "+attack", true) == true) end
assert(hooks.PlayerBindPress(player, "+attack", true) == nil and #pending == 0)
probe = newProbe()
checkZoom(1)
assert(hooks.PlayerBindPress(player, "+attack2", true) == nil)
for _, factor in ipairs({3, 6, 1, 3}) do
    click()
    checkZoom(factor)
    click() -- Even slow file loading must not allow a second zoom.
    assert(#pending == 1, "zoom advanced while loading its sound")
    checkZoom(factor)
    local channel = completeLoad()
    now = now + 0.5
    click()
    assert(not channel.stopped and #pending == 0, "zoom interrupted a playing cue")
    checkZoom(factor)
    assert(hooks.PlayerBindPress(player, "+attack", false) == true)
    checkZoom(factor)
    now = now + channel:GetLength() - 0.5 + 0.06 -- Wait for either clip's full length.
end
assert(plays == 4 and failures == 0)
probe = nil
assert(hooks.CalcView(player, nil, nil, 90) == nil and channels[4].stopped)
probe = newProbe()
checkZoom(1)
click()
-- An asynchronous result from an ended flight must never play in a later one.
probe = nil
hooks.CalcView(player, nil, nil, 90)
probe = newProbe()
local stale = completeLoad()
assert(stale.stopped and plays == 4)
checkZoom(1)
click()
completeLoad()
assert(plays == 5, "new flight could not play its zoom sound")
print("Zoom checks passed: optical cycle, FOV, stereo cues, loading guard, full-clip pause, releases, flight cleanup and stale callbacks")
