-- Source NPCs need a combat-character target to aim and fire at an anim SENT.
-- A hidden bullseye supplies that target; its hull forwards hits to the probe.
local acquisitionRange = 2000
local priority = 99

local function forgetProbe(npc, probe, target)
    local enemy = npc:GetEnemy()
    if IsValid(target) then npc:ClearEnemyMemory(target) end
    npc:ClearEnemyMemory(probe)
    if enemy == target or enemy == probe then
        npc:SetEnemy(NULL)
        npc:ClearSchedule()
    end
end

function ENT:CreateNPCTarget()
    if IsValid(self.NPCTarget) then return end
    local target = ents.Create("npc_bullseye")
    if not IsValid(target) then return end
    local center = (self.HullMins + self.HullMaxs) * 0.5
    target:SetPos(self:LocalToWorld(center))
    target:SetAngles(self:GetAngles())
    target:SetKeyValue("health", "1000000")
    target:Spawn()
    target:Activate()
    -- Keep it unparented: Source makes parented entities non-solid to rays.
    -- SyncNPCTarget moves it with the drone before and after every flight tick.
    -- Slightly enclose the probe so weapon LOS and bullet traces hit the
    -- actual NPC target, rather than treating the drone as intervening cover.
    local margin = Vector(1, 1, 1)
    target:SetCollisionBounds(self.HullMins - center - margin, self.HullMaxs - center + margin)
    target:SetNoDraw(true)
    target.ProbeDroidOwner = self
    self.NPCTarget = target
    self:SetAimTarget(target)
    self:DeleteOnRemove(target)
    self.TargetNPCs = self.TargetNPCs or {}
    if self:GetStealth() then target:AddFlags(FL_NOTARGET) end
end

function ENT:SyncNPCTarget()
    if IsValid(self.NPCTarget) then
        self.NPCTarget:SetPos(self:LocalToWorld((self.HullMins + self.HullMaxs) * 0.5))
    end
end

function ENT:SetStealthMode(enabled)
    if self:GetStealth() == enabled then return end
    -- Settle the previous mode before switching, including between Think ticks.
    self:UpdateBatteryDrain()
    self:SetStealth(enabled)
    self:EmitSound(enabled and "buttons/combine_button1.wav" or "buttons/combine_button2.wav",
        65, enabled and 90 or 110, 0.7)
    local target = self.NPCTarget
    if IsValid(target) then
        if enabled then target:AddFlags(FL_NOTARGET) else target:RemoveFlags(FL_NOTARGET) end
    end
    self.NextNPCTargetUpdate = 0
    self:UpdateNPCTargeting()
end

function ENT:UpdateNPCTargeting()
    self:SyncNPCTarget()
    if CurTime() < (self.NextNPCTargetUpdate or 0) then return end
    self.NextNPCTargetUpdate = CurTime() + 0.5
    self:CreateNPCTarget()
    local target, pilot = self.NPCTarget, self:GetPilot()
    if not IsValid(target) or not IsValid(pilot) then return end
    local tracked = self.TargetNPCs
    -- Include previous attackers even after the drone has flown away, so a
    -- stealth toggle always clears their memory and interrupts their attack.
    for _, npc in ipairs(ents.FindInSphere(self:GetPos(), acquisitionRange)) do
        if npc:IsNPC() and npc:GetClass() ~= "npc_bullseye" then tracked[npc] = true end
    end
    local ignorePlayers = GetConVar("ai_ignoreplayers")
    local hidden = self:GetStealth() or (ignorePlayers and ignorePlayers:GetBool())
    for npc in pairs(tracked) do
        if not IsValid(npc) then
            tracked[npc] = nil
        else
            local nearby = npc:GetPos():DistToSqr(self:GetPos()) <= acquisitionRange ^ 2
            local hostile = not hidden and nearby and npc:Health() > 0 and npc:Disposition(pilot) == D_HT
            npc:AddEntityRelationship(target, hostile and D_HT or D_NU, priority)
            if not hostile then
                forgetProbe(npc, self, target)
                if not nearby then tracked[npc] = nil end
            elseif npc:IsInViewCone(target:WorldSpaceCenter()) then
                local trace = util.TraceLine({start = npc:EyePos(), endpos = target:WorldSpaceCenter(),
                    filter = npc, mask = MASK_SHOT})
                if not trace.Hit or trace.Entity == target or trace.Entity == self then
                    local enemy = npc:GetEnemy()
                    -- Let unrelated fights continue; the pilot's drone can
                    -- take over from the pilot when it enters the NPC's view.
                    if not IsValid(enemy) or enemy == pilot or enemy == self or enemy == target then
                        npc:SetEnemy(target)
                        npc:UpdateEnemyMemory(target, target:GetPos())
                    end
                end
            end
        end
    end
end

function ENT:RemoveNPCTarget()
    local target = self.NPCTarget
    for npc in pairs(self.TargetNPCs or {}) do
        if IsValid(npc) then
            if IsValid(target) then npc:AddEntityRelationship(target, D_NU, priority) end
            forgetProbe(npc, self, target)
        end
    end
    self.TargetNPCs = nil
    if IsValid(target) then target:Remove() end
    self.NPCTarget = nil
    self:SetAimTarget(NULL)
end

hook.Add("EntityTakeDamage", "ProbeDroid.NPCTargetDamage", function(ent, damage)
    local probe = ent.ProbeDroidOwner
    if not IsValid(probe) then return end
    -- Radius damage already hits the drone itself; do not apply it twice.
    if not damage:IsExplosionDamage() then probe:TakeDamageInfo(damage) end
    return true
end)
