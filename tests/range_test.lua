-- Exercise startup migration with saved values and a deferred config override.
local file = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local source = file:read("*a")
file:close()
local block = assert(source:match("^(if SERVER then.-)\nlocal function controlledProbe"))

local function check(saved, migrated, configured, expected)
    local values = {probe_droid_range = saved, probe_droid_range_migrated_5000 = migrated}
    local pending
    local function convar(name)
        return {
            GetBool = function() return values[name] ~= 0 end,
            GetFloat = function() return values[name] end,
            SetFloat = function(_, value) values[name] = value end,
            SetBool = function(_, value) values[name] = value and 1 or 0 end
        }
    end
    local probes = {}
    for i, value in ipairs({3000, 2000}) do
        probes[i] = {range = value, GetMaxRange = function(self) return self.range end,
            SetMaxRange = function(self, range) self.range = range end}
    end
    local env = {
        SERVER = true, FCVAR_ARCHIVE = 1, ipairs = ipairs,
        AddCSLuaFile = function() end, resource = {AddFile = function() end},
        CreateConVar = function(name, default)
            if values[name] == nil then values[name] = tonumber(default) end
            return convar(name)
        end,
        GetConVar = convar,
        timer = {Simple = function(_, callback) pending = callback end},
        ents = {FindByClass = function() return probes end}
    }
    local chunk = assert(loadstring(block))
    setfenv(chunk, env)
    chunk()
    if configured then values.probe_droid_range = configured end
    pending()
    assert(values.probe_droid_range == expected, "incorrect migrated range")
    local upgraded = migrated ~= 1 and (configured or saved) == 3000
    assert(probes[1].range == (upgraded and 5000 or 3000), "incorrect active probe range")
    assert(probes[2].range == 2000, "custom active probe range changed")
    assert(values.probe_droid_range_migrated_5000 == 1, "migration marker not saved")
    values.probe_droid_range = 3000
    pending()
    assert(values.probe_droid_range == 3000, "migration repeated")
end

check(nil, nil, nil, 5000)
check(3000, 0, nil, 5000)
check(2000, 0, nil, 2000)
check(5000, 0, 3000, 5000)
check(3000, 1, nil, 3000)
print("Range migration checks passed")
