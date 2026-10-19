-- Exercise actual battery accounting and model draw passes.
local file = assert(io.open("lua/entities/sent_probe_droid/init.lua", "rb"))
local source = file:read("*a")
file:close()
local batterySource = assert(source:match("(function ENT:UpdateBatteryDrain%(%).-\nend)"))
local now = 0
local env = setmetatable({ENT = {}, CurTime = function() return now end}, {__index = _G})
local chunk = assert(loadstring(batterySource))
setfenv(chunk, env)
chunk()
local probe = setmetatable({deadline = 120, LastBatteryUpdate = 0}, {__index = env.ENT})
function probe:GetStealth() return self.stealth end
function probe:GetBatteryEnd() return self.deadline end
function probe:SetBatteryEnd(value) self.deadline = value end
now = 10
probe:UpdateBatteryDrain()
assert(probe.deadline - now == 110, "normal mode drain changed")
probe.stealth = true
now = 20
probe:UpdateBatteryDrain()
assert(probe.deadline - now == 90, "stealth did not consume 20 battery seconds in 10 seconds")
-- Repeated updates at the same time cannot charge the battery twice.
probe:UpdateBatteryDrain()
assert(probe.deadline == 110, "repeated update duplicated drain")
now = 20.25
probe:UpdateBatteryDrain()
probe.stealth = false
now = 30
probe:UpdateBatteryDrain()
assert(probe.deadline == 109.75, "leaving stealth changed prior charge or continued extra drain")
-- Long server stalls still charge the full elapsed time, unlike flight's capped dt.
probe.stealth = true
now = 70
probe:UpdateBatteryDrain()
assert(probe.deadline == 69.75 and now >= probe.deadline, "stealth failed to exhaust the battery")

local blend, draws, own = 0.8, {}, false
local player = {valid = true, GetNW2Entity = function() return own and probe or nil end}
env.include = function() end
env.LocalPlayer = function() return player end
env.IsValid = function(ent) return ent and ent.valid end
env.render = {GetBlend = function() return blend end, SetBlend = function(value) blend = value end}
chunk = assert(loadfile("lua/entities/sent_probe_droid/cl_init.lua"))
setfenv(chunk, env)
chunk()
function probe:DrawModel() draws[#draws + 1] = blend end
probe.stealth = false
probe:Draw()
probe:DrawTranslucent()
assert(#draws == 1 and draws[1] == 0.8, "normal model did not draw exactly once at normal opacity")
probe.stealth = true
probe:Draw()
probe:DrawTranslucent()
assert(#draws == 2 and draws[2] == 0.4, "stealth model did not draw exactly once at half opacity")
assert(blend == 0.8, "stealth opacity leaked into other models")
probe.stealth = false
probe:Draw()
assert(draws[3] == 0.8, "exiting stealth failed to restore opacity")
own = true
probe:Draw()
probe.stealth = true
probe:DrawTranslucent()
assert(#draws == 3, "pilot's own model obscured first-person camera")
print("Stealth checks passed: battery drain, exhaustion, opacity, draw passes and render-state restoration")
