AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")
include("npc_targeting.lua")

function ENT:Initialize()
    self:SetModel(self.Model)

    -- Fit the supplied ship model into a small, usable drone envelope.
    local mins, maxs = self:GetModelBounds()
    local size = maxs - mins
    local scale = math.min(56 / math.max(size.x, size.y, 1), 72 / math.max(size.z, 1))
    self:SetModelScale(scale, 0)
    mins, maxs = mins * scale, maxs * scale
    local radius = math.max(math.abs(mins.x), math.abs(maxs.x), math.abs(mins.y), math.abs(maxs.y), 8)
    self.HullMins = Vector(-radius, -radius, mins.z)
    self.HullMaxs = Vector(radius, radius, math.max(maxs.z, mins.z + 8))
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(self.HullMins, self.HullMaxs)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:SetCameraOffset(Vector(0, 0, mins.z + (maxs.z - mins.z) * 0.8))
    self:SetMaxHealth(GetConVar("probe_droid_health"):GetInt())
    self:SetHealth(self:GetMaxHealth())
    self.FlightVelocity = Vector(0, 0, 0)
    self.InputDirection = Vector(0, 0, 0)
    self.LastInputTime = CurTime()
    self.LastFlightTime = CurTime()
end

function ENT:BeginControl(ply, weapon)
    self.ControlWeapon = weapon
    self.PreviousMoveType = ply:GetMoveType()
    self.PreviousViewEntity = ply:GetViewEntity()
    self.PreviousEyeAngles = ply:EyeAngles()
    ply:SetNW2Angle("ProbeDroidBodyAngles", self.PreviousEyeAngles)
    self:SetPilot(ply)
    self:SetLaunchPosition(ply:GetPos())
    self:SetMaxRange(GetConVar("probe_droid_range"):GetFloat())
    self:SetBatteryDuration(GetConVar("probe_droid_battery"):GetFloat())
    self:SetBatteryEnd(CurTime() + self:GetBatteryDuration())
    self.LastBatteryUpdate = CurTime()
    self.SensorMode = 0
    self.ControlStarted = CurTime()
    ply:SetNW2Entity("ProbeDroidControlled", self)
    ply:SetLocalVelocity(vector_origin)
    ply:SetMoveType(MOVETYPE_NONE)
    ply:SetViewEntity(self)
    self:CreateNPCTarget()
end

function ENT:EndControl()
    local ply = self:GetPilot()
    if not IsValid(ply) or ply:GetNW2Entity("ProbeDroidControlled") ~= self then return end
    ply:SetNW2Entity("ProbeDroidControlled", NULL)
    local previous = self.PreviousViewEntity
    ply:SetViewEntity(IsValid(previous) and previous or ply)
    -- Death/respawn owns the movement type once the pilot has died.
    if ply:Alive() then
        ply:SetMoveType(self.PreviousMoveType or MOVETYPE_WALK)
        ply:SetLocalVelocity(vector_origin)
        if self.PreviousEyeAngles then ply:SetEyeAngles(self.PreviousEyeAngles) end
    end
end

function ENT:UpdateBatteryDrain()
    local now = CurTime()
    local elapsed = math.max(0, now - (self.LastBatteryUpdate or now))
    self.LastBatteryUpdate = now
    -- The deadline already accounts for normal drain. Add the power costs:
    -- stealth +100%, thermal +100%, night vision +25% of the base rate.
    local sensorCost = self.SensorMode == 1 and 1 or self.SensorMode == 2 and 0.25 or 0
    local extraDrain = (self:GetStealth() and 1 or 0) + sensorCost
    if extraDrain > 0 and elapsed > 0 then
        self:SetBatteryEnd(self:GetBatteryEnd() - elapsed * extraDrain)
    end
end

function ENT:UpdateSpeech()
    local now = CurTime()
    self.NextSpeech = self.NextSpeech or now + math.Rand(3, 7)
    if now < self.NextSpeech then return end
    local last = self.LastSpeech
    local index = last and ((last - 1 + math.random(1, 2)) % 3 + 1) or math.random(1, 3)
    self.LastSpeech = index
    -- A single cue synchronizes all listeners, including the pilot. Old cues
    -- are ignored when a player first enters the drone's visibility/range.
    self:SetNW2String("ProbeDroidSpeechCue", string.format("%d:%.3f", index, now))
    local duration = SoundDuration("probe_droid/probedroidspeak" .. index .. ".wav")
    self.NextSpeech = now + math.max(duration, 0.1) + math.Rand(5, 12)
end

function ENT:DestroyProbe(reason)
    if self.Destroying then return end
    self.Destroying = true
    local ply = self:GetPilot()
    if IsValid(ply) and reason then ply:ChatPrint("Probe lost: " .. reason) end
    local effect = EffectData()
    effect:SetOrigin(self:WorldSpaceCenter())
    util.Effect("cball_explode", effect, true, true)
    self:EmitSound("ambient/energy/weld2.wav", 70, 80)
    self:EndControl()
    self:Remove()
end

function ENT:Think()
    local ply = self:GetPilot()
    if not IsValid(ply) or not ply:Alive() then
        self:DestroyProbe()
        return
    end
    if not IsValid(self.ControlWeapon) or ply:GetActiveWeapon() ~= self.ControlWeapon then
        self:DestroyProbe("controller disconnected")
        return
    end
    self:UpdateBatteryDrain()
    if CurTime() >= self:GetBatteryEnd() then
        self:DestroyProbe("battery depleted")
        return
    end
    if self:GetCameraPosition():DistToSqr(self:GetLaunchPosition()) > self:GetMaxRange() ^ 2 then
        self:DestroyProbe("out of range")
        return
    end

    self:UpdateSpeech()
    self:UpdateNPCTargeting()
    local dt = math.Clamp(CurTime() - self.LastFlightTime, 0, 0.1)
    self.LastFlightTime = CurTime()
    local direction = self.InputDirection
    -- Stop if commands stop arriving (disconnects, stalls, or a lost connection).
    if CurTime() - self.LastInputTime > 0.25 then
        direction = vector_origin
        self.FlightVelocity = Vector(0, 0, 0)
    end
    local speed = GetConVar("probe_droid_speed"):GetFloat() * (self.Boosting and 1.8 or 1)
    self:UpdateFlightVelocity(direction, speed, dt)

    -- Swept collision prevents passing through walls, even while boosting.
    local position = self:GetPos()
    local remaining = dt
    for _ = 1, 3 do
        if self.FlightVelocity:LengthSqr() < 0.0001 then break end
        local trace = util.TraceHull({
            start = position,
            endpos = position + self.FlightVelocity * remaining,
            mins = self.HullMins,
            maxs = self.HullMaxs,
            filter = {self, ply, self.NPCTarget},
            mask = MASK_SOLID
        })
        if trace.StartSolid then
            self.FlightVelocity = Vector(0, 0, 0)
            break
        end
        position = trace.HitPos
        if not trace.Hit then break end
        position = position + trace.HitNormal * 0.1
        self.FlightVelocity = self.FlightVelocity - trace.HitNormal * math.min(self.FlightVelocity:Dot(trace.HitNormal), 0)
        remaining = remaining * (1 - trace.Fraction)
    end
    -- Keep bob displacement separate from propulsion so it cannot accumulate
    -- into vertical drift. Track only the offset actually allowed by collision.
    local hoverOffset = self.HoverOffset or 0
    local hoverDelta = self:UpdateHoverBob(direction, dt) - hoverOffset
    if math.abs(hoverDelta) > 0.001 then
        local trace = util.TraceHull({
            start = position,
            endpos = position + Vector(0, 0, hoverDelta),
            mins = self.HullMins,
            maxs = self.HullMaxs,
            filter = {self, ply, self.NPCTarget},
            mask = MASK_SOLID
        })
        if not trace.StartSolid then
            self.HoverOffset = hoverOffset + trace.HitPos.z - position.z
            position = trace.HitPos
        end
    end
    self:SetPos(position)
    self:SyncNPCTarget()
    -- Camera banking uses the collision-resolved motion; send at most 20 Hz.
    if CurTime() >= (self.NextMotionUpdate or 0) then
        self:SetNW2Vector("ProbeDroidVelocity", self.FlightVelocity)
        self.NextMotionUpdate = CurTime() + 0.05
    end
    if self.FlightAngles then self:SetAngles(Angle(0, self.FlightAngles.y, 0)) end
    if not util.IsInWorld(self:GetCameraPosition()) then
        self:DestroyProbe("signal lost outside the map")
        return
    end
    -- Check after moving too: there is no extra tick of flight beyond the limit.
    if self:GetCameraPosition():DistToSqr(self:GetLaunchPosition()) > self:GetMaxRange() ^ 2 then
        self:DestroyProbe("out of range")
        return
    end
    self:NextThink(CurTime())
    return true
end

function ENT:OnTakeDamage(damage)
    if self.Destroying then return end
    self:SetHealth(self:Health() - damage:GetDamage())
    if self:Health() <= 0 then self:DestroyProbe("droid destroyed") end
end

function ENT:OnRemove()
    self:RemoveNPCTarget()
    self:EndControl()
end
