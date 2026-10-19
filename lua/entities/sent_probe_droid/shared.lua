ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Probe Droid"
ENT.Spawnable = false
ENT.WantsTranslucency = true
ENT.Model = "models/starwars/syphadias/ships/probe_droid/probe_droid.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Pilot")
    self:NetworkVar("Entity", 1, "AimTarget")
    self:NetworkVar("Float", 0, "BatteryEnd")
    self:NetworkVar("Float", 1, "BatteryDuration")
    self:NetworkVar("Float", 2, "MaxRange")
    self:NetworkVar("Vector", 0, "LaunchPosition")
    self:NetworkVar("Vector", 1, "CameraOffset")
    self:NetworkVar("Bool", 0, "Stealth")
end

function ENT:GetCameraPosition()
    return self:LocalToWorld(self:GetCameraOffset())
end

function ENT:UpdateFlightVelocity(direction, speed, dt)
    -- Exponential response keeps the same flight feel at different tick rates.
    -- Releasing the controls leaves a short glide before the hover stabilizes.
    local response = direction:LengthSqr() > 0 and 0.22 or 0.35
    self.FlightVelocity = LerpVector(1 - math.exp(-dt / response),
        self.FlightVelocity or vector_origin, direction * speed)
    if direction:LengthSqr() == 0 and self.FlightVelocity:LengthSqr() < 0.25 then
        self.FlightVelocity = Vector(0, 0, 0)
    end
end

function ENT:UpdateHoverBob(direction, dt)
    local idle = direction:LengthSqr() == 0
        and 1 - math.Clamp(self.FlightVelocity:Length() / 45, 0, 1) or 0
    self.HoverBlend = Lerp(1 - math.exp(-dt * 4), self.HoverBlend or 0, idle)
    -- Six-unit peak-to-peak hover, with a slightly different phase per droid.
    return math.sin(CurTime() * 1.8 + self:EntIndex() * 0.37) * 3 * self.HoverBlend
end
