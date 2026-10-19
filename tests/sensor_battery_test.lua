-- Exercise actual battery costs and client/server sensor synchronization.
local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end
local autorun = read("lua/autorun/probe_droid.lua")
local init = read("lua/entities/sent_probe_droid/init.lua")
local now, receiver, requested = 0, nil, 0
local pilot = {}
local probe
local env = setmetatable({SERVER = true, ENT = {},
    CurTime = function() return now end,
    controlledProbe = function(ply) if ply == pilot then return probe end end,
    util = {AddNetworkString = function() end},
    net = {Receive = function(_, callback) receiver = callback end,
        ReadUInt = function(bits) assert(bits == 2) return requested end}}, {__index = _G})
local function run(source, scope)
    local chunk = assert(loadstring(source))
    setfenv(chunk, scope)
    chunk()
end
run(assert(init:match("(function ENT:UpdateBatteryDrain%(%).-\nend)")), env)
run(assert(autorun:match('(if SERVER then\n    util.AddNetworkString%("ProbeDroid.SensorMode".-)\nhook.Add%("StartCommand"')), env)
probe = setmetatable({}, {__index = env.ENT})
function probe:GetStealth() return self.stealth end
function probe:GetBatteryEnd() return self.deadline end
function probe:SetBatteryEnd(value) self.deadline = value end
local function reset(mode, stealth)
    now, probe.LastBatteryUpdate, probe.deadline = 0, 0, 120
    probe.SensorMode, probe.stealth = mode, stealth
end
for _, case in ipairs({{0, false, 1}, {1, false, 2}, {2, false, 1.25},
    {0, true, 2}, {1, true, 3}, {2, true, 2.25}}) do
    reset(case[1], case[2])
    now = 10
    probe:UpdateBatteryDrain()
    assert(probe.deadline - now == 120 - 10 * case[3], "incorrect combined sensor/stealth drain")
end
reset(0, false)
now, requested = 10, 1
receiver(2, pilot)
assert(probe.SensorMode == 1 and probe.deadline == 120, "thermal switch charged previous optical interval")
now, requested = 20, 2
receiver(2, pilot)
assert(probe.SensorMode == 2 and probe.deadline == 110, "night vision switch lost thermal charge")
now, requested = 30, 0
receiver(2, pilot)
assert(probe.SensorMode == 0 and probe.deadline == 107.5, "optical switch lost night vision charge")
now = 40
probe:UpdateBatteryDrain()
assert(probe.deadline == 107.5, "extra drain continued in optical mode")
requested = 3
receiver(2, pilot)
assert(probe.SensorMode == 0, "invalid sensor mode accepted")
requested = 1
receiver(2, {})
assert(probe.SensorMode == 0, "non-pilot modified another flight")

local thermal, night, current, sync = false, false, probe, nil
local messages, pending = {}, nil
local client = setmetatable({
    controlledProbe = function() return current end, LocalPlayer = function() return pilot end,
    thermalVision = {GetBool = function() return thermal end},
    nightVision = {GetBool = function() return night end},
    hook = {Add = function(_, _, callback) sync = callback end},
    net = {Start = function(name) assert(name == "ProbeDroid.SensorMode") end,
        WriteUInt = function(mode, bits) assert(bits == 2) pending = mode end,
        SendToServer = function() messages[#messages + 1] = pending end}}, {__index = _G})
run(assert(autorun:match('(do\n    local lastProbe, lastMode\n    hook.Add%("Think", "ProbeDroid.SensorBatteryMode".-)\n%-%- Keep console commands')), client)
sync()
sync()
assert(#messages == 1 and messages[1] == 0, "unchanged mode sends repeatedly")
thermal = true
sync()
assert(messages[2] == 1, "thermal mode not synchronized")
thermal, night = false, true
sync()
assert(messages[3] == 2, "night vision mode not synchronized")
current = nil
sync()
assert(#messages == 3, "sensor message sent without a flight")
current = {}
sync()
assert(#messages == 4 and messages[4] == 2, "sensor preference not applied to new flight")
night = false
sync()
assert(messages[5] == 0, "optical mode not synchronized")
print("Sensor battery checks passed: rates, combined costs, mode transitions, authorization and synchronization")
