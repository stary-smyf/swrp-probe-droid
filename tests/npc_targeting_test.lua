-- Load the real server AI code with deterministic NPCs and collision results.
local vectorMeta = {}
vectorMeta.__index = vectorMeta
local function vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta) end
function vectorMeta.__add(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function vectorMeta.__sub(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vectorMeta.__mul(a, n) return vector(a.x * n, a.y * n, a.z * n) end
function vectorMeta:DistToSqr(b) local d = self - b return d.x*d.x + d.y*d.y + d.z*d.z end
function vectorMeta:LengthSqr() return self:DistToSqr(vector()) end
local now, found, damageHook, ignorePlayers = 0, {}, nil, false
local env = setmetatable({ENT = {}, Vector = vector, D_HT = 1, D_NU = 4,
    FL_NOTARGET = 65536, MASK_SHOT = 1, NULL = {},
    CurTime = function() return now end,
    IsValid = function(ent) return type(ent) == "table" and ent.valid == true end,
    GetConVar = function() return {GetBool = function() return ignorePlayers end} end,
    hook = {Add = function(_, _, callback) damageHook = callback end},
    util = {TraceLine = function(request)
        if request.filter.blocked then return {Hit = true, Entity = {}} end
        return {Hit = false}
    end}}, {__index = _G})
env.ents = {
    FindInSphere = function() return found end,
    Create = function(class)
        assert(class == "npc_bullseye")
        return {valid = true,
            SetPos = function(self, value) self.position = value end,
            GetPos = function(self) return self.position end,
            WorldSpaceCenter = function(self) return self.position end,
            SetAngles = function() end, SetKeyValue = function() end,
            Spawn = function() end, Activate = function() end,
            SetCollisionBounds = function(self, mins, maxs) self.mins, self.maxs = mins, maxs end,
            SetNoDraw = function() end,
            AddFlags = function(self) self.hidden = true end,
            RemoveFlags = function(self) self.hidden = false end,
            Remove = function(self) self.valid = false end}
    end}
local chunk = assert(loadfile("lua/entities/sent_probe_droid/npc_targeting.lua"))
setfenv(chunk, env)
chunk()
local initFile = assert(io.open("lua/entities/sent_probe_droid/init.lua", "rb"))
local initSource = initFile:read("*a")
initFile:close()
local batteryChunk = assert(loadstring(assert(initSource:match("(function ENT:UpdateBatteryDrain%(%).-\nend)"))))
setfenv(batteryChunk, env)
batteryChunk()
local pilot = {valid = true}
local probe = setmetatable({valid = true, position = vector(),
    HullMins = vector(-20, -20, -20), HullMaxs = vector(20, 20, 20)}, {__index = env.ENT})
function probe:LocalToWorld(v) return self.position + v end
function probe:GetPos() return self.position end
function probe:GetAngles() return {} end
function probe:GetPilot() return pilot end
function probe:GetStealth() return self.stealth or false end
function probe:SetStealth(value) self.stealth = value end
function probe:SetAimTarget(value) self.aimTarget = value end
function probe:DeleteOnRemove(value) self.deleteTarget = value end
function probe:TakeDamageInfo(damage) self.damage = (self.damage or 0) + damage.amount end
function probe:GetBatteryEnd() return self.batteryEnd or 120 end
function probe:SetBatteryEnd(value) self.batteryEnd = value end
function probe:EmitSound(sound)
    self.sounds = self.sounds or {}
    self.sounds[#self.sounds + 1] = sound
end
local function npc(hostile)
    return {valid = true, position = vector(100, 0, 0), hostile = hostile,
        IsNPC = function() return true end, GetClass = function() return "npc_combine_s" end,
        GetPos = function(self) return self.position end,
        EyePos = function(self) return self.position end,
        Health = function() return 100 end,
        Disposition = function(self, ent) assert(ent == pilot) return self.hostile and env.D_HT or env.D_NU end,
        AddEntityRelationship = function(self, target, disposition) self.relationship = disposition end,
        GetEnemy = function(self) return self.enemy end,
        SetEnemy = function(self, enemy) self.enemy = enemy end,
        ClearEnemyMemory = function(self, target) self.forgot = self.forgot or {} self.forgot[target] = true end,
        ClearSchedule = function(self) self.clears = (self.clears or 0) + 1 end,
        IsInViewCone = function(self) return not self.turnedAway end,
        UpdateEnemyMemory = function(self, target) self.memory = target end}
end
local hostile, friendly, blocked, turnedAway, occupied = npc(true), npc(false), npc(true), npc(true), npc(true)
blocked.blocked, turnedAway.turnedAway = true, true
occupied.enemy = {valid = true}
found = {hostile, friendly, blocked, turnedAway, occupied}
probe:UpdateNPCTargeting()
local target = probe.NPCTarget
assert(target.valid and probe.aimTarget == target and probe.deleteTarget == target, "target lifecycle missing")
assert(target.mins.x == -21 and target.maxs.x == 21, "target must enclose the drone hull")
assert(hostile.enemy == target and hostile.memory == target, "visible hostile did not acquire drone")
assert(friendly.enemy == nil and friendly.relationship == env.D_NU, "friendly NPC attacked")
assert(blocked.enemy == nil and turnedAway.enemy == nil, "NPC acquired drone through wall or behind it")
assert(occupied.enemy ~= target and occupied.clears == nil, "unrelated fight interrupted")

-- Stealth clears the current attack immediately and prevents reacquisition.
probe:SetStealthMode(true)
assert(probe.sounds[1] == "buttons/combine_button1.wav", "stealth entry sound missing")
probe:SetStealthMode(true)
assert(#probe.sounds == 1, "unchanged stealth mode replayed sound")
assert(target.hidden and hostile.enemy == env.NULL, "stealth did not drop enemy")
assert(hostile.forgot[target] and hostile.forgot[probe] and hostile.clears == 1, "enemy memory/schedule not cleared")
assert(hostile.relationship == env.D_NU, "stealth target still hostile")
now = 1
probe:UpdateNPCTargeting()
assert(hostile.enemy == env.NULL and hostile.clears == 1, "stealth reacquired or reset unrelated schedule")
probe:SetStealthMode(false)
assert(probe.sounds[2] == "buttons/combine_button2.wav", "stealth exit sound missing")
assert(not target.hidden and hostile.enemy == target, "NPC failed to reacquire after stealth")

-- Former attackers outside the next discovery sphere must also forget it.
found = {}
hostile.position = vector(9000, 0, 0)
probe:SetStealthMode(true)
assert(hostile.enemy == env.NULL and hostile.relationship == env.D_NU, "distant attacker kept aggro")

-- Late spawns, player-ignore mode, and target replacement are handled.
local late = npc(true)
found, now = {late}, 2
probe:UpdateNPCTargeting()
assert(late.enemy == nil and late.relationship == env.D_NU, "late NPC saw stealthed drone")
probe:SetStealthMode(false)
assert(late.enemy == target, "late NPC did not acquire revealed drone")
ignorePlayers, now = true, 3
probe:UpdateNPCTargeting()
assert(late.enemy == env.NULL, "ai_ignoreplayers ignored")
ignorePlayers, now = false, 4
probe:UpdateNPCTargeting()
assert(late.enemy == target, "ignore mode did not recover")
late.hostile, now = false, 5
probe:UpdateNPCTargeting()
assert(late.enemy == env.NULL, "newly friendly NPC kept attacking")

probe.position = vector(700, 0, 0)
probe:SyncNPCTarget()
assert(target.position.x == 700, "target did not follow drone")
local damage = {amount = 20, IsExplosionDamage = function() return false end}
assert(damageHook(target, damage) == true and probe.damage == 20, "bullet damage not forwarded once")
damage.IsExplosionDamage = function() return true end
damageHook(target, damage)
assert(probe.damage == 20, "explosion damage duplicated")
probe:SetStealthMode(true)
damage.IsExplosionDamage = function() return false end
damageHook(target, damage)
assert(probe.damage == 40, "stealth incorrectly grants invulnerability")
assert(damageHook({}, damage) == nil, "unrelated damage intercepted")

-- Run each command through the client hook before sending it to the server.
-- This catches client suppression accidentally deleting the stealth input.
local inputFile = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local inputSource = inputFile:read("*a")
inputFile:close()
local inputBlock = assert(inputSource:match('(hook.Add%("StartCommand".-)\nhook.Add%("PlayerSwitchWeapon"'))
local inputHook
env.hook = {Add = function(_, _, callback) inputHook = callback end}
env.SERVER, env.CLIENT = true, false
env.controlledProbe = function() return probe end
for _, key in ipairs({"IN_USE", "IN_ATTACK", "IN_ATTACK2", "IN_RELOAD", "IN_FORWARD", "IN_BACK", "IN_MOVERIGHT",
    "IN_MOVELEFT", "IN_JUMP", "IN_DUCK", "IN_SPEED"}) do env[key] = key end
local inputChunk = assert(loadstring(inputBlock))
setfenv(inputChunk, env)
inputChunk()
function pilot:GetActiveWeapon() return nil end
env.Angle = function(p, y, r) return {p = p, y = y, r = r} end
local function deliverCommand(held)
    local cmd = {buttons = {[env.IN_ATTACK2] = held, [env.IN_ATTACK] = true, [env.IN_RELOAD] = true},
        KeyDown = function(self, key) return self.buttons[key] or false end,
        RemoveKey = function(self, key) self.buttons[key] = nil end,
        GetViewAngles = function() return {p = 0, y = 0} end,
        ClearMovement = function() end,
        ClearButtons = function(self) self.buttons = {} end,
        SetImpulse = function() end}
    env.SERVER, env.CLIENT = false, true
    inputHook(pilot, cmd)
    assert(cmd:KeyDown(env.IN_ATTACK2) == held, "client stripped stealth input before server received it")
    assert(not cmd:KeyDown(env.IN_ATTACK) and not cmd:KeyDown(env.IN_RELOAD), "client weapon suppression changed")
    env.SERVER, env.CLIENT = true, false
    inputHook(pilot, cmd)
    assert(next(cmd.buttons) == nil, "server did not suppress weapon actions after reading input")
end
probe:SetStealthMode(false)
deliverCommand(true)
assert(probe:GetStealth(), "right click failed to enable stealth")
deliverCommand(true)
assert(probe:GetStealth(), "held right click toggled repeatedly")
deliverCommand(false)
deliverCommand(true)
assert(not probe:GetStealth(), "second click failed to disable stealth")

probe:RemoveNPCTarget()
assert(not target.valid and probe.NPCTarget == nil and probe.aimTarget == env.NULL, "orphan target on cleanup")
print("NPC targeting checks passed: visibility, hostility, stealth, reacquisition, damage and cleanup")
