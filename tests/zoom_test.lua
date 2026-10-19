-- Exercise the real input and camera hooks, including perspective magnification.
local file = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local source = file:read("*a")
file:close()
local first = assert(source:find("local flightCamera\n", 1, true))
local last = assert(source:find("local thermalVision =", first, true))
local hooks, sounds = {}, 0
local probe
local player = {}
local env = setmetatable({
    controlledProbe = function(ply) assert(ply == player) return probe end,
    LocalPlayer = function() return player end,
    hook = {Add = function(event, _, callback) hooks[event] = callback end},
    surface = {PlaySound = function() sounds = sounds + 1 end},
    cameraSway = {GetFloat = function() return 0 end},
    -- Skip the independent motion-sway update for these optical checks.
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
local function checkZoom(factor)
    assert(hooks.AdjustMouseSensitivity() == 1 / factor, "incorrect aiming sensitivity")
    for _, baseFOV in ipairs({75, 90, 110}) do
        local view = hooks.CalcView(player, nil, nil, baseFOV)
        local magnification = math.tan(math.rad(baseFOV) / 2) / math.tan(math.rad(view.fov) / 2)
        assert(math.abs(magnification - factor) < 0.000001, "incorrect optical magnification")
        assert(view.origin == "camera" and view.drawviewer and view.znear == 2)
    end
end
assert(hooks.PlayerBindPress(player, "+attack", true) == nil and sounds == 0,
    "zoom intercepted deployment outside a flight")
assert(hooks.AdjustMouseSensitivity() == nil and hooks.CalcView(player, nil, nil, 90) == nil)
probe = newProbe()
checkZoom(1)
assert(hooks.PlayerBindPress(player, "+attack2", true) == nil, "zoom intercepted stealth")
for _, factor in ipairs({3, 6, 1, 3}) do
    assert(hooks.PlayerBindPress(player, "+attack", true) == true)
    checkZoom(factor)
    assert(hooks.PlayerBindPress(player, "+attack", false) == true)
    checkZoom(factor) -- Releasing the mouse must not advance zoom again.
end
assert(sounds == 4, "zoom feedback played on release or outside a flight")
probe = nil
assert(hooks.AdjustMouseSensitivity() == nil and hooks.CalcView(player, nil, nil, 90) == nil,
    "zoom persisted after control ended")
probe = newProbe()
checkZoom(1)
print("Zoom checks passed: LMB cycle, release, FOV magnification, sensitivity, flight reset and inactive controls")
