-- Exercise the actual HUD scanner with deterministic engine mocks.
local sourceFile = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
local scanSource = assert(source:match("(local state = {nextScan = 0, contacts = {}, profile = {}}.-)\nlocal function compass"),
    "HUD scan source not found")

local vectorMeta = {}
vectorMeta.__index = vectorMeta
local function vector(x, y, z)
    return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta)
end
function vectorMeta.__add(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function vectorMeta.__sub(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vectorMeta.__mul(a, b) return vector(a.x * b, a.y * b, a.z * b) end
function vectorMeta:DistToSqr(other)
    local d = self - other
    return d.x * d.x + d.y * d.y + d.z * d.z
end
function vectorMeta:Distance(other) return math.sqrt(self:DistToSqr(other)) end
local function angle(p, y)
    return {p = p, y = y, Forward = function(self)
        local pitch, yaw = math.rad(self.p), math.rad(self.y)
        return vector(math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch))
    end}
end
local function actor(index, player)
    return {valid = true, alive = true, position = vector(index, index, 0),
        IsNPC = function() return not player end,
        GetClass = function(self) return self.class or "npc_combine_s" end,
        IsPlayer = function() return player or false end,
        Alive = function(self) return self.alive end,
        WorldSpaceCenter = function(self) return self.position end}
end
local function harness()
    local now, frame = 0, 0
    local pilot, probe = actor(0, true), {GetAimTarget = function() end}
    local found, traces, radarTraces = {}, {}, {}
    local sphereCalls, depthCalls = 0, 0
    for i = 1, 20 do found[i] = actor(i, i == 6) end
    local env = setmetatable({RADAR_RANGE = 1000, MASK_SHOT = 1, MASK_SOLID = 2, MASK_VISIBLE = 3,
        CurTime = function() return now end, FrameNumber = function() return frame end,
        LocalPlayer = function() return pilot end, Angle = angle,
        IsValid = function(ent) return ent and ent.valid end,
        Lerp = function(t, a, b) return a + (b - a) * t end,
        ents = {FindInSphere = function() sphereCalls = sphereCalls + 1 return found end},
        util = {TraceLine = function(request)
            traces[#traces + 1] = request
            if request.mask == 2 then
                depthCalls = depthCalls + 1
                return {Fraction = depthCalls / 100}
            elseif request.mask == 3 then
                local ent
                for _, candidate in ipairs(found) do
                    if candidate.position == request.endpos then ent = candidate break end
                end
                radarTraces[#radarTraces + 1] = ent
                return {Hit = ent.blocked or ent.hitSelf, Entity = ent.hitSelf and ent or nil}
            end
            return {Hit = false, Fraction = 1}
        end}}, {__index = _G})
    local chunk = assert(loadstring(scanSource .. "\nreturn scan, function() return state end"))
    setfenv(chunk, env)
    local scan, getState = chunk()
    local h = {probe = probe, found = found, traces = traces, radarTraces = radarTraces, state = getState}
    function h:step(time, position, view, range, sameFrame, selectedProbe)
        now = time
        if not sameFrame then frame = frame + 1 end
        local before = #traces
        scan(selectedProbe or probe, position or vector(), view or angle(0, 0), range or 3000)
        local cost = #traces - before
        assert(cost <= 11, "scan exceeded eleven collision traces: " .. cost)
        return cost
    end
    function h:sphereCalls() return sphereCalls end
    return h
end

local h = harness()
local origin, view = vector(10, 20, 30), angle(5, 10)
assert(h:step(0, origin, view, 9000) == 11, "first budget must be aim + 6 depth + 4 radar")
assert(h:step(0, origin, view, 9000, true) == 0, "duplicate HUD paint rescanned")
assert(#h.state().profile == 0, "partial depth sweep was published")
h:step(0.05, vector(200, 0, 0), angle(80, 150))
assert(#h.state().profile == 0, "partial depth sweep was published")
h:step(0.1, vector(300, 0, 0), angle(-80, -150))
assert(#h.state().profile == 17 and h.state().sounding == 6000, "complete capped profile missing")
for i, fraction in ipairs(h.state().profile) do assert(fraction == i / 100, "depth sample lost") end
local depthIndex = 0
for _, request in ipairs(h.traces) do
    if request.mask == 2 then
        depthIndex = depthIndex + 1
        local expected = origin + angle(view.p, view.y + (depthIndex - 9) * 4):Forward() * 6000
        assert(request.start == origin and request.endpos:Distance(expected) < 0.000001,
            "depth sweep mixed camera snapshots")
    end
end
assert(#h.state().contacts == 0, "partial radar sweep was published")
h:step(0.15)
assert(#h.state().contacts == 16 and #h.radarTraces == 16, "radar target budget changed")
assert(h:sphereCalls() == 1, "radar discovery was repeated during its sweep")
for i = 4, 19 do h:step(i * 0.05) end
local aimCount = 0
for _, request in ipairs(h.traces) do if request.mask == 1 then aimCount = aimCount + 1 end end
assert(aimCount >= 4 and aimCount <= 5, "aim trace cadence changed")
assert(h:sphereCalls() == 2, "radar discovery must run at 2 Hz")

-- Deferred entities can disappear, die or move; preserve wall occlusion and
-- accept a trace that hits the candidate itself.
h = harness()
h:step(0)
h.found[5].valid = false
h.found[6].alive = false
h.found[7].position = vector(2000, 0, 0)
h.found[8].blocked = true
h.found[9].hitSelf = true
h:step(0.05)
h:step(0.1)
h:step(0.15)
assert(#h.state().contacts == 12, "radar validity/occlusion checks failed")
assert(#h.radarTraces == 13, "invalid, dead or distant candidates were traced")

-- Slow rendering must finish old sweeps instead of replacing them every tick.
h = harness()
h:step(0)
h:step(1)
h:step(2)
assert(#h.state().profile == 17, "slow frames starved depth completion")
h:step(3)
assert(#h.state().contacts == 16, "slow frames starved radar completion")
local previous = h.state()
h:step(3, vector(), angle(0, 0), 3000, true, {GetAimTarget = function() end})
assert(h.state() ~= previous and #h.state().profile == 0 and #h.state().contacts == 0,
    "new probe reused previous scanner state")

-- An empty radar sweep must clear old contacts immediately.
h = harness()
for i = #h.found, 1, -1 do h.found[i] = nil end
h:step(0)
assert(#h.state().contacts == 0 and not h.state().radarSweep, "empty radar sweep did not finish")
print("HUD scan tests passed: bounded traces, cadence, snapshots, cleanup and slow-frame completion")
