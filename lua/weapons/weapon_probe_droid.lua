if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_base"
SWEP.PrintName = "Probe Droid Controller"
SWEP.Author = "Probe Droid"
SWEP.Instructions = "Stand still on the ground and left click to deploy a probe droid. Right click toggles stealth in flight. Hold E for 3 seconds to end flight."
SWEP.Category = "Star Wars"
SWEP.IconOverride = "entities/weapon_probe_droid.png"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands = true
SWEP.ViewModel = "models/swcw_items/sw_datapad_v.mdl"
SWEP.WorldModel = "models/swcw_items/sw_datapad.mdl"
SWEP.ViewModelFOV = 54
-- Matches the original Star Wars Datapad SWEP.
SWEP.HoldType = "slam"
SWEP.Slot = 4
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 2)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then return end
    if IsValid(ply:GetNW2Entity("ProbeDroidControlled")) then return end
    -- Check authoritative movement before spawning or freezing the pilot.
    -- Allow only negligible velocity jitter while standing on solid ground.
    if not ply:OnGround() or ply:GetMoveType() ~= MOVETYPE_WALK
        or ply:GetVelocity():LengthSqr() > 1 then
        ply:ChatPrint("Stand still on the ground to deploy the probe.")
        return
    end
    local model = "models/starwars/syphadias/ships/probe_droid/probe_droid.mdl"
    if not file.Exists(model, "GAME") then
        ply:ChatPrint("Probe model missing. Install/mount the addon containing " .. model)
        return
    end

    local probe = ents.Create("sent_probe_droid")
    if not IsValid(probe) then return end
    probe:SetPos(ply:EyePos())
    probe:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    probe:Spawn()
    local midZ = (probe.HullMins.z + probe.HullMaxs.z) * 0.5
    local start = ply:EyePos() - Vector(0, 0, midZ)
    local trace = util.TraceHull({
        start = start,
        endpos = start + ply:GetAimVector() * (probe.HullMaxs.x + 80),
        mins = probe.HullMins,
        maxs = probe.HullMaxs,
        filter = {ply, probe},
        mask = MASK_SOLID
    })
    if trace.StartSolid or trace.AllSolid or trace.Fraction < 0.4 then
        probe:Remove()
        ply:ChatPrint("Not enough room to deploy the probe. Aim at an open area.")
        return
    end
    probe:SetPos(trace.HitPos - (trace.Hit and ply:GetAimVector() * 2 or vector_origin))
    probe:BeginControl(ply, self)
    self:EmitSound("buttons/button14.wav")
end

function SWEP:SecondaryAttack() end
function SWEP:Reload() end

function SWEP:Holster()
    local ply = self:GetOwner()
    return not IsValid(ply) or not IsValid(ply:GetNW2Entity("ProbeDroidControlled"))
end

function SWEP:OnRemove()
    if CLIENT then return end
    for _, probe in ipairs(ents.FindByClass("sent_probe_droid")) do
        if probe.ControlWeapon == self then probe:DestroyProbe("controller removed") end
    end
end
