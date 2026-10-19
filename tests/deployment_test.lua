-- Run the real weapon entry point; rejected launches must never create a drone.
local creates, modelChecks, messages = 0, 0, 0
local player = {valid = true, grounded = true, moveType = 2, speedSquared = 0, alive = true}
function player:Alive() return self.alive end
function player:InVehicle() return self.vehicle end
function player:GetNW2Entity() return self.probe end
function player:OnGround() return self.grounded end
function player:GetMoveType() return self.moveType end
function player:GetVelocity() return {LengthSqr = function() return self.speedSquared end} end
function player:ChatPrint(message)
    assert(message == "Stand still on the ground to deploy the probe.")
    messages = messages + 1
end
local env = setmetatable({SERVER = true, CLIENT = false, MOVETYPE_WALK = 2,
    SWEP = {Primary = {}, Secondary = {}},
    AddCSLuaFile = function() end, CurTime = function() return 0 end,
    IsValid = function(ent) return ent and ent.valid end,
    file = {Exists = function() modelChecks = modelChecks + 1 return true end},
    ents = {Create = function(class)
        assert(class == "sent_probe_droid")
        creates = creates + 1
        -- Stop after the authorization boundary; geometry is unrelated here.
        return nil
    end}}, {__index = _G})
local chunk = assert(loadfile("lua/weapons/weapon_probe_droid.lua"))
setfenv(chunk, env)
chunk()
local weapon = setmetatable({}, {__index = env.SWEP})
function weapon:GetOwner() return player end
function weapon:SetNextPrimaryFire() end
for _, case in ipairs({
    {true, 2, 10000}, -- walking/running
    {true, 2, 4}, -- slow motion must still block deployment
    {false, 2, 90000}, -- falling
    {false, 2, 0}, -- jump apex: zero velocity is insufficient without ground
    {true, 2, 2500}, -- vertical/platform motion, despite a ground flag
    {true, 8, 0}, -- noclip with a stale ground flag
    {true, 9, 0} -- ladder
}) do
    player.grounded, player.moveType, player.speedSquared = unpack(case)
    weapon:PrimaryAttack()
end
assert(creates == 0 and modelChecks == 0, "moving or airborne player reached deployment")
assert(messages == 7, "blocked launch did not explain stationary requirement")
player.grounded, player.moveType, player.speedSquared = true, 2, 0
weapon:PrimaryAttack()
assert(creates == 1 and modelChecks == 1, "stationary grounded player cannot deploy")
player.speedSquared = 0.01
weapon:PrimaryAttack()
assert(creates == 2, "negligible velocity jitter blocks stationary player")
env.CLIENT = true
weapon:PrimaryAttack()
assert(creates == 2, "client attempted server entity creation")
-- Complete deployment too: an error after Spawn leaves an unpiloted entity
-- that destroys itself on its first Think. Syntax checks cannot catch API typos.
env.CLIENT = false
local vectorMeta = {}
local function vector(x, y, z)
    return setmetatable({x = x, y = y, z = z}, vectorMeta)
end
function vectorMeta.__add(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function vectorMeta.__sub(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vectorMeta.__mul(a, b) return vector(a.x * b, a.y * b, a.z * b) end
env.Vector, env.vector_origin = vector, vector(0, 0, 0)
env.Angle = function(p, y, r) return {p = p, y = y, r = r} end
function player:EyePos() return vector(0, 0, 64) end
function player:EyeAngles() return env.Angle(0, 0, 0) end
function player:GetAimVector() return vector(1, 0, 0) end
function weapon:SetHoldType(value) self.holdType = value end
weapon:Initialize()
assert(weapon.holdType == "slam" and env.SWEP.UseHands, "controller initialization broke")
local spawned, blocked = nil, false
env.ents.Create = function()
    spawned = {valid = true}
    function spawned:SetPos(pos) self.pos = pos end
    function spawned:SetAngles() end
    function spawned:Spawn()
        self.HullMins, self.HullMaxs = vector(-20, -20, 0), vector(20, 20, 60)
    end
    function spawned:BeginControl(ply, controller)
        assert(self.pos.x == 100 and self.pos.z == 34, "incorrect deployment position")
        self.pilot, self.ControlWeapon = ply, controller
        ply.probe = self
    end
    function spawned:EmitSound(path)
        assert(self.pilot == player, "deployment sound played before control began")
        assert(path == "npc/roller/mine/rmine_blades_out1.wav")
        self.soundPlayed = true
    end
    function spawned:Remove() self.valid = false end
    return spawned
end
env.util = {TraceHull = function(trace)
    assert(trace.mins == spawned.HullMins and trace.maxs == spawned.HullMaxs)
    assert(trace.filter[1] == player and trace.filter[2] == spawned)
    return {StartSolid = blocked, Fraction = blocked and 0 or 1, HitPos = trace.endpos}
end}
weapon:PrimaryAttack()
assert(spawned.pilot == player and spawned.ControlWeapon == weapon and spawned.soundPlayed,
    "spawned drone did not finish deployment")
assert(weapon:Holster() == false, "pilot can holster controller in flight")
player.probe, blocked = nil, true
function player:ChatPrint(message)
    assert(message == "Not enough room to deploy the probe. Aim at an open area.")
end
weapon:PrimaryAttack()
assert(not spawned.valid and not spawned.pilot and not spawned.soundPlayed,
    "obstructed deployment left a drone active")
print("Deployment checks passed: stationary ground, complete spawn/control, controller initialization and obstructed launch cleanup")
