-- Process actual client/server commands to verify a continuous two-second hold.
local file = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local source = file:read("*a")
file:close()
local block = assert(source:match('(hook.Add%("StartCommand".-)\nhook.Add%("PlayerSwitchWeapon"'))
local now, inputHook, probe = 0, nil, nil
local player = {GetActiveWeapon = function() end}
local env = setmetatable({SERVER = true, CLIENT = false,
    CurTime = function() return now end,
    controlledProbe = function() return probe end,
    IsValid = function() return false end,
    Vector = function() return {LengthSqr = function() return 0 end} end,
    Angle = function(p, y, r) return {p = p, y = y, r = r} end,
    hook = {Add = function(_, _, callback) inputHook = callback end}}, {__index = _G})
for _, key in ipairs({"IN_USE", "IN_ATTACK", "IN_ATTACK2", "IN_RELOAD", "IN_FORWARD", "IN_BACK",
    "IN_MOVERIGHT", "IN_MOVELEFT", "IN_JUMP", "IN_DUCK", "IN_SPEED"}) do env[key] = key end
local chunk = assert(loadstring(block))
setfenv(chunk, env)
chunk()
local function newProbe()
    return {ControlStarted = -1, exits = 0,
        SetNW2Float = function(self, key, value)
            assert(key == "ProbeDroidExitEnd") self.deadline = value
        end,
        DestroyProbe = function(self, reason)
            assert(reason == "flight ended by pilot") self.exits = self.exits + 1
        end}
end
local function step(time, held, forced)
    now = time
    local cmd = {buttons = {[env.IN_USE] = held},
        KeyDown = function(self, key) return self.buttons[key] or false end,
        IsForced = function() return forced or false end,
        RemoveKey = function(self, key) self.buttons[key] = nil end,
        ClearButtons = function(self) self.buttons = {} end,
        ClearMovement = function() end, SetImpulse = function() end,
        GetViewAngles = function() return {p = 0, y = 0} end}
    env.SERVER, env.CLIENT = false, true
    inputHook(player, cmd)
    assert(cmd:KeyDown(env.IN_USE) == held, "client stripped exit input")
    env.SERVER, env.CLIENT = true, false
    inputHook(player, cmd)
    assert(next(cmd.buttons) == nil, "server left use button active")
end
probe = newProbe()
step(0, true)
assert(probe.deadline == 2 and probe.exits == 0, "tap exited immediately or countdown missing")
step(0.1, false)
assert(probe.deadline == 0 and probe.ExitHoldStarted == nil, "release did not cancel")
step(1, true)
for i = 1, 10 do step(1 + i / 10, true) end
step(2.1, false)
assert(probe.exits == 0, "partial hold ended flight")
step(3, true)
for i = 1, 19 do step(3 + i / 10, true) end
assert(probe.exits == 0, "exit completed before two seconds")
step(5, true)
assert(probe.exits == 1, "continuous two-second hold failed to exit")

probe = newProbe()
step(10, true)
step(10.1, true)
step(11, true)
assert(probe.ExitHoldStarted == 11 and probe.deadline == 13, "input gap did not restart countdown")
step(11.1, true, true)
assert(probe.deadline == 0 and probe.ExitHoldStarted == nil, "forced backup command continued exit hold")
for i = 1, 40 do step(11.1 + i / 10, true, true) end
assert(probe.exits == 0, "stale backup commands ended flight")
probe = newProbe()
step(20, true)
assert(probe.deadline == 22 and probe.exits == 0, "new flight inherited exit progress")
assert(probe.LastInputTime == 20, "flight controls stopped updating while holding exit")
print("Exit hold checks passed: taps, cancellation, continuous hold, input gaps, stale commands and new flights")
