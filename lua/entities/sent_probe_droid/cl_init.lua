include("shared.lua")

function ENT:Think()
    local velocity = self:GetNW2Vector("ProbeDroidVelocity", vector_origin)
    local horizontal = Vector(velocity.x, velocity.y, 0)
    -- Keep diagonal flight within the same maximum lean as straight flight.
    local tilt = horizontal * (18 / 350)
    if tilt:LengthSqr() > 25 * 25 then
        tilt = tilt:GetNormalized() * 25
    end
    self.FlightTilt = LerpVector(1 - math.exp(-FrameTime() * 8),
        self.FlightTilt or vector_origin, tilt)
end

function ENT:DrawFlightModel()
    local angles = self:GetAngles()
    local heading = Angle(0, angles.y, 0)
    local tilt = self.FlightTilt or vector_origin
    -- Apply banking only while rendering, keeping the pilot's camera level.
    local previousAngles = self:GetRenderAngles()
    self:SetRenderAngles(Angle(tilt:Dot(heading:Forward()), angles.y,
        tilt:Dot(heading:Right())))
    self:DrawModel()
    self:SetRenderAngles(previousAngles)
end

function ENT:Draw()
    if self:GetStealth() then return end
    local ply = LocalPlayer()
    if IsValid(ply) and ply:GetNW2Entity("ProbeDroidControlled") == self then return end
    self:DrawFlightModel()
end

function ENT:DrawTranslucent()
    if not self:GetStealth() then return end
    local ply = LocalPlayer()
    if IsValid(ply) and ply:GetNW2Entity("ProbeDroidControlled") == self then return end
    local blend = render.GetBlend()
    render.SetBlend(blend * 0.2)
    self:DrawFlightModel()
    render.SetBlend(blend)
end
