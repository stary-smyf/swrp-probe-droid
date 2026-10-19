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
print("Deployment checks passed: stationary ground requirement, movement, falling, jump apex and noclip")
